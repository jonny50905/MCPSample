// ps-oracle-preflight-gate.js — Oracle 連線前置（第 0 步）的確定性閘門（OpenCode plugin）
//
// 規則（與主 agent 第 0 步一致）：主 agent 在同一則使用者訊息內，未依序完成
//   oracleMCP_list_connections（成功）→ oracleMCP_connect（成功）
// 之前，任何「會查 DB 的 subagent」委派（task 工具）都在執行前被擋下，模型收到
//   PS_ORACLE_PREFLIGHT_REQUIRED
// 的工具錯誤並被告知下一步；模型選錯順序不會變成錯誤的執行。閘門只擋、不改參數。
//
// 判準：
//   - 會查 DB 的 subagent＝.opencode/agent/*.md 的 tools 表對 oracleMCP_run_sql 為開
//     （OpenCode 規則：最後匹配者優先；沒列＝預設開）。不在 agent 目錄的名字一律視為會查 DB（保守）。
//   - 純 ES＋Source 的 subagent（oracleMCP_* 全關）不受閘門影響。
//   - oracleMCP 未掛載（/mcp 狀態非 connected）→ 閘門退讓，交由 subagent 的 ORACLE_MCP_DOWN 協定。
//   - 狀態以 session 為單位，每則使用者訊息重置為 NEED_LIST（第 0 步「不因上一題已連過就省略」）。
//   - subagent 報告 blockedReason=NOT_CONNECTED → 狀態退回 NEED_CONNECT（重派前必須再 connect 一次）。
//   - 本 session 呼叫 oracleMCP_disconnect → 狀態退回 NEED_LIST。
//   - 連線是 SQLcl MCP server 的全域單例（所有 session、所有 OpenCode 行程共用）：任何 session 的
//     connect／disconnect 嘗試都會推進「連線 epoch」（寫在 auto-loop-logs/ps-oracle-gate/connection-epoch.json，
//     跨行程可見）；session 的 READY 只在「完成前置時的 epoch ＝ 目前 epoch」才算數，否則視為共用連線已被
//     別的 session／視窗改動，退回 NEED_LIST、擋下並要求重做第 0 步。
//   - oracleMCP 掛載狀態每次即時查（不快取）——退讓與否是正確性判斷，不能用舊資料。
//   - 「每則訊息重置」只算真實 user 訊息：全部 part 都是 synthetic 的（背景 subagent 結果回灌、compaction
//     自動續行）不重置；turn 識別用該則 user 訊息 id（跨行程唯一）。
//
// 模式：enforce（預設）＝擋；observe＝只記錄不擋（做 hook 覆蓋率探測時用）。
//   環境變數 PS_ORACLE_GATE_MODE 優先，其次 customization-profile.yaml 的 oracle.preflightGate。
// 交易紀錄：<專案>/auto-loop-logs/ps-oracle-gate/<sessionID>.jsonl（只記 oracleMCP_*／task／訊息事件，
//   不記工具輸出原文）；plugin 載入紀錄在同目錄 _plugin.log。
//
// 零外部相依（只用 node:fs／node:path；公司網路封鎖 npm）。OpenCode 自動載入 .opencode/plugin/*.js。

import fs from "node:fs"
import path from "node:path"

const MCP_NAME = "oracleMCP"
const MCP_PREFIX = MCP_NAME + "_"
const TOOL_LIST = MCP_PREFIX + "list_connections"
const TOOL_CONNECT = MCP_PREFIX + "connect"
const TOOL_DISCONNECT = MCP_PREFIX + "disconnect"
const TOOL_RUN_SQL = MCP_PREFIX + "run_sql"
const TOOL_TASK = "task"
const ERROR_CODE = "PS_ORACLE_PREFLIGHT_REQUIRED"
const LOG_SUBDIR = path.join("auto-loop-logs", "ps-oracle-gate")
const PROFILE_REL = path.join(".opencode", "peoplesoft", "customization-profile.yaml")
const AGENT_DIR_REL = path.join(".opencode", "agent")
const EPOCH_FILE_NAME = "connection-epoch.json"
const ANCESTOR_MAX_DEPTH = 6

// connect／list_connections 回傳文字若命中以下樣式，視為「未成功」（狀態不前進）。
// 只列不可能出現在成功訊息裡的樣式；保守寬鬆——誤判成功的後果是既有的 NOT_CONNECTED 復原路徑，
// 誤判失敗的後果是閘門永遠不開，後者更糟。
const FAILURE_PATTERNS = [
  /\bORA-\d{5}\b/,
  /\bTNS-\d{5}\b/,
  /\bnot connected\b/i,
  /\bno (?:current |active )?connection\b/i,
  /\b(?:failed|unable) to connect\b/i,
  /\bconnection (?:failed|refused|timed out|error)\b/i,
  /\binvalid (?:username|password|connection)\b/i,
  /^\s*error\b/i,
]

function nowIso() {
  return new Date().toISOString()
}

function wildcardMatch(value, pattern) {
  const rx = "^" + pattern.split("*").map((s) => s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")).join(".*") + "$"
  return new RegExp(rx).test(value)
}

function frontmatterLines(text) {
  const lines = text.replace(/^\uFEFF/, "").split(/\r?\n/)
  if (lines[0] !== "---") return []
  const out = []
  for (let i = 1; i < lines.length; i++) {
    if (lines[i] === "---") return out
    out.push(lines[i])
  }
  return []
}

// tools 表 → 依檔案順序的 [key, enabled] 陣列（YAML 只需支援 `  key: true|false` 與 # 註解）
function parseToolsMap(lines) {
  const entries = []
  let inTools = false
  for (const raw of lines) {
    if (/^tools:\s*(#.*)?$/.test(raw)) {
      inTools = true
      continue
    }
    if (!inTools) continue
    if (raw.trim() === "" || raw.trim().startsWith("#")) continue
    if (!/^\s/.test(raw)) break
    const m = raw.match(/^\s+("?)([^"#:]+)\1\s*:\s*(true|false)\b/)
    if (!m) continue
    entries.push([m[2].trim(), m[3] === "true"])
  }
  return entries
}

function frontmatterValue(lines, key) {
  for (const raw of lines) {
    const m = raw.match(new RegExp("^" + key + ":\\s*([^#]+?)\\s*(#.*)?$"))
    if (m) return m[1].trim()
  }
  return undefined
}

// 最後匹配者優先；沒有任何規則匹配＝預設開（OpenCode tools 表是覆寫表）
function toolEnabled(entries, tool) {
  let enabled = true
  for (const [key, value] of entries) {
    if (wildcardMatch(tool, key)) enabled = value
  }
  return enabled
}

function loadAgentCatalog(directory) {
  const dir = path.join(directory, AGENT_DIR_REL)
  const catalog = new Map()
  let files = []
  try {
    files = fs.readdirSync(dir).filter((f) => f.endsWith(".md"))
  } catch {
    return catalog
  }
  for (const file of files) {
    try {
      const text = fs.readFileSync(path.join(dir, file), "utf8")
      const fm = frontmatterLines(text)
      const tools = parseToolsMap(fm)
      catalog.set(file.slice(0, -3), {
        mode: frontmatterValue(fm, "mode") ?? "all",
        db: toolEnabled(tools, TOOL_RUN_SQL),
      })
    } catch {
      // 讀不到的檔跳過；不在目錄裡的名字會被視為會查 DB（保守）
    }
  }
  return catalog
}

function readMode(directory) {
  const env = String(process.env.PS_ORACLE_GATE_MODE ?? "").trim().toLowerCase()
  if (env === "enforce" || env === "observe") return env
  try {
    const text = fs.readFileSync(path.join(directory, PROFILE_REL), "utf8").replace(/^\uFEFF/, "")
    const lines = text.split(/\r?\n/)
    let inOracle = false
    for (const raw of lines) {
      if (/^oracle:\s*(#.*)?$/.test(raw)) {
        inOracle = true
        continue
      }
      if (!inOracle) continue
      if (raw.trim() === "" || raw.trim().startsWith("#")) continue
      if (!/^\s/.test(raw)) break
      const m = raw.match(/^\s+preflightGate:\s*(enforce|observe)\b/i)
      if (m) return m[1].toLowerCase()
    }
  } catch {
    // 沒有 profile 或讀不到 → 預設 enforce
  }
  return "enforce"
}

function outputText(output) {
  if (typeof output === "string") return output
  if (!output || typeof output !== "object") return ""
  if (typeof output.output === "string") return output.output
  if (Array.isArray(output.content)) {
    return output.content
      .filter((c) => c && c.type === "text" && typeof c.text === "string")
      .map((c) => c.text)
      .join("\n")
  }
  return ""
}

function failureMatch(text) {
  for (const rx of FAILURE_PATTERNS) {
    if (rx.test(text)) return rx.source
  }
  return ""
}

function buildBlockMessage(target, state, blockedCount, reason) {
  const why = reason || "第 0 步尚未完成"
  const lines = [
    `${ERROR_CODE}：本次 task 未執行（被 Oracle 連線前置閘門擋下，不是權限問題）。` +
      `原因：${why}，不得委派會查 DB 的 subagent「${target}」。目前狀態＝${state}。`,
  ]
  if (state === "NEED_CONNECT") {
    lines.push(
      "下一步：list_connections 已完成，只差 oracleMCP_connect 成功——呼叫 oracleMCP_connect" +
        "（connection_name 取自清單：profile oracle.connectionName 有填且在清單裡就用它，否則清單第一個），" +
        "成功後再用相同參數重新呼叫本次 task。",
    )
  } else {
    lines.push(
      "下一步（依序）：1) oracleMCP_list_connections  2) oracleMCP_connect" +
        "（connection_name 取自清單：profile oracle.connectionName 有填且在清單裡就用它，否則清單第一個）。" +
        "兩者都成功後，再用相同參數重新呼叫本次 task。",
    )
  }
  if (blockedCount >= 3) {
    lines.push(
      `（本輪已被擋 ${blockedCount} 次。connect 若一直失敗，依第 0 步規則：本題不派 DB 委派，` +
        "向使用者回報「DB 連線建立失敗（<connect 回的錯誤>）」，其餘部分照常作答。）",
    )
  }
  return lines.join("\n")
}

export const PsOraclePreflightGate = async (input) => {
  const directory = String(input?.directory ?? process.cwd())
  const client = input?.client
  const logDir = path.join(directory, LOG_SUBDIR)
  const sessions = new Map()
  const parents = new Map()
  let catalog = loadAgentCatalog(directory)
  let catalogLoaded = Date.now()
  const epochFile = path.join(logDir, EPOCH_FILE_NAME)
  let epochCounter = 0
  let memEpoch = ""

  function ensureLogDir() {
    try {
      fs.mkdirSync(logDir, { recursive: true })
    } catch {
      // 記錄失敗不影響閘門
    }
  }

  function pluginLog(line) {
    try {
      ensureLogDir()
      fs.appendFileSync(path.join(logDir, "_plugin.log"), `${nowIso()} pid=${process.pid} ${line}\n`)
    } catch {
      // 忽略
    }
  }

  function record(sessionID, entry) {
    try {
      ensureLogDir()
      const safe = String(sessionID ?? "unknown").replace(/[^A-Za-z0-9_.-]/g, "_")
      fs.appendFileSync(
        path.join(logDir, `${safe}.jsonl`),
        JSON.stringify({ ts: nowIso(), pid: process.pid, sessionID, ...entry }) + "\n",
      )
    } catch {
      // 忽略
    }
  }

  // 全域連線 epoch：檔案為準（跨行程），讀不到才用本行程記憶
  function readEpoch() {
    try {
      const obj = JSON.parse(fs.readFileSync(epochFile, "utf8"))
      if (obj && typeof obj.epoch === "string" && obj.epoch) {
        memEpoch = obj.epoch
        return obj.epoch
      }
    } catch {
      // 沒有檔或壞掉 → 用記憶值（第一次為空字串）
    }
    return memEpoch
  }

  function bumpEpoch(sessionID, tool) {
    epochCounter += 1
    const token = `${Date.now()}-${process.pid}-${epochCounter}`
    memEpoch = token
    try {
      ensureLogDir()
      const tmp = epochFile + "." + process.pid + ".tmp"
      fs.writeFileSync(tmp, JSON.stringify({ epoch: token, ts: nowIso(), pid: process.pid, sessionID, tool }))
      fs.renameSync(tmp, epochFile)
    } catch {
      // 寫不進去：本行程仍以記憶值運作
    }
    return token
  }

  function getSession(sessionID) {
    let s = sessions.get(sessionID)
    if (!s) {
      s = { state: "NEED_LIST", agent: undefined, turn: 0, turnId: `${process.pid}-0`, blocked: 0, readyEpoch: undefined }
      sessions.set(sessionID, s)
    }
    return s
  }

  // READY 只在 epoch 沒被別人推進時算數；過期就退回 NEED_LIST（回傳過期說明）
  function readiness(s, epoch) {
    if (s.state !== "READY") return { ready: false }
    if (s.readyEpoch === epoch) return { ready: true }
    const stale = `shared connection changed since preflight (epoch ${s.readyEpoch} -> ${epoch})`
    s.state = "NEED_LIST"
    s.readyEpoch = undefined
    return { ready: false, stale }
  }

  function catalogFresh() {
    if (Date.now() - catalogLoaded > 60000) {
      catalog = loadAgentCatalog(directory)
      catalogLoaded = Date.now()
    }
    return catalog
  }

  // 目標 subagent 是否會查 DB（要不要過閘門）
  function classifyTarget(target) {
    const entry = catalogFresh().get(target)
    if (!entry) return { gated: true, basis: "unknown-agent(default:DB)" }
    return { gated: entry.db, basis: entry.db ? "run_sql:enabled" : "run_sql:disabled" }
  }

  // 每次即時查，不快取：退讓是正確性判斷
  async function oracleMounted() {
    try {
      const res = await client.mcp.status()
      const data = res && typeof res === "object" && "data" in res ? res.data : res
      const st = data && typeof data === "object" ? data[MCP_NAME] : undefined
      if (!st) return { mounted: false, basis: "mcp-status:absent" }
      return { mounted: st.status === "connected", basis: "mcp-status:" + String(st.status) }
    } catch (e) {
      return { mounted: undefined, basis: "mcp-status:unavailable(" + String(e && e.message ? e.message : e).slice(0, 80) + ")" }
    }
  }

  async function readyAncestor(sessionID, epoch) {
    let id = sessionID
    for (let depth = 0; depth < ANCESTOR_MAX_DEPTH; depth++) {
      let parent = parents.get(id)
      if (parent === undefined) {
        try {
          const res = await client.session.get({ path: { id } })
          const data = res && typeof res === "object" && "data" in res ? res.data : res
          parent = data && typeof data === "object" && typeof data.parentID === "string" ? data.parentID : null
        } catch {
          parent = null
        }
        parents.set(id, parent)
      }
      if (!parent) return undefined
      const ps = sessions.get(parent)
      if (ps && readiness(ps, epoch).ready) return parent
      id = parent
    }
    return undefined
  }

  pluginLog(
    `loaded directory=${directory} mode=${readMode(directory)} epochFile=${epochFile} agents=${JSON.stringify(
      [...catalog.entries()].map(([name, v]) => `${name}:${v.db ? "DB" : "noDB"}`),
    )}`,
  )

  return {
    "chat.message": async (msg, out) => {
      const sessionID = msg?.sessionID
      if (!sessionID) return
      const s = getSession(sessionID)
      if (msg.agent) s.agent = String(msg.agent)
      // 全部 part 都是 synthetic 的 user 訊息（背景 subagent 結果回灌、compaction 自動續行）不是新的一題：
      // OpenCode 自己也不把它當真實訊息（prompt.ts 對 title／summary 的判定同此），不重置狀態
      const parts = out && typeof out === "object" && Array.isArray(out.parts) ? out.parts : []
      const synthetic = parts.length > 0 && parts.every((p) => p && typeof p === "object" && p.synthetic === true)
      if (synthetic) {
        record(sessionID, { hook: "chat.message", agent: s.agent, turn: s.turn, turnId: s.turnId, state: s.state, next: s.state, synthetic: true, note: "all parts synthetic: no reset" })
        return
      }
      const prev = s.state
      s.state = "NEED_LIST"
      s.readyEpoch = undefined
      s.turn += 1
      // turn 識別用該則 user 訊息的 id（跨行程唯一；opencode run --session 續接是新行程，計數器會歸零）
      const mid = out && typeof out === "object" && out.message && typeof out.message.id === "string" ? out.message.id : msg.messageID
      s.turnId = typeof mid === "string" && mid ? mid : `${process.pid}-${s.turn}`
      s.blocked = 0
      record(sessionID, { hook: "chat.message", agent: s.agent, turn: s.turn, turnId: s.turnId, state: prev, next: s.state, mode: readMode(directory) })
    },

    "tool.execute.before": async (info, out) => {
      const tool = String(info?.tool ?? "")
      const sessionID = info?.sessionID
      const args = out && typeof out === "object" && out.args && typeof out.args === "object" ? out.args : {}
      if (tool !== TOOL_TASK) {
        if (tool.startsWith(MCP_PREFIX)) {
          const s = getSession(sessionID)
          // connect／disconnect 的「嘗試」就可能改動全域連線（含失敗的 connect）→ 先推進 epoch
          const epoch = tool === TOOL_CONNECT || tool === TOOL_DISCONNECT ? bumpEpoch(sessionID, tool) : undefined
          record(sessionID, { hook: "before", tool, agent: s.agent, turn: s.turn, turnId: s.turnId, state: s.state, decision: "observe", epoch })
        }
        return
      }
      const target = String(args.subagent_type ?? "")
      const s = getSession(sessionID)
      const mode = readMode(directory)
      const cls = classifyTarget(target)
      const epoch = readEpoch()
      const base = { hook: "before", tool, agent: s.agent, turn: s.turn, turnId: s.turnId, target, state: s.state, mode, basis: cls.basis, epoch }
      if (!cls.gated) {
        record(sessionID, { ...base, decision: "allow", note: "target does not query DB" })
        return
      }
      const rd = readiness(s, epoch)
      if (rd.ready) {
        record(sessionID, { ...base, decision: "allow" })
        return
      }
      const ancestor = await readyAncestor(sessionID, epoch)
      if (ancestor) {
        record(sessionID, { ...base, decision: "allow", note: "ancestor READY " + ancestor })
        return
      }
      const mcp = await oracleMounted()
      if (mcp.mounted === false) {
        record(sessionID, { ...base, state: s.state, decision: "allow", note: "gate stands down: " + mcp.basis + (rd.stale ? "; " + rd.stale : "") })
        return
      }
      s.blocked += 1
      const reason = rd.stale
        ? "你完成第 0 步之後，共用的 Oracle 連線已被其他 session／視窗的 connect 或 disconnect 改動過（連線是全域單例），必須重做第 0 步"
        : undefined
      const message = buildBlockMessage(target, s.state, s.blocked, reason)
      const note = [mcp.basis, rd.stale].filter(Boolean).join("; ")
      if (mode === "observe") {
        record(sessionID, { ...base, state: s.state, decision: "observe-would-block", blocked: s.blocked, note })
        return
      }
      record(sessionID, { ...base, state: s.state, decision: "block", blocked: s.blocked, note })
      throw new Error(message)
    },

    "tool.execute.after": async (info, out) => {
      const tool = String(info?.tool ?? "")
      const sessionID = info?.sessionID
      if (tool !== TOOL_TASK && !tool.startsWith(MCP_PREFIX)) return
      const s = getSession(sessionID)
      const text = outputText(out)
      const prev = s.state
      const base = { hook: "after", tool, agent: s.agent, turn: s.turn, turnId: s.turnId, state: prev, outputLength: text.length }
      if (tool === TOOL_LIST) {
        const fail = failureMatch(text)
        if (!fail && s.state === "NEED_LIST") s.state = "NEED_CONNECT"
        record(sessionID, { ...base, next: s.state, ok: !fail, failureMatch: fail || undefined })
        return
      }
      if (tool === TOOL_CONNECT) {
        const fail = failureMatch(text)
        const epoch = readEpoch()
        let note
        if (!fail && (s.state === "NEED_CONNECT" || s.state === "READY")) {
          s.state = "READY"
          s.readyEpoch = epoch
        } else if (!fail && s.state === "NEED_LIST") {
          note = "connect before list_connections: list still required"
        }
        record(sessionID, { ...base, next: s.state, ok: !fail, failureMatch: fail || undefined, epoch, note })
        return
      }
      if (tool === TOOL_DISCONNECT) {
        s.state = "NEED_LIST"
        s.readyEpoch = undefined
        record(sessionID, { ...base, next: s.state, epoch: readEpoch(), note: "disconnect in this session" })
        return
      }
      if (tool === TOOL_TASK) {
        const args = info && typeof info.args === "object" && info.args ? info.args : {}
        const target = String(args.subagent_type ?? "")
        const cls = classifyTarget(target)
        const notConnected = /"blockedReason"\s*:\s*"NOT_CONNECTED"/.test(text)
        let note
        if (cls.gated && notConnected && s.state === "READY") {
          s.state = "NEED_CONNECT"
          s.readyEpoch = undefined
          note = "subagent reported NOT_CONNECTED: connect again before re-dispatch"
        }
        record(sessionID, { ...base, target, executed: true, basis: cls.basis, next: s.state, notConnected, note })
        return
      }
      record(sessionID, { ...base, next: s.state })
    },
  }
}

// ps-oracle-preflight-gate.js — Oracle 連線前置（第 0 步）的確定性閘門（OpenCode plugin）
//
// 不變量（與主 agent 第 0 步一致；每一則真實使用者訊息各自成立）：
//   NEED_LIST ─ list_connections 成功 ─▶ NEED_CONNECT ─ connect 成功 ─▶ READY ─▶ 才准執行「會查 DB 的 subagent」委派（task）
// 未 READY 就派會查 DB 的 subagent → 該 task 在執行前被擋（throw），模型收到 PS_ORACLE_PREFLIGHT_REQUIRED 與下一步指示，
// 做完前置再用相同參數重派。模型選錯順序不會變成錯誤的執行。閘門只擋、不改參數、不代模型 connect。
//
// 唯一的例外：目標 subagent 確定沒有 Oracle 能力（.opencode/agent/*.md 的 tools 表對 oracleMCP_run_sql 最後匹配為 false；
//   OpenCode 規則：最後匹配者優先、沒列＝預設開）→ 不需要 READY。判定依據是「能力」不是任務意圖：ps-auditor 即使做純 chunk
//   任務也要過閘門；不在 agent 目錄的名字一律視為會查 DB（保守）。
// 環境層的退讓：oracleMCP 未掛載（/mcp 狀態非 connected；每次即時查、不快取）＝整個環境沒有 Oracle 能力（主 agent 沒有
//   list／connect 可呼叫、subagent 沒有 run_sql），閘門退讓並記錄，交 subagent 的 ORACLE_MCP_DOWN 協定；狀態查不到 → 保守仍擋。
// 沒有其他退讓：connect／list 一直失敗仍擋（第 0 步規則：本題不派 DB 委派、其餘照常作答）；不跨 session、不跨行程協調
//   （共用連線的防護待 topology 實驗定案後另案設計，見 SOP-21）。
//
// 狀態以 session 為單位：
//   - 每則「真實」使用者訊息重置為 NEED_LIST（第 0 步「不因上一題已連過就省略」）；turnId＝該則 user 訊息 id（跨行程唯一）。
//     全部 part 都是 synthetic 的訊息（背景 subagent 結果回灌、compaction 續行）與同一 id 重複到達不重置。
//   - subagent 報告 blockedReason=NOT_CONNECTED → 退回 NEED_CONNECT（重派前必須再 connect 一次）。
//   - 本 session 呼叫 oracleMCP_disconnect → 退回 NEED_LIST。
//   - task 入場（before）時快照 turn／turnId／state，after 列用快照（使用者在 task 執行中送下一題時該 task 不會被錯標到新題）。
//
// 模式：enforce（預設）＝擋；observe＝只記錄不擋（做 hook 覆蓋率探測時用）。
//   環境變數 PS_ORACLE_GATE_MODE 優先，其次 customization-profile.yaml 的 oracle.preflightGate。
// 交易紀錄：<專案>/auto-loop-logs/ps-oracle-gate/<sessionID>.jsonl（只記 oracleMCP_*／task／訊息事件，不記工具輸出原文）；
//   plugin 載入紀錄在同目錄 _plugin.log。
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
const ADMITTED_MAX = 500

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

function buildBlockMessage(target, state, blockedCount) {
  const lines = [
    `${ERROR_CODE}：本次 task 未執行（被 Oracle 連線前置閘門擋下，不是權限問題）。` +
      `原因：第 0 步尚未完成，不得委派會查 DB 的 subagent「${target}」。目前狀態＝${state}。`,
  ]
  if (state === "NEED_CONNECT") {
    lines.push(
      "下一步：list_connections 已完成，只差 oracleMCP_connect 成功——呼叫 oracleMCP_connect" +
        "（connection_name 取自清單：profile oracle.connectionName 有填且在清單裡就用它，否則清單第一個），" +
        "成功後再用相同參數重新呼叫本次 task。connect 與 task 要依序分開呼叫，不要同一步並行。",
    )
  } else {
    lines.push(
      "下一步（依序）：1) oracleMCP_list_connections  2) oracleMCP_connect" +
        "（connection_name 取自清單：profile oracle.connectionName 有填且在清單裡就用它，否則清單第一個）。" +
        "兩者都成功後，再用相同參數重新呼叫本次 task。三個呼叫要依序分開，不要同一步並行。",
    )
  }
  if (blockedCount >= 3) {
    lines.push(
      `（本輪已被擋 ${blockedCount} 次。list_connections／connect 若一直失敗，依第 0 步規則：本題不派 DB 委派，` +
        "向使用者回報「DB 連線建立失敗（<connect 回的錯誤>）」；工具清單裡根本沒有 oracleMCP_ 工具則回報 ORACLE_MCP_DOWN。其餘部分照常作答。）",
    )
  }
  return lines.join("\n")
}

export const PsOraclePreflightGate = async (input) => {
  const directory = String(input?.directory ?? process.cwd())
  const client = input?.client
  const logDir = path.join(directory, LOG_SUBDIR)
  const sessions = new Map()
  // task 入場時（before）的快照，after 列用它標 turn／state（鍵＝session:callID；OpenAI 相容端點的 call_0 這種 id 會跨 session 重複）
  const admitted = new Map()
  let catalog = loadAgentCatalog(directory)
  let catalogLoaded = Date.now()

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

  function getSession(sessionID) {
    let s = sessions.get(sessionID)
    if (!s) {
      s = { state: "NEED_LIST", agent: undefined, turn: 0, turnId: `${process.pid}-0`, blocked: 0 }
      sessions.set(sessionID, s)
    }
    return s
  }

  function keyOf(sessionID, callID) {
    return `${sessionID}:${callID}`
  }

  function stamp(s) {
    return { agent: s.agent, turn: s.turn, turnId: s.turnId }
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

  // 每次即時查、不快取：退讓是正確性判斷，不能用舊資料。查不到（例外或非 2xx）→ mounted=undefined＝保守擋
  async function oracleMounted() {
    try {
      const res = await client.mcp.status()
      if (res && typeof res === "object" && res.error) {
        const status = res.response && typeof res.response === "object" ? res.response.status : "?"
        return { mounted: undefined, basis: `mcp-status:error(${status})` }
      }
      const data = res && typeof res === "object" && "data" in res ? res.data : res
      const st = data && typeof data === "object" ? data[MCP_NAME] : undefined
      if (!st) return { mounted: false, basis: "mcp-status:absent" }
      return { mounted: st.status === "connected", basis: "mcp-status:" + String(st.status) }
    } catch (e) {
      return { mounted: undefined, basis: "mcp-status:unavailable(" + String(e && e.message ? e.message : e).slice(0, 80) + ")" }
    }
  }

  pluginLog(
    `loaded directory=${directory} mode=${readMode(directory)} agents=${JSON.stringify(
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
      // OpenCode 自己也不把它當真實訊息（prompt.ts 對 title 的判定同此），不重置狀態
      const parts = out && typeof out === "object" && Array.isArray(out.parts) ? out.parts : []
      const synthetic = parts.length > 0 && parts.every((p) => p && typeof p === "object" && p.synthetic === true)
      if (synthetic) {
        record(sessionID, { hook: "chat.message", ...stamp(s), state: s.state, next: s.state, synthetic: true, note: "all parts synthetic: no reset" })
        return
      }
      // turn 識別用該則 user 訊息的 id（跨行程唯一；opencode run --session 續接是新行程，計數器會歸零）
      const mid = out && typeof out === "object" && out.message && typeof out.message.id === "string" ? out.message.id : msg.messageID
      if (typeof mid === "string" && mid && mid === s.turnId) {
        record(sessionID, { hook: "chat.message", ...stamp(s), state: s.state, next: s.state, note: "same message id: no reset" })
        return
      }
      const prev = s.state
      s.state = "NEED_LIST"
      s.turn += 1
      s.turnId = typeof mid === "string" && mid ? mid : `${process.pid}-${s.turn}`
      s.blocked = 0
      record(sessionID, { hook: "chat.message", ...stamp(s), state: prev, next: s.state, mode: readMode(directory) })
    },

    "tool.execute.before": async (info, out) => {
      const tool = String(info?.tool ?? "")
      const sessionID = info?.sessionID
      const callID = String(info?.callID ?? "")
      const args = out && typeof out === "object" && out.args && typeof out.args === "object" ? out.args : {}
      if (tool !== TOOL_TASK) {
        if (tool.startsWith(MCP_PREFIX)) {
          const s = getSession(sessionID)
          record(sessionID, { hook: "before", tool, callID, ...stamp(s), state: s.state, decision: "observe" })
        }
        return
      }
      const target = String(args.subagent_type ?? "")
      const s = getSession(sessionID)
      const mode = readMode(directory)
      const cls = classifyTarget(target)
      const base = { hook: "before", tool, callID, ...stamp(s), target, state: s.state, mode, basis: cls.basis }
      const admit = (decision) => {
        if (callID) admitted.set(keyOf(sessionID, callID), { turn: s.turn, turnId: s.turnId, state: s.state, decision })
        if (admitted.size > ADMITTED_MAX) admitted.delete(admitted.keys().next().value)
      }
      if (!cls.gated) {
        admit("allow")
        record(sessionID, { ...base, decision: "allow", note: "target does not query DB" })
        return
      }
      if (s.state === "READY") {
        admit("allow")
        record(sessionID, { ...base, decision: "allow" })
        return
      }
      const mcp = await oracleMounted()
      // await 期間狀態可能已變（同一步並行的 connect 已完成）：再判一次
      if (s.state === "READY") {
        admit("allow")
        record(sessionID, { ...base, state: s.state, decision: "allow", note: "became READY during status check" })
        return
      }
      if (mcp.mounted === false) {
        admit("allow")
        record(sessionID, { ...base, decision: "allow", note: "gate stands down: " + mcp.basis })
        return
      }
      s.blocked += 1
      const message = buildBlockMessage(target, s.state, s.blocked)
      if (mode === "observe") {
        admit("observe-would-block")
        record(sessionID, { ...base, decision: "observe-would-block", blocked: s.blocked, note: mcp.basis })
        return
      }
      record(sessionID, { ...base, decision: "block", blocked: s.blocked, note: mcp.basis })
      throw new Error(message)
    },

    "tool.execute.after": async (info, out) => {
      const tool = String(info?.tool ?? "")
      const sessionID = info?.sessionID
      if (tool !== TOOL_TASK && !tool.startsWith(MCP_PREFIX)) return
      const callID = String(info?.callID ?? "")
      const s = getSession(sessionID)
      const text = outputText(out)
      const prev = s.state
      const base = { hook: "after", tool, callID, ...stamp(s), state: prev, outputLength: text.length }
      if (tool === TOOL_LIST) {
        const fail = failureMatch(text)
        if (!fail && s.state === "NEED_LIST") s.state = "NEED_CONNECT"
        record(sessionID, { ...base, next: s.state, ok: !fail, failureMatch: fail || undefined })
        return
      }
      if (tool === TOOL_CONNECT) {
        const fail = failureMatch(text)
        let note
        if (!fail && s.state === "NEED_CONNECT") s.state = "READY"
        else if (!fail && s.state === "NEED_LIST") note = "connect before list_connections: list still required"
        record(sessionID, { ...base, next: s.state, ok: !fail, failureMatch: fail || undefined, note })
        return
      }
      if (tool === TOOL_DISCONNECT) {
        s.state = "NEED_LIST"
        record(sessionID, { ...base, next: s.state, note: "disconnect in this session" })
        return
      }
      if (tool === TOOL_TASK) {
        const args = info && typeof info.args === "object" && info.args ? info.args : {}
        const target = String(args.subagent_type ?? "")
        const cls = classifyTarget(target)
        const notConnected = /"blockedReason"\s*:\s*"NOT_CONNECTED"/.test(text)
        const k = keyOf(sessionID, callID)
        const adm = callID ? admitted.get(k) : undefined
        if (callID) admitted.delete(k)
        let note
        if (cls.gated && notConnected && s.state === "READY") {
          s.state = "NEED_CONNECT"
          note = "subagent reported NOT_CONNECTED: connect again before re-dispatch"
        }
        // turn／state 用入場時的快照（使用者在 task 執行中送下一題，狀態已被重置，但這個 task 屬於前一題）
        const stamped = adm ? { turn: adm.turn, turnId: adm.turnId, state: adm.state, admitted: adm.decision } : { admitted: "unknown" }
        record(sessionID, { ...base, ...stamped, target, executed: true, basis: cls.basis, next: s.state, notConnected, note })
        return
      }
      record(sessionID, { ...base, next: s.state })
    },
  }
}

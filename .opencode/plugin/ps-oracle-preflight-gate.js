// ps-oracle-preflight-gate.js — Oracle 連線前置（第 0 步）的確定性閘門（OpenCode plugin）
//
// 規則（與主 agent 第 0 步一致）：主 agent 在同一則使用者訊息內，未依序完成
//   oracleMCP_list_connections（成功）→ oracleMCP_connect（成功）
// 之前，任何「會查 DB 的 subagent」委派（task 工具）都在執行前被擋下，模型收到
//   PS_ORACLE_PREFLIGHT_REQUIRED
// 的工具錯誤並被告知下一步；模型選錯順序不會變成錯誤的執行。閘門只擋順序、不改參數、不代模型 connect。
//
// 判準：
//   - 會查 DB 的 subagent＝.opencode/agent/*.md 的 tools 表對 oracleMCP_run_sql 為開
//     （OpenCode 規則：最後匹配者優先；沒列＝預設開）。不在 agent 目錄的名字一律視為會查 DB（保守）。
//     這是「能力」判定：oracleMCP_* 全關的 subagent 不受影響；ps-auditor 即使做純 chunk 任務也過閘門。
//   - 狀態以 session 為單位，每則真實使用者訊息重置為 NEED_LIST（第 0 步「不因上一題已連過就省略」）；
//     全部 part 都是 synthetic 的訊息（背景 subagent 結果回灌、compaction 自動續行）不重置；
//     turn 識別用該則 user 訊息 id（跨行程唯一）。
//   - 連線是 SQLcl MCP server 的全域單例（所有 session、所有 OpenCode 視窗共用）。共用狀態以「連線名」為身分，
//     寫在 auto-loop-logs/ps-oracle-gate/connection-state.json（跨行程可見）：換名 connect 或 disconnect 才會作廢
//     別的 session 的 READY；同名重連（每題第 0 步的常態）不作廢任何人。作廢時退回 NEED_CONNECT（list 仍有效），
//     擋下並告知目前連線是誰改的、只需再 connect 一次。connect 完成時核對共用狀態仍是自己的連線名——
//     兩個 session 交錯 connect 不同名時，只有最後起跑的那個算 READY。
//   - subagent 報告 blockedReason=NOT_CONNECTED → 狀態退回 NEED_CONNECT（重派前必須再 connect 一次）。
//   - 本 session 呼叫 oracleMCP_disconnect → 狀態退回 NEED_LIST。
//   - 只擋順序、不擋可用性（退讓＝放行並記 note）：oracleMCP 未掛載（/mcp 狀態非 connected，每次即時查不快取）；
//     同一題內 list 成功後 connect 嘗試 ≥ 2 次零成功；list 嘗試 ≥ 2 次零成功；command 驅動的 subtask
//     （OpenCode 在 prompt 迴圈直接派、模型沒有機會做前置）。退讓後交 subagent 的 ORACLE_MCP_DOWN／NOT_CONNECTED 協定。
//
// 模式：enforce（預設）＝擋；observe＝只記錄不擋（做 hook 覆蓋率探測時用）。
//   環境變數 PS_ORACLE_GATE_MODE 優先，其次 customization-profile.yaml 的 oracle.preflightGate。
// 交易紀錄：<專案>/auto-loop-logs/ps-oracle-gate/<sessionID>.jsonl（只記 list／connect／disconnect／task／訊息事件，
//   不記工具輸出原文；純 subagent 的 session 不建檔）；plugin 載入與異常記在同目錄 _plugin.log。
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
const STATE_FILE_NAME = "connection-state.json"
const ANCESTOR_MAX_DEPTH = 6
const DISCONNECTED = null

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
// SQLcl 對「已連線再 connect」若回 isError（after hook 不會觸發），這種文字視為成功
const ALREADY_CONNECTED = /already connected/i

function nowIso() {
  return new Date().toISOString()
}

function wildcardMatch(value, pattern) {
  const rx = "^" + pattern.split("*").map((s) => s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")).join(".*") + "$"
  return new RegExp(rx).test(value)
}

function frontmatterLines(text) {
  const lines = text.replace(/^﻿/, "").split(/\r?\n/)
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
        task: toolEnabled(tools, TOOL_TASK),
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
    const text = fs.readFileSync(path.join(directory, PROFILE_REL), "utf8").replace(/^﻿/, "")
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

function connectionNameOf(args) {
  if (!args || typeof args !== "object") return "(unnamed)"
  for (const k of ["connection_name", "connectionName", "name", "connection"]) {
    if (typeof args[k] === "string" && args[k].trim()) return args[k].trim()
  }
  return "(unnamed)"
}

function describeBy(by) {
  if (!by || typeof by !== "object") return "unknown source"
  return `${by.tool ?? "?"} by session ${by.sessionID ?? "?"} pid ${by.pid ?? "?"}`
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
        "成功後再用相同參數重新呼叫本次 task。list_connections、connect、task 要依序分開呼叫，不要同一步並行。",
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
  const stateFile = path.join(logDir, STATE_FILE_NAME)
  const sessions = new Map()
  const parents = new Map()
  // task 入場時（before）的快照，after 列用它標 turn／state——使用者在 task 執行中送下一題時，after 列才不會被錯標到新 turn
  const admitted = new Map()
  const seenConnectErrors = new Set()
  let catalog = loadAgentCatalog(directory)
  let catalogLoaded = Date.now()
  // 共用連線狀態的本行程記憶（檔案讀不到或寫不進去時的後盾）
  let memState = { name: undefined, changed: "", by: undefined }
  let fileTrusted = true
  let changeCounter = 0

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

  // 共用連線狀態：檔案為準（跨行程）；本行程上次寫檔失敗時以記憶為準（避免拿舊檔跟自己的記憶比出假衝突）
  function readState() {
    if (!fileTrusted) return memState
    for (let attempt = 0; attempt < 2; attempt++) {
      try {
        const obj = JSON.parse(fs.readFileSync(stateFile, "utf8"))
        if (obj && typeof obj === "object" && "name" in obj) {
          memState = { name: obj.name === null ? DISCONNECTED : typeof obj.name === "string" ? obj.name : undefined, changed: String(obj.changed ?? ""), by: obj.by }
          return memState
        }
        break
      } catch (e) {
        if (e && e.code === "ENOENT") break
        // 壞掉／讀到一半 → 再讀一次
      }
    }
    return memState
  }

  function writeState(name, sessionID, tool) {
    changeCounter += 1
    const changed = `${Date.now()}-${process.pid}-${changeCounter}`
    const by = { tool, sessionID, pid: process.pid }
    memState = { name, changed, by }
    let written = false
    let lastErr = ""
    const tmp = stateFile + "." + process.pid + ".tmp"
    for (let attempt = 0; attempt < 3 && !written; attempt++) {
      try {
        ensureLogDir()
        fs.writeFileSync(tmp, JSON.stringify({ name, changed, ts: nowIso(), by }))
        fs.renameSync(tmp, stateFile)
        written = true
      } catch (e) {
        lastErr = String(e && e.code ? e.code : e)
      }
    }
    if (!written) {
      try {
        fs.rmSync(tmp, { force: true })
      } catch {
        // 忽略
      }
      fileTrusted = false
      pluginLog(`connection-state write failed (${lastErr}) session=${sessionID} tool=${tool}: this process now trusts its in-memory state only`)
    } else {
      fileTrusted = true
    }
    return { changed, written, error: written ? undefined : lastErr }
  }

  function getSession(sessionID) {
    let s = sessions.get(sessionID)
    if (!s) {
      s = {
        state: "NEED_LIST",
        agent: undefined,
        turn: 0,
        turnId: `${process.pid}-0`,
        blocked: 0,
        staleBlocks: 0,
        readyName: undefined,
        pending: undefined,
        listAttempts: 0,
        listSuccesses: 0,
        connectAttempts: 0,
        connectSuccesses: 0,
      }
      sessions.set(sessionID, s)
    }
    return s
  }

  function keyOf(sessionID, callID) {
    return `${sessionID}:${callID}`
  }

  // 純判斷、不改狀態：READY 只在共用連線仍是自己那條時算數
  function readiness(s, st) {
    if (s.state !== "READY") return { ready: false }
    if (st.name !== undefined && st.name !== DISCONNECTED && st.name === s.readyName) return { ready: true }
    const now = st.name === DISCONNECTED ? "none (disconnected)" : st.name === undefined ? "unknown" : `"${st.name}"`
    return { ready: false, stale: `shared connection changed since preflight (now ${now}, expected "${s.readyName}"; ${describeBy(st.by)})` }
  }

  function applyStale(s) {
    s.state = "NEED_CONNECT"
    s.readyName = undefined
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

  // 純 subagent（mode subagent 且不能 task）的 session 不建交易紀錄檔
  function recordsFor(agentName) {
    if (!agentName) return true
    const entry = catalogFresh().get(agentName)
    if (!entry) return true
    return entry.mode !== "subagent" || entry.task
  }

  // 每次即時查，不快取：退讓是正確性判斷。查不到（例外或非 2xx）→ undefined＝保守擋
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

  // 只讀：祖先 session 是否 READY（subagent_depth > 1 時子 session 派 task 才會用到）；不改祖先狀態
  async function readyAncestor(sessionID, st) {
    let id = sessionID
    for (let depth = 0; depth < ANCESTOR_MAX_DEPTH; depth++) {
      let parent = parents.get(id)
      if (parent === undefined) {
        try {
          const res = await client.session.get({ path: { id } })
          const data = res && typeof res === "object" && "data" in res ? res.data : res
          if (data && typeof data === "object") {
            parent = typeof data.parentID === "string" ? data.parentID : null
            parents.set(id, parent)
          } else {
            parent = null
          }
        } catch {
          parent = null
        }
      }
      if (!parent) return undefined
      const ps = sessions.get(parent)
      if (ps && readiness(ps, st).ready) return parent
      id = parent
    }
    return undefined
  }

  function connectSucceeded(s, sessionID, callID, name) {
    const p = s.pending && s.pending.key === keyOf(sessionID, callID) ? s.pending : undefined
    s.pending = undefined
    const st = readState()
    if (s.state === "NEED_LIST") return { note: "connect before list_connections: list still required" }
    if (p && fileTrusted && st.changed !== p.token && st.name !== name) {
      // 我起跑後又有人 connect 到別的名字或 disconnect：伺服器上的目前連線不是我的
      applyStale(s)
      return { note: `another connect/disconnect interleaved with yours (now ${st.name === DISCONNECTED ? "none" : JSON.stringify(st.name)}; ${describeBy(st.by)}): connect again` }
    }
    // 成功的 connect 證明伺服器目前連線就是這個名字：共用狀態若還沒反映（例如 before 沒寫到）就補寫
    if (st.name !== name) writeState(name, sessionID, TOOL_CONNECT)
    s.state = "READY"
    s.readyName = name
    s.connectSuccesses += 1
    return { note: fileTrusted ? undefined : "connection-state file not writable: READY on in-memory state" }
  }

  pluginLog(
    `loaded directory=${directory} mode=${readMode(directory)} stateFile=${stateFile} agents=${JSON.stringify(
      [...catalog.entries()].map(([name, v]) => `${name}:${v.db ? "DB" : "noDB"}${v.task ? "+task" : ""}`),
    )}`,
  )

  return {
    event: async ({ event }) => {
      try {
        if (!event || typeof event !== "object") return
        if (event.type === "session.deleted") {
          const id = event.properties && event.properties.info ? event.properties.info.id : undefined
          if (id) {
            sessions.delete(id)
            parents.delete(id)
          }
          return
        }
        if (event.type !== "message.part.updated") return
        const part = event.properties ? event.properties.part : undefined
        if (!part || part.type !== "tool" || part.tool !== TOOL_CONNECT || !part.state || part.state.status !== "error") return
        const k = keyOf(part.sessionID, part.callID)
        if (seenConnectErrors.has(k)) return
        seenConnectErrors.add(k)
        if (seenConnectErrors.size > 500) seenConnectErrors.delete(seenConnectErrors.values().next().value)
        const s = getSession(part.sessionID)
        const err = String(part.state.error ?? "")
        const name = connectionNameOf(part.state.input)
        const base = { hook: "after", tool: TOOL_CONNECT, callID: part.callID, agent: s.agent, turn: s.turn, turnId: s.turnId, state: s.state, viaEvent: true }
        if (ALREADY_CONNECTED.test(err)) {
          // SQLcl 對已連線再 connect 回 isError 的「already connected」：視為成功（第 0 步規則）
          const r = connectSucceeded(s, part.sessionID, part.callID, name)
          record(part.sessionID, { ...base, next: s.state, ok: true, failureMatch: undefined, note: "isError but already connected: treated as success" + (r.note ? "; " + r.note : "") })
          return
        }
        s.pending = undefined
        record(part.sessionID, { ...base, next: s.state, ok: false, failureMatch: "isError", errorLength: err.length })
      } catch {
        // 事件處理失敗不影響閘門
      }
    },

    "chat.message": async (msg, out) => {
      const sessionID = msg?.sessionID
      if (!sessionID) return
      const s = getSession(sessionID)
      if (msg.agent) s.agent = String(msg.agent)
      const keep = recordsFor(s.agent)
      // 全部 part 都是 synthetic 的 user 訊息（背景 subagent 結果回灌、compaction 自動續行）不是新的一題：
      // OpenCode 自己也不把它當真實訊息（prompt.ts 對 title／summary 的判定同此），不重置狀態
      const parts = out && typeof out === "object" && Array.isArray(out.parts) ? out.parts : []
      const synthetic = parts.length > 0 && parts.every((p) => p && typeof p === "object" && p.synthetic === true)
      if (synthetic) {
        if (keep) record(sessionID, { hook: "chat.message", agent: s.agent, turn: s.turn, turnId: s.turnId, state: s.state, next: s.state, synthetic: true, note: "all parts synthetic: no reset" })
        return
      }
      // turn 識別用該則 user 訊息的 id（跨行程唯一；opencode run --session 續接是新行程，計數器會歸零）
      const mid = out && typeof out === "object" && out.message && typeof out.message.id === "string" ? out.message.id : msg.messageID
      if (typeof mid === "string" && mid && mid === s.turnId) {
        if (keep) record(sessionID, { hook: "chat.message", agent: s.agent, turn: s.turn, turnId: s.turnId, state: s.state, next: s.state, note: "same message id: no reset" })
        return
      }
      const prev = s.state
      s.state = "NEED_LIST"
      s.readyName = undefined
      s.pending = undefined
      s.turn += 1
      s.turnId = typeof mid === "string" && mid ? mid : `${process.pid}-${s.turn}`
      s.blocked = 0
      s.staleBlocks = 0
      s.listAttempts = 0
      s.listSuccesses = 0
      s.connectAttempts = 0
      s.connectSuccesses = 0
      if (keep) record(sessionID, { hook: "chat.message", agent: s.agent, turn: s.turn, turnId: s.turnId, state: prev, next: s.state, mode: readMode(directory) })
    },

    "tool.execute.before": async (info, out) => {
      const tool = String(info?.tool ?? "")
      const sessionID = info?.sessionID
      const args = out && typeof out === "object" && out.args && typeof out.args === "object" ? out.args : {}
      const callID = String(info?.callID ?? "")
      if (tool !== TOOL_TASK) {
        if (tool === TOOL_LIST || tool === TOOL_CONNECT || tool === TOOL_DISCONNECT) {
          const s = getSession(sessionID)
          let stateWrite
          let name
          if (tool === TOOL_LIST) s.listAttempts += 1
          if (tool === TOOL_CONNECT) {
            // 「嘗試」就可能改動全域連線（含失敗的 connect）：換名才寫共用狀態（同名重連不作廢任何人）
            name = connectionNameOf(args)
            s.connectAttempts += 1
            const st = readState()
            if (st.name !== name) stateWrite = writeState(name, sessionID, tool)
            // token＝我起跑時共用狀態的版本（自己寫的或當時檔上的）；after 用它判斷中途有沒有人再改
            s.pending = { key: keyOf(sessionID, callID), name, token: stateWrite ? stateWrite.changed : st.changed }
          }
          if (tool === TOOL_DISCONNECT) stateWrite = writeState(DISCONNECTED, sessionID, tool)
          record(sessionID, {
            hook: "before", tool, callID, agent: s.agent, turn: s.turn, turnId: s.turnId, state: s.state, decision: "observe",
            connection: name, stateChanged: stateWrite ? stateWrite.changed : undefined, stateWriteError: stateWrite ? stateWrite.error : undefined,
          })
        }
        return
      }
      const target = String(args.subagent_type ?? "")
      const s = getSession(sessionID)
      const mode = readMode(directory)
      const cls = classifyTarget(target)
      const st = readState()
      const base = { hook: "before", tool, callID, agent: s.agent, turn: s.turn, turnId: s.turnId, target, state: s.state, mode, basis: cls.basis, connection: st.name === DISCONNECTED ? null : st.name }
      const admit = (decision) => {
        if (callID) admitted.set(keyOf(sessionID, callID), { turnId: s.turnId, turn: s.turn, state: s.state, decision })
        if (admitted.size > 500) admitted.delete(admitted.keys().next().value)
      }
      if (!cls.gated) {
        admit("allow")
        record(sessionID, { ...base, decision: "allow", note: "target does not query DB" })
        return
      }
      let rd = readiness(s, st)
      if (rd.ready) {
        admit("allow")
        record(sessionID, { ...base, decision: "allow" })
        return
      }
      // command 驅動的 subtask（OpenCode 在 prompt 迴圈直接派，part id 當 callID）：throw 會殺掉整個 prompt、模型沒機會做前置 → 退讓
      if (/^prt_/.test(callID)) {
        admit("allow")
        record(sessionID, { ...base, decision: "allow", note: "gate stands down: command-driven subtask (model cannot preflight)" + (rd.stale ? "; " + rd.stale : "") })
        return
      }
      const ancestor = await readyAncestor(sessionID, st)
      if (ancestor) {
        admit("allow")
        record(sessionID, { ...base, decision: "allow", note: "ancestor READY " + ancestor })
        return
      }
      const mcp = await oracleMounted()
      // 兩個 await 期間狀態可能已變（同一步並行的 connect 已完成）：再判一次
      const st2 = readState()
      rd = readiness(s, st2)
      if (rd.ready) {
        admit("allow")
        record(sessionID, { ...base, state: s.state, connection: st2.name === DISCONNECTED ? null : st2.name, decision: "allow", note: "became READY during checks" })
        return
      }
      if (rd.stale) applyStale(s)
      if (mcp.mounted === false) {
        admit("allow")
        record(sessionID, { ...base, state: s.state, decision: "allow", note: "gate stands down: " + mcp.basis + (rd.stale ? "; " + rd.stale : "") })
        return
      }
      // 第 0 步已誠實做過但連不上／列不出來（含「再試一次」）：只擋順序、不擋可用性 → 退讓
      if (s.state === "NEED_CONNECT" && s.connectAttempts >= 2 && s.connectSuccesses === 0) {
        admit("allow")
        record(sessionID, { ...base, state: s.state, decision: "allow", note: `gate stands down: connect failed x${s.connectAttempts} after list_connections (subagent NOT_CONNECTED protocol applies)` })
        return
      }
      if (s.state === "NEED_LIST" && s.listAttempts >= 2 && s.listSuccesses === 0) {
        admit("allow")
        record(sessionID, { ...base, state: s.state, decision: "allow", note: `gate stands down: list_connections failed x${s.listAttempts} (subagent NOT_CONNECTED/ORACLE_MCP_DOWN protocol applies)` })
        return
      }
      let reason
      if (rd.stale) {
        s.staleBlocks += 1
        const now = st2.name === DISCONNECTED ? "已被 disconnect（目前沒有連線）" : st2.name === undefined ? "狀態不明" : `目前是「${st2.name}」`
        reason = `你完成第 0 步之後，共用的 Oracle 連線已被改動過（${now}；改動者：${describeBy(st2.by)}；連線是全域單例），你的前置連的是「${s.readyName ?? "?"}」——請再呼叫 oracleMCP_connect（connection_name＝你原本的連線名）後重派，不必重做 list`
      } else {
        s.blocked += 1
      }
      const message = buildBlockMessage(target, s.state, s.blocked, reason)
      const note = [mcp.basis, rd.stale].filter(Boolean).join("; ")
      if (mode === "observe") {
        admit("observe-would-block")
        record(sessionID, { ...base, state: s.state, decision: "observe-would-block", blocked: s.blocked, staleBlocks: s.staleBlocks, note })
        return
      }
      record(sessionID, { ...base, state: s.state, decision: "block", blocked: s.blocked, staleBlocks: s.staleBlocks, note })
      throw new Error(message)
    },

    "tool.execute.after": async (info, out) => {
      const tool = String(info?.tool ?? "")
      const sessionID = info?.sessionID
      if (tool !== TOOL_TASK && tool !== TOOL_LIST && tool !== TOOL_CONNECT && tool !== TOOL_DISCONNECT) return
      const callID = String(info?.callID ?? "")
      const s = getSession(sessionID)
      const text = outputText(out)
      const prev = s.state
      const base = { hook: "after", tool, callID, agent: s.agent, turn: s.turn, turnId: s.turnId, state: prev, outputLength: text.length }
      if (tool === TOOL_LIST) {
        const fail = failureMatch(text)
        if (!fail) {
          s.listSuccesses += 1
          if (s.state === "NEED_LIST") s.state = "NEED_CONNECT"
        }
        record(sessionID, { ...base, next: s.state, ok: !fail, failureMatch: fail || undefined })
        return
      }
      if (tool === TOOL_CONNECT) {
        const args = info && typeof info.args === "object" && info.args ? info.args : {}
        const name = connectionNameOf(args)
        const fail = failureMatch(text)
        let note
        if (fail) {
          s.pending = undefined
        } else {
          note = connectSucceeded(s, sessionID, callID, name).note
        }
        record(sessionID, { ...base, next: s.state, ok: !fail, failureMatch: fail || undefined, connection: name, note })
        return
      }
      if (tool === TOOL_DISCONNECT) {
        s.state = "NEED_LIST"
        s.readyName = undefined
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
          // 連線在題目中途斷了：重派前必須再 connect；連線計數歸零，讓「連失敗兩次退讓」還能再觸發
          s.state = "NEED_CONNECT"
          s.readyName = undefined
          s.connectAttempts = 0
          s.connectSuccesses = 0
          note = "subagent reported NOT_CONNECTED: connect again before re-dispatch"
        }
        // turn／state 用入場時的快照（使用者在 task 執行中送下一題，狀態已被重置，但這個 task 屬於前一題）
        const stamped = adm ? { turn: adm.turn, turnId: adm.turnId, state: adm.state, admitted: adm.decision } : { admitted: "unknown" }
        record(sessionID, { ...base, ...stamped, target, executed: true, basis: cls.basis, next: s.state, notConnected, note })
        return
      }
    },
  }
}

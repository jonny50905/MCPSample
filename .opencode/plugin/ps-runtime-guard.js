// ps-runtime-guard.js — OpenCode plugin：三件小事，沒有派工閘門、沒有 READY／todo 狀態機
//
// (1) Oracle connect 目標 guard（無狀態）：oracleMCP_connect 執行前只比對「本次呼叫的 connection_name」與 profile
//     oracle.connectionName：未填／FILL_ME → ORACLE_CONNECTION_NOT_CONFIGURED；不一致 → ORACLE_CONNECTION_MISMATCH。
//     擋＝throw（工具不執行、不改參數；模型收到錯誤碼與下一步）。不保存 READY／turnId／連線世代、不查 task 能力、
//     不代模型 connect、不拿回覆文字決定能不能派工。這是參數限制，不是前置閘門。
//     env PS_ORACLE_CONNECT_GUARD=observe 或 profile oracle.connectGuard: observe → 只記錄不擋（enforce 為預設）。
// (2) task 目標檢查（無狀態）：subagent_type 是 .opencode/skills/<名>/SKILL.md 而不是 .opencode/agent/<名>.md
//     → PS_TASK_TARGET_INVALID（throw；訊息指出承載 agent：ps-security-flow／ps-data-lineage／ps-process-flow → ps-metadata-flow；
//     主 agent 自讀的 skill 不委派）。task 的 after：報告 suggestedNext[].agent 是 skill 名或不存在的 agent → 在工具輸出末尾
//     附一行驗證註記（報告本文不動、不轉發）。這是路由錯誤，訊息不提 ORACLE_MCP_DOWN、不引發 connect 或重掛。
// (3) oracleMCP 診斷（觀察，不參與任何派工決策）：
//     - session 紀錄 <專案>/auto-loop-logs/ps-runtime-guard/<sessionID>.jsonl：chat.message（訊息 id、agent）、oracleMCP_* 的
//       before／after（ok 三態＝回覆文字的事實，不是連線有效性證明）、task 的 before／after（target、dbCapable、報告
//       status／blockedReason／childSessionID、suggestedNext 驗證）、invalid（模型呼叫了它看不到的工具名）。
//     - 主機紀錄 _mcp-diag.jsonl：mcp.tools.changed 事件、狀態快照（runtimeStatus／error 遮罩摘要／工具目錄探測）、
//       oracleMCP_ 工具 part 出錯的遮罩摘要、受控重掛的起迄／結果／恢復世代。只記工具名、計數、事件與遮罩後的錯誤摘要——
//       不記 SQL、結果、prompt、密碼、完整連線字串。
//     - 受控重掛（預設 off；env PS_ORACLE_MCP_AUTO_RECOVER=on 或 profile oracle.mcpAutoRecover: on）：只在 host 證據觸發——
//       /mcp 狀態 failed（transport 關閉），或 tools.changed 之後某個先前執行過的 oracleMCP_ 工具對允許它的 agent 變成不可見
//       （OpenCode 把呼叫改判成 invalid）；LLM 的 ORACLE_MCP_DOWN 字串不算證據。同一故障事件只重掛一次；有 oracleMCP_ 呼叫在途
//       先等（有界）；disabled／needs_auth／needs_client_registration 不重掛；一次失敗即停（人工 SOP）；每列帶恢復世代，
//       舊掛載上的回覆不推翻新恢復；恢復後在下一次 oracleMCP_／task 回覆附註「已重掛，舊 DB 連線與 schema 不再有效」——
//       plugin 拿不到「呼叫工具」的 API，profile 目標 connect 與 SELECT 1 FROM DUAL 的驗證由主 agent／subagent 做。
//       off 時同樣判定、只記 would-remount（診斷先行）。
//     整個 tools 表混寫「oracleMCP_* 萬用字元 deny＋個別 true」的 agent 在載入時記 WARN（某些版本會把整個 MCP 對它隱藏）。
//
// 零外部相依（只用 node:fs／node:path／node:crypto；公司網路封鎖 npm）。OpenCode 自動載入 .opencode/plugin/*.js。

import crypto from "node:crypto"
import fs from "node:fs"
import path from "node:path"

const MCP_NAME = "oracleMCP"
const MCP_PREFIX = MCP_NAME + "_"
const TOOL_CONNECT = MCP_PREFIX + "connect"
const TOOL_SQL_RUN = MCP_PREFIX + "sql_run"
const TOOL_TASK = "task"
const TOOL_INVALID = "invalid"
const CODE_TARGET = "PS_TASK_TARGET_INVALID"
const LOG_SUBDIR = path.join("auto-loop-logs", "ps-runtime-guard")
const PROFILE_REL = path.join(".opencode", "peoplesoft", "customization-profile.yaml")
const AGENT_DIR_REL = path.join(".opencode", "agent")
const SKILL_DIR_REL = path.join(".opencode", "skills")
const BUILTIN_AGENTS = new Set(["build", "plan", "general", "explore"])
// skill → 承載 agent（skill 名與 agent 名相同的不在此表：那本來就是 agent）
const SKILL_CARRIER = {
  "ps-security-flow": "ps-metadata-flow",
  "ps-data-lineage": "ps-metadata-flow",
  "ps-process-flow": "ps-metadata-flow",
}
// 主 agent 自己讀、不委派的 skill
const SKILL_PRIMARY_ONLY = new Set(["ps-business-discovery", "ps-business-explain", "ps-impact-analysis"])
const INFLIGHT_TTL_MS = 120000
// 時間常數可用 env 縮短（只給沙箱測試用）
const msEnv = (name, def) => { const v = Number(process.env[name]); return Number.isFinite(v) && v > 0 ? v : def }
const REMOUNT_TIMEOUT_MS = msEnv("PS_GUARD_REMOUNT_TIMEOUT_MS", 30000)
const REMOUNT_DEFER_MAX_MS = msEnv("PS_GUARD_REMOUNT_DEFER_MAX_MS", 60000)
const REMOUNT_POLL_MS = msEnv("PS_GUARD_REMOUNT_POLL_MS", 1000)
const REMOUNT_VERIFY_MS = msEnv("PS_GUARD_REMOUNT_VERIFY_MS", 10000)

// connect／sql_run 回傳文字若命中以下樣式，記為 ok:false（只是紀錄，不驅動任何狀態）。
// 不列 ORA-nnnnn：SQLcl connect 成功的回覆帶說明文字、裡面引用 ORA-nnnnn（公司機實測）。
const FAILURE_PATTERNS = [
  /\bconnection not (?:connected|established|found)\b/i,
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

// 同一表裡「oracleMCP_* 萬用字元 deny」＋「個別 oracleMCP_ 工具 true」的混寫（見檔頭）
function wildcardDenyMix(entries) {
  const deny = entries.some(([k, v]) => k.startsWith(MCP_PREFIX) && k.includes("*") && v === false)
  const allow = entries.some(([k, v]) => k.startsWith(MCP_PREFIX) && !k.includes("*") && v === true)
  return deny && allow
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
        db: toolEnabled(tools, TOOL_SQL_RUN),
        tools,
        wildcardDenyMix: wildcardDenyMix(tools),
      })
    } catch {
      // 讀不到的檔跳過；不在目錄裡的名字會被視為會查 DB（保守）
    }
  }
  return catalog
}

function loadSkillNames(directory) {
  try {
    return new Set(
      fs
        .readdirSync(path.join(directory, SKILL_DIR_REL), { withFileTypes: true })
        .filter((d) => d.isDirectory() && fs.existsSync(path.join(directory, SKILL_DIR_REL, d.name, "SKILL.md")))
        .map((d) => d.name),
    )
  } catch {
    return new Set()
  }
}

// profile 的 oracle: 區塊 → { key: value }（只需支援 `  key: value` 與 # 註解）
function readProfileOracle(directory) {
  const out = {}
  try {
    const text = fs.readFileSync(path.join(directory, PROFILE_REL), "utf8").replace(/^\uFEFF/, "")
    let inOracle = false
    for (const raw of text.split(/\r?\n/)) {
      if (/^oracle:\s*(#.*)?$/.test(raw)) {
        inOracle = true
        continue
      }
      if (!inOracle) continue
      if (raw.trim() === "" || raw.trim().startsWith("#")) continue
      if (!/^\s/.test(raw)) break
      const m = raw.match(/^\s+([A-Za-z_][A-Za-z0-9_]*):\s*([^#]*?)\s*(#.*)?$/)
      if (m) out[m[1]] = m[2].replace(/^["']|["']$/g, "")
    }
  } catch {
    // 沒有 profile 或讀不到 → 空
  }
  return out
}

function readSwitch(directory, envName, profileKey, values, fallback) {
  const env = String(process.env[envName] ?? "").trim().toLowerCase()
  if (values.includes(env)) return env
  const v = String(readProfileOracle(directory)[profileKey] ?? "").trim().toLowerCase()
  if (values.includes(v)) return v
  return fallback
}
const readConnectGuard = (d) => readSwitch(d, "PS_ORACLE_CONNECT_GUARD", "connectGuard", ["enforce", "observe"], "enforce")
const readAutoRecover = (d) => readSwitch(d, "PS_ORACLE_MCP_AUTO_RECOVER", "mcpAutoRecover", ["on", "off"], "off")
const readDiag = (d) => readSwitch(d, "PS_ORACLE_MCP_DIAG", "mcpDiag", ["on", "off"], "on")

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

// 三態：true＝有文字且不命中失敗樣式；false＝isError 或命中失敗樣式；"unknown"＝沒有任何文字
function classifyResult(output) {
  const text = outputText(output)
  if (output && typeof output === "object" && output.isError === true) return { ok: false, failureMatch: "isError", textLength: text.length }
  if (!text.trim()) return { ok: "unknown", failureMatch: "", textLength: text.length }
  const fail = failureMatch(text)
  return { ok: !fail, failureMatch: fail, textLength: text.length }
}

// task 工具的輸出：<task id="<子 session>" state="completed|error"><task_result>…</task_result></task>；子 agent 的最終文字應是契約 JSON
function parseReport(text) {
  const t = String(text ?? "")
  const wrapper = t.match(/<task id="([^"]*)" state="([^"]*)">/)
  const taskState = wrapper ? wrapper[2] : undefined
  const taskId = wrapper ? wrapper[1] : undefined
  const bodies = []
  const inner = t.match(/<task_(?:result|error)>([\s\S]*?)<\/task_(?:result|error)>/)
  if (inner) bodies.push(inner[1])
  bodies.push(t)
  for (const b of [...bodies]) {
    const f = b.match(/```(?:json)?\s*([\s\S]*?)```/)
    if (f) bodies.push(f[1])
  }
  for (const b of bodies) {
    const start = b.indexOf("{")
    const end = b.lastIndexOf("}")
    if (start < 0 || end <= start) continue
    let obj
    try {
      obj = JSON.parse(b.slice(start, end + 1))
    } catch {
      continue
    }
    if (!obj || typeof obj !== "object" || Array.isArray(obj)) continue
    const status = String(obj.status ?? "").toUpperCase()
    const valid = status === "COMPLETE" || status === "PARTIAL" || status === "BLOCKED"
    const reason = typeof obj.blockedReason === "string" && obj.blockedReason ? obj.blockedReason.toUpperCase() : undefined
    const suggestedNext = Array.isArray(obj.suggestedNext)
      ? obj.suggestedNext.filter((x) => x && typeof x === "object").map((x) => ({ agent: typeof x.agent === "string" ? x.agent : "", task: typeof x.task === "string" ? x.task.slice(0, 80) : "" }))
      : []
    return { valid, status: valid ? status : "INVALID", blockedReason: reason, taskState, taskId, suggestedNext }
  }
  return { valid: false, status: "INVALID", blockedReason: undefined, taskState, taskId, suggestedNext: [] }
}

function connectionNameOf(args) {
  if (!args || typeof args !== "object") return undefined
  for (const k of ["connection_name", "connectionName", "name", "connection"]) {
    if (typeof args[k] === "string" && args[k].trim()) return args[k].trim()
  }
  return undefined
}

function profileUnset(profileName) {
  return !profileName || profileName.toUpperCase() === "FILL_ME"
}

// connect 的目標檢查：回 undefined＝可以執行；否則回 { code, message }
function connectProblem(profileName, target) {
  const tail =
    "模型：不要猜、不要從 list_connections 的清單挑名字（清單把名稱和連線字串黏在一起）；本題不派會查 DB 的委派，" +
    "向使用者回報「Oracle 連線未設定／連線名不一致（profile oracle.connectionName＝<值>）」，其餘部分照常作答。這不是 oracleMCP 掛載故障，不要重掛。"
  if (profileUnset(profileName)) {
    return {
      code: "ORACLE_CONNECTION_NOT_CONFIGURED",
      message:
        `ORACLE_CONNECTION_NOT_CONFIGURED：本次 oracleMCP_connect 未執行（被 Oracle 連線目標 guard 擋下，不是權限問題）。profile oracle.connectionName 未填` +
        `（目前＝${profileName || "空"}）——請管理者在 .opencode/peoplesoft/customization-profile.yaml 回填 SQLcl 已儲存連線名（實際連得上的那個名字）。` +
        tail,
    }
  }
  if (!target) {
    return {
      code: "ORACLE_CONNECTION_MISMATCH",
      message:
        `ORACLE_CONNECTION_MISMATCH：本次 oracleMCP_connect 未執行（被 Oracle 連線目標 guard 擋下，不是權限問題）。呼叫沒有帶 connection_name；` +
        `只准連 profile oracle.connectionName 指定的「${profileName}」——用 connection_name＝「${profileName}」重新呼叫。`,
    }
  }
  if (target !== profileName) {
    return {
      code: "ORACLE_CONNECTION_MISMATCH",
      message:
        `ORACLE_CONNECTION_MISMATCH：本次 oracleMCP_connect 未執行（被 Oracle 連線目標 guard 擋下，不是權限問題）。connect 目標「${target}」≠ profile oracle.connectionName「${profileName}」。` +
        `只准連 profile 指定的連線：用 connection_name＝「${profileName}」原樣重新呼叫 connect。` +
        tail,
    }
  }
  return undefined
}

function targetProblem(target, agentNames, skillNames) {
  if (!target || agentNames.has(target) || BUILTIN_AGENTS.has(target)) return undefined
  if (!skillNames.has(target)) return undefined
  const carrier = SKILL_CARRIER[target]
  const where = `.opencode/skills/${target}/SKILL.md`
  let next
  if (carrier) {
    next =
      `請改派承載 agent「${carrier}」（subagent_type=${carrier}），並在 prompt 指定「讀取 ${where}，依 oracle-query-cookbook.md 對應章節查證，回傳既定 JSON 報告」。`
  } else if (SKILL_PRIMARY_ONLY.has(target)) {
    next = `這個 skill 由主 agent 自己 read ${where} 後遵守，不委派；需要檢索時依委派表拆成 ps-* subagent 的 task。`
  } else {
    next = `請依主 agent 的委派表選擇對應的 ps-* agent，並在 prompt 指定讀取 ${where}。`
  }
  return {
    code: CODE_TARGET,
    carrier,
    message:
      `${CODE_TARGET}：本次 task 未執行——「${target}」是 skill（${where}），不是可委派的 agent。` +
      next +
      "這是路由錯誤，不是 Oracle 掛載或 DB 連線問題：不要 connect、不要重掛 MCP、不要當成 Oracle 掛載故障回報，用正確的 subagent_type 重新委派即可。",
  }
}

// 遮罩：只留第一行、去掉 jdbc 連線字串／@host／密碼類 token，最多 160 字
function maskError(text) {
  let s = String(text ?? "").split(/\r?\n/)[0]
  s = s.replace(/jdbc:[^\s)}]+/gi, "jdbc:***").replace(/@[^\s)}]+/g, "@***").replace(/(password|pwd|passwd)\s*[=:]\s*\S+/gi, "$1=***")
  return s.slice(0, 160)
}

function withTimeout(promise, ms, label) {
  let timer
  const timeout = new Promise((_, reject) => {
    timer = setTimeout(() => reject(new Error(`${label} timed out after ${ms}ms`)), ms)
  })
  return Promise.race([promise, timeout]).finally(() => clearTimeout(timer))
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms))

export const PsRuntimeGuard = async (input) => {
  const directory = String(input?.directory ?? process.cwd())
  const client = input?.client
  const logDir = path.join(directory, LOG_SUBDIR)
  const instanceId = crypto.randomBytes(6).toString("hex")
  const sessions = new Map()
  const inflight = new Map()
  const seenTools = new Set()
  let catalog = loadAgentCatalog(directory)
  let skills = loadSkillNames(directory)
  let catalogLoaded = Date.now()
  // 故障偵測與受控重掛（host 層；不參與派工）
  const recovery = { gen: 0, phase: "idle", faultId: null, catalogSuspect: false, lastFaultReason: null, noticeGen: 0, evaluating: false }

  function ensureLogDir() {
    try {
      fs.mkdirSync(logDir, { recursive: true })
    } catch {
      // 記錄失敗不影響 guard
    }
  }

  function pluginLog(line) {
    try {
      ensureLogDir()
      fs.appendFileSync(path.join(logDir, "_plugin.log"), `${nowIso()} pid=${process.pid} instance=${instanceId} ${line}\n`)
    } catch {
      // 忽略
    }
  }

  function record(sessionID, entry) {
    try {
      ensureLogDir()
      const safe = String(sessionID ?? "unknown").replace(/[^A-Za-z0-9_.-]/g, "_")
      fs.appendFileSync(path.join(logDir, `${safe}.jsonl`), JSON.stringify({ ts: nowIso(), pid: process.pid, instance: instanceId, sessionID, ...entry }) + "\n")
    } catch {
      // 忽略
    }
  }

  function diag(entry) {
    if (readDiag(directory) !== "on") return
    try {
      ensureLogDir()
      fs.appendFileSync(path.join(logDir, "_mcp-diag.jsonl"), JSON.stringify({ ts: nowIso(), pid: process.pid, instance: instanceId, directory, mcp: MCP_NAME, recoveryGen: recovery.gen, ...entry }) + "\n")
    } catch {
      // 忽略
    }
  }

  function getSession(sessionID) {
    let s = sessions.get(sessionID)
    if (!s) {
      s = { agent: undefined, messageID: undefined, noticeGen: 0 }
      sessions.set(sessionID, s)
    }
    return s
  }

  function stamp(s) {
    return { agent: s.agent, messageID: s.messageID }
  }

  function fresh() {
    if (Date.now() - catalogLoaded > 60000) {
      catalog = loadAgentCatalog(directory)
      skills = loadSkillNames(directory)
      catalogLoaded = Date.now()
    }
    return catalog
  }

  function classifyTarget(target) {
    const entry = fresh().get(target)
    if (!entry) return { db: true, basis: "unknown-agent(default:DB)" }
    return { db: entry.db, basis: entry.db ? "sql_run:enabled" : "sql_run:disabled" }
  }

  function agentAllows(agent, tool) {
    const entry = agent ? fresh().get(agent) : undefined
    if (!entry) return undefined
    return toolEnabled(entry.tools, tool)
  }

  function inflightAdd(sessionID, callID, tool) {
    if (!callID) return
    inflight.set(`${sessionID}:${callID}`, { tool, ts: Date.now() })
  }
  function inflightRemove(sessionID, callID) {
    if (callID) inflight.delete(`${sessionID}:${callID}`)
  }
  function inflightCount() {
    const cutoff = Date.now() - INFLIGHT_TTL_MS
    for (const [k, v] of inflight) if (v.ts < cutoff) inflight.delete(k)
    return inflight.size
  }

  // 同 host 的 /mcp 狀態（plugin 的 client 綁在自己這個 server 行程）；查不到 → status "unavailable"
  async function oracleStatus() {
    if (!client || !client.mcp || typeof client.mcp.status !== "function") return { status: "unavailable", basis: "client.mcp.status missing" }
    try {
      const res = await withTimeout(client.mcp.status(), 10000, "mcp.status")
      if (res && typeof res === "object" && res.error) {
        const code = res.response && typeof res.response === "object" ? res.response.status : "?"
        return { status: "unavailable", basis: `mcp-status:error(${code})` }
      }
      const data = res && typeof res === "object" && "data" in res ? res.data : res
      const st = data && typeof data === "object" ? data[MCP_NAME] : undefined
      if (!st) return { status: "absent", basis: "mcp-status:absent" }
      return { status: String(st.status), error: st.error ? maskError(st.error) : undefined, basis: "mcp-status:" + String(st.status) }
    } catch (e) {
      return { status: "unavailable", basis: "mcp-status:unavailable(" + maskError(e && e.message ? e.message : e).slice(0, 80) + ")" }
    }
  }

  // 工具目錄探測：1.18.29 的 /experimental/tool/ids 只有內建工具（不含 MCP）——回空表示這個版本不暴露；較新版本若含 oracleMCP_ 名就有用
  async function probeToolIds() {
    const fn = client && client.experimental && client.experimental.tool && typeof client.experimental.tool.ids === "function" ? client.experimental.tool.ids.bind(client.experimental.tool) : null
    if (!fn) return { source: "experimental.tool.ids", available: false, oracleTools: [] }
    try {
      const res = await withTimeout(fn(), 10000, "tool.ids")
      const data = res && typeof res === "object" && "data" in res ? res.data : res
      const ids = Array.isArray(data) ? data.filter((x) => typeof x === "string") : []
      return { source: "experimental.tool.ids", available: true, total: ids.length, oracleTools: ids.filter((x) => x.startsWith(MCP_PREFIX)).sort() }
    } catch (e) {
      return { source: "experimental.tool.ids", available: false, error: maskError(e && e.message ? e.message : e), oracleTools: [] }
    }
  }

  async function snapshot(reason, extra) {
    const st = await oracleStatus()
    const probe = await probeToolIds()
    const row = {
      kind: "snapshot", reason, runtimeStatus: st.status, configuredEnabled: st.status !== "disabled" && st.status !== "absent", statusError: st.error,
      toolCatalog: probe.available ? (probe.oracleTools.length ? probe.oracleTools : "empty (or not exposed by this host version)") : "not exposed by host API",
      toolCatalogSource: probe.source, seenTools: [...seenTools].sort(), catalogSuspect: recovery.catalogSuspect, inflight: inflightCount(), phase: recovery.phase, ...extra,
    }
    diag(row)
    return { ...st, probe }
  }

  // 受控重掛：host 證據 → 判定 → 至多一次（同一故障事件內多個 agent 同時報錯只算一次）
  async function considerRecovery(reason, evidence, sessionID) {
    if (recovery.evaluating || recovery.phase === "remounting" || recovery.phase === "pending") {
      diag({ kind: "recovery", faultReason: reason, evidence, sessionID, decision: "merged", note: "a recovery for this fault event is already being evaluated or performed" })
      return
    }
    recovery.evaluating = true
    try {
      await considerRecoveryInner(reason, evidence, sessionID)
    } finally {
      recovery.evaluating = false
    }
  }

  async function considerRecoveryInner(reason, evidence, sessionID) {
    const st = await snapshot("recovery-candidate", { faultReason: reason, evidence })
    const auto = readAutoRecover(directory)
    const base = { kind: "recovery", faultReason: reason, evidence, runtimeStatus: st.status, autoRecover: auto, sessionID }
    if (recovery.phase === "failed") {
      diag({ ...base, decision: "suppressed", note: "previous automatic recovery failed; manual SOP required (a later executed oracleMCP_ call resets this)" })
      return
    }
    if (recovery.phase === "recovered-unverified" && st.status !== "connected") {
      // 重掛後還沒有任何 oracleMCP_ 呼叫成功就又故障＝那次恢復沒有真的救回來：不再自動重掛，交人工
      recovery.phase = "failed"
      diag({ ...base, decision: "suppressed", faultId: recovery.faultId, gen: recovery.gen, note: "a new fault arrived before the previous remount was verified by any executed call: treating the recovery as failed (manual SOP)" })
      return
    }
    if (st.status === "disabled" || st.status === "absent" || st.status === "needs_auth" || st.status === "needs_client_registration" || st.status === "unavailable") {
      diag({ ...base, decision: "not-eligible", note: `status ${st.status} is not a transient fault (admin disable／auth／not configured／status unavailable)` })
      return
    }
    if (st.status === "connected" && reason === "transport-closed") {
      diag({ ...base, decision: "not-needed", note: "status already connected again" })
      recovery.catalogSuspect = false
      return
    }
    if (auto !== "on") {
      diag({ ...base, decision: "would-remount", note: "automatic recovery is off (profile oracle.mcpAutoRecover／env PS_ORACLE_MCP_AUTO_RECOVER); follow the manual SOP" })
      return
    }
    recovery.faultId = recovery.faultId ?? `${Date.now().toString(36)}-${crypto.randomBytes(3).toString("hex")}`
    recovery.lastFaultReason = reason
    const started = Date.now()
    while (inflightCount() > 0) {
      if (recovery.phase !== "pending") {
        recovery.phase = "pending"
        diag({ ...base, decision: "deferred", faultId: recovery.faultId, note: `${inflightCount()} oracleMCP_ call(s) in flight; waiting up to ${REMOUNT_DEFER_MAX_MS}ms` })
      }
      if (Date.now() - started > REMOUNT_DEFER_MAX_MS) {
        recovery.phase = "failed"
        diag({ ...base, decision: "gave-up", faultId: recovery.faultId, note: "in-flight oracleMCP_ calls did not finish in time; not remounting over unfinished work (manual SOP)" })
        return
      }
      await sleep(REMOUNT_POLL_MS)
    }
    await remount(base)
  }

  async function mcpOp(op, name) {
    const fn = client && client.mcp && typeof client.mcp[op] === "function" ? client.mcp[op].bind(client.mcp) : null
    if (!fn) return { ok: false, error: `client.mcp.${op} unavailable on this host` }
    let lastErr = ""
    for (const args of [{ path: { name } }, { name }]) {
      try {
        const res = await withTimeout(fn(args), REMOUNT_TIMEOUT_MS, `mcp.${op}`)
        if (res && typeof res === "object" && res.error) {
          const code = res.response && typeof res.response === "object" ? res.response.status : "?"
          lastErr = `HTTP ${code}`
          continue
        }
        return { ok: true }
      } catch (e) {
        lastErr = maskError(e && e.message ? e.message : e)
        if (/timed out/.test(lastErr)) break
      }
    }
    return { ok: false, error: lastErr }
  }

  async function remount(base) {
    recovery.phase = "remounting"
    recovery.gen += 1
    const gen = recovery.gen
    const t0 = Date.now()
    diag({ ...base, decision: "remount-start", faultId: recovery.faultId, gen })
    const d = await mcpOp("disconnect", MCP_NAME)
    const c = await mcpOp("connect", MCP_NAME)
    let st = await oracleStatus()
    const until = Date.now() + REMOUNT_VERIFY_MS
    while (st.status !== "connected" && Date.now() < until) {
      await sleep(REMOUNT_POLL_MS)
      st = await oracleStatus()
    }
    const ok = c.ok && st.status === "connected"
    if (ok) {
      recovery.phase = "recovered-unverified"
      recovery.catalogSuspect = false
      recovery.noticeGen = gen
      diag({ ...base, decision: "remount-ok", faultId: recovery.faultId, gen, ms: Date.now() - t0, disconnect: d.ok, connect: c.ok, runtimeStatus: st.status, verify: "tools restored is verified by the next executed oracleMCP_ call; DB verification (connect to the profile target, then SELECT 1 FROM DUAL) is the agents' job" })
    } else {
      recovery.phase = "failed"
      diag({ ...base, decision: "remount-failed", faultId: recovery.faultId, gen, ms: Date.now() - t0, disconnect: d.ok, connect: c.ok, connectError: c.error, runtimeStatus: st.status, statusError: st.error, note: "stopping after one attempt; follow the manual SOP" })
    }
  }

  function recoveryNotice() {
    return (
      `\n\n[ps-runtime-guard] oracleMCP 已在本主機重掛（恢復世代 ${recovery.noticeGen}）。重掛前的 DB 連線、CURRENT_SCHEMA 設定與「已連線」結論都不再有效：` +
      "主 agent 先 oracleMCP_connect（connection_name＝profile oracle.connectionName 原樣），再由查詢 subagent 執行 SELECT 1 FROM DUAL 確認，之後才繼續業務查詢；" +
      "只重派尚未完成的唯讀工作一次；重掛前的失敗回報不代表現況。"
    )
  }

  // 恢復後的下一次回覆附註（每 session 一次）；out 可能是 MCP 原始結果（content[]）或 registry 工具輸出（output 字串）
  function maybeAnnotate(sessionID, out) {
    if (recovery.phase !== "recovered-unverified" && recovery.noticeGen === 0) return false
    const s = getSession(sessionID)
    if (s.noticeGen >= recovery.noticeGen) return false
    const text = recoveryNotice()
    if (out && typeof out === "object") {
      if (Array.isArray(out.content)) out.content.push({ type: "text", text })
      else if (typeof out.output === "string") out.output += text
      else return false
      s.noticeGen = recovery.noticeGen
      return true
    }
    return false
  }

  function suggestedNextProblems(list) {
    const problems = []
    for (const item of list) {
      const p = targetProblem(item.agent, new Set(fresh().keys()), skills)
      if (p) problems.push({ agent: item.agent, kind: "skill", carrier: p.carrier })
      else if (item.agent && !fresh().has(item.agent) && !BUILTIN_AGENTS.has(item.agent)) problems.push({ agent: item.agent, kind: "unknown" })
    }
    return problems
  }

  function annotateSuggestedNext(out, problems) {
    if (!problems.length || !out || typeof out !== "object" || typeof out.output !== "string") return
    const lines = problems.map((p) =>
      p.kind === "skill"
        ? `「${p.agent}」是 skill、不是 agent${p.carrier ? `：改派 ${p.carrier}（subagent_type=${p.carrier}），並在 task 文字指定讀取 .opencode/skills/${p.agent}/SKILL.md` : "：主 agent 自讀該 SKILL.md，不委派"}；不要用 subagent_type=${p.agent}`
        : `「${p.agent}」不是已載入的 agent；依主 agent 的委派表改派`,
    )
    out.output += "\n\n[ps-runtime-guard] 報告的 suggestedNext 含無效委派目標（不轉發、不算 Oracle 掛載或 DB 連線問題）：\n- " + lines.join("\n- ")
  }

  pluginLog(
    `loaded directory=${directory} execPath=${process.execPath} platform=${process.platform} connectGuard=${readConnectGuard(directory)} autoRecover=${readAutoRecover(directory)} diag=${readDiag(directory)} agents=${JSON.stringify(
      [...catalog.entries()].map(([name, v]) => `${name}:${v.db ? "DB" : "noDB"}`),
    )} skills=${JSON.stringify([...skills].sort())} wildcardDenyMix=${JSON.stringify([...catalog.entries()].filter(([, v]) => v.wildcardDenyMix).map(([name]) => name))}`,
  )
  for (const [name, v] of catalog.entries()) {
    if (v.wildcardDenyMix) pluginLog(`WARN agent ${name}: tools 表混寫 oracleMCP_* deny ＋ 個別工具 true——某些版本會把整個 MCP 對它隱藏；請逐工具明寫`)
  }
  diag({ kind: "loaded", execPath: process.execPath, platform: process.platform, connectGuard: readConnectGuard(directory), autoRecover: readAutoRecover(directory) })

  return {
    "chat.message": async (msg, out) => {
      const sessionID = msg?.sessionID
      if (!sessionID) return
      const s = getSession(sessionID)
      if (msg.agent) s.agent = String(msg.agent)
      const parts = out && typeof out === "object" && Array.isArray(out.parts) ? out.parts : []
      const synthetic = parts.length > 0 && parts.every((p) => p && typeof p === "object" && p.synthetic === true)
      const mid = out && typeof out === "object" && out.message && typeof out.message.id === "string" ? out.message.id : msg.messageID
      if (!synthetic && typeof mid === "string" && mid) s.messageID = mid
      record(sessionID, { hook: "chat.message", ...stamp(s), synthetic: synthetic || undefined })
    },

    event: async (input) => {
      const ev = input && input.event
      if (!ev || typeof ev !== "object") return
      const props = ev.properties && typeof ev.properties === "object" ? ev.properties : {}
      if (ev.type === "mcp.tools.changed") {
        if (String(props.server ?? "") !== MCP_NAME) return
        diag({ kind: "event", type: ev.type, server: props.server })
        const st = await snapshot("tools-changed")
        if (st.status === "connected") {
          // 目錄被重抓：1.18.29 拿不到工具數；先標記「可疑」，等下一次呼叫證實（執行得到＝仍在；invalid＝消失）
          recovery.catalogSuspect = true
          diag({ kind: "event", type: ev.type, note: "catalog refreshed while connected: marked suspect until the next oracleMCP_ call proves the tools are still visible" })
          return
        }
        // failed＝transport 關閉（候選）；disabled／needs_auth／absent／unavailable 由判定記 not-eligible（管理者主動關、授權、未設定都不是暫時故障）
        await considerRecovery(st.status === "failed" ? "transport-closed" : "status-" + st.status, { event: ev.type, statusError: st.error })
        return
      }
      if (ev.type === "message.part.updated") {
        const part = props.part && typeof props.part === "object" ? props.part : undefined
        if (!part || part.type !== "tool" || typeof part.tool !== "string" || !part.tool.startsWith(MCP_PREFIX)) return
        const state = part.state && typeof part.state === "object" ? part.state : {}
        if (state.status === "error") {
          inflightRemove(part.sessionID, part.callID)
          const err = maskError(state.error)
          diag({ kind: "tool-error", tool: part.tool, sessionID: part.sessionID, callID: part.callID, error: err })
          record(part.sessionID, { hook: "part-error", tool: part.tool, callID: part.callID, ...stamp(getSession(part.sessionID)), error: err })
          if (/MCP error|transport|closed|not connected to (?:the )?server/i.test(String(state.error ?? ""))) {
            const st = await snapshot("tool-error")
            if (st.status === "failed") await considerRecovery("transport-closed", { tool: part.tool, error: err }, part.sessionID)
          }
        }
      }
    },

    "tool.execute.before": async (info, out) => {
      const tool = String(info?.tool ?? "")
      const sessionID = info?.sessionID
      const callID = String(info?.callID ?? "")
      const args = out && typeof out === "object" && out.args && typeof out.args === "object" ? out.args : {}
      const s = getSession(sessionID)
      if (tool === TOOL_INVALID) {
        const attempted = typeof args.tool === "string" ? args.tool : ""
        if (!attempted.startsWith(MCP_PREFIX)) return
        const allowed = agentAllows(s.agent, attempted)
        const seen = seenTools.has(attempted)
        let note
        if (allowed === false) note = "tool is denied by this agent's tools table (permission-filtered, not an MCP fault)"
        else if (!seen) note = "tool name never executed on this host (likely a wrong name; not treated as an MCP fault)"
        else note = "a previously executed oracleMCP_ tool is no longer visible to an agent that allows it: host-side catalog loss"
        record(sessionID, { hook: "invalid", tool, callID, ...stamp(s), attempted, allowedByAgent: allowed, seenBefore: seen, note })
        diag({ kind: "invalid-tool", attempted, agent: s.agent, sessionID, allowedByAgent: allowed, seenBefore: seen, note })
        if (allowed !== false && seen) {
          const st = await snapshot("invalid-tool")
          if (st.status === "failed") await considerRecovery("transport-closed", { attempted, agent: s.agent }, sessionID)
          else if (st.status === "connected") await considerRecovery("catalog-lost", { attempted, agent: s.agent, catalogSuspect: recovery.catalogSuspect }, sessionID)
        }
        return
      }
      if (tool === TOOL_TASK) {
        const target = String(args.subagent_type ?? "")
        const cls = classifyTarget(target)
        const problem = targetProblem(target, new Set(fresh().keys()), skills)
        if (problem) {
          record(sessionID, { hook: "before", tool, callID, ...stamp(s), target, dbCapable: cls.db, basis: cls.basis, decision: "block", note: `${problem.code}:skill`, carrier: problem.carrier })
          throw new Error(problem.message)
        }
        record(sessionID, { hook: "before", tool, callID, ...stamp(s), target, dbCapable: cls.db, basis: cls.basis, decision: "allow" })
        return
      }
      if (!tool.startsWith(MCP_PREFIX)) return
      seenTools.add(tool)
      if (recovery.catalogSuspect) {
        recovery.catalogSuspect = false
        diag({ kind: "event", type: "catalog-proven", tool, note: "an oracleMCP_ call executed after the catalog refresh: tools are visible" })
      }
      if (tool === TOOL_CONNECT) {
        const mode = readConnectGuard(directory)
        const profileName = String(readProfileOracle(directory).connectionName ?? "").trim()
        const target = connectionNameOf(args)
        const problem = connectProblem(profileName, target)
        const head = { hook: "before", tool, callID, ...stamp(s), connection: target, profileConnection: profileName, mode }
        if (problem && mode !== "observe") {
          record(sessionID, { ...head, decision: "block", note: problem.code })
          throw new Error(problem.message)
        }
        inflightAdd(sessionID, callID, tool)
        record(sessionID, { ...head, decision: problem ? "observe-would-block" : "allow", note: problem ? problem.code : undefined })
        return
      }
      inflightAdd(sessionID, callID, tool)
      record(sessionID, { hook: "before", tool, callID, ...stamp(s), decision: "observe" })
    },

    "tool.execute.after": async (info, out) => {
      const tool = String(info?.tool ?? "")
      const sessionID = info?.sessionID
      const callID = String(info?.callID ?? "")
      const s = getSession(sessionID)
      if (tool === TOOL_TASK) {
        const args = info && typeof info.args === "object" && info.args ? info.args : {}
        const target = String(args.subagent_type ?? "")
        const cls = classifyTarget(target)
        const text = outputText(out)
        const rep = parseReport(text)
        const notConnected = rep.blockedReason === "NOT_CONNECTED" || /"blockedReason"\s*:\s*"NOT_CONNECTED"/.test(text)
        const meta = out && typeof out === "object" && out.metadata && typeof out.metadata === "object" ? out.metadata : {}
        const child = typeof meta.sessionId === "string" && meta.sessionId ? meta.sessionId : rep.taskId
        const problems = suggestedNextProblems(rep.suggestedNext)
        annotateSuggestedNext(out, problems)
        const annotated = maybeAnnotate(sessionID, out)
        record(sessionID, {
          hook: "after", tool, callID, ...stamp(s), target, dbCapable: cls.db, basis: cls.basis, executed: true,
          notConnected, reportValid: rep.valid, reportStatus: rep.status, blockedReason: rep.blockedReason, taskState: rep.taskState, childSessionID: child,
          suggestedNextInvalid: problems.length ? problems : undefined, recoveryNotice: annotated || undefined,
        })
        return
      }
      if (!tool.startsWith(MCP_PREFIX)) return
      inflightRemove(sessionID, callID)
      const r = classifyResult(out)
      if (recovery.phase === "recovered-unverified" || recovery.phase === "failed") {
        const was = recovery.phase
        recovery.phase = "idle"
        recovery.faultId = null
        diag({ kind: "recovery", decision: "verified-by-call", tool, sessionID, gen: recovery.gen, note: was === "failed" ? "an oracleMCP_ call executed after a failed automatic recovery (manual recovery happened): fault event closed" : "an oracleMCP_ call executed on the new mount: tools restored" })
      }
      const annotated = maybeAnnotate(sessionID, out)
      record(sessionID, {
        hook: "after", tool, callID, ...stamp(s), ok: r.ok, failureMatch: r.failureMatch || undefined, outputLength: r.textLength,
        ...(tool === TOOL_CONNECT ? { connection: connectionNameOf(info?.args) } : {}), recoveryGen: recovery.gen || undefined, recoveryNotice: annotated || undefined,
      })
    },
  }
}

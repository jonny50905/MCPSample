// ps-oracle-preflight-gate.js — Oracle 連線前置（第 0 步）的確定性閘門（OpenCode plugin）
//
// 不變量（與主 agent 第 0 步一致；每一則真實使用者訊息各自成立；沒有環境層退讓）：
//   NEED_CONNECT ─ connect 成功（connection_name＝profile oracle.connectionName 原樣）─▶ READY ─▶ 才准執行「會查 DB 的 subagent」委派（task）
//   list_connections 不是前置的一部分：SQLcl 清單把名稱和連線字串黏在一起（Name:<名>Connect string: {…}），模型從清單挑名字會讀錯；
//   連線名只從 profile 拿。list 的 after 只記錄、不改狀態（主 agent 只在 connect 兩次都失敗時呼叫它，把清單原文附給管理者核對）。
// 未 READY 就派會查 DB 的 subagent → 該 task 在執行前被擋（throw），模型收到 PS_ORACLE_PREFLIGHT_REQUIRED 與下一步指示，
// 做完前置再用相同參數重派。模型選錯順序不會變成錯誤的執行。閘門只擋、不改參數、不代模型 connect。
//
// 唯一的例外：目標 subagent 確定沒有 Oracle 能力（.opencode/agent/*.md 的 tools 表對 oracleMCP_run_sql 最後匹配為 false；
//   OpenCode 規則：最後匹配者優先、沒列＝預設開）→ 不需要 READY。判定依據是「能力」不是任務意圖：ps-auditor 即使做純 chunk
//   任務也要過閘門；不在 agent 目錄的名字一律視為會查 DB（保守）。每一列都寫 dbCapable（true／false），analyzer 用它、不用說明字串。
// oracleMCP 未掛載（/mcp 狀態非 connected；每次即時查、不快取）：一樣擋，只是錯誤訊息改為 ORACLE_MCP_DOWN 協定——不得委派
//   會查 DB 的 subagent，DB 部分如實回報、非 DB 部分改派沒有 Oracle 能力的 subagent。狀態查不到 → 一樣擋。
// 沒有其他退讓：connect／list 一直失敗仍擋（第 0 步規則：本題不派 DB 委派、其餘照常作答）；不跨 session、不跨行程協調
//   （共用連線的防護待 topology 實驗定案後另案設計，見 SOP-21）。
//
// connect 的目標在執行前強制比對：profile oracle.connectionName 未填／FILL_ME → ORACLE_CONNECTION_NOT_CONFIGURED；connect 的
//   connection_name 與 profile 不完全一致 → ORACLE_CONNECTION_MISMATCH。兩者都在工具執行前擋（observe 模式只記錄）。清單成員資格
//   不驗（清單格式不可靠），profile 值是連線名唯一的來源。
// 連線嘗試與世代：每次准許執行的 connect 嘗試都 connectGen+1，並把 READY 退回 NEED_CONNECT——READY 只由「該次嘗試」的成功恢復；
//   例外、timeout、無 after、被較晚的嘗試取代，都不會保留先前的成功證明。task 入場記下當時的 gen：之後又 connect 過（gen 已變）
//   的 task 回 NOT_CONNECTED，不作廢新世代的 READY（同題內舊連線上的工作晚回，不算新連線斷了）。
// task 回報解析：after 把子 agent 報告的 status（COMPLETE／PARTIAL／BLOCKED，其餘＝INVALID）、blockedReason、task 包裝的 state
//   與子 session id 記到列上（analyzer 的「可用」判定用它，不用「沒回 NOT_CONNECTED」）；run_sql 的 after 也記三態 ok。
//
// 第 0 步提醒（注入，不是擋）：主 agent（tools 表有 connect 的 primary）的每一則真實使用者訊息，chat.message 會補一個
//   synthetic text part：「先 connect（connection_name＝profile 值原樣；不先 list、不從清單挑名字）→ 才准派會查 DB 的 subagent；
//   工具清單沒有 oracleMCP_ 工具就走 ORACLE_MCP_DOWN」。提醒跟著訊息走（模型最看得到的位置），把「第 0 步常被略過」從 prompt 章節問題變成每題都在眼前的指令；
//   不查 /mcp 狀態、不改狀態機——硬性保證仍是下面的擋。env PS_ORACLE_GATE_REMINDER=off 或 profile oracle.preflightReminder: off 可關。
//
// 呼叫配對（會影響狀態的呼叫都在 before 留入場快照，after 依 session:callID 配對）：
//   - list／connect／disconnect／task 的 before 記 (turn, turnId, state[, target, dbCapable, decision])；after 列用快照標題目，
//     不用「現在」的題目。沒有入場快照的 after → attribution=unknown，不前進。
//   - after 的回覆若屬於上一題（快照 turnId ≠ 目前 turnId）→ attribution=stale：不拿它滿足新題的前置（上一題晚到的
//     connect 成功不算數），也不拿它作廢新題的狀態（上一題晚到的 NOT_CONNECTED 不把新題退回）。disconnect 例外：連線真的
//     斷了，一律退回 NEED_CONNECT。
//   - task 在 await（查 /mcp 狀態）期間題目換了 → 以「題目已換」擋下（保守），列上同時記入場題與決定時的題。
// 成功判定三態：after 有文字且不命中失敗樣式＝成功（true）；命中或 isError＝失敗（false）；沒有文字（空輸出）＝未知
//   （"unknown"）——失敗與未知都不前進。MCP isError 在 OpenCode 內會 throw、after 不觸發（＝失敗）。
//
// 狀態以 session 為單位：
//   - 每則「真實」使用者訊息重置為 NEED_CONNECT（第 0 步「不因上一題已連過就省略」）；turnId＝該則 user 訊息 id（跨行程唯一）。
//     全部 part 都是 synthetic 的訊息（背景 subagent 結果回灌、compaction 續行）與同一 id 重複到達不重置。
//   - subagent 報告 blockedReason=NOT_CONNECTED（同一題）→ 退回 NEED_CONNECT（重派前必須再 connect 一次）。
//   - 本 session 呼叫 oracleMCP_disconnect → 退回 NEED_CONNECT。
// agent tools 表：逐工具明寫、不用 oracleMCP_* 萬用字元 deny 再開個別工具——某些 OpenCode 版本會因萬用字元 deny 把整個 MCP 對該 agent
//   隱藏、後面的 true 救不回（公司機實測）。載入時把有這種混寫的 agent 記到 _plugin.log（wildcardDenyMix），判定本身不變。
//
// 模式：enforce（預設）＝擋；observe＝只記錄不擋（做 hook 覆蓋率探測時用）。
//   環境變數 PS_ORACLE_GATE_MODE 優先，其次 customization-profile.yaml 的 oracle.preflightGate。
// 交易紀錄：<專案>/auto-loop-logs/ps-oracle-gate/<sessionID>.jsonl（只記 oracleMCP_*／task／訊息事件，不記工具輸出原文）；
//   plugin 載入紀錄在同目錄 _plugin.log。
//
// 零外部相依（只用 node:fs／node:path；公司網路封鎖 npm）。OpenCode 自動載入 .opencode/plugin/*.js。

import crypto from "node:crypto"
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
const CALLS_MAX = 2000

// connect／list_connections 回傳文字若命中以下樣式，視為「未成功」（狀態不前進）。
// 只列不可能出現在成功訊息裡的樣式；保守寬鬆——誤判成功的後果是既有的 NOT_CONNECTED 復原路徑，
// 誤判失敗的後果是閘門永遠不開，後者更糟。
// 不列 ORA-nnnnn：SQLcl connect 成功的回覆帶一段說明文字，裡面剛好引用 ORA-nnnnn 錯誤碼（公司機實測）——用它判失敗會讓閘門永遠不開；
// 改用「connection not connected／established／found」這種只會出現在失敗回覆的句型。
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
        db: toolEnabled(tools, TOOL_RUN_SQL),
        connect: toolEnabled(tools, TOOL_CONNECT),
        wildcardDenyMix: wildcardDenyMix(tools),
      })
    } catch {
      // 讀不到的檔跳過；不在目錄裡的名字會被視為會查 DB（保守）
    }
  }
  return catalog
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

function readReminder(directory) {
  const env = String(process.env.PS_ORACLE_GATE_REMINDER ?? "").trim().toLowerCase()
  if (env === "on" || env === "off") return env
  const v = String(readProfileOracle(directory).preflightReminder ?? "").toLowerCase()
  if (v === "on" || v === "off") return v
  return "on"
}

const BASE62 = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"
let idLast = 0n
// 與 OpenCode 的 Identifier.ascending("part") 同形：prt_ + 6 byte（毫秒×4096＋同毫秒計數）hex + 14 碼 base62。
// OpenCode 讀訊息時 part 依 id 排序：提醒要排在使用者文字之後，所以 id 一律取「現有 part 的最大 id＋1」與「現在」的較大者
// （同一毫秒內 OpenCode 自己的計數可能比我們大，不能只看時間）。
function partId(parts) {
  const MASK48 = (1n << 48n) - 1n
  // OpenCode 只寫入低 48 bit（6 byte），比較也在同一個空間做
  let n = (BigInt(Date.now()) * 4096n + 1n) & MASK48
  for (const p of Array.isArray(parts) ? parts : []) {
    const m = typeof p?.id === "string" ? p.id.match(/^prt_([0-9a-f]{12})/) : null
    if (m) {
      const v = BigInt("0x" + m[1]) + 1n
      if (v > n) n = v
    }
  }
  if (n <= idLast) n = idLast + 1n
  idLast = n
  const bytes = Buffer.alloc(6)
  for (let i = 0; i < 6; i++) bytes[i] = Number((n >> BigInt(40 - 8 * i)) & 0xffn)
  const rnd = crypto.randomBytes(14)
  let tail = ""
  for (let i = 0; i < 14; i++) tail += BASE62[rnd[i] % 62]
  return "prt_" + bytes.toString("hex") + tail
}

function buildReminder(profileName, dbTargets) {
  const targets = dbTargets.length ? dbTargets.join("／") : "會查 DB 的 subagent"
  const rule = profileUnset(profileName)
    ? "profile oracle.connectionName 目前未填（FILL_ME）：不要 connect、本題不派會查 DB 的委派，回報「Oracle 連線未設定」"
    : `connection_name＝「${profileName}」原樣照抄，即 profile oracle.connectionName；不必先 list_connections、不要從清單挑名字；其他值會被閘門擋下`
  return (
    "【Oracle 第 0 步（執行期閘門提醒）】回答本題之前，先呼叫 oracleMCP_connect（" + rule + "），" +
    `成功後才准派會查 DB 的 subagent（${targets}）。每一題都要做，不因上一題連過就省略；沒做完就派會被擋下並要求補做。` +
    "connect 失敗 → 再 connect 一次；仍失敗 → 本題不派會查 DB 的 subagent，回報「DB 連線建立失敗」並附 oracleMCP_list_connections 的原文供管理者核對 profile。" +
    "工具清單裡沒有 oracleMCP_ 工具（未掛載）→ 不派會查 DB 的 subagent，DB 部分回 ORACLE_MCP_DOWN。不查 DB 的部分照常作答。"
  )
}

function readMode(directory) {
  const env = String(process.env.PS_ORACLE_GATE_MODE ?? "").trim().toLowerCase()
  if (env === "enforce" || env === "observe") return env
  const v = String(readProfileOracle(directory).preflightGate ?? "").toLowerCase()
  if (v === "enforce" || v === "observe") return v
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

// 三態：true＝有文字且不命中失敗樣式；false＝isError 或命中失敗樣式；"unknown"＝沒有任何文字（不當成功）
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
    return { valid, status: valid ? status : "INVALID", blockedReason: reason, taskState, taskId }
  }
  return { valid: false, status: "INVALID", blockedReason: undefined, taskState, taskId }
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

function connectRule(profileName) {
  const shown = profileUnset(profileName) ? "（目前是 FILL_ME／未填）" : `「${profileName}」`
  return (
    "connection_name＝profile oracle.connectionName 的值" + shown + "原樣照抄；不必先 list_connections、不要從清單挑名字（清單把名稱和連線字串黏在一起，會讀錯）；" +
    "profile 未填／FILL_ME → 不要 connect、本題不派 DB 委派，向使用者回報「Oracle 連線未設定（profile oracle.connectionName＝<值>）」；" +
    "connect 失敗 → 再 connect 一次，仍失敗才呼叫 list_connections 把清單原文附在回報裡讓管理者核對" +
    "（閘門會在執行前擋掉 connection_name ≠ profile 值的 connect）"
  )
}

// connect 的目標檢查：回 undefined＝可以執行；否則回 { code, message }
function connectProblem(profileName, target) {
  if (profileUnset(profileName)) {
    return {
      code: "ORACLE_CONNECTION_NOT_CONFIGURED",
      message:
        `ORACLE_CONNECTION_NOT_CONFIGURED：本次 oracleMCP_connect 未執行（被 Oracle 連線前置閘門擋下）。profile oracle.connectionName 未填` +
        `（目前＝${profileName || "空"}）——請管理者在 .opencode/peoplesoft/customization-profile.yaml 回填 SQLcl 已儲存連線名（實際連得上的那個名字；list_connections 的清單只供核對，它把名稱和連線字串黏在一起）。` +
        "模型：不要猜、不要從清單挑名字；本題不派 DB 委派，向使用者回報「Oracle 連線未設定（profile oracle.connectionName＝<值>）」，其餘部分照常作答。",
    }
  }
  if (!target) {
    return {
      code: "ORACLE_CONNECTION_MISMATCH",
      message:
        `ORACLE_CONNECTION_MISMATCH：本次 oracleMCP_connect 未執行（被 Oracle 連線前置閘門擋下）。呼叫沒有帶 connection_name；` +
        `只准連 profile oracle.connectionName 指定的「${profileName}」——用 connection_name＝「${profileName}」重新呼叫。`,
    }
  }
  if (target !== profileName) {
    return {
      code: "ORACLE_CONNECTION_MISMATCH",
      message:
        `ORACLE_CONNECTION_MISMATCH：本次 oracleMCP_connect 未執行（被 Oracle 連線前置閘門擋下）。connect 目標「${target}」≠ profile oracle.connectionName「${profileName}」。` +
        `只准連 profile 指定的連線：用 connection_name＝「${profileName}」原樣重新呼叫 connect，不要從 list_connections 的清單挑名字（清單把名稱和連線字串黏在一起，會讀錯）。` +
        "仍連不上 → 不派 DB 委派，向使用者回報「DB 連線建立失敗（<connect 回的錯誤>）」並附 list_connections 原文讓管理者核對 profile，其餘部分照常作答。",
    }
  }
  return undefined
}

function buildBlockMessage(target, state, blockedCount, profileName) {
  const lines = [
    `${ERROR_CODE}：本次 task 未執行（被 Oracle 連線前置閘門擋下，不是權限問題）。` +
      `原因：第 0 步尚未完成，不得委派會查 DB 的 subagent「${target}」。目前狀態＝${state}。`,
  ]
  lines.push(
    "下一步：呼叫 oracleMCP_connect（" + connectRule(profileName) + "），成功後再用相同參數重新呼叫本次 task。" +
      "connect 與 task 要依序分開呼叫，不要同一步並行。",
  )
  if (blockedCount >= 3) {
    lines.push(
      `（本輪已被擋 ${blockedCount} 次。connect 若一直失敗，依第 0 步規則：本題不派 DB 委派，` +
        "向使用者回報「DB 連線建立失敗（<connect 回的錯誤>）」，並呼叫一次 oracleMCP_list_connections 把清單原文附上讓管理者核對 profile 值；" +
        "工具清單裡根本沒有 oracleMCP_ 工具則回報 ORACLE_MCP_DOWN。其餘部分照常作答。）",
    )
  }
  return lines.join("\n")
}

function buildDownMessage(target, basis, alternatives) {
  const alt = alternatives.length ? alternatives.join("／") : "（本專案沒有這種 subagent）"
  return [
    `${ERROR_CODE}：本次 task 未執行（被 Oracle 連線前置閘門擋下，不是權限問題）。` +
      `原因：oracleMCP 未掛載（${basis}），本環境目前沒有 Oracle 能力，不得委派會查 DB 的 subagent「${target}」。`,
    "下一步：不要重試本次 task、不要呼叫 list_connections／connect。依 ORACLE_MCP_DOWN 協定：本題需要 DB 的部分如實回報 " +
      "ORACLE_MCP_DOWN（oracleMCP 未掛載），不要用猜的補；非 DB 的部分改派沒有 Oracle 能力的 subagent（" + alt + "）或照常作答。",
  ].join("\n")
}

export const PsOraclePreflightGate = async (input) => {
  const directory = String(input?.directory ?? process.cwd())
  const client = input?.client
  const logDir = path.join(directory, LOG_SUBDIR)
  const sessions = new Map()
  // 入場快照：鍵＝session:callID（OpenAI 相容端點的 call_0 這種 id 會跨 session 重複），值＝before 當下的題目／狀態／判定
  const calls = new Map()
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
      s = { state: "NEED_CONNECT", agent: undefined, turn: 0, turnId: `${process.pid}-0`, blocked: 0, connectGen: 0 }
      sessions.set(sessionID, s)
    }
    return s
  }

  function keyOf(sessionID, callID) {
    return `${sessionID}:${callID}`
  }

  function putEntry(sessionID, callID, entry) {
    if (!callID) return
    const k = keyOf(sessionID, callID)
    calls.delete(k)
    calls.set(k, entry)
    if (calls.size > CALLS_MAX) calls.delete(calls.keys().next().value)
  }

  function takeEntry(sessionID, callID) {
    if (!callID) return undefined
    const k = keyOf(sessionID, callID)
    const e = calls.get(k)
    if (e) calls.delete(k)
    return e
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

  // 目標 subagent 是否會查 DB（要不要過閘門）；dbCapable 是機械欄位，basis 只是說明
  function classifyTarget(target) {
    const entry = catalogFresh().get(target)
    if (!entry) return { gated: true, basis: "unknown-agent(default:DB)" }
    return { gated: entry.db, basis: entry.db ? "run_sql:enabled" : "run_sql:disabled" }
  }

  // 會查 DB 的 subagent 名單（提醒用）
  function dbSubagents() {
    return [...catalogFresh().entries()]
      .filter(([, v]) => v.mode === "subagent" && v.db)
      .map(([name]) => name)
      .sort()
  }

  // 沒有 Oracle 能力的 subagent 名單（oracleMCP 未掛載時錯誤訊息用）
  function nonDbSubagents() {
    return [...catalogFresh().entries()]
      .filter(([, v]) => v.mode === "subagent" && !v.db)
      .map(([name]) => name)
      .sort()
  }

  // 每次即時查、不快取：查不到（例外或非 2xx）→ mounted=undefined＝保守擋
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
    `loaded directory=${directory} mode=${readMode(directory)} reminder=${readReminder(directory)} agents=${JSON.stringify(
      [...catalog.entries()].map(([name, v]) => `${name}:${v.db ? "DB" : "noDB"}`),
    )} wildcardDenyMix=${JSON.stringify([...catalog.entries()].filter(([, v]) => v.wildcardDenyMix).map(([name]) => name))}`,
  )
  for (const [name, v] of catalog.entries()) {
    if (v.wildcardDenyMix) pluginLog(`WARN agent ${name}: tools 表混寫 oracleMCP_* deny ＋ 個別工具 true——某些版本會把整個 MCP 對它隱藏；請逐工具明寫`)
  }

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
      s.state = "NEED_CONNECT"
      s.turn += 1
      s.turnId = typeof mid === "string" && mid ? mid : `${process.pid}-${s.turn}`
      s.blocked = 0
      // 第 0 步提醒：只給有 connect 的主 agent、且訊息 id 已知；補在使用者文字之後（synthetic），模型每題都看得到
      let reminder = false
      if (readReminder(directory) === "on" && typeof mid === "string" && mid && Array.isArray(parts)) {
        const entry = s.agent ? catalogFresh().get(s.agent) : undefined
        if (entry && entry.mode === "primary" && entry.connect) {
          const profileName = String(readProfileOracle(directory).connectionName ?? "").trim()
          parts.push({ id: partId(parts), sessionID, messageID: mid, type: "text", synthetic: true, text: buildReminder(profileName, dbSubagents()) })
          reminder = true
        }
      }
      record(sessionID, { hook: "chat.message", ...stamp(s), state: prev, next: s.state, mode: readMode(directory), reminder })
    },

    "tool.execute.before": async (info, out) => {
      const tool = String(info?.tool ?? "")
      const sessionID = info?.sessionID
      const callID = String(info?.callID ?? "")
      const args = out && typeof out === "object" && out.args && typeof out.args === "object" ? out.args : {}
      if (tool !== TOOL_TASK) {
        if (!tool.startsWith(MCP_PREFIX)) return
        const s = getSession(sessionID)
        if (tool === TOOL_CONNECT) {
          const mode = readMode(directory)
          const profileName = String(readProfileOracle(directory).connectionName ?? "").trim()
          const target = connectionNameOf(args)
          const problem = connectProblem(profileName, target)
          const head = { hook: "before", tool, callID, ...stamp(s), connection: target, profileConnection: profileName }
          if (problem && mode !== "observe") {
            record(sessionID, { ...head, state: s.state, next: s.state, decision: "block", note: problem.code })
            throw new Error(problem.message)
          }
          // 嘗試開始：READY 作廢，直到「這一次」嘗試成功才恢復；世代 +1
          s.connectGen += 1
          const prev = s.state
          if (s.state === "READY") s.state = "NEED_CONNECT"
          putEntry(sessionID, callID, { tool, turn: s.turn, turnId: s.turnId, state: prev, gen: s.connectGen, target })
          record(sessionID, {
            ...head, state: prev, next: s.state, gen: s.connectGen, decision: problem ? "observe-would-block" : "allow",
            note: problem ? problem.code : prev === "READY" ? "connect attempt invalidates READY until it succeeds" : undefined,
          })
          return
        }
        if (tool === TOOL_LIST || tool === TOOL_DISCONNECT || tool === TOOL_RUN_SQL) {
          putEntry(sessionID, callID, { tool, turn: s.turn, turnId: s.turnId, state: s.state })
        }
        record(sessionID, { hook: "before", tool, callID, ...stamp(s), state: s.state, decision: "observe" })
        return
      }
      const target = String(args.subagent_type ?? "")
      const s = getSession(sessionID)
      const mode = readMode(directory)
      const cls = classifyTarget(target)
      const entryTurn = { turn: s.turn, turnId: s.turnId }
      const base = { hook: "before", tool, callID, agent: s.agent, ...entryTurn, target, state: s.state, mode, basis: cls.basis, dbCapable: cls.gated, gen: s.connectGen }
      const admit = (decision) =>
        putEntry(sessionID, callID, { tool, ...entryTurn, state: s.state, target, dbCapable: cls.gated, basis: cls.basis, decision, gen: s.connectGen })
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
      // await 期間題目可能換了（使用者送下一題）或狀態可能已變（同一步並行的 connect 已完成）：兩者都再判一次
      const turnChanged = s.turnId !== entryTurn.turnId
      if (!turnChanged && s.state === "READY") {
        admit("allow")
        record(sessionID, { ...base, state: s.state, decision: "allow", note: "became READY during status check" })
        return
      }
      s.blocked += 1
      const down = mcp.mounted === false
      const profileName = String(readProfileOracle(directory).connectionName ?? "")
      const message = down
        ? buildDownMessage(target, mcp.basis, nonDbSubagents())
        : buildBlockMessage(target, s.state, s.blocked, profileName)
      const note =
        (down ? `oracleMCP not mounted (${mcp.basis}): DB-capable dispatch refused` : mcp.basis) +
        (turnChanged ? `; turn changed during status check (now ${s.turnId})` : "")
      const row = { ...base, state: s.state, blocked: s.blocked, note, ...(turnChanged ? { turnAtDecision: s.turnId } : {}) }
      if (mode === "observe") {
        admit("observe-would-block")
        record(sessionID, { ...row, decision: "observe-would-block" })
        return
      }
      record(sessionID, { ...row, decision: "block" })
      throw new Error(message)
    },

    "tool.execute.after": async (info, out) => {
      const tool = String(info?.tool ?? "")
      const sessionID = info?.sessionID
      if (tool !== TOOL_TASK && !tool.startsWith(MCP_PREFIX)) return
      const callID = String(info?.callID ?? "")
      const s = getSession(sessionID)
      const prev = s.state
      const entry = takeEntry(sessionID, callID)
      // 配對：有快照且題目相同＝current；有快照但題目已換＝stale；沒有快照＝unknown（不前進）
      const attribution = entry ? (entry.turnId === s.turnId ? "current" : "stale") : "unknown"
      const stamped = entry ? { agent: s.agent, turn: entry.turn, turnId: entry.turnId } : stamp(s)
      const base = {
        hook: "after", tool, callID, ...stamped, attribution,
        ...(attribution === "stale" ? { stale: true, replyTurnId: s.turnId } : {}),
      }
      if (tool === TOOL_LIST) {
        // 只記錄、不改狀態：清單不是前置的一部分（名稱與連線字串黏在一起，不能拿來挑名字）；主 agent 只在 connect 失敗後用它附原文給管理者
        const r = classifyResult(out)
        const note = "list_connections is informational: state unchanged" + (attribution === "stale" ? " (reply from previous turn)" : "")
        record(sessionID, { ...base, state: prev, entryState: entry ? entry.state : undefined, next: s.state, ok: r.ok, failureMatch: r.failureMatch || undefined, outputLength: r.textLength, note })
        return
      }
      if (tool === TOOL_CONNECT) {
        const r = classifyResult(out)
        const target = connectionNameOf(info?.args)
        let note
        if (r.ok === true && attribution === "current") {
          if (entry.gen !== s.connectGen) note = "superseded by a later connect attempt: not counted"
          else if (entry.target && target && entry.target !== target) note = "connect args differ from admission: not counted"
          else if (s.state === "NEED_CONNECT") s.state = "READY"
        } else if (r.ok === true && attribution === "stale") note = "stale reply from previous turn: not counted for this turn"
        else if (r.ok === true) note = "no entry snapshot for this callID: not counted"
        else if (r.ok === "unknown") note = "empty tool output: not counted as success"
        record(sessionID, {
          ...base, state: prev, entryState: entry ? entry.state : undefined, gen: entry ? entry.gen : undefined, next: s.state, ok: r.ok,
          failureMatch: r.failureMatch || undefined, outputLength: r.textLength, connection: target, note,
        })
        return
      }
      if (tool === TOOL_RUN_SQL) {
        const r = classifyResult(out)
        record(sessionID, { ...base, state: prev, next: s.state, ok: r.ok, failureMatch: r.failureMatch || undefined, outputLength: r.textLength })
        return
      }
      if (tool === TOOL_DISCONNECT) {
        s.state = "NEED_CONNECT"
        record(sessionID, {
          ...base, state: prev, next: s.state,
          note: "disconnect in this session" + (attribution === "stale" ? " (issued in a previous turn; the connection is gone regardless)" : ""),
        })
        return
      }
      if (tool === TOOL_TASK) {
        const args = info && typeof info.args === "object" && info.args ? info.args : {}
        const target = String(args.subagent_type ?? "")
        const text = outputText(out)
        const rep = parseReport(text)
        const notConnected = rep.blockedReason === "NOT_CONNECTED" || /"blockedReason"\s*:\s*"NOT_CONNECTED"/.test(text)
        const meta = out && typeof out === "object" && out.metadata && typeof out.metadata === "object" ? out.metadata : {}
        const child = typeof meta.sessionId === "string" && meta.sessionId ? meta.sessionId : rep.taskId
        // 能力用入場快照（不在 after 重讀 catalog）；沒有快照才現算並註明
        const cls = entry && typeof entry.dbCapable === "boolean" ? { gated: entry.dbCapable, basis: entry.basis } : { ...classifyTarget(target), late: true }
        let note
        if (cls.gated && notConnected) {
          if (attribution === "stale") note = "stale NOT_CONNECTED from previous turn: current turn state kept"
          else if (entry && typeof entry.gen === "number" && entry.gen !== s.connectGen) {
            note = `NOT_CONNECTED from an older connection attempt (admitted gen ${entry.gen}, now ${s.connectGen}): state kept`
          } else if (s.state === "READY") {
            s.state = "NEED_CONNECT"
            note = "subagent reported NOT_CONNECTED: connect again before re-dispatch"
          }
        }
        record(sessionID, {
          ...base, state: entry ? entry.state : prev, admitted: entry ? entry.decision : "unknown", target, executed: true,
          dbCapable: cls.gated, basis: cls.late ? cls.basis + "(classified after)" : cls.basis, gen: entry ? entry.gen : undefined, next: s.state,
          notConnected, reportValid: rep.valid, reportStatus: rep.status, blockedReason: rep.blockedReason, taskState: rep.taskState,
          childSessionID: child, note,
        })
        return
      }
      record(sessionID, { ...base, state: prev, next: s.state })
    },
  }
}

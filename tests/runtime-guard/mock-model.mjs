// mock-model.mjs — 假 OpenAI 相容模型（/v1/chat/completions、SSE 串流；只給沙箱端到端測試用）
// 依對話內容決定下一個工具呼叫（劇本），把「模型的順序與路由選擇」做成可重現的確定性事件。
// 環境變數：
//   MOCK_MODEL_PORT       監聽埠（預設 18081）
//   MOCK_MODEL_SCENARIO   主 agent 劇本（每一則 user 訊息之後重新走；沒有派工閘門，順序只是劇本）：
//     compliant       connect（profile 值）→ task(ps-ui-flow) → 收尾
//     task-first      先 task(ps-ui-flow)（DB 未連 → subagent 回 BLOCKED(NOT_CONNECTED)）→ connect 一次 → 重派一次 → 收尾
//                     （驗「至多重連＋重派一次」；第二次仍 NOT_CONNECTED 就放棄，不迴圈）
//     nodb            直接派 ps-peoplecode-flow（不查 DB 的 subagent）→ 收尾
//     connect-fail    connect（失敗）→ 再 connect（失敗）→ list 一次附清單原文 → 回報「DB 連線建立失敗」；connect 被目標 guard 擋
//                     （ORACLE_CONNECTION_NOT_CONFIGURED／MISMATCH）→ 回報「Oracle 連線未設定」，不猜名字、不派 DB 委派
//     skill-as-agent  connect → task(subagent_type=ps-security-flow)（誤派，被 guard 擋）→ 依錯誤訊息改派 ps-metadata-flow → 收尾；
//                     被擋之後不 connect、不 list
//     suggested-skill connect → task(ps-ui-flow)（其報告 suggestedNext 帶 ps-security-flow）→ 看到 guard 附註 → 派 ps-metadata-flow → 收尾
//     down-aware      工具清單裡沒有 oracleMCP_connect → 不猜工具名、不派 DB 委派，回報 ORACLE_MCP_DOWN 並結束；有工具就同 compliant
//     down-probe      同 down-aware，但工具消失的那一題會「憑記憶」呼叫一次 oracleMCP_connect（模擬模型記得上一題有這個工具）
//                     → OpenCode 改判 invalid → 之後回報 ORACLE_MCP_DOWN、不再重試
//   MOCK_MODEL_CONNECT_NAME 主 agent「讀到」的 profile 連線名（預設 HR_DEV）：劇本只 connect 這個名字（原樣），從不解析 list 的清單
//   MOCK_MODEL_SUGGEST_SKILL =1 → subagent 的 COMPLETE 報告帶 suggestedNext [{agent:"ps-security-flow"}]（驗 guard 的附註）
//   MOCK_MODEL_LOG        每次請求追加一行 JSON（含該次請求可見的 task／oracleMCP_ 工具名——驗允許清單與工具消失；userText＝最後一則 user 訊息尾端）
import http from "node:http"
import fs from "node:fs"

const port = Number(process.env.MOCK_MODEL_PORT ?? 18081)
const scenario = String(process.env.MOCK_MODEL_SCENARIO ?? "compliant")

function log(entry) {
  const file = process.env.MOCK_MODEL_LOG
  if (!file) return
  try { fs.appendFileSync(file, JSON.stringify({ ts: new Date().toISOString(), ...entry }) + "\n") } catch {}
}

function contentText(c) {
  if (typeof c === "string") return c
  if (Array.isArray(c)) return c.map((p) => (typeof p === "string" ? p : p?.text ?? "")).join("\n")
  return ""
}

function toolNames(body) {
  return new Set((body.tools ?? []).map((t) => t?.function?.name).filter(Boolean))
}

// 把對話壓成「最後一則 user 訊息之後已發生的工具呼叫序列」：[{name, args, result}]；並數 user 訊息（＝第幾題）
function history(body) {
  let calls = []
  let users = 0
  let lastUser = ""
  const byId = new Map()
  for (const m of body.messages ?? []) {
    if (m.role === "user") { calls = []; users += 1; lastUser = contentText(m.content); continue }
    if (m.role === "assistant" && Array.isArray(m.tool_calls)) {
      for (const tc of m.tool_calls) {
        let args = {}
        try { args = JSON.parse(tc.function?.arguments ?? "{}") } catch {}
        const entry = { name: tc.function?.name, args, result: "" }
        calls.push(entry)
        byId.set(tc.id, entry)
      }
    }
    if (m.role === "tool") {
      const e = byId.get(m.tool_call_id)
      if (e) e.result = contentText(m.content)
    }
  }
  return { calls, users, lastUser }
}

const CONNECT_NAME = String(process.env.MOCK_MODEL_CONNECT_NAME ?? "HR_DEV")
const TASK = (target) => ({ name: "task", args: { description: "query " + target, prompt: "請依契約回 JSON：查 MIL_STATUS 的選項", subagent_type: target } })
const LIST = { name: "oracleMCP_list_connections", args: {} }
const CONNECT = (name) => ({ name: "oracleMCP_connect", args: { connection_name: name } })
const done = (calls, extra) => ({ text: "DONE: " + JSON.stringify({ scenario, calls: calls.map((c) => c.name), ...extra }) })

function lastListResult(calls) {
  const l = [...calls].reverse().find((c) => c.name === "oracleMCP_list_connections")
  return l ? l.result : ""
}

function reportOf(call) {
  const m = String(call?.result ?? "").match(/\{[\s\S]*\}/)
  if (!m) return null
  try { return JSON.parse(m[0]) } catch { return null }
}

// 主 agent 劇本：回傳下一個工具呼叫，或 {text} 收尾
function primaryNext(calls, users, tools) {
  const n = calls.length
  const last = calls[n - 1]
  const tasks = calls.filter((c) => c.name === "task")
  const completed = tasks.filter((c) => { const r = reportOf(c); return r && r.status === "COMPLETE" })
  const notConnected = tasks.filter((c) => { const r = reportOf(c); return r && r.blockedReason === "NOT_CONNECTED" })
  const connects = calls.filter((c) => c.name === "oracleMCP_connect")
  const hasOracle = tools.has("oracleMCP_connect")
  switch (scenario) {
    case "down-aware":
    case "down-probe": {
      // 本題已經有一次呼叫被 OpenCode 改判 invalid（工具看不到）→ 回報 DOWN、不再試（就算工具在同一題內又出現）
      const probed = calls.some((c) => c.name === "invalid" || (c.name.startsWith("oracleMCP_") && /unavailable tool|invalid/i.test(c.result)))
      if (probed) return { text: "ORACLE_MCP_DOWN：oracleMCP 工具在本題不可用（呼叫被判 invalid）；不猜工具名、不重試、不派 DB 委派。依人工恢復 SOP（/mcps 重掛）後再問。" + JSON.stringify(calls.map((c) => c.name)) }
      if (!hasOracle) {
        if (scenario === "down-probe" && n === 0) return CONNECT(CONNECT_NAME)
        return { text: "ORACLE_MCP_DOWN：工具清單裡沒有 oracleMCP_ 工具，本題需要 DB 的部分無法回答；不猜工具名、不重試、不派 DB 委派。依人工恢復 SOP（/mcps 重掛）後再問。" + JSON.stringify(calls.map((c) => c.name)) }
      }
      if (n === 0) return CONNECT(CONNECT_NAME)
      if (completed.length >= 1) return done(calls)
      if (last.name === "oracleMCP_connect") return TASK("ps-ui-flow")
      return done(calls, { gaveUp: true })
    }
    case "compliant": {
      if (n === 0) return CONNECT(CONNECT_NAME)
      if (completed.length >= 1) return done(calls)
      if (last.name === "oracleMCP_connect") return TASK("ps-ui-flow")
      return done(calls, { gaveUp: true })
    }
    case "task-first": {
      if (n === 0) return TASK("ps-ui-flow")
      if (completed.length >= 1) return done(calls)
      // NOT_CONNECTED → 至多重連一次、重派一次；第二次仍 NOT_CONNECTED → 放棄（不迴圈）
      if (notConnected.length >= 2) return { text: "DB 連線建立失敗（重連一次後 subagent 仍回 NOT_CONNECTED）：本題不再重派，其餘部分照常作答。" + JSON.stringify(calls.map((c) => c.name)) }
      if (notConnected.length === 1 && connects.length === 0) return CONNECT(CONNECT_NAME)
      if (last.name === "oracleMCP_connect") return TASK("ps-ui-flow")
      return done(calls, { gaveUp: true })
    }
    case "nodb": {
      if (n === 0) return TASK("ps-peoplecode-flow")
      return done(calls)
    }
    case "connect-fail": {
      const guardBlocked = calls.some((c) => c.name === "oracleMCP_connect" && /ORACLE_CONNECTION_(NOT_CONFIGURED|MISMATCH)/.test(c.result))
      if (guardBlocked) return { text: "Oracle 連線未設定（profile oracle.connectionName 未填或與 connect 目標不一致）：本題不派 DB 委派、不猜名字，其餘部分照常作答。" + JSON.stringify(calls.map((c) => c.name)) }
      if (connects.length < 2) return CONNECT(CONNECT_NAME)
      if (!calls.some((c) => c.name === "oracleMCP_list_connections")) return LIST
      return { text: "DB 連線建立失敗（connect 兩次都沒有成功）：本題不派 DB 委派，其餘部分照常作答。清單原文：" + lastListResult(calls) + " " + JSON.stringify(calls.map((c) => c.name)) }
    }
    case "skill-as-agent": {
      if (n === 0) return CONNECT(CONNECT_NAME)
      if (completed.length >= 1) return done(calls)
      const wrong = tasks.find((c) => c.args?.subagent_type === "ps-security-flow")
      if (!wrong) return TASK("ps-security-flow")
      // 錯誤訊息指出承載 agent → 改派；不 connect、不 list
      if (/PS_TASK_TARGET_INVALID/.test(wrong.result) && /ps-metadata-flow/.test(wrong.result) && !tasks.some((c) => c.args?.subagent_type === "ps-metadata-flow")) return TASK("ps-metadata-flow")
      return done(calls, { gaveUp: true })
    }
    case "suggested-skill": {
      if (n === 0) return CONNECT(CONNECT_NAME)
      if (last.name === "oracleMCP_connect") return TASK("ps-ui-flow")
      const first = tasks[0]
      const annotated = first && /\[ps-runtime-guard\]/.test(first.result) && /ps-metadata-flow/.test(first.result)
      if (first && annotated && tasks.length === 1) return TASK("ps-metadata-flow")
      if (first && !annotated && tasks.length === 1) return TASK("ps-security-flow")
      return done(calls, { annotated })
    }
    default:
      return done(calls, { unknownScenario: scenario })
  }
}

// subagent 劇本：有 sql_run 就查一次再回 JSON；沒有（純 ES）直接回 JSON
function subagentNext(calls, tools) {
  if (tools.has("oracleMCP_sql_run") && calls.length === 0) return { name: "oracleMCP_sql_run", args: { sql: "SELECT 1 FROM DUAL" } }
  const sql = calls.find((c) => c.name === "oracleMCP_sql_run")
  const blocked = sql && /not connected/i.test(sql.result)
  const report = blocked
    ? { task: "mock", status: "BLOCKED", blockedReason: "NOT_CONNECTED", findings: [], dependencies: [], dynamicRuntimeWarnings: [], gaps: [] }
    : { task: "mock", status: "COMPLETE", blockedReason: "NOT_APPLICABLE", findings: [{ claim: "MIL_STATUS has 3 values", confidence: "CONFIRMED" }], dependencies: [], dynamicRuntimeWarnings: [], gaps: [] }
  if (!blocked && process.env.MOCK_MODEL_SUGGEST_SKILL === "1") report.suggestedNext = [{ agent: "ps-security-flow", task: "查核 MIL_STATUS 畫面的授權路徑" }]
  return { text: JSON.stringify(report) }
}

let counter = 0
function sse(res, body, next) {
  const id = "chatcmpl-" + ++counter
  res.writeHead(200, { "Content-Type": "text/event-stream", "Cache-Control": "no-cache", Connection: "keep-alive" })
  const chunk = (delta, finish) => res.write("data: " + JSON.stringify({ id, object: "chat.completion.chunk", created: Math.floor(Date.now() / 1000), model: body.model ?? "scripted", choices: [{ index: 0, delta, finish_reason: finish ?? null }] }) + "\n\n")
  if (next.text !== undefined) {
    chunk({ role: "assistant", content: next.text })
    chunk({}, "stop")
  } else {
    chunk({ role: "assistant", tool_calls: [{ index: 0, id: "call_" + counter, type: "function", function: { name: next.name, arguments: JSON.stringify(next.args) } }] })
    chunk({}, "tool_calls")
  }
  res.write("data: " + JSON.stringify({ id, object: "chat.completion.chunk", created: Math.floor(Date.now() / 1000), model: body.model ?? "scripted", choices: [], usage: { prompt_tokens: 10, completion_tokens: 5, total_tokens: 15 } }) + "\n\n")
  res.write("data: [DONE]\n\n")
  res.end()
}

const server = http.createServer((req, res) => {
  let raw = ""
  req.on("data", (c) => (raw += c))
  req.on("end", () => {
    if (req.method === "GET" && req.url?.startsWith("/v1/models")) {
      res.writeHead(200, { "Content-Type": "application/json" })
      return res.end(JSON.stringify({ object: "list", data: [{ id: "scripted", object: "model" }] }))
    }
    let body = {}
    try { body = JSON.parse(raw || "{}") } catch {}
    const tools = toolNames(body)
    const { calls, users, lastUser } = history(body)
    const system = contentText((body.messages ?? []).find((m) => m.role === "system")?.content ?? "")
    let next
    if (tools.has("task")) next = primaryNext(calls, users, tools)
    else if (tools.size > 0) next = subagentNext(calls, tools)
    else next = { text: /title/i.test(system) ? "mock title" : "ok" }
    log({ url: req.url, stream: body.stream, users, tools: [...tools].filter((t) => /^(task|oracleMCP_)/.test(t)), calls: calls.map((c) => c.name), next: next.name ?? "text", userText: lastUser.slice(-300) })
    if (body.stream === false) {
      res.writeHead(200, { "Content-Type": "application/json" })
      const message = next.text !== undefined
        ? { role: "assistant", content: next.text }
        : { role: "assistant", content: null, tool_calls: [{ id: "call_" + ++counter, type: "function", function: { name: next.name, arguments: JSON.stringify(next.args) } }] }
      return res.end(JSON.stringify({ id: "chatcmpl-x", object: "chat.completion", created: 0, model: "scripted", choices: [{ index: 0, message, finish_reason: next.text !== undefined ? "stop" : "tool_calls" }], usage: { prompt_tokens: 1, completion_tokens: 1, total_tokens: 2 } }))
    }
    sse(res, body, next)
  })
})
server.listen(port, "127.0.0.1", () => {
  process.stdout.write("mock-model listening on " + port + " scenario=" + scenario + "\n")
})

// mock-model.mjs — 假 OpenAI 相容模型（/v1/chat/completions、SSE 串流；只給沙箱端到端測試用）
// 依對話內容決定下一個工具呼叫（劇本），把「模型的順序與路由選擇」做成可重現的確定性事件。
// oracleMCP＝@vdeserto/oracle-mcp-server：沒有 connect；主 agent 看不到任何 oracleMCP_ 工具，查詢只由 subagent 以 oracleMCP_oracle_execute_query 做。
// 環境變數：
//   MOCK_MODEL_PORT       監聽埠（預設 18081）
//   MOCK_MODEL_SCENARIO   劇本（每一則 user 訊息之後重新走；沒有派工閘門，順序只是劇本）：
//     compliant        主 agent 直接 task(ps-ui-flow，DB 題) → 收尾
//     redispatch-once  task(ps-ui-flow) → subagent 回 BLOCKED(NOT_CONNECTED) → 重派一次 → COMPLETE 收尾；第二次仍 NOT_CONNECTED → 回報「DB 連線失敗」（不迴圈）
//     nodb             直接派 ps-peoplecode-flow（不查 DB 的 subagent）→ 收尾
//     stale-connect    主 agent 先憑記憶呼叫 SQLcl 時代的 oracleMCP_connect（OpenCode 判 invalid）→ 照常 task(ps-ui-flow) → 收尾
//     skill-as-agent   task(subagent_type=ps-security-flow)（誤派，被 guard 擋）→ 依錯誤訊息改派 ps-metadata-flow → 收尾
//     suggested-skill  task(ps-ui-flow)（其報告 suggestedNext 帶 ps-security-flow）→ 看到 guard 附註 → 派 ps-metadata-flow → 收尾
//     down-aware       task(ps-ui-flow)；subagent 的工具清單裡沒有 oracleMCP_oracle_execute_query → 回 BLOCKED(ORACLE_MCP_DOWN)，主 agent 不重派、回報 DOWN
//     down-probe       同 down-aware，但工具消失時 subagent 會「憑記憶」呼叫一次 oracleMCP_oracle_execute_query（模擬記得上一題有這個工具）
//                      → OpenCode 改判 invalid → 之後回 ORACLE_MCP_DOWN、不再重試
//   subagent（沒有 task 工具的請求）：委派 prompt 含 [DB] 才查 DB——先送業務查詢；回「Error: Database query failed.」就送 SELECT 1 AS OK FROM DUAL，
//     也失敗 → BLOCKED(NOT_CONNECTED)；查得到 → COMPLETE。沒有 [DB]（純 ES 類）直接回 COMPLETE。
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

const Q = "oracleMCP_oracle_execute_query"
const TASK = (target, db = true) => ({ name: "task", args: { description: "query " + target, prompt: (db ? "[DB] " : "") + "請依契約回 JSON：查 MIL_STATUS 的選項", subagent_type: target } })
const STALE_CONNECT = { name: "oracleMCP_connect", args: { connection_name: "HR_DEV" } }
const done = (calls, extra) => ({ text: "DONE: " + JSON.stringify({ scenario, calls: calls.map((c) => c.name), ...extra }) })

function reportOf(call) {
  const m = String(call?.result ?? "").match(/\{[\s\S]*\}/)
  if (!m) return null
  try { return JSON.parse(m[0]) } catch { return null }
}

const invalidCall = (c) => c.name === "invalid" || (c.name.startsWith("oracleMCP_") && /unavailable tool|invalid/i.test(c.result))

// 主 agent 劇本：回傳下一個工具呼叫，或 {text} 收尾。主 agent 沒有 oracleMCP 工具，也沒有開線步驟
function primaryNext(calls, users, tools) {
  const n = calls.length
  const tasks = calls.filter((c) => c.name === "task")
  const reports = tasks.map(reportOf)
  const completed = reports.filter((r) => r && r.status === "COMPLETE")
  const notConnected = reports.filter((r) => r && r.blockedReason === "NOT_CONNECTED")
  const down = reports.filter((r) => r && r.blockedReason === "ORACLE_MCP_DOWN")
  switch (scenario) {
    case "compliant": {
      if (n === 0) return TASK("ps-ui-flow")
      if (completed.length >= 1) return done(calls)
      return done(calls, { gaveUp: true })
    }
    case "redispatch-once": {
      if (n === 0) return TASK("ps-ui-flow")
      if (completed.length >= 1) return done(calls)
      // NOT_CONNECTED → 至多重派一次；第二次仍 NOT_CONNECTED → 回報、不迴圈
      if (notConnected.length >= 2) return { text: "DB 連線失敗（重派一次後 subagent 仍回 NOT_CONNECTED：Error: Database query failed.）：請管理者依 SOP-21 檢查 oracleMCP 的連線設定；本題不再派會查 DB 的委派。" + JSON.stringify(calls.map((c) => c.name)) }
      if (notConnected.length === 1) return TASK("ps-ui-flow")
      return done(calls, { gaveUp: true })
    }
    case "nodb": {
      if (n === 0) return TASK("ps-peoplecode-flow", false)
      return done(calls)
    }
    case "stale-connect": {
      if (n === 0) return STALE_CONNECT
      if (tasks.length === 0) return TASK("ps-ui-flow")
      return done(calls, { staleRejected: invalidCall(calls[0]) })
    }
    case "skill-as-agent": {
      if (completed.length >= 1) return done(calls)
      const wrong = tasks.find((c) => c.args?.subagent_type === "ps-security-flow")
      if (!wrong) return TASK("ps-security-flow")
      // 錯誤訊息指出承載 agent → 改派
      if (/PS_TASK_TARGET_INVALID/.test(wrong.result) && /ps-metadata-flow/.test(wrong.result) && !tasks.some((c) => c.args?.subagent_type === "ps-metadata-flow")) return TASK("ps-metadata-flow")
      return done(calls, { gaveUp: true })
    }
    case "suggested-skill": {
      if (n === 0) return TASK("ps-ui-flow")
      const first = tasks[0]
      const annotated = first && /\[ps-runtime-guard\]/.test(first.result) && /ps-metadata-flow/.test(first.result)
      if (first && annotated && tasks.length === 1) return TASK("ps-metadata-flow")
      if (first && !annotated && tasks.length === 1) return TASK("ps-security-flow")
      return done(calls, { annotated })
    }
    case "down-aware":
    case "down-probe": {
      if (n === 0) return TASK("ps-ui-flow")
      if (down.length >= 1) return { text: "ORACLE_MCP_DOWN：subagent 回報 oracleMCP 工具不可用（掛載故障）；不猜工具名、不重派會查 DB 的委派。依人工恢復 SOP（/mcps 重掛）後再問。" + JSON.stringify(calls.map((c) => c.name)) }
      if (completed.length >= 1) return done(calls)
      return done(calls, { gaveUp: true })
    }
    default:
      return done(calls, { unknownScenario: scenario })
  }
}

// subagent 劇本：[DB] 題先送業務查詢；Database query failed → SELECT 1 AS OK FROM DUAL 判連線；工具不見 → ORACLE_MCP_DOWN
function subagentNext(calls, tools, lastUser) {
  const report = (status, blockedReason, extra = {}) => ({ text: JSON.stringify({ task: "mock", status, blockedReason, findings: status === "COMPLETE" ? [{ claim: "MIL_STATUS has 3 values", confidence: "CONFIRMED" }] : [], dependencies: [], dynamicRuntimeWarnings: [], gaps: [], ...extra }) })
  const complete = () => {
    const r = report("COMPLETE", "NOT_APPLICABLE")
    if (process.env.MOCK_MODEL_SUGGEST_SKILL === "1") {
      const o = JSON.parse(r.text)
      o.suggestedNext = [{ agent: "ps-security-flow", task: "查核 MIL_STATUS 畫面的授權路徑" }]
      return { text: JSON.stringify(o) }
    }
    return r
  }
  if (!/\[DB\]/.test(lastUser)) return complete()
  if (calls.some(invalidCall)) return report("BLOCKED", "ORACLE_MCP_DOWN", { gaps: ["oracleMCP 工具不可用（掛載故障）"] })
  if (!tools.has(Q)) {
    if (scenario === "down-probe" && calls.length === 0) return { name: Q, args: { sql: "SELECT 1 AS OK FROM DUAL", limit: 1 } }
    return report("BLOCKED", "ORACLE_MCP_DOWN", { gaps: ["工具清單沒有 " + Q] })
  }
  const qs = calls.filter((c) => c.name === Q)
  if (qs.length === 0) return { name: Q, args: { sql: "SELECT FIELDVALUE, XLATLONGNAME FROM DEMOOWN.PSXLATITEM WHERE FIELDNAME = 'MIL_STATUS' FETCH FIRST 100 ROWS ONLY", limit: 100 } }
  const last = qs[qs.length - 1]
  const failed = /^\s*Error: Database query failed\./.test(last.result)
  if (!failed) return complete()
  if (qs.length === 1) return { name: Q, args: { sql: "SELECT 1 AS OK FROM DUAL", limit: 1 } }
  return report("BLOCKED", "NOT_CONNECTED", { gaps: ["Error: Database query failed.（SELECT 1 AS OK FROM DUAL 也失敗）"] })
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
    else if (tools.size > 0) next = subagentNext(calls, tools, lastUser)
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

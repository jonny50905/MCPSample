// mock-model.mjs — 假 OpenAI 相容模型（/v1/chat/completions、SSE 串流；只給沙箱端到端測試用）
// 依對話內容決定下一個工具呼叫（劇本），把「模型選錯順序」做成可重現的確定性事件。
// 環境變數：
//   MOCK_MODEL_PORT       監聽埠（預設 18081）
//   MOCK_MODEL_SCENARIO   主 agent 劇本：
//     task-first     （預設）先 task → 被擋 → list → connect → task → 收尾（模擬「常見錯序」）
//     connect-first  先 connect（跳過 list）→ task → 被擋 → list → connect → task → 收尾
//     compliant      list → connect → task → 收尾（第 0 步照做）
//     stubborn       只會一直 task（不做前置），連續 4 次後放棄作答（驗證閘門不放行）
//     nodb           直接派 ps-peoplecode-flow（不查 DB 的 subagent）→ 收尾（驗證不受閘門影響）
//   MOCK_MODEL_LOG        每次請求追加一行 JSON
import http from "node:http"
import fs from "node:fs"

const port = Number(process.env.MOCK_MODEL_PORT ?? 18081)
const scenario = String(process.env.MOCK_MODEL_SCENARIO ?? "task-first")

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

// 把對話壓成「已發生的工具呼叫序列」：[{name, args, result}]
function history(body) {
  const calls = []
  const byId = new Map()
  for (const m of body.messages ?? []) {
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
  return calls
}

function pickConnection(listResult) {
  const m = listResult.match(/^- (.+)$/m)
  return m ? m[1].trim() : "HR_DEV"
}

const TASK = (target) => ({ name: "task", args: { description: "query " + target, prompt: "請依契約回 JSON：查 MIL_STATUS 的選項", subagent_type: target } })
const LIST = { name: "oracleMCP_list_connections", args: {} }
const CONNECT = (name) => ({ name: "oracleMCP_connect", args: { connection_name: name } })

function lastListResult(calls) {
  const l = [...calls].reverse().find((c) => c.name === "oracleMCP_list_connections")
  return l ? l.result : ""
}

// 主 agent 劇本：回傳下一個工具呼叫，或 {text} 收尾
function primaryNext(calls) {
  const n = calls.length
  const last = calls[n - 1]
  const taskDone = calls.filter((c) => c.name === "task" && /task_result/.test(c.result) && !/PS_ORACLE_PREFLIGHT_REQUIRED/.test(c.result)).length
  if (taskDone >= 1) return { text: "DONE: " + JSON.stringify({ scenario, calls: calls.map((c) => c.name) }) }
  switch (scenario) {
    case "compliant": {
      if (n === 0) return LIST
      if (n === 1) return CONNECT(pickConnection(calls[0].result))
      return TASK("ps-ui-flow")
    }
    case "connect-first": {
      if (n === 0) return CONNECT("HR_DEV")
      if (n === 1) return TASK("ps-ui-flow")
      if (last.name === "task") return LIST
      if (last.name === "oracleMCP_list_connections") return CONNECT(pickConnection(last.result))
      return TASK("ps-ui-flow")
    }
    case "stubborn": {
      const attempts = calls.filter((c) => c.name === "task").length
      if (attempts >= 4) return { text: "GAVE_UP after " + attempts + " blocked task attempts" }
      return TASK("ps-ui-flow")
    }
    case "nodb": {
      if (n === 0) return TASK("ps-peoplecode-flow")
      return { text: "DONE: " + JSON.stringify({ scenario, calls: calls.map((c) => c.name) }) }
    }
    case "task-first":
    default: {
      if (n === 0) return TASK("ps-ui-flow")
      if (last.name === "task") return LIST
      if (last.name === "oracleMCP_list_connections") return CONNECT(pickConnection(last.result))
      if (last.name === "oracleMCP_connect") return TASK("ps-ui-flow")
      return TASK("ps-ui-flow")
    }
  }
}

// subagent 劇本：有 run_sql 就查一次再回 JSON；沒有（純 ES）直接回 JSON
function subagentNext(calls, tools) {
  if (tools.has("oracleMCP_run_sql") && calls.length === 0) return { name: "oracleMCP_run_sql", args: { sql: "SELECT 1 FROM DUAL" } }
  const sql = calls.find((c) => c.name === "oracleMCP_run_sql")
  const blocked = sql && /not connected/i.test(sql.result)
  const report = blocked
    ? { task: "mock", status: "BLOCKED", blockedReason: "NOT_CONNECTED", findings: [], dependencies: [], dynamicRuntimeWarnings: [], gaps: [] }
    : { task: "mock", status: "COMPLETE", blockedReason: "NOT_APPLICABLE", findings: [{ claim: "MIL_STATUS has 3 values", confidence: "CONFIRMED" }], dependencies: [], dynamicRuntimeWarnings: [], gaps: [] }
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
    const calls = history(body)
    const system = contentText((body.messages ?? []).find((m) => m.role === "system")?.content ?? "")
    let next
    if (tools.has("task")) next = primaryNext(calls)
    else if (tools.size > 0) next = subagentNext(calls, tools)
    else next = { text: /title/i.test(system) ? "mock title" : "ok" }
    log({ url: req.url, stream: body.stream, tools: [...tools].filter((t) => /^(task|oracleMCP_)/.test(t)), calls: calls.map((c) => c.name), next: next.name ?? "text" })
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

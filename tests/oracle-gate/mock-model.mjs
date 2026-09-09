// mock-model.mjs — 假 OpenAI 相容模型（/v1/chat/completions、SSE 串流；只給沙箱端到端測試用）
// 依對話內容決定下一個工具呼叫（劇本），把「模型選錯順序」做成可重現的確定性事件。
// 環境變數：
//   MOCK_MODEL_PORT       監聽埠（預設 18081）
//   MOCK_MODEL_SCENARIO   主 agent 劇本：
//     task-first     （預設）先 task → 被擋 → list → connect → task → 收尾（模擬「常見錯序」）；
//                    被擋的原因是 oracleMCP 未掛載（ORACLE_MCP_DOWN）→ 不重試、直接回報 ORACLE_MCP_DOWN
//     connect-first  先 connect（跳過 list）→ task → 被擋 → list → connect → task → 收尾
//     compliant      list → connect → task → 收尾（第 0 步照做）
//     stubborn       只會一直 task（不做前置），連續 4 次後放棄作答（驗證閘門不放行）
//     nodb           直接派 ps-peoplecode-flow（不查 DB 的 subagent）→ 收尾（驗證不受閘門影響）
//     connect-fail   task → 被擋 → list → connect（失敗／空輸出）→ task → 被擋 → connect → task → 被擋 → 依第 0 步規則放棄 DB 委派、
//                    回報「DB 連線建立失敗」（驗證閘門沒有「失敗幾次就放行」、空輸出不算成功）
//     stale-probe    第一題：list → connect（慢）→ …；第二題（在第一題的 connect 完成前送進來）：list → task → 被擋 → connect → task
//                    （驗證上一題晚到的 connect 回覆不會替新題完成前置）
//     reconnect-probe list → connect（成功、READY）→ 再 connect 一次（失敗）→ task → 被擋 → connect（失敗）→ task → 被擋 → 放棄
//                    （驗證「已 READY 後再 connect」的嘗試會先作廢 READY，失敗就不放行）
//   connect-fail／reconnect-probe：connect 若被閘門在執行前擋下（ORACLE_CONNECTION_NOT_CONFIGURED／MISMATCH），照第 0 步規則回報「Oracle 連線未設定」
//   劇本以「最後一則 user 訊息之後」的工具呼叫為準（同 session 多 turn 時每 turn 重新走劇本）
//   MOCK_MODEL_LOG        每次請求追加一行 JSON（含該次請求可見的 task／oracleMCP_ 工具名——驗 subagent 的 Oracle 允許清單；
//                         userText＝最後一則 user 訊息文字的尾端——驗閘門注入的第 0 步提醒有送到模型）
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
function primaryNext(calls, users) {
  const n = calls.length
  const last = calls[n - 1]
  const taskDone = calls.filter((c) => c.name === "task" && /task_result/.test(c.result) && !/PS_ORACLE_PREFLIGHT_REQUIRED/.test(c.result)).length
  if (taskDone >= 1) return { text: "DONE: " + JSON.stringify({ scenario, calls: calls.map((c) => c.name) }) }
  const blockedByDown = last && last.name === "task" && /ORACLE_MCP_DOWN/.test(last.result) && /PS_ORACLE_PREFLIGHT_REQUIRED/.test(last.result)
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
    case "connect-fail": {
      if (n === 0) return TASK("ps-ui-flow")
      const blockedTasks = calls.filter((c) => c.name === "task" && /PS_ORACLE_PREFLIGHT_REQUIRED/.test(c.result)).length
      const gateConnect = calls.some((c) => c.name === "oracleMCP_connect" && /ORACLE_CONNECTION_(NOT_CONFIGURED|MISMATCH)/.test(c.result))
      if (blockedTasks >= 3 && gateConnect) return { text: "Oracle 連線未設定（profile oracle.connectionName 與清單不一致或未填）：本題不派 DB 委派，其餘部分照常作答。" + JSON.stringify(calls.map((c) => c.name)) }
      if (blockedTasks >= 3) return { text: "DB 連線建立失敗（connect 沒有成功）：本題不派 DB 委派，其餘部分照常作答。" + JSON.stringify(calls.map((c) => c.name)) }
      const listed = calls.some((c) => c.name === "oracleMCP_list_connections")
      if (last.name === "task") return listed ? CONNECT(pickConnection(lastListResult(calls))) : LIST
      if (last.name === "oracleMCP_list_connections") return CONNECT(pickConnection(last.result))
      return TASK("ps-ui-flow")
    }
    case "stale-probe": {
      if (users <= 1) {
        if (n === 0) return LIST
        if (n === 1) return CONNECT(pickConnection(calls[0].result))
        return TASK("ps-ui-flow")
      }
      if (n === 0) return LIST
      if (n === 1) return TASK("ps-ui-flow")
      if (last.name === "task") return CONNECT(pickConnection(lastListResult(calls)))
      return TASK("ps-ui-flow")
    }
    case "reconnect-probe": {
      if (n === 0) return LIST
      if (n === 1) return CONNECT(pickConnection(calls[0].result))
      if (n === 2) return CONNECT(pickConnection(calls[0].result))
      const blockedTasks = calls.filter((c) => c.name === "task" && /PS_ORACLE_PREFLIGHT_REQUIRED/.test(c.result)).length
      if (blockedTasks >= 3) return { text: "DB 連線建立失敗（再 connect 沒有成功）：本題不派 DB 委派，其餘部分照常作答。" + JSON.stringify(calls.map((c) => c.name)) }
      if (last.name === "task") return CONNECT(pickConnection(calls[0].result))
      return TASK("ps-ui-flow")
    }
    case "task-first":
    default: {
      if (n === 0) return TASK("ps-ui-flow")
      if (blockedByDown) return { text: "ORACLE_MCP_DOWN：oracleMCP 未掛載，本題需要 DB 的部分無法回答；不重試。" + JSON.stringify(calls.map((c) => c.name)) }
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
    const { calls, users, lastUser } = history(body)
    const system = contentText((body.messages ?? []).find((m) => m.role === "system")?.content ?? "")
    let next
    if (tools.has("task")) next = primaryNext(calls, users)
    else if (tools.size > 0) next = subagentNext(calls, tools)
    else next = { text: /title/i.test(system) ? "mock title" : "ok" }
    log({ url: req.url, stream: body.stream, users, tools: [...tools].filter((t) => /^(task|oracleMCP_)/.test(t)), calls: calls.map((c) => c.name), next: next.name ?? "text", userText: lastUser.slice(-600) })
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

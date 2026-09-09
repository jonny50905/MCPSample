// mock-oracle-mcp.mjs — 假 SQLcl MCP server（stdio、JSON-RPC 2.0；只給沙箱端到端測試用）
// 工具名與真 oracleMCP 相同：list_connections／connect／sql_run／disconnect。
// 環境變數：
//   MOCK_ORACLE_LOG                    每次 tools/call 追加一行 JSON（供交叉比對；在呼叫「開始」時寫）
//   MOCK_ORACLE_CONNECT_FAIL           =1 → connect 回 isError（模擬連不上）
//   MOCK_ORACLE_CONNECT_FAIL_FROM      =N → 第 N 次（含）以後的 connect 回 isError（模擬「已連上，再連卻失敗」）
//   MOCK_ORACLE_EMPTY_CONNECT          =1 → connect 成功但回空 content（模擬「成功卻沒有文字」——閘門應判未知、不前進）
//   MOCK_ORACLE_CONNECT_DELAY_FIRST_MS 第一次 connect 延遲 N 毫秒才回（模擬慢連線，讓下一題在它完成前送進來）
//   MOCK_ORACLE_CONNECTIONS            逗號分隔的已儲存連線名（預設 HR_DEV,HR_UAT）
// list_connections 的輸出仿真 SQLcl：每筆「Name:<名>Connect string: {…}」黏在一起、沒有分隔——模型從這裡挑名字會讀錯，
// 所以第 0 步只 connect profile 的值；清單只在 connect 失敗後附原文給管理者核對。
import fs from "node:fs"

const names = String(process.env.MOCK_ORACLE_CONNECTIONS ?? "HR_DEV,HR_UAT").split(",").map((s) => s.trim()).filter(Boolean)
const delayFirst = Number(process.env.MOCK_ORACLE_CONNECT_DELAY_FIRST_MS ?? 0)
const failFrom = Number(process.env.MOCK_ORACLE_CONNECT_FAIL_FROM ?? 0)
let connected = null
let connectCalls = 0
let buffer = ""

function log(entry) {
  const file = process.env.MOCK_ORACLE_LOG
  if (!file) return
  try { fs.appendFileSync(file, JSON.stringify({ ts: new Date().toISOString(), pid: process.pid, ...entry }) + "\n") } catch {}
}

function send(msg) {
  process.stdout.write(JSON.stringify(msg) + "\n")
}

const tools = [
  { name: "list_connections", description: "List saved SQLcl connections", inputSchema: { type: "object", properties: {} } },
  { name: "connect", description: "Connect to a saved connection", inputSchema: { type: "object", properties: { connection_name: { type: "string" } }, required: ["connection_name"] } },
  { name: "sql_run", description: "Run a SQL statement", inputSchema: { type: "object", properties: { sql: { type: "string" } }, required: ["sql"] } },
  { name: "disconnect", description: "Disconnect", inputSchema: { type: "object", properties: {} } },
]

function text(t, isError) {
  return isError ? { content: [{ type: "text", text: t }], isError: true } : { content: [{ type: "text", text: t }] }
}

const wait = (ms) => new Promise((r) => setTimeout(r, ms))

async function call(name, args) {
  log({ tool: name, args, connectedBefore: connected })
  switch (name) {
    case "list_connections":
      return text(names.length ? names.map((n) => "Name:" + n + "Connect string: {jdbc:oracle:thin:@//db.example.internal:1521/" + n + "}").join("\n") : "No saved connections")
    case "connect": {
      connectCalls += 1
      if (connectCalls === 1 && delayFirst > 0) await wait(delayFirst)
      const n = String(args?.connection_name ?? "")
      if (process.env.MOCK_ORACLE_CONNECT_FAIL === "1") return text("ORA-12541: TNS:no listener", true)
      if (failFrom > 0 && connectCalls >= failFrom) return text("ORA-12541: TNS:no listener", true)
      if (!names.includes(n)) return text("Error: connection " + n + " not found", true)
      const already = connected === n
      connected = n
      if (process.env.MOCK_ORACLE_EMPTY_CONNECT === "1") return { content: [] }
      return text(already ? "Already connected to " + n : "Successfully connected to " + n)
    }
    case "sql_run":
      if (!connected) return text("Error: Not connected to a database. Use connect first.", true)
      return text("ROW_COUNT\n1\n(query executed on " + connected + ")")
    case "disconnect":
      connected = null
      return text("Disconnected")
    default:
      return text("Unknown tool " + name, true)
  }
}

function handle(msg) {
  const { id, method, params } = msg
  if (method === "initialize") {
    return send({ jsonrpc: "2.0", id, result: { protocolVersion: params?.protocolVersion ?? "2024-11-05", capabilities: { tools: {} }, serverInfo: { name: "mock-oracle-mcp", version: "0.0.2" } } })
  }
  if (method === "notifications/initialized" || method === "notifications/cancelled") return
  if (method === "ping") return send({ jsonrpc: "2.0", id, result: {} })
  if (method === "tools/list") return send({ jsonrpc: "2.0", id, result: { tools } })
  if (method === "tools/call") {
    call(params?.name, params?.arguments ?? {}).then((result) => send({ jsonrpc: "2.0", id, result }))
    return
  }
  if (id !== undefined) send({ jsonrpc: "2.0", id, error: { code: -32601, message: "Method not found: " + method } })
}

process.stdin.setEncoding("utf8")
process.stdin.on("data", (chunk) => {
  buffer += chunk
  let idx
  while ((idx = buffer.indexOf("\n")) >= 0) {
    const line = buffer.slice(0, idx).trim()
    buffer = buffer.slice(idx + 1)
    if (!line) continue
    try { handle(JSON.parse(line)) } catch (e) { log({ parseError: String(e), line: line.slice(0, 200) }) }
  }
})
process.stdin.on("end", () => process.exit(0))

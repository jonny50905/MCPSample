// mock-oracle-mcp.mjs — 假 SQLcl MCP server（stdio、JSON-RPC 2.0；只給沙箱端到端測試用）
// 工具名與真 oracleMCP 相同：list_connections／connect／run_sql／disconnect。
// 環境變數：
//   MOCK_ORACLE_LOG            每次 tools/call 追加一行 JSON（供交叉比對）
//   MOCK_ORACLE_CONNECT_FAIL   =1 → connect 回 isError（模擬連不上）
//   MOCK_ORACLE_CONNECTIONS    逗號分隔的已儲存連線名（預設 HR_DEV,HR_UAT）
import fs from "node:fs"

const names = String(process.env.MOCK_ORACLE_CONNECTIONS ?? "HR_DEV,HR_UAT").split(",").map((s) => s.trim()).filter(Boolean)
let connected = null
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
  { name: "run_sql", description: "Run a SQL statement", inputSchema: { type: "object", properties: { sql: { type: "string" } }, required: ["sql"] } },
  { name: "disconnect", description: "Disconnect", inputSchema: { type: "object", properties: {} } },
]

function text(t, isError) {
  return isError ? { content: [{ type: "text", text: t }], isError: true } : { content: [{ type: "text", text: t }] }
}

function call(name, args) {
  log({ tool: name, args, connectedBefore: connected })
  switch (name) {
    case "list_connections":
      return text(names.length ? "Saved connections:\n" + names.map((n) => "- " + n).join("\n") : "No saved connections")
    case "connect": {
      const n = String(args?.connection_name ?? "")
      if (process.env.MOCK_ORACLE_CONNECT_FAIL === "1") return text("ORA-12541: TNS:no listener", true)
      if (!names.includes(n)) return text("Error: connection " + n + " not found", true)
      const already = connected === n
      connected = n
      return text(already ? "Already connected to " + n : "Successfully connected to " + n)
    }
    case "run_sql":
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
    return send({ jsonrpc: "2.0", id, result: { protocolVersion: params?.protocolVersion ?? "2024-11-05", capabilities: { tools: {} }, serverInfo: { name: "mock-oracle-mcp", version: "0.0.1" } } })
  }
  if (method === "notifications/initialized" || method === "notifications/cancelled") return
  if (method === "ping") return send({ jsonrpc: "2.0", id, result: {} })
  if (method === "tools/list") return send({ jsonrpc: "2.0", id, result: { tools } })
  if (method === "tools/call") {
    const result = call(params?.name, params?.arguments ?? {})
    return send({ jsonrpc: "2.0", id, result })
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

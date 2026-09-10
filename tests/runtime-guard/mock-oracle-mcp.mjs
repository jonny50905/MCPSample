// mock-oracle-mcp.mjs — 假 SQLcl MCP server（stdio、JSON-RPC 2.0；只給沙箱端到端測試用）
// 工具名與真 oracleMCP 相同：list_connections／connect／sql_run／disconnect（sqlcl_run 不提供，與允許清單無關）。
// 環境變數：
//   MOCK_ORACLE_LOG                    每次 initialize／tools/list／tools/call 追加一行 JSON（供交叉比對；tools/call 在呼叫「開始」時寫）
//   MOCK_ORACLE_CONNECT_FAIL           =1 → connect 回 isError（模擬連不上）
//   MOCK_ORACLE_CONNECT_FAIL_FROM      =N → 第 N 次（含）以後的 connect 回 isError
//   MOCK_ORACLE_EMPTY_CONNECT          =1 → connect 成功但回空 content
//   MOCK_ORACLE_CONNECT_DELAY_FIRST_MS 第一次 connect 延遲 N 毫秒才回
//   MOCK_ORACLE_CONNECTIONS            逗號分隔的已儲存連線名（預設 HR_DEV,HR_UAT）
//   故障注入（issue #31；都配合 MOCK_ORACLE_FAULT_MARKER=<檔>：標記檔不存在才注入一次並建立它——OpenCode 重掛會重新起一個行程，
//   新行程看到標記檔就不再注入，才能驗「重掛後恢復」）：
//   MOCK_ORACLE_VANISH_AFTER_CALLS     =N → 第 N 次 tools/call 回覆後送 notifications/tools/list_changed，之後 tools/list 回空、tools/call 回 Unknown tool
//                                          （模擬「仍 connected、工具目錄變空」）
//   MOCK_ORACLE_EXIT_AFTER_CALLS       =N → 第 N 次 tools/call 回覆後行程結束（模擬 transport 關閉 → OpenCode 狀態 failed: Connection closed）
// list_connections 的輸出仿真 SQLcl：每筆「Name:<名>Connect string: {…}」黏在一起、沒有分隔——模型從這裡挑名字會讀錯，
// 所以主 agent 只 connect profile 的值；清單只在 connect 失敗後附原文給管理者核對。
import fs from "node:fs"

const names = String(process.env.MOCK_ORACLE_CONNECTIONS ?? "HR_DEV,HR_UAT").split(",").map((s) => s.trim()).filter(Boolean)
const delayFirst = Number(process.env.MOCK_ORACLE_CONNECT_DELAY_FIRST_MS ?? 0)
const failFrom = Number(process.env.MOCK_ORACLE_CONNECT_FAIL_FROM ?? 0)
const vanishAfter = Number(process.env.MOCK_ORACLE_VANISH_AFTER_CALLS ?? 0)
const exitAfter = Number(process.env.MOCK_ORACLE_EXIT_AFTER_CALLS ?? 0)
const marker = process.env.MOCK_ORACLE_FAULT_MARKER ?? ""
let connected = null
let connectCalls = 0
let calls = 0
let vanished = false
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

// 故障只注入一次（標記檔）：沒有標記檔 → 注入並建立；已有 → 這個行程是重掛後的新行程，正常服務
function faultArmed() {
  if (!marker) return true
  if (fs.existsSync(marker)) return false
  try { fs.writeFileSync(marker, String(process.pid)) } catch {}
  return true
}

async function call(name, args) {
  log({ tool: name, args, connectedBefore: connected, vanished })
  if (vanished) return text("Unknown tool " + name, true)
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
      return text(already ? "Already connected to " + n : "Successfully connected to " + n + ". (Note: ORA-12170 style timeouts are reported as errors by this tool.)")
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

function afterCall() {
  calls += 1
  if (vanishAfter > 0 && calls === vanishAfter && !vanished && faultArmed()) {
    vanished = true
    log({ fault: "vanish", calls })
    send({ jsonrpc: "2.0", method: "notifications/tools/list_changed" })
  }
  if (exitAfter > 0 && calls === exitAfter && faultArmed()) {
    log({ fault: "exit", calls })
    setTimeout(() => process.exit(0), 100)
  }
}

function handle(msg) {
  const { id, method, params } = msg
  if (method === "initialize") {
    log({ event: "initialize", protocolVersion: params?.protocolVersion })
    return send({ jsonrpc: "2.0", id, result: { protocolVersion: params?.protocolVersion ?? "2024-11-05", capabilities: { tools: { listChanged: true } }, serverInfo: { name: "mock-oracle-mcp", version: "0.0.3" } } })
  }
  if (method === "notifications/initialized" || method === "notifications/cancelled") return
  if (method === "ping") return send({ jsonrpc: "2.0", id, result: {} })
  if (method === "tools/list") {
    log({ event: "tools/list", count: vanished ? 0 : tools.length })
    return send({ jsonrpc: "2.0", id, result: { tools: vanished ? [] : tools } })
  }
  if (method === "tools/call") {
    call(params?.name, params?.arguments ?? {}).then((result) => { send({ jsonrpc: "2.0", id, result }); afterCall() })
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

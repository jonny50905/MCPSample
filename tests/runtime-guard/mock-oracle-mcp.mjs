// mock-oracle-mcp.mjs — 假 oracleMCP（仿 @vdeserto/oracle-mcp-server 1.0.0；stdio、JSON-RPC 2.0；只給沙箱端到端測試用）
// 工具名與真 server 相同：oracle_list_schemas／oracle_list_tables／oracle_describe_table／oracle_execute_query／oracle_get_table_data。
// 沒有 connect／disconnect：連線由環境變數決定（真 server 讀 ORACLE_USER／ORACLE_PASSWORD／ORACLE_CONNECTION_STRING，這裡不檢查）。
// oracle_execute_query 照真 server 的送出前檢查（validateReadOnlySql 的同一組規則）拒絕：分號、註解、非 SELECT／WITH 開頭、DML／DDL 字、
// DBMS_ 等套件名、SELECT…INTO、FOR UPDATE；拒絕訊息與真 server 一樣是葡萄牙文、以「Error:」開頭、不設 isError。
// 成功回 markdown 表格：「**N linha(s) retornada(s)**」＋表格（同真 server 的 formatRows）。
// 環境變數：
//   MOCK_ORACLE_LOG                    每次 initialize／tools/list／tools/call 追加一行 JSON（供交叉比對；tools/call 在呼叫「開始」時寫）
//   MOCK_ORACLE_DB_DOWN                =1 → 每次查詢回「Error: Database query failed.」（真 server 連不上 DB 時的回覆）
//   MOCK_ORACLE_DB_DOWN_CALLS          =N → 前 N 次查詢回「Error: Database query failed.」，之後正常（DB 一時連不上）
//   故障注入（都配合 MOCK_ORACLE_FAULT_MARKER=<檔>：標記檔不存在才注入一次並建立它——OpenCode 重掛會重新起一個行程，
//   新行程看到標記檔就不再注入，才能驗「重掛後恢復」）：
//   MOCK_ORACLE_VANISH_AFTER_CALLS     =N → 第 N 次 tools/call 回覆後送 notifications/tools/list_changed，之後 tools/list 回空、tools/call 回 Unknown tool
//                                          （模擬「仍 connected、工具目錄變空」）
//   MOCK_ORACLE_EXIT_AFTER_CALLS       =N → 第 N 次 tools/call 回覆後行程結束（模擬 transport 關閉 → OpenCode 狀態 failed: Connection closed）
import fs from "node:fs"

const vanishAfter = Number(process.env.MOCK_ORACLE_VANISH_AFTER_CALLS ?? 0)
const exitAfter = Number(process.env.MOCK_ORACLE_EXIT_AFTER_CALLS ?? 0)
const downCalls = Number(process.env.MOCK_ORACLE_DB_DOWN_CALLS ?? 0)
const marker = process.env.MOCK_ORACLE_FAULT_MARKER ?? ""
let calls = 0
let queries = 0
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

const fmt = { type: "string", enum: ["markdown", "json"] }
const tools = [
  { name: "oracle_list_schemas", description: "List schemas", inputSchema: { type: "object", properties: { response_format: fmt } } },
  { name: "oracle_list_tables", description: "List tables", inputSchema: { type: "object", properties: { schema: { type: "string" }, filter: { type: "string" }, limit: { type: "number" }, offset: { type: "number" }, response_format: fmt } } },
  { name: "oracle_describe_table", description: "Describe a table", inputSchema: { type: "object", properties: { table_name: { type: "string" }, schema: { type: "string" }, response_format: fmt }, required: ["table_name"] } },
  { name: "oracle_execute_query", description: "Execute a read-only SELECT", inputSchema: { type: "object", properties: { sql: { type: "string" }, binds: { type: "array" }, limit: { type: "number" }, response_format: fmt }, required: ["sql"] } },
  { name: "oracle_get_table_data", description: "Get table rows", inputSchema: { type: "object", properties: { table_name: { type: "string" }, schema: { type: "string" }, filters: { type: "array" }, order_by: { type: "string" }, columns: { type: "array" }, limit: { type: "number" }, offset: { type: "number" }, response_format: fmt }, required: ["table_name"] } },
]

const text = (t) => ({ content: [{ type: "text", text: t }] })

// 真 server 的 validateReadOnlySql（utils/validation.js）同一組規則
const DANGEROUS = [
  /\bINSERT\b/i, /\bUPDATE\b/i, /\bDELETE\b/i, /\bMERGE\b/i, /\bUPSERT\b/i, /\bDROP\b/i, /\bCREATE\b/i, /\bALTER\b/i, /\bTRUNCATE\b/i,
  /\bRENAME\b/i, /\bCOMMENT\b/i, /\bGRANT\b/i, /\bREVOKE\b/i, /\bEXECUTE\b/i, /\bEXEC\b/i, /\bCALL\b/i,
  /DBMS_/i, /UTL_/i, /OWA_/i, /XMLDB/i, /XDB_/i, /CTXSYS/i, /HTTPURITYPE/i, /URIFACTORY/i, /HTTPWATCHERPACKAGE/i, /\bANYDATA\b/i, /\bXMLTYPE\b/i,
]
function rejectSql(sql) {
  const s = String(sql ?? "").normalize("NFKC")
  if (s.includes(";")) return "Error: Múltiplos statements (;) não são permitidos."
  if (/--/.test(s) || /\/\*/.test(s)) return "Error: Comentários SQL (-- ou /* */) não são permitidos."
  const upper = s.toUpperCase()
  const leading = upper.trimStart()
  if (!leading.startsWith("SELECT") && !leading.startsWith("WITH")) return "Error: Somente SELECT (ou WITH ... SELECT) é permitido. Este servidor é somente leitura."
  if (/\bFOR\s+UPDATE\b/.test(upper)) return "Error: FOR UPDATE não é permitido. Este servidor é somente leitura."
  if (/\bSELECT\b[\s\S]+\bINTO\b/.test(upper)) return "Error: SELECT INTO não é permitido. Este servidor é somente leitura."
  for (const p of DANGEROUS) if (p.test(upper)) return "Error: Operação proibida detectada. Este servidor é somente leitura."
  return ""
}

function call(name, args) {
  log({ tool: name, args, vanished })
  if (vanished) return { content: [{ type: "text", text: "Unknown tool " + name }], isError: true }
  switch (name) {
    case "oracle_execute_query": {
      const bad = rejectSql(args?.sql)
      if (bad) return text(bad)
      queries += 1
      if (process.env.MOCK_ORACLE_DB_DOWN === "1" || queries <= downCalls) return text("Error: Database query failed.")
      return text("**1 linha(s) retornada(s)**\n\n| OK |\n| --- |\n| 1 |")
    }
    case "oracle_list_schemas":
      return text("# Schemas Oracle\n\n- **DEMOOWN**")
    case "oracle_list_tables":
    case "oracle_describe_table":
    case "oracle_get_table_data":
      return text("Nenhum resultado encontrado.")
    default:
      return { content: [{ type: "text", text: "Unknown tool " + name }], isError: true }
  }
}

// 故障只注入一次（標記檔）：沒有標記檔 → 注入並建立；已有 → 這個行程是重掛後的新行程，正常服務
function faultArmed() {
  if (!marker) return true
  if (fs.existsSync(marker)) return false
  try { fs.writeFileSync(marker, String(process.pid)) } catch {}
  return true
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
    return send({ jsonrpc: "2.0", id, result: { protocolVersion: params?.protocolVersion ?? "2024-11-05", capabilities: { tools: { listChanged: true } }, serverInfo: { name: "oracle-mcp-server", version: "1.0.0" } } })
  }
  if (method === "notifications/initialized" || method === "notifications/cancelled") return
  if (method === "ping") return send({ jsonrpc: "2.0", id, result: {} })
  if (method === "tools/list") {
    log({ event: "tools/list", count: vanished ? 0 : tools.length })
    return send({ jsonrpc: "2.0", id, result: { tools: vanished ? [] : tools } })
  }
  if (method === "tools/call") {
    const result = call(params?.name, params?.arguments ?? {})
    send({ jsonrpc: "2.0", id, result })
    afterCall()
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

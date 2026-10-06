// mock-source-mcp.mjs — 假 PeoplecodeElasticSearch／PeoplecodeSource（stdio JSON-RPC；只給維護端 Claude Code e2e 用）
// argv[2]＝es｜source。es：search_chunks 回一筆候選；source：get_chunks_details 回該 chunk 全文、get_file_structure 回一段結構。
// 環境變數 MOCK_SOURCE_LOG：每次 tools/call 追加一行 JSON（工具名與參數鍵名，不記內容）。
import fs from "node:fs"

const mode = process.argv[2] === "source" ? "source" : "es"
const CHUNK = "3f2a9c1e-7b4d-4e8a-9c6f-1d2e3a4b5c6d"
const FILE = "peoplecode/TW_MILITARY_DATA/TW_MILITARY.MIL_STATUS.FieldChange.pcode"
const tools = mode === "es"
  ? [{ name: "search_chunks", description: "Search PeopleCode/SQR/SQL chunks; returns candidate chunk ids only", inputSchema: { type: "object", properties: { query: { type: "string" }, componentType: { type: "string" }, size: { type: "number" } }, required: ["query"] } }]
  : [
      { name: "get_chunks_details", description: "Get full chunk text by chunk ids", inputSchema: { type: "object", properties: { chunkIds: { type: "array", items: { type: "string" } } }, required: ["chunkIds"] } },
      { name: "get_file_structure", description: "Get file outline by fileId", inputSchema: { type: "object", properties: { fileId: { type: "string" } }, required: ["fileId"] } },
    ]
let buffer = ""
const send = (m) => process.stdout.write(JSON.stringify(m) + "\n")
const text = (t) => ({ content: [{ type: "text", text: t }] })
function log(entry) {
  const f = process.env.MOCK_SOURCE_LOG
  if (f) try { fs.appendFileSync(f, JSON.stringify({ ts: new Date().toISOString(), mode, ...entry }) + "\n") } catch {}
}
function call(name, args) {
  log({ tool: name, keys: Object.keys(args ?? {}) })
  if (name === "search_chunks") return text(JSON.stringify({ result: [{ chunkId: CHUNK, filePath: FILE, fileId: "F-001", objectName: "TW_MILITARY_DATA", eventName: "FieldChange", snippet: "If TW_MILITARY.MIL_STATUS = \"E\" Then ..." }] }))
  if (name === "get_chunks_details") return text(JSON.stringify([{ ChunkId: CHUNK, FilePath: FILE, StartLine: 1, EndLine: 6, ComponentType: "PeopleCode", ObjectName: "TW_MILITARY_DATA", EventName: "FieldChange", FieldName: "MIL_STATUS", ChunkText: "If TW_MILITARY.MIL_STATUS = \"E\" Then\n   TW_MILITARY.EXEMPT_RSN.Enabled = True;\n   TW_MILITARY.EXEMPT_DT.Value = %Date;\nElse\n   TW_MILITARY.EXEMPT_RSN.Enabled = False;\nEnd-If;" }]))
  if (name === "get_file_structure") return text(JSON.stringify({ File: { FilePath: FILE }, sections: [{ name: "FieldChange", startLine: 1, endLine: 6 }] }))
  return { content: [{ type: "text", text: "Unknown tool " + name }], isError: true }
}
function handle(msg) {
  const { id, method, params } = msg
  if (method === "initialize") return send({ jsonrpc: "2.0", id, result: { protocolVersion: params?.protocolVersion ?? "2024-11-05", capabilities: { tools: {} }, serverInfo: { name: "mock-" + mode, version: "0.0.1" } } })
  if (method === "notifications/initialized" || method === "notifications/cancelled") return
  if (method === "ping") return send({ jsonrpc: "2.0", id, result: {} })
  if (method === "tools/list") return send({ jsonrpc: "2.0", id, result: { tools } })
  if (method === "tools/call") return send({ jsonrpc: "2.0", id, result: call(params?.name, params?.arguments ?? {}) })
  if (id !== undefined) send({ jsonrpc: "2.0", id, error: { code: -32601, message: "Method not found: " + method } })
}
process.stdin.setEncoding("utf8")
process.stdin.on("data", (c) => {
  buffer += c
  let i
  while ((i = buffer.indexOf("\n")) >= 0) {
    const line = buffer.slice(0, i).trim()
    buffer = buffer.slice(i + 1)
    if (line) try { handle(JSON.parse(line)) } catch (e) { log({ parseError: String(e) }) }
  }
})
process.stdin.on("end", () => process.exit(0))

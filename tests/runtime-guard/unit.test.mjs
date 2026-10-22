// unit.test.mjs — ps-runtime-guard 的單元測試（node --test；零相依）
// 用法：node --test tests/runtime-guard/unit.test.mjs   （repo 根目錄執行）
// 受測：(1) task 目標檢查（skill 名擋下並指出承載 agent；suggestedNext 驗證附註）；
//       (2) oracleMCP 診斷與受控重掛（host 證據觸發、每個故障事件一次、在途不重掛、disabled 不覆蓋、失敗即停、恢復附註一次）。
// oracleMCP＝@vdeserto/oracle-mcp-server：沒有 connect 工具、guard 不擋任何 oracleMCP_ 呼叫（只記錄）；紀錄列上沒有 state／next／READY。
import { test } from "node:test"
import assert from "node:assert/strict"
import fs from "node:fs"
import os from "node:os"
import path from "node:path"
import { fileURLToPath, pathToFileURL } from "node:url"

const here = path.dirname(fileURLToPath(import.meta.url))
const repoRoot = path.resolve(here, "..", "..")
const pluginPath = path.join(repoRoot, ".opencode", "plugin", "ps-runtime-guard.js")
process.env.PS_GUARD_REMOUNT_VERIFY_MS = "1500"
process.env.PS_GUARD_REMOUNT_POLL_MS = "200"
const { PsRuntimeGuard } = await import(pathToFileURL(pluginPath).href)

// 假 client：只用 mcp.status／connect／disconnect 與 experimental.tool.ids；記下每次呼叫
function fakeClient({ status = "connected", error, connectFails = false, connectTo = "connected", toolIds = ["read", "task"] } = {}) {
  const state = { status, error, calls: [] }
  return {
    state,
    mcp: {
      status: async () => {
        state.calls.push("status")
        if (state.status === "throw") throw new Error("boom")
        if (state.status === "absent") return { data: {} }
        return { data: { oracleMCP: { status: state.status, ...(state.error ? { error: state.error } : {}) } } }
      },
      connect: async (args) => {
        // OpenCode 的 /mcp/{name}/connect 連不上也回 true（只有 NotFound 才是錯誤），失敗只看之後的狀態
        state.calls.push("connect:" + JSON.stringify(args))
        if (connectFails) { state.status = "failed"; state.error = "spawn failed"; return { data: true } }
        state.status = connectTo
        state.error = undefined
        return { data: true }
      },
      disconnect: async (args) => {
        state.calls.push("disconnect:" + JSON.stringify(args))
        state.status = "disabled"
        return { data: true }
      },
    },
    experimental: { tool: { ids: async () => ({ data: toolIds }) } },
    session: { get: async () => { throw new Error("session.get must not be called by the guard") } },
  }
}

function copyDir(src, dst) {
  fs.mkdirSync(dst, { recursive: true })
  for (const e of fs.readdirSync(src, { withFileTypes: true })) {
    const s = path.join(src, e.name), d = path.join(dst, e.name)
    if (e.isDirectory()) copyDir(s, d)
    else fs.copyFileSync(s, d)
  }
}

function tempProject({ autoRecover, extraAgent } = {}) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "guard-unit-"))
  copyDir(path.join(repoRoot, ".opencode", "agent"), path.join(dir, ".opencode", "agent"))
  copyDir(path.join(repoRoot, ".opencode", "skills"), path.join(dir, ".opencode", "skills"))
  fs.mkdirSync(path.join(dir, ".opencode", "peoplesoft"), { recursive: true })
  if (extraAgent) fs.writeFileSync(path.join(dir, ".opencode", "agent", extraAgent.name + ".md"), extraAgent.text)
  const profile =
    "searchPolicy:\n  defaultMode: CUSTOM_FIRST\noracle:\n  currentSchema: FILL_ME\n" +
    (autoRecover ? `  mcpAutoRecover: ${autoRecover}\n` : "") +
    "businessDomainMap: business-domain-map.yaml\n"
  fs.writeFileSync(path.join(dir, ".opencode", "peoplesoft", "customization-profile.yaml"), profile)
  return dir
}

const mcpOk = (text) => ({ content: [{ type: "text", text }] })
const taskArgs = (target) => ({ args: { description: "d", prompt: "p", subagent_type: target } })
const userMsg = (id, text = "q") => ({ message: { id }, parts: [{ type: "text", text }] })
const S = "ses_primary"
const COMPLETE_JSON = '{"task":"mock","status":"COMPLETE","blockedReason":"NOT_APPLICABLE","findings":[],"gaps":[]}'
const NOT_CONNECTED_JSON = '{"task":"mock","status":"BLOCKED","blockedReason":"NOT_CONNECTED","findings":[],"gaps":[]}'
const wrap = (child, body, state = "completed") => `<task id="${child}" state="${state}">\n<${state === "error" ? "task_error" : "task_result"}>\n${body}\n</${state === "error" ? "task_error" : "task_result"}>\n</task>`

const before = (hooks, sid, tool, callID, args = {}) => hooks["tool.execute.before"]({ tool, sessionID: sid, callID }, { args })
const after = (hooks, sid, tool, callID, out, args = {}) => hooks["tool.execute.after"]({ tool, sessionID: sid, callID, args }, out)
async function call(hooks, sid, tool, callID, out, args = {}) {
  await before(hooks, sid, tool, callID, args)
  await after(hooks, sid, tool, callID, out, args)
}
const Q = "oracleMCP_oracle_execute_query"
const query = (hooks, sid, id, text = "**1 linha(s) retornada(s)**\n\n| OK |\n| --- |\n| 1 |", sql = "SELECT 1 AS OK FROM DUAL") => call(hooks, sid, Q, id, mcpOk(text), { sql, limit: 1 })
const task = (hooks, sid, id, target = "ps-ui-flow") => hooks["tool.execute.before"]({ tool: "task", sessionID: sid, callID: id }, taskArgs(target))
function taskOut(child, body, state) { return { title: "t", metadata: { parentSessionId: S, sessionId: child }, output: wrap(child, body, state) } }
async function taskDone(hooks, sid, id, body, { target = "ps-ui-flow", child = "ses_child_" + id, state = "completed" } = {}) {
  const out = taskOut(child, body, state)
  await hooks["tool.execute.after"]({ tool: "task", sessionID: sid, callID: id, args: taskArgs(target).args }, out)
  return out
}
const chat = (hooks, sid, id, agent = "ps-orchestrator") => hooks["chat.message"]({ sessionID: sid, agent }, userMsg(id))
const toolsChanged = (hooks, server = "oracleMCP") => hooks.event({ event: { id: "e", type: "mcp.tools.changed", properties: { server } } })
const partError = (hooks, sid, tool, callID, error) => hooks.event({ event: { id: "e", type: "message.part.updated", properties: { part: { type: "tool", tool, sessionID: sid, callID, state: { status: "error", error } } } } })
const invalid = (hooks, sid, attempted, callID = "i") => before(hooks, sid, "invalid", callID, { tool: attempted, error: "Model tried to call unavailable tool '" + attempted + "'" })

function readLog(dir, session) {
  const file = path.join(dir, "auto-loop-logs", "ps-runtime-guard", session + ".jsonl")
  if (!fs.existsSync(file)) return []
  return fs.readFileSync(file, "utf8").trim().split("\n").filter(Boolean).map((l) => JSON.parse(l))
}
function readDiag(dir) {
  const file = path.join(dir, "auto-loop-logs", "ps-runtime-guard", "_mcp-diag.jsonl")
  if (!fs.existsSync(file)) return []
  return fs.readFileSync(file, "utf8").trim().split("\n").filter(Boolean).map((l) => JSON.parse(l))
}
const pluginLog = (dir) => fs.readFileSync(path.join(dir, "auto-loop-logs", "ps-runtime-guard", "_plugin.log"), "utf8")
const last = (dir, session) => readLog(dir, session).at(-1)
const sleep = (ms) => new Promise((r) => setTimeout(r, ms))
const noState = (rows) => rows.every((r) => !("state" in r) && !("next" in r) && !("turnId" in r) && !("gen" in r))

test("oracleMCP_ 呼叫一律只記錄、不擋（沒有 connect 工具也沒有連線目標可比對）；回覆三態：Error: 開頭／isError＝false、空＝unknown", async () => {
  const dir = tempProject()
  const hooks = await PsRuntimeGuard({ directory: dir, client: fakeClient() })
  await chat(hooks, S, "m1", "ps-ui-flow")
  await query(hooks, S, "q1")
  await query(hooks, S, "q2", "Error: Database query failed.")
  await query(hooks, S, "q3", "Error: Múltiplos statements (;) não são permitidos.", "SELECT 1 FROM DUAL;")
  await query(hooks, S, "q4", "Error: Failed to connect to Oracle database. Check your connection settings.")
  await call(hooks, S, Q, "q5", { content: [] }, { sql: "SELECT 1 AS OK FROM DUAL" })
  await call(hooks, S, Q, "q6", { content: [{ type: "text", text: "x" }], isError: true }, { sql: "SELECT 1 AS OK FROM DUAL" })
  // 舊名（SQLcl 的 connect）若被呼叫也只記錄、不擋——工具不存在時 OpenCode 自己會改判成 invalid
  await call(hooks, S, "oracleMCP_connect", "c1", mcpOk("x"), { connection_name: "HR" })
  const log = readLog(dir, S)
  const row = (id, hook) => log.find((l) => l.hook === hook && l.callID === id)
  assert.ok(["q1", "q2", "q3", "q4", "q5", "q6", "c1"].every((id) => row(id, "before").decision === "observe" && row(id, "before").messageID === "m1"))
  assert.equal(row("q1", "after").ok, true)
  for (const id of ["q2", "q3", "q4"]) assert.equal(row(id, "after").ok, false, id)
  assert.match(row("q4", "after").failureMatch, /error|connect/i)
  assert.equal(row("q5", "after").ok, "unknown")
  assert.equal(row("q6", "after").ok, false)
  assert.ok(log.every((l) => l.decision !== "block"), "nothing on oracleMCP is blocked")
  assert.ok(log.every((l) => !("connection" in l) && !("profileConnection" in l) && !("mode" in l)), "no connect-target fields")
  assert.ok(noState(log), "rows carry no dispatch state")
  assert.equal(readDiag(dir).filter((d) => d.kind === "recovery").length, 0, "DB-level errors are never MCP recovery evidence")
})

test("沒有派工閘門：task 一律放行（不擋 DB 委派）；能力只是紀錄欄位（dbCapable＝tools 表開 oracle_execute_query）；查詢 after 三態只記錄", async () => {
  const dir = tempProject()
  const hooks = await PsRuntimeGuard({ directory: dir, client: fakeClient() })
  await chat(hooks, S, "m1")
  for (const t of ["ps-ui-flow", "ps-metadata-flow", "ps-ae-flow", "ps-auditor", "ps-peoplecode-flow", "ps-sql-flow", "ps-sqr-flow", "explore", "general", "scout", "some-unknown-agent"]) {
    await task(hooks, S, "t-" + t, t)
  }
  const log = readLog(dir, S)
  const befores = log.filter((l) => l.hook === "before" && l.tool === "task")
  assert.equal(befores.length, 11)
  assert.ok(befores.every((l) => l.decision === "allow" && typeof l.dbCapable === "boolean" && l.messageID === "m1"))
  assert.deepEqual(befores.filter((l) => l.dbCapable).map((l) => l.target), ["ps-ui-flow", "ps-metadata-flow", "ps-ae-flow", "ps-auditor", "some-unknown-agent"])
  assert.equal(befores.find((l) => l.target === "some-unknown-agent").basis, "unknown-agent(default:DB)")
  assert.ok(noState(log))
  const C = "ses_child"
  await chat(hooks, C, "mc", "ps-ui-flow")
  await call(hooks, C, Q, "q1", mcpOk("**1 linha(s) retornada(s)**\n\n| ROW_COUNT |\n| --- |\n| 1 |"))
  await call(hooks, C, Q, "q2", { content: [{ type: "text", text: "x" }], isError: true })
  await call(hooks, C, Q, "q3", { content: [] })
  const q = (id) => readLog(dir, C).find((l) => l.hook === "after" && l.callID === id)
  assert.equal(q("q1").ok, true); assert.equal(q("q2").ok, false); assert.equal(q("q3").ok, "unknown")
  assert.ok(readLog(dir, C).filter((l) => l.hook === "before").every((l) => l.decision === "observe"))
})

test("task 目標檢查：skill 名不是 agent → 執行前擋、指出承載 agent；同名 agent 與內建 agent 放行；訊息不提 ORACLE_MCP_DOWN", async () => {
  const dir = tempProject()
  const hooks = await PsRuntimeGuard({ directory: dir, client: fakeClient() })
  await chat(hooks, S, "m1")
  await assert.rejects(() => task(hooks, S, "t1", "ps-security-flow"), (e) =>
    /^PS_TASK_TARGET_INVALID/.test(e.message) && /ps-metadata-flow/.test(e.message) && /skills\/ps-security-flow\/SKILL\.md/.test(e.message) &&
    /subagent_type=ps-metadata-flow/.test(e.message) && !/ORACLE_MCP_DOWN/.test(e.message) && !/NOT_CONNECTED/.test(e.message) && /路由錯誤/.test(e.message))
  const row = last(dir, S)
  assert.ok(row.hook === "before" && row.tool === "task" && row.decision === "block" && row.note === "PS_TASK_TARGET_INVALID:skill" && row.carrier === "ps-metadata-flow" && row.target === "ps-security-flow", JSON.stringify(row))
  await assert.rejects(() => task(hooks, S, "t2", "ps-data-lineage"), /ps-metadata-flow/)
  await assert.rejects(() => task(hooks, S, "t3", "ps-process-flow"), /ps-metadata-flow/)
  await assert.rejects(() => task(hooks, S, "t4", "ps-business-explain"), /主 agent 自己 read/)
  for (const ok of ["ps-ui-flow", "ps-ae-flow", "ps-peoplecode-flow", "ps-sql-flow", "ps-sqr-flow", "ps-metadata-flow", "ps-auditor", "general", "explore", "scout"]) await task(hooks, S, "ok-" + ok, ok)
  assert.equal(readLog(dir, S).filter((l) => l.decision === "block").length, 4)
  assert.equal(readDiag(dir).filter((d) => d.kind === "recovery").length, 0, "routing errors never trigger recovery")
})

test("task 的 after：報告解析（COMPLETE／BLOCKED NOT_CONNECTED／非 JSON／task_error）與 suggestedNext 驗證附註（skill 名→承載 agent；不存在的 agent）", async () => {
  const dir = tempProject()
  const hooks = await PsRuntimeGuard({ directory: dir, client: fakeClient() })
  await chat(hooks, S, "m1")
  await task(hooks, S, "t1")
  const o1 = await taskDone(hooks, S, "t1", COMPLETE_JSON.replace('"gaps":[]', '"gaps":[],"suggestedNext":[{"agent":"ps-security-flow","task":"查授權"},{"agent":"ps-metadata-flow","task":"排程"},{"agent":"ps-nope","task":"x"}]'))
  assert.match(o1.output, /\[ps-runtime-guard\] 報告的 suggestedNext 含無效委派目標/)
  assert.match(o1.output, /「ps-security-flow」是 skill、不是 agent：改派 ps-metadata-flow（subagent_type=ps-metadata-flow）/)
  assert.match(o1.output, /「ps-nope」不是已載入的 agent/)
  assert.ok(!/ps-metadata-flow」/.test(o1.output.split("[ps-runtime-guard]")[1].replace(/subagent_type=ps-metadata-flow|改派 ps-metadata-flow/g, "")), "the valid suggestion is not flagged")
  assert.match(o1.output, /^<task id="ses_child_t1"/, "report body untouched, note appended")
  let row = last(dir, S)
  assert.ok(row.hook === "after" && row.reportStatus === "COMPLETE" && row.reportValid === true && row.childSessionID === "ses_child_t1" && row.taskState === "completed" && row.notConnected === false, JSON.stringify(row))
  assert.deepEqual(row.suggestedNextInvalid, [{ agent: "ps-security-flow", kind: "skill", carrier: "ps-metadata-flow" }, { agent: "ps-nope", kind: "unknown" }])
  const o2 = await taskDone(hooks, S, "t2", COMPLETE_JSON.replace('"gaps":[]', '"gaps":[],"suggestedNext":[{"agent":"ps-metadata-flow","task":"排程"}]'))
  assert.ok(!/ps-runtime-guard/.test(o2.output)); assert.equal(last(dir, S).suggestedNextInvalid, undefined)
  await taskDone(hooks, S, "t3", NOT_CONNECTED_JSON)
  row = last(dir, S); assert.ok(row.notConnected === true && row.reportStatus === "BLOCKED" && row.blockedReason === "NOT_CONNECTED")
  await taskDone(hooks, S, "t4", "not json at all")
  row = last(dir, S); assert.ok(row.reportValid === false && row.reportStatus === "INVALID")
  await taskDone(hooks, S, "t5", "boom", { state: "error" })
  row = last(dir, S); assert.ok(row.taskState === "error" && row.reportStatus === "INVALID")
  assert.equal(readDiag(dir).filter((d) => d.kind === "recovery").length, 0, "NOT_CONNECTED reports are DB-level: never MCP recovery evidence")
  assert.ok(noState(readLog(dir, S)))
})

test("chat.message 只記錄訊息 id 與 agent（synthetic 標記）；沒有重置語意", async () => {
  const dir = tempProject()
  const hooks = await PsRuntimeGuard({ directory: dir, client: fakeClient() })
  await chat(hooks, S, "m1")
  await hooks["chat.message"]({ sessionID: S, agent: "ps-orchestrator" }, { message: { id: "ms" }, parts: [{ type: "text", text: "continue", synthetic: true }] })
  await task(hooks, S, "t1")
  await chat(hooks, S, "m2")
  await task(hooks, S, "t2")
  const log = readLog(dir, S)
  assert.deepEqual(log.map((l) => [l.hook, l.messageID, l.synthetic]), [["chat.message", "m1", undefined], ["chat.message", "m1", true], ["before", "m1", undefined], ["chat.message", "m2", undefined], ["before", "m2", undefined]])
  assert.ok(noState(log))
})

test("診斷（auto off）：tools.changed→狀態 failed 記 would-remount、不呼叫 connect；connected 時標 catalog suspect、下一次呼叫證實；part error 遮罩；其他 server 不理", async () => {
  const dir = tempProject()
  const client = fakeClient({ status: "failed", error: "Connection closed" })
  const hooks = await PsRuntimeGuard({ directory: dir, client })
  await toolsChanged(hooks, "otherMCP")
  assert.equal(readDiag(dir).filter((d) => d.kind !== "loaded").length, 0)
  await toolsChanged(hooks)
  let diag = readDiag(dir)
  assert.deepEqual(diag.filter((d) => d.kind !== "loaded").map((d) => [d.kind, d.reason ?? d.decision ?? d.type]), [["event", "mcp.tools.changed"], ["snapshot", "tools-changed"], ["snapshot", "recovery-candidate"], ["recovery", "would-remount"]])
  const rec = diag.find((d) => d.kind === "recovery")
  assert.ok(rec.faultReason === "transport-closed" && rec.runtimeStatus === "failed" && rec.autoRecover === "off" && rec.recoveryGen === 0, JSON.stringify(rec))
  const snap = diag.find((d) => d.kind === "snapshot")
  assert.ok(snap.runtimeStatus === "failed" && snap.statusError === "Connection closed" && snap.configuredEnabled === true && snap.toolCatalog === "empty (or not exposed by this host version)" && Array.isArray(snap.seenTools), JSON.stringify(snap))
  assert.ok(!client.state.calls.some((c) => /connect/.test(c)), "no connect/disconnect when auto recovery is off")
  client.state.status = "connected"
  await toolsChanged(hooks)
  diag = readDiag(dir)
  assert.match(diag.at(-1).note, /marked suspect/)
  assert.equal(diag.at(-2).catalogSuspect, false)
  await chat(hooks, S, "m1")
  await query(hooks, S, "q1")
  assert.equal(readDiag(dir).at(-1).type, "catalog-proven")
  await partError(hooks, S, Q, "q2", "MCP error -32000: transport closed jdbc:oracle:thin:@//db.internal:1521/HR password=secret")
  const te = readDiag(dir).find((d) => d.kind === "tool-error")
  assert.ok(te && te.error === "MCP error -32000: transport closed jdbc:*** password=***" && te.tool === Q, JSON.stringify(te))
  assert.equal(last(dir, S).hook, "part-error")
})

test("invalid 呼叫的判讀：從沒執行過的名字＝可能錯名（不重掛）；agent 的 tools 表本來就關＝權限過濾（不重掛）；執行過的工具對允許它的 agent 消失＝目錄遺失（候選）", async () => {
  const dir = tempProject()
  const client = fakeClient()
  const hooks = await PsRuntimeGuard({ directory: dir, client })
  const U = "ses_ui"
  await chat(hooks, U, "mu", "ps-ui-flow")
  await invalid(hooks, U, "oracleMCP_sql_run", "i1")
  let row = last(dir, U)
  assert.ok(row.hook === "invalid" && row.attempted === "oracleMCP_sql_run" && row.seenBefore === false && row.allowedByAgent === true && /wrong name/.test(row.note), JSON.stringify(row))
  assert.equal(readDiag(dir).filter((d) => d.kind === "recovery").length, 0)
  await chat(hooks, S, "m1", "ps-orchestrator")
  await invalid(hooks, S, Q, "i2")
  row = last(dir, S)
  assert.ok(row.allowedByAgent === false && /permission-filtered/.test(row.note), JSON.stringify(row))
  assert.equal(readDiag(dir).filter((d) => d.kind === "recovery").length, 0)
  await query(hooks, U, "q1")
  await invalid(hooks, U, Q, "i3")
  row = last(dir, U)
  assert.ok(row.seenBefore === true && row.allowedByAgent === true && /catalog loss/.test(row.note), JSON.stringify(row))
  const rec = readDiag(dir).filter((d) => d.kind === "recovery")
  assert.equal(rec.length, 1); assert.ok(rec[0].faultReason === "catalog-lost" && rec[0].decision === "would-remount" && rec[0].evidence.attempted === Q && rec[0].evidence.agent === "ps-ui-flow")
})

test("受控重掛（auto on）：failed → disconnect+connect 各一次 → remount-ok；恢復附註每 session 一次；verified-by-call 關閉故障事件；新事件才再重掛", async () => {
  const dir = tempProject({ autoRecover: "on" })
  const client = fakeClient({ status: "failed", error: "Connection closed" })
  const hooks = await PsRuntimeGuard({ directory: dir, client })
  await chat(hooks, S, "m1")
  await toolsChanged(hooks)
  let rec = readDiag(dir).filter((d) => d.kind === "recovery")
  assert.deepEqual(rec.map((r) => r.decision), ["remount-start", "remount-ok"])
  assert.ok(rec[1].gen === 1 && rec[1].disconnect === true && rec[1].connect === true && rec[1].runtimeStatus === "connected" && /SELECT 1 AS OK FROM DUAL/.test(rec[1].verify), JSON.stringify(rec[1]))
  assert.deepEqual(client.state.calls.filter((c) => /connect/.test(c)), ['disconnect:{"path":{"name":"oracleMCP"}}', 'connect:{"path":{"name":"oracleMCP"}}'])
  // 恢復附註：本 session 的下一次 oracleMCP_／task 回覆附一次
  const out = mcpOk("**1 linha(s) retornada(s)**\n\n| OK |\n| --- |\n| 1 |")
  await before(hooks, S, Q, "c1", { sql: "SELECT 1 AS OK FROM DUAL" })
  await after(hooks, S, Q, "c1", out, { sql: "SELECT 1 AS OK FROM DUAL" })
  assert.ok(out.content.length === 2 && /恢復世代 1/.test(out.content[1].text) && /SELECT 1 AS OK FROM DUAL/.test(out.content[1].text) && !/connect/.test(out.content[1].text), JSON.stringify(out))
  assert.ok(last(dir, S).recoveryNotice === true && last(dir, S).recoveryGen === 1)
  assert.equal(readDiag(dir).at(-1).decision, "verified-by-call")
  const out2 = mcpOk("1")
  await call(hooks, S, Q, "q1", out2)
  assert.equal(out2.content.length, 1, "notice only once per session")
  const o3 = await taskDone(hooks, "ses_other", "t9", COMPLETE_JSON)
  assert.match(o3.output, /恢復世代 1/, "another session gets the notice once, on a task reply")
  // 故障事件已關閉（verified-by-call）→ 新的故障可以再自動恢復一次（gen 2）
  client.state.status = "failed"
  await toolsChanged(hooks)
  rec = readDiag(dir).filter((d) => d.kind === "recovery")
  assert.equal(rec.filter((r) => r.decision === "remount-ok").length, 2)
  assert.equal(rec.at(-1).gen, 2)
})

test("受控重掛的邊界：同時多個證據只重掛一次；重掛後未驗證就再故障＝失敗（不迴圈）；失敗後 suppressed；disabled／needs_auth／absent 不重掛；在途呼叫先等", async () => {
  process.env.PS_ORACLE_MCP_AUTO_RECOVER = "on"
  try {
    // 同時多個證據
    const dir = tempProject()
    const client = fakeClient({ status: "failed", error: "Connection closed" })
    const hooks = await PsRuntimeGuard({ directory: dir, client })
    await Promise.all([toolsChanged(hooks), toolsChanged(hooks), partError(hooks, S, Q, "q1", "MCP error: transport closed")])
    let rec = readDiag(dir).filter((d) => d.kind === "recovery")
    assert.equal(rec.filter((r) => r.decision === "remount-ok").length, 1)
    assert.ok(rec.some((r) => r.decision === "merged"))
    assert.equal(client.state.calls.filter((c) => c.startsWith("connect:")).length, 1)
    // 未驗證就再故障 → 視為恢復失敗；之後 suppressed，不再 connect
    client.state.status = "failed"
    await toolsChanged(hooks)
    rec = readDiag(dir).filter((d) => d.kind === "recovery")
    assert.ok(rec.at(-1).decision === "suppressed" && /before the previous remount was verified/.test(rec.at(-1).note), JSON.stringify(rec.at(-1)))
    await toolsChanged(hooks)
    assert.ok(/previous automatic recovery failed/.test(readDiag(dir).filter((d) => d.kind === "recovery").at(-1).note))
    assert.equal(client.state.calls.filter((c) => c.startsWith("connect:")).length, 1, "no reconnect loop")
    // 人工恢復後有一次呼叫成功 → 故障事件關閉
    await chat(hooks, S, "m1")
    await call(hooks, S, Q, "q2", mcpOk("1"))
    assert.match(readDiag(dir).at(-1).note, /manual recovery happened/)
    // remount 本身失敗 → remount-failed、之後 suppressed
    const dir2 = tempProject()
    const client2 = fakeClient({ status: "failed", error: "Connection closed", connectFails: true })
    const hooks2 = await PsRuntimeGuard({ directory: dir2, client: client2 })
    await toolsChanged(hooks2)
    let rec2 = readDiag(dir2).filter((d) => d.kind === "recovery")
    assert.deepEqual(rec2.map((r) => r.decision), ["remount-start", "remount-failed"])
    assert.ok(rec2[1].connect === true && rec2[1].runtimeStatus === "failed" && rec2[1].statusError === "spawn failed" && /manual SOP/.test(rec2[1].note), JSON.stringify(rec2[1]))
    await toolsChanged(hooks2)
    assert.equal(readDiag(dir2).filter((d) => d.kind === "recovery").at(-1).decision, "suppressed")
    assert.equal(client2.state.calls.filter((c) => c.startsWith("connect:")).length, 1)
    // disabled／needs_auth／absent／unavailable 不重掛
    for (const st of ["disabled", "needs_auth", "needs_client_registration", "absent", "throw"]) {
      const d3 = tempProject()
      const c3 = fakeClient({ status: st })
      const h3 = await PsRuntimeGuard({ directory: d3, client: c3 })
      await toolsChanged(h3)
      const r3 = readDiag(d3).filter((d) => d.kind === "recovery")
      assert.ok(r3.length === 1 && r3[0].decision === "not-eligible", st + ": " + JSON.stringify(r3))
      assert.ok(!c3.state.calls.some((c) => /connect/.test(c)), st + ": no connect")
    }
    // 在途呼叫：先 deferred，after 回來後才重掛
    const dir4 = tempProject()
    const client4 = fakeClient({ status: "connected" })
    const hooks4 = await PsRuntimeGuard({ directory: dir4, client: client4 })
    await chat(hooks4, S, "m1")
    await before(hooks4, S, Q, "q1", { sql: "SELECT 1 AS OK FROM DUAL" })
    client4.state.status = "failed"; client4.state.error = "Connection closed"
    const pending = toolsChanged(hooks4)
    await sleep(300)
    let rec4 = readDiag(dir4).filter((d) => d.kind === "recovery")
    assert.ok(rec4.at(-1).decision === "deferred" && /in flight/.test(rec4.at(-1).note), JSON.stringify(rec4))
    assert.equal(client4.state.calls.filter((c) => c.startsWith("connect:")).length, 0, "not remounting over in-flight work")
    await after(hooks4, S, Q, "q1", mcpOk("1"), { sql: "SELECT 1 AS OK FROM DUAL" })
    await pending
    rec4 = readDiag(dir4).filter((d) => d.kind === "recovery")
    assert.equal(rec4.at(-1).decision, "remount-ok")
    assert.equal(client4.state.calls.filter((c) => c.startsWith("connect:")).length, 1)
  } finally {
    delete process.env.PS_ORACLE_MCP_AUTO_RECOVER
  }
})

test("載入紀錄：自動重掛／診斷開關（沒有連線 guard 開關）；tools 表混寫萬用字元 deny＋個別 true 記 WARN；skills 清單", async () => {
  const dir = tempProject({ extraAgent: { name: "ps-mixed", text: '---\nmode: subagent\ntools:\n  "oracleMCP_*": false\n  "oracleMCP_oracle_execute_query": true\n---\n# mixed\n' } })
  await PsRuntimeGuard({ directory: dir, client: fakeClient() })
  const log = pluginLog(dir)
  assert.match(log, /loaded .* autoRecover=off diag=on/)
  assert.doesNotMatch(log, /connectGuard/)
  assert.match(log, /wildcardDenyMix=\["ps-mixed"\]/)
  assert.match(log, /WARN agent ps-mixed/)
  assert.match(log, /skills=\[.*"ps-security-flow".*\]/)
  assert.match(log, /"ps-ui-flow:DB"/); assert.match(log, /"ps-peoplecode-flow:noDB"/)
  assert.equal(readDiag(dir)[0].kind, "loaded")
})

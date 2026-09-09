// unit.test.mjs — ps-oracle-preflight-gate 的狀態機單元測試（node --test；零相依）
// 用法：node --test tests/oracle-gate/unit.test.mjs   （repo 根目錄執行）
// 真實 host 的每次工具呼叫都是 before → after 成對（同一 callID）；這裡的工具呼叫一律兩段都送，
// 只有刻意驗「晚到」「沒有入場紀錄」的案例才把 before／after 拆開或省略。
import { test } from "node:test"
import assert from "node:assert/strict"
import fs from "node:fs"
import os from "node:os"
import path from "node:path"
import { fileURLToPath } from "node:url"

const here = path.dirname(fileURLToPath(import.meta.url))
const repoRoot = path.resolve(here, "..", "..")
const pluginPath = path.join(repoRoot, ".opencode", "plugin", "ps-oracle-preflight-gate.js")
const { PsOraclePreflightGate } = await import(pluginPath)

// 假 client：閘門只用 mcp.status。statusSeq 依序回不同狀態（驗「每次即時查、不快取」）；onStatus 可在查狀態時插事件（驗 await 期間題目換了）；
// session.get 一律炸——閘門不得查祖先 session
function fakeClient({ mcp = "connected", statusSeq, onStatus } = {}) {
  return {
    mcp: {
      status: async () => {
        if (onStatus) await onStatus()
        const cur = statusSeq && statusSeq.length ? statusSeq.shift() : mcp
        if (cur === "throw") throw new Error("boom")
        if (cur === "http-error") return { error: { name: "x" }, response: { status: 500 } }
        return { data: cur === "absent" ? {} : { oracleMCP: { status: cur } } }
      },
    },
    session: { get: async () => { throw new Error("session.get must not be called by the gate") } },
  }
}

function tempProject({ profileGate, connectionName = "HR", reminder } = {}) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "gate-unit-"))
  fs.mkdirSync(path.join(dir, ".opencode", "agent"), { recursive: true })
  fs.mkdirSync(path.join(dir, ".opencode", "peoplesoft"), { recursive: true })
  for (const f of fs.readdirSync(path.join(repoRoot, ".opencode", "agent"))) {
    fs.copyFileSync(path.join(repoRoot, ".opencode", "agent", f), path.join(dir, ".opencode", "agent", f))
  }
  const profile = "searchPolicy:\n  defaultMode: CUSTOM_FIRST\noracle:\n  currentSchema: FILL_ME\n  connectionName: " + connectionName + "\n" + (profileGate ? `  preflightGate: ${profileGate}\n` : "") + (reminder ? `  preflightReminder: ${reminder}\n` : "") + "businessDomainMap: business-domain-map.yaml\n"
  fs.writeFileSync(path.join(dir, ".opencode", "peoplesoft", "customization-profile.yaml"), profile)
  return dir
}

const mcpOk = (text) => ({ content: [{ type: "text", text }] })
const taskArgs = (target) => ({ args: { description: "d", prompt: "p", subagent_type: target } })
const userMsg = (id, text = "q") => ({ message: { id }, parts: [{ type: "text", text }] })
const S = "ses_primary"
const NOT_CONNECTED = '<task_result>{"status":"BLOCKED","blockedReason":"NOT_CONNECTED"}</task_result>'
const COMPLETE = '<task_result>{"status":"COMPLETE"}</task_result>'
const NOT_CONNECTED_JSON = '{"task":"mock","status":"BLOCKED","blockedReason":"NOT_CONNECTED","findings":[],"gaps":[]}'

const before = (hooks, sid, tool, callID, args = {}) => hooks["tool.execute.before"]({ tool, sessionID: sid, callID }, { args })
const after = (hooks, sid, tool, callID, out, args = {}) => hooks["tool.execute.after"]({ tool, sessionID: sid, callID, args }, out)
async function call(hooks, sid, tool, callID, out, args = {}) {
  await before(hooks, sid, tool, callID, args)
  await after(hooks, sid, tool, callID, out, args)
}
const list = (hooks, sid, id = "l", text = "Saved connections:\n- HR") => call(hooks, sid, "oracleMCP_list_connections", id, mcpOk(text))
const connect = (hooks, sid, id = "c", text = "Successfully connected to HR", name = "HR") => call(hooks, sid, "oracleMCP_connect", id, mcpOk(text), { connection_name: name })
const disconnect = (hooks, sid, id = "d") => call(hooks, sid, "oracleMCP_disconnect", id, mcpOk("Disconnected"))
const task = (hooks, sid, id, target = "ps-ui-flow") => hooks["tool.execute.before"]({ tool: "task", sessionID: sid, callID: id }, taskArgs(target))
const taskDone = (hooks, sid, id, text, target = "ps-ui-flow", child = "ses_child_" + id) =>
  hooks["tool.execute.after"]({ tool: "task", sessionID: sid, callID: id, args: taskArgs(target).args }, { title: "t", metadata: { parentSessionId: sid, sessionId: child }, output: text })
// OpenCode task 工具的輸出包裝：<task id="<子 session>" state="…"><task_result>…</task_result></task>
const wrap = (child, body, state = "completed") => `<task id="${child}" state="${state}">\n<${state === "error" ? "task_error" : "task_result"}>\n${body}\n</${state === "error" ? "task_error" : "task_result"}>\n</task>`
const chat = (hooks, sid, id, agent = "ps-orchestrator") => hooks["chat.message"]({ sessionID: sid, agent }, userMsg(id))

async function expectBlock(fn, state) {
  await assert.rejects(fn, (e) => /PS_ORACLE_PREFLIGHT_REQUIRED/.test(e.message) && new RegExp("目前狀態＝" + state).test(e.message))
}

function readLog(dir, session) {
  const file = path.join(dir, "auto-loop-logs", "ps-oracle-gate", session + ".jsonl")
  return fs.readFileSync(file, "utf8").trim().split("\n").map((l) => JSON.parse(l))
}
const last = (dir, session) => readLog(dir, session).at(-1)

test("agent 目錄分類：只有 run_sql 開的 subagent 過閘門；不認識的名字保守視為會查 DB；每列都有 dbCapable", async () => {
  const dir = tempProject()
  const hooks = await PsOraclePreflightGate({ directory: dir, client: fakeClient() })
  await chat(hooks, S, "m1")
  for (const t of ["ps-ui-flow", "ps-metadata-flow", "ps-ae-flow", "ps-auditor", "some-unknown-agent"]) {
    await expectBlock(() => task(hooks, S, "c", t), "NEED_LIST")
  }
  for (const t of ["ps-peoplecode-flow", "ps-sql-flow", "ps-sqr-flow", "explore", "general", "scout"]) {
    await task(hooks, S, "c", t)
  }
  const log = readLog(dir, S)
  const blocks = log.filter((l) => l.decision === "block")
  assert.equal(blocks.length, 5)
  assert.ok(blocks.every((l) => l.dbCapable === true))
  const allows = log.filter((l) => l.decision === "allow")
  assert.equal(allows.length, 6)
  assert.ok(allows.every((l) => l.dbCapable === false && l.basis === "run_sql:disabled"))
  assert.ok(log.some((l) => l.basis === "unknown-agent(default:DB)" && l.dbCapable === true))
  assert.ok(log.filter((l) => l.hook === "before").every((l) => l.turnId === "m1" && l.callID === "c"))
})

test("狀態機：list → connect → READY 才放行；connect 先於 list 不算；失敗樣式／isError／空輸出都不前進（三態）", async () => {
  const dir = tempProject()
  const hooks = await PsOraclePreflightGate({ directory: dir, client: fakeClient() })
  await chat(hooks, S, "m1")
  await connect(hooks, S, "c0")
  await expectBlock(() => task(hooks, S, "t1"), "NEED_LIST")
  await list(hooks, S, "l1")
  await expectBlock(() => task(hooks, S, "t2"), "NEED_CONNECT")
  await connect(hooks, S, "c1", "ORA-12541: TNS:no listener")
  await expectBlock(() => task(hooks, S, "t3"), "NEED_CONNECT")
  await call(hooks, S, "oracleMCP_connect", "c2", { content: [] }, { connection_name: "HR" })
  await expectBlock(() => task(hooks, S, "t4"), "NEED_CONNECT")
  await call(hooks, S, "oracleMCP_connect", "c3", { content: [{ type: "text", text: "Connected" }], isError: true }, { connection_name: "HR" })
  await expectBlock(() => task(hooks, S, "t5"), "NEED_CONNECT")
  await connect(hooks, S, "c4", "Already connected to HR")
  await task(hooks, S, "t6")
  // READY 之後再 list／connect 一次（模型多做）不影響
  await list(hooks, S, "l2")
  await connect(hooks, S, "c5", "Already connected to HR")
  await task(hooks, S, "t7")
  const log = readLog(dir, S)
  const blocks = log.filter((l) => l.decision === "block")
  assert.deepEqual(blocks.map((b) => b.state), ["NEED_LIST", "NEED_CONNECT", "NEED_CONNECT", "NEED_CONNECT", "NEED_CONNECT"])
  assert.deepEqual(blocks.map((b) => b.blocked), [1, 2, 3, 4, 5])
  const rows = (id) => log.find((l) => l.hook === "after" && l.callID === id)
  assert.equal(rows("c0").note, "connect before list_connections: list still required")
  assert.equal(rows("c1").ok, false); assert.ok(rows("c1").failureMatch)
  assert.equal(rows("c2").ok, "unknown"); assert.match(rows("c2").note, /empty tool output/); assert.equal(rows("c2").next, "NEED_CONNECT")
  assert.equal(rows("c3").ok, false); assert.equal(rows("c3").failureMatch, "isError")
  assert.equal(rows("c4").ok, true); assert.equal(rows("c4").next, "READY"); assert.equal(rows("c4").connection, "HR")
  const c5b = log.find((l) => l.hook === "before" && l.callID === "c5")
  assert.ok(c5b.state === "READY" && c5b.next === "NEED_CONNECT" && /invalidates READY/.test(c5b.note) && c5b.decision === "allow" && c5b.profileConnection === "HR", "READY 後再 connect：嘗試開始就作廢 READY")
  assert.equal(rows("c5").next, "READY")
  assert.ok(log.filter((l) => l.hook === "after" && /^oracleMCP_/.test(l.tool)).every((l) => l.attribution === "current" && l.turnId === "m1"))
  assert.deepEqual(log.filter((l) => l.decision === "allow" && l.tool === "task").map((l) => l.state), ["READY", "READY"])
})

test("沒有入場紀錄的 after（只送 after）：attribution=unknown、不前進；成對的呼叫才算", async () => {
  const dir = tempProject()
  const hooks = await PsOraclePreflightGate({ directory: dir, client: fakeClient() })
  await chat(hooks, S, "m1")
  await after(hooks, S, "oracleMCP_list_connections", "ghost-l", mcpOk("- HR"))
  await after(hooks, S, "oracleMCP_connect", "ghost-c", mcpOk("Successfully connected to HR"), { connection_name: "HR" })
  let log = readLog(dir, S)
  assert.deepEqual(log.filter((l) => l.hook === "after").map((l) => [l.attribution, l.ok, l.next]), [["unknown", true, "NEED_LIST"], ["unknown", true, "NEED_LIST"]])
  assert.ok(log.filter((l) => l.hook === "after").every((l) => /no entry snapshot/.test(l.note)))
  await expectBlock(() => task(hooks, S, "t1"), "NEED_LIST")
  await list(hooks, S)
  await connect(hooks, S)
  await task(hooks, S, "t2")
  log = readLog(dir, S)
  assert.equal(log.at(-1).decision, "allow")
  // task 沒有入場紀錄 → admitted=unknown、能力現算並註明
  await taskDone(hooks, S, "ghost-t", COMPLETE)
  const row = last(dir, S)
  assert.equal(row.admitted, "unknown"); assert.equal(row.attribution, "unknown"); assert.equal(row.dbCapable, true); assert.match(row.basis, /classified after/)
})

test("subagent 回 NOT_CONNECTED → 重派前必須再 connect；disconnect → 從頭；新訊息 → 重置（turnId＝訊息 id）", async () => {
  const dir = tempProject()
  const hooks = await PsOraclePreflightGate({ directory: dir, client: fakeClient() })
  await chat(hooks, S, "m1")
  await list(hooks, S)
  await connect(hooks, S)
  await task(hooks, S, "t1")
  await taskDone(hooks, S, "t1", NOT_CONNECTED)
  await expectBlock(() => task(hooks, S, "t2"), "NEED_CONNECT")
  await connect(hooks, S, "c2")
  await task(hooks, S, "t3")
  await disconnect(hooks, S)
  await expectBlock(() => task(hooks, S, "t4"), "NEED_LIST")
  await list(hooks, S, "l2")
  await connect(hooks, S, "c3")
  await task(hooks, S, "t5")
  await chat(hooks, S, "m2")
  await expectBlock(() => task(hooks, S, "t6"), "NEED_LIST")
  const log = readLog(dir, S)
  const nc = log.find((l) => l.hook === "after" && l.tool === "task" && l.callID === "t1")
  assert.ok(nc.notConnected === true && nc.next === "NEED_CONNECT" && nc.state === "READY" && nc.admitted === "allow" && nc.dbCapable === true && nc.attribution === "current")
  const chats = log.filter((l) => l.hook === "chat.message")
  assert.deepEqual(chats.map((c) => [c.turn, c.turnId, c.state, c.next]), [[1, "m1", "NEED_LIST", "NEED_LIST"], [2, "m2", "READY", "NEED_LIST"]])
  assert.equal(log.at(-1).turnId, "m2")
})

test("observe 模式（env 優先、其次 profile）只記錄不擋；after 列標 admitted=observe-would-block", async () => {
  const dir = tempProject({ profileGate: "observe" })
  const hooks = await PsOraclePreflightGate({ directory: dir, client: fakeClient() })
  await chat(hooks, S, "m1")
  await task(hooks, S, "t1")
  assert.equal(last(dir, S).decision, "observe-would-block")
  await taskDone(hooks, S, "t1", NOT_CONNECTED)
  const row = last(dir, S)
  assert.equal(row.executed, true); assert.equal(row.admitted, "observe-would-block"); assert.equal(row.state, "NEED_LIST"); assert.equal(row.dbCapable, true)
  process.env.PS_ORACLE_GATE_MODE = "enforce"
  try {
    await expectBlock(() => task(hooks, S, "t2"), "NEED_LIST")
  } finally {
    delete process.env.PS_ORACLE_GATE_MODE
  }
})

test("oracleMCP 未掛載（absent／disabled／failed／needs_auth）→ 一樣擋，訊息改 ORACLE_MCP_DOWN 協定；查不到→擋；每次即時查不快取；READY／不查 DB 的委派不查狀態", async () => {
  const dir = tempProject()
  for (const [mcp, down] of [["absent", true], ["disabled", true], ["failed", true], ["needs_auth", true], ["throw", false], ["http-error", false], ["connected", false]]) {
    const hooks = await PsOraclePreflightGate({ directory: dir, client: fakeClient({ mcp }) })
    const sid = "ses_" + mcp
    await chat(hooks, sid, "m1")
    await assert.rejects(() => task(hooks, sid, "c"), (e) => /PS_ORACLE_PREFLIGHT_REQUIRED/.test(e.message) && (down
      ? /oracleMCP 未掛載/.test(e.message) && /ORACLE_MCP_DOWN/.test(e.message) && /ps-peoplecode-flow/.test(e.message) && !/list_connections  2\)/.test(e.message)
      : /目前狀態＝NEED_LIST/.test(e.message) && !/未掛載/.test(e.message)))
    const row = last(dir, sid)
    assert.equal(row.decision, "block")
    assert.equal(row.blocked, 1)
    if (down) assert.match(row.note, /^oracleMCP not mounted \(mcp-status:/)
  }
  assert.match(last(dir, "ses_http-error").note, /mcp-status:error\(500\)/)
  assert.match(last(dir, "ses_throw").note, /mcp-status:unavailable\(boom\)/)
  assert.match(last(dir, "ses_absent").note, /mcp-status:absent/)
  // 不快取：failed 之後馬上 connected → 第二次訊息就是一般前置訊息
  const hooks = await PsOraclePreflightGate({ directory: dir, client: fakeClient({ statusSeq: ["failed", "connected"] }) })
  await chat(hooks, S, "m1")
  await assert.rejects(() => task(hooks, S, "c1"), /未掛載/)
  await assert.rejects(() => task(hooks, S, "c2"), (e) => /目前狀態＝NEED_LIST/.test(e.message) && !/未掛載/.test(e.message))
  // 不查 DB 的委派與 READY 的 session 不查 mcp 狀態（client 一查就炸）
  const hooks2 = await PsOraclePreflightGate({ directory: dir, client: fakeClient({ mcp: "throw" }) })
  await chat(hooks2, "ses_noquery", "m1")
  await task(hooks2, "ses_noquery", "n1", "ps-peoplecode-flow")
  assert.equal(last(dir, "ses_noquery").decision, "allow")
  await list(hooks2, "ses_noquery")
  await connect(hooks2, "ses_noquery")
  await task(hooks2, "ses_noquery", "n2")
  assert.equal(last(dir, "ses_noquery").decision, "allow")
})

test("全部 part 都 synthetic 的 user 訊息不重置；同一訊息 id 重複到達不重置；真實新訊息才重置", async () => {
  const dir = tempProject()
  const hooks = await PsOraclePreflightGate({ directory: dir, client: fakeClient() })
  await chat(hooks, S, "msg_1")
  await list(hooks, S)
  await connect(hooks, S)
  await hooks["chat.message"]({ sessionID: S, agent: "ps-orchestrator" }, { message: { id: "msg_synth" }, parts: [{ type: "text", text: "<task_result>…</task_result>", synthetic: true }] })
  await task(hooks, S, "t1")
  let log = readLog(dir, S)
  assert.equal(log.at(-1).decision, "allow")
  assert.equal(log.at(-1).turnId, "msg_1")
  assert.ok(log.some((l) => l.hook === "chat.message" && l.synthetic === true && l.state === "READY" && l.next === "READY"))
  await chat(hooks, S, "msg_1")
  assert.match(last(dir, S).note, /same message id: no reset/)
  await task(hooks, S, "t2")
  assert.equal(last(dir, S).decision, "allow")
  await chat(hooks, S, "msg_2")
  await expectBlock(() => task(hooks, S, "t3"), "NEED_LIST")
  log = readLog(dir, S)
  assert.equal(log.at(-1).turnId, "msg_2")
  assert.equal(log.filter((l) => l.hook === "chat.message" && l.mode).length, 2)
})

test("task 執行中使用者送下一題：after 列用入場快照；上一題晚到的 NOT_CONNECTED 不把新題的 READY 退回", async () => {
  const dir = tempProject()
  const hooks = await PsOraclePreflightGate({ directory: dir, client: fakeClient() })
  await chat(hooks, S, "m1")
  await list(hooks, S, "l1")
  await connect(hooks, S, "c1")
  await task(hooks, S, "t1")
  // 下一題到了（狀態重置），新題自己做完前置
  await chat(hooks, S, "m2")
  await list(hooks, S, "l2")
  await connect(hooks, S, "c2")
  // 舊題的 task 此時才回 NOT_CONNECTED
  await taskDone(hooks, S, "t1", NOT_CONNECTED)
  const row = last(dir, S)
  assert.equal(row.executed, true); assert.equal(row.turnId, "m1"); assert.equal(row.turn, 1); assert.equal(row.state, "READY"); assert.equal(row.admitted, "allow")
  assert.equal(row.attribution, "stale"); assert.equal(row.replyTurnId, "m2"); assert.equal(row.notConnected, true)
  assert.equal(row.next, "READY"); assert.match(row.note, /stale NOT_CONNECTED from previous turn/)
  await task(hooks, S, "t2")
  assert.equal(last(dir, S).decision, "allow")
  // 同一題的 NOT_CONNECTED 才退回
  await taskDone(hooks, S, "t2", NOT_CONNECTED)
  assert.equal(last(dir, S).next, "NEED_CONNECT")
  await expectBlock(() => task(hooks, S, "t3"), "NEED_CONNECT")
})

test("上一題晚到的 connect／list 成功回覆：標 stale、不拿來滿足新題的前置", async () => {
  const dir = tempProject()
  const hooks = await PsOraclePreflightGate({ directory: dir, client: fakeClient() })
  await chat(hooks, S, "m1")
  await list(hooks, S, "l1")
  await before(hooks, S, "oracleMCP_connect", "c1", { connection_name: "HR" }) // A 題的 connect 開始，尚未完成
  await chat(hooks, S, "m2")
  await list(hooks, S, "l2") // B 題 list 完成 → NEED_CONNECT
  await after(hooks, S, "oracleMCP_connect", "c1", mcpOk("Successfully connected to HR"), { connection_name: "HR" }) // A 題的 connect 此時才回
  let row = last(dir, S)
  assert.equal(row.attribution, "stale"); assert.equal(row.stale, true); assert.equal(row.turnId, "m1"); assert.equal(row.replyTurnId, "m2")
  assert.equal(row.ok, true); assert.equal(row.next, "NEED_CONNECT"); assert.match(row.note, /stale reply from previous turn/)
  await expectBlock(() => task(hooks, S, "t1"), "NEED_CONNECT") // B 沒有自己 connect → 仍擋
  await connect(hooks, S, "c2")
  await task(hooks, S, "t2")
  assert.equal(last(dir, S).decision, "allow")
  // 晚到的 list 也一樣
  await chat(hooks, S, "m3")
  await before(hooks, S, "oracleMCP_list_connections", "l3")
  await chat(hooks, S, "m4")
  await after(hooks, S, "oracleMCP_list_connections", "l3", mcpOk("- HR"))
  row = last(dir, S)
  assert.equal(row.attribution, "stale"); assert.equal(row.turnId, "m3"); assert.equal(row.next, "NEED_LIST")
  await expectBlock(() => task(hooks, S, "t3"), "NEED_LIST")
  // 上一題發出的 disconnect 晚到：連線真的斷了，一律退回 NEED_LIST
  await list(hooks, S, "l4")
  await before(hooks, S, "oracleMCP_disconnect", "d1")
  await chat(hooks, S, "m5")
  await list(hooks, S, "l5")
  await connect(hooks, S, "c5")
  await after(hooks, S, "oracleMCP_disconnect", "d1", mcpOk("Disconnected"))
  row = last(dir, S)
  assert.equal(row.attribution, "stale"); assert.equal(row.next, "NEED_LIST"); assert.match(row.note, /previous turn/)
  await expectBlock(() => task(hooks, S, "t4"), "NEED_LIST")
})

test("task 在查 /mcp 狀態的 await 期間題目換了：以「題目已換」擋下，列上同時記入場題與決定時的題", async () => {
  const dir = tempProject()
  let hooks
  const client = fakeClient({ onStatus: async () => { await chat(hooks, S, "m2") } })
  hooks = await PsOraclePreflightGate({ directory: dir, client })
  await chat(hooks, S, "m1")
  await expectBlock(() => task(hooks, S, "t1"), "NEED_LIST")
  const row = last(dir, S)
  assert.equal(row.turnId, "m1"); assert.equal(row.turnAtDecision, "m2"); assert.match(row.note, /turn changed during status check \(now m2\)/)
  // 新題照常做前置後放行（client 之後不再插事件）
  client.mcp.status = async () => ({ data: { oracleMCP: { status: "connected" } } })
  await list(hooks, S)
  await connect(hooks, S)
  await task(hooks, S, "t2")
  assert.equal(last(dir, S).decision, "allow"); assert.equal(last(dir, S).turnId, "m2")
})

test("沒有 fail-open：connect／list 一直失敗，會查 DB 的 task 一律擋（第 0 步規則：本題不派 DB 委派）", async () => {
  const dir = tempProject()
  const hooks = await PsOraclePreflightGate({ directory: dir, client: fakeClient() })
  await chat(hooks, S, "m1", "ps-deep-research")
  await list(hooks, S, "l")
  // connect 回 MCP isError → 只有 before（after 不會觸發）
  await before(hooks, S, "oracleMCP_connect", "c1", { connection_name: "HR" })
  await expectBlock(() => task(hooks, S, "t1", "ps-auditor"), "NEED_CONNECT")
  await connect(hooks, S, "c2", "ORA-12541: TNS:no listener")
  await expectBlock(() => task(hooks, S, "t2", "ps-auditor"), "NEED_CONNECT")
  await before(hooks, S, "oracleMCP_connect", "c3", { connection_name: "HR" })
  await assert.rejects(() => task(hooks, S, "t3", "ps-auditor"), (e) => /目前狀態＝NEED_CONNECT/.test(e.message) && /已被擋 3 次/.test(e.message) && /DB 連線建立失敗/.test(e.message))
  let log = readLog(dir, S)
  assert.equal(log.filter((l) => l.hook === "before" && l.tool === "task" && l.decision === "allow").length, 0)
  assert.deepEqual(log.filter((l) => l.decision === "block").map((l) => l.blocked), [1, 2, 3])
  // list 一直失敗：前兩次 isError（無 after）、第三次回錯誤文字 → 仍 NEED_LIST、仍擋
  const S2 = "ses_nolist"
  await chat(hooks, S2, "m9", "ps-deep-research")
  await before(hooks, S2, "oracleMCP_list_connections", "a")
  await before(hooks, S2, "oracleMCP_list_connections", "b")
  await after(hooks, S2, "oracleMCP_list_connections", "b", mcpOk("Error: cannot list"))
  await expectBlock(() => task(hooks, S2, "t", "ps-auditor"), "NEED_LIST")
  log = readLog(dir, S2)
  assert.equal(log.filter((l) => l.decision === "allow").length, 0)
  assert.ok(log.some((l) => l.tool === "oracleMCP_list_connections" && l.hook === "after" && l.ok === false))
})

test("沒有祖先放行：父 session READY 不代表子 session READY；閘門不查 session.get", async () => {
  const dir = tempProject()
  const hooks = await PsOraclePreflightGate({ directory: dir, client: fakeClient() })
  await chat(hooks, "ses_root", "m1", "ps-deep-research")
  await list(hooks, "ses_root")
  await connect(hooks, "ses_root")
  await task(hooks, "ses_root", "t", "ps-auditor")
  await chat(hooks, "ses_child", "mc", "ps-audit-orchestrator")
  await expectBlock(() => task(hooks, "ses_child", "t", "ps-auditor"), "NEED_LIST")
  assert.equal(last(dir, "ses_root").decision, "allow")
  assert.equal(last(dir, "ses_child").decision, "block")
})

test("同一 callID 字串跨 session 不互撞（OpenAI 相容端點的 call_0）：入場快照各歸各的 session", async () => {
  const dir = tempProject()
  const hooks = await PsOraclePreflightGate({ directory: dir, client: fakeClient() })
  const X = "ses_X", Y = "ses_Y"
  for (const sid of [X, Y]) {
    await chat(hooks, sid, "m" + sid)
    await list(hooks, sid, "call_0")
  }
  await connect(hooks, X, "call_0")
  await task(hooks, X, "call_1")
  await expectBlock(() => task(hooks, Y, "call_1"), "NEED_CONNECT")
  await connect(hooks, Y, "call_0")
  await task(hooks, Y, "call_1")
  await taskDone(hooks, X, "call_1", COMPLETE)
  await taskDone(hooks, Y, "call_1", COMPLETE)
  assert.equal(last(dir, X).turnId, "mses_X"); assert.equal(last(dir, X).admitted, "allow"); assert.equal(last(dir, X).attribution, "current")
  assert.equal(last(dir, Y).turnId, "mses_Y"); assert.equal(last(dir, Y).admitted, "allow")
})

test("擋下訊息裡的連線規則：profile oracle.connectionName 有填就點名，沒填就說 FILL_ME；都不准自己挑清單第一個", async () => {
  const dir1 = tempProject({ connectionName: "HR_PROD" })
  const h1 = await PsOraclePreflightGate({ directory: dir1, client: fakeClient() })
  await chat(h1, S, "m1")
  await assert.rejects(() => task(h1, S, "t1"), (e) => /「HR_PROD」/.test(e.message) && /不要自己挑清單第一個/.test(e.message) && !/否則清單第一個/.test(e.message))
  const dir2 = tempProject({ connectionName: "FILL_ME" })
  const h2 = await PsOraclePreflightGate({ directory: dir2, client: fakeClient() })
  await chat(h2, S, "m1")
  await list(h2, S)
  await assert.rejects(() => task(h2, S, "t1"), (e) => /FILL_ME／未填/.test(e.message) && /只差 oracleMCP_connect/.test(e.message))
})

test("connect 目標在執行前強制比對 profile：FILL_ME／未填 → ORACLE_CONNECTION_NOT_CONFIGURED；不一致 → ORACLE_CONNECTION_MISMATCH；一致才執行；observe 只記", async () => {
  const dir = tempProject({ connectionName: "HR_PROD" })
  const hooks = await PsOraclePreflightGate({ directory: dir, client: fakeClient() })
  await chat(hooks, S, "m1")
  await list(hooks, S)
  await assert.rejects(() => before(hooks, S, "oracleMCP_connect", "c1", { connection_name: "HR_UAT" }), (e) => /ORACLE_CONNECTION_MISMATCH/.test(e.message) && /「HR_UAT」≠ profile/.test(e.message) && /「HR_PROD」/.test(e.message))
  let row = last(dir, S)
  assert.equal(row.decision, "block"); assert.equal(row.note, "ORACLE_CONNECTION_MISMATCH"); assert.equal(row.connection, "HR_UAT"); assert.equal(row.profileConnection, "HR_PROD"); assert.equal(row.next, "NEED_CONNECT")
  await assert.rejects(() => before(hooks, S, "oracleMCP_connect", "c2", {}), /ORACLE_CONNECTION_MISMATCH.*沒有帶 connection_name/)
  // 被擋的 connect 不會有 after（工具沒執行）；就算模型端偽造一個 after 也沒有快照 → 不前進
  await after(hooks, S, "oracleMCP_connect", "c1", mcpOk("Successfully connected to HR_UAT"), { connection_name: "HR_UAT" })
  assert.equal(last(dir, S).attribution, "unknown"); assert.equal(last(dir, S).next, "NEED_CONNECT")
  await expectBlock(() => task(hooks, S, "t1"), "NEED_CONNECT")
  await connect(hooks, S, "c3", "Successfully connected to HR_PROD", "HR_PROD")
  await task(hooks, S, "t2")
  assert.equal(last(dir, S).decision, "allow")
  // profile 未填
  const dir2 = tempProject({ connectionName: "FILL_ME" })
  const h2 = await PsOraclePreflightGate({ directory: dir2, client: fakeClient() })
  await chat(h2, S, "m1")
  await list(h2, S)
  await assert.rejects(() => before(h2, S, "oracleMCP_connect", "c1", { connection_name: "HR" }), (e) => /ORACLE_CONNECTION_NOT_CONFIGURED/.test(e.message) && /回填/.test(e.message))
  assert.equal(last(dir2, S).note, "ORACLE_CONNECTION_NOT_CONFIGURED")
  await expectBlock(() => task(h2, S, "t1"), "NEED_CONNECT")
  // observe：只記 would-block，connect 照跑、READY 照給（純探測）
  const dir3 = tempProject({ connectionName: "FILL_ME", profileGate: "observe" })
  const h3 = await PsOraclePreflightGate({ directory: dir3, client: fakeClient() })
  await chat(h3, S, "m1")
  await list(h3, S)
  await connect(h3, S, "c1", "Successfully connected to HR", "HR")
  const rows3 = readLog(dir3, S)
  const b3 = rows3.find((l) => l.hook === "before" && l.callID === "c1")
  assert.ok(b3.decision === "observe-would-block" && b3.note === "ORACLE_CONNECTION_NOT_CONFIGURED" && b3.gen === 1)
  assert.equal(rows3.at(-1).next, "READY")
})

test("connect 嘗試作廢 READY：READY 後再 connect 失敗（isError，無 after）→ NEED_CONNECT、task 被擋；較晚的嘗試取代較早的", async () => {
  const dir = tempProject()
  const hooks = await PsOraclePreflightGate({ directory: dir, client: fakeClient() })
  await chat(hooks, S, "m1")
  await list(hooks, S)
  await connect(hooks, S, "c1")
  await task(hooks, S, "t1")
  assert.equal(last(dir, S).decision, "allow")
  await before(hooks, S, "oracleMCP_connect", "c2", { connection_name: "HR" }) // isError → after 不觸發
  let row = last(dir, S)
  assert.ok(row.state === "READY" && row.next === "NEED_CONNECT" && row.gen === 2)
  await expectBlock(() => task(hooks, S, "t2"), "NEED_CONNECT")
  await connect(hooks, S, "c3")
  await task(hooks, S, "t3")
  assert.equal(last(dir, S).decision, "allow")
  // 兩個嘗試並行：較早的成功不算（gen 已被取代），較晚的成功才恢復
  await before(hooks, S, "oracleMCP_connect", "c4", { connection_name: "HR" })
  await before(hooks, S, "oracleMCP_connect", "c5", { connection_name: "HR" })
  await after(hooks, S, "oracleMCP_connect", "c4", mcpOk("Successfully connected to HR"), { connection_name: "HR" })
  row = last(dir, S)
  assert.ok(row.ok === true && row.gen === 4 && row.next === "NEED_CONNECT" && /superseded/.test(row.note), JSON.stringify(row))
  await expectBlock(() => task(hooks, S, "t4"), "NEED_CONNECT")
  await after(hooks, S, "oracleMCP_connect", "c5", mcpOk("Successfully connected to HR"), { connection_name: "HR" })
  assert.equal(last(dir, S).next, "READY")
  await task(hooks, S, "t5")
  assert.equal(last(dir, S).decision, "allow")
})

test("同題連線世代：同題兩個 task 在舊連線上，A 回 NOT_CONNECTED → 重連 → B 晚回的 NOT_CONNECTED 不作廢新世代的 READY", async () => {
  const dir = tempProject()
  const hooks = await PsOraclePreflightGate({ directory: dir, client: fakeClient() })
  await chat(hooks, S, "m1")
  await list(hooks, S)
  await connect(hooks, S, "c1") // gen 1
  await task(hooks, S, "tA")
  await task(hooks, S, "tB")
  await taskDone(hooks, S, "tA", wrap("ses_a", NOT_CONNECTED_JSON))
  let row = last(dir, S)
  assert.ok(row.next === "NEED_CONNECT" && row.gen === 1 && row.notConnected === true, JSON.stringify(row))
  await connect(hooks, S, "c2") // gen 2 → READY
  await taskDone(hooks, S, "tB", wrap("ses_b", NOT_CONNECTED_JSON))
  row = last(dir, S)
  assert.ok(row.next === "READY" && row.gen === 1 && /older connection attempt \(admitted gen 1, now 2\)/.test(row.note), JSON.stringify(row))
  await task(hooks, S, "tC")
  assert.equal(last(dir, S).decision, "allow")
  // 同世代的 NOT_CONNECTED 才退回
  await taskDone(hooks, S, "tC", wrap("ses_c", NOT_CONNECTED_JSON))
  assert.equal(last(dir, S).next, "NEED_CONNECT")
  await expectBlock(() => task(hooks, S, "tD"), "NEED_CONNECT")
})

test("task 回報解析：COMPLETE／PARTIAL／BLOCKED(QUERY_TIMEOUT)／非 JSON／task_error 都記到列上，只有 NOT_CONNECTED 退狀態；run_sql 的 after 記三態 ok", async () => {
  const dir = tempProject()
  const hooks = await PsOraclePreflightGate({ directory: dir, client: fakeClient() })
  await chat(hooks, S, "m1")
  await list(hooks, S)
  await connect(hooks, S)
  const cases = [
    ["t1", wrap("ses_1", '{"task":"x","status":"COMPLETE","blockedReason":"NOT_APPLICABLE","findings":[]}'), { reportValid: true, reportStatus: "COMPLETE", blockedReason: "NOT_APPLICABLE", childSessionID: "ses_1", taskState: "completed", next: "READY" }],
    ["t2", wrap("ses_2", "```json\n{\"status\":\"PARTIAL\",\"blockedReason\":\"NO_EVIDENCE\"}\n```"), { reportValid: true, reportStatus: "PARTIAL", blockedReason: "NO_EVIDENCE", childSessionID: "ses_2", next: "READY" }],
    ["t3", wrap("ses_3", '{"status":"BLOCKED","blockedReason":"QUERY_TIMEOUT"}'), { reportValid: true, reportStatus: "BLOCKED", blockedReason: "QUERY_TIMEOUT", notConnected: false, next: "READY" }],
    ["t4", wrap("ses_4", '{"status":"BLOCKED","blockedReason":"SCHEMA_UNRESOLVED"}'), { reportStatus: "BLOCKED", blockedReason: "SCHEMA_UNRESOLVED", notConnected: false, next: "READY" }],
    ["t5", wrap("ses_5", "I could not do it, sorry."), { reportValid: false, reportStatus: "INVALID", notConnected: false, next: "READY" }],
    ["t6", wrap("ses_6", "boom", "error"), { reportValid: false, reportStatus: "INVALID", taskState: "error", next: "READY" }],
    ["t7", wrap("ses_7", '{"status":"weird"}'), { reportValid: false, reportStatus: "INVALID", next: "READY" }],
  ]
  for (const [id, text, expected] of cases) {
    await task(hooks, S, id)
    await taskDone(hooks, S, id, text, "ps-ui-flow", "ses_meta_" + id)
    const row = last(dir, S)
    for (const [k, v] of Object.entries(expected)) {
      const want = k === "childSessionID" ? "ses_meta_" + id : v
      assert.equal(row[k], want, `${id}.${k}: got ${JSON.stringify(row[k])}`)
    }
  }
  // 沒有 metadata 時用包裝標籤的 task id 當子 session
  await task(hooks, S, "t8")
  await hooks["tool.execute.after"]({ tool: "task", sessionID: S, callID: "t8", args: taskArgs("ps-ui-flow").args }, { title: "t", output: wrap("ses_from_tag", '{"status":"COMPLETE"}') })
  assert.equal(last(dir, S).childSessionID, "ses_from_tag")
  // NOT_CONNECTED（契約 JSON）才退狀態
  await task(hooks, S, "t9")
  await taskDone(hooks, S, "t9", wrap("ses_9", NOT_CONNECTED_JSON))
  assert.ok(last(dir, S).notConnected === true && last(dir, S).next === "NEED_CONNECT" && last(dir, S).reportStatus === "BLOCKED")
  // 子 session 的 run_sql：成功／未連線／空輸出
  const C = "ses_child"
  await call(hooks, C, "oracleMCP_run_sql", "q1", mcpOk("ROW_COUNT\n1"), { sql: "SELECT 1 FROM DUAL" })
  await call(hooks, C, "oracleMCP_run_sql", "q2", mcpOk("Error: Not connected to a database."), { sql: "SELECT 1 FROM DUAL" })
  await call(hooks, C, "oracleMCP_run_sql", "q3", { content: [] }, { sql: "SELECT 1 FROM DUAL" })
  const q = readLog(dir, C).filter((l) => l.hook === "after")
  assert.deepEqual(q.map((l) => [l.callID, l.ok, l.attribution]), [["q1", true, "current"], ["q2", false, "current"], ["q3", "unknown", "current"]])
})

test("第 0 步提醒注入：主 agent 的每則真實訊息補一個 synthetic part；subagent／synthetic 訊息／同 id／不認識的 agent 不注入；不查 /mcp 狀態；env／profile 可關", async () => {
  const dir = tempProject({ connectionName: "HR_DEV" })
  const hooks = await PsOraclePreflightGate({ directory: dir, client: fakeClient() })
  const out = userMsg("m1", "兵役狀態有哪些選項？")
  await hooks["chat.message"]({ sessionID: S, agent: "ps-orchestrator", messageID: "m1" }, out)
  assert.equal(out.parts.length, 2)
  assert.equal(out.parts[0].text, "兵役狀態有哪些選項？")
  const p = out.parts[1]
  assert.ok(p.synthetic === true && p.type === "text" && p.messageID === "m1" && p.sessionID === S && /^prt_[0-9a-f]{12}[0-9A-Za-z]{14}$/.test(p.id), JSON.stringify(p))
  assert.match(p.text, /oracleMCP_list_connections → oracleMCP_connect/)
  assert.match(p.text, /「HR_DEV」/)
  assert.match(p.text, /ps-ui-flow／?/)
  assert.ok(/ps-auditor/.test(p.text) && !/ps-peoplecode-flow/.test(p.text), "提醒列的是會查 DB 的 subagent")
  assert.equal(last(dir, S).reminder, true)
  // 同 id 重複到達不再注入；synthetic-only 訊息不注入
  const again = userMsg("m1")
  await hooks["chat.message"]({ sessionID: S, agent: "ps-orchestrator" }, again)
  assert.equal(again.parts.length, 1)
  const syn = { message: { id: "m2" }, parts: [{ type: "text", text: "<task_result>…</task_result>", synthetic: true }] }
  await hooks["chat.message"]({ sessionID: S, agent: "ps-orchestrator" }, syn)
  assert.equal(syn.parts.length, 1)
  // subagent session、不認識的 agent（build）不注入
  const sub = userMsg("mc")
  await hooks["chat.message"]({ sessionID: "ses_child", agent: "ps-ui-flow" }, sub)
  assert.equal(sub.parts.length, 1)
  const b = userMsg("mb")
  await hooks["chat.message"]({ sessionID: "ses_build", agent: "build" }, b)
  assert.equal(b.parts.length, 1)
  assert.equal(last(dir, "ses_build").reminder, false)
  // 兩個 part 的 id 不同、遞增；且一定排在使用者文字 part 之後——即使 OpenCode 在同一毫秒內已發了更大的計數
  const o2 = userMsg("m3")
  await hooks["chat.message"]({ sessionID: S, agent: "ps-orchestrator" }, o2)
  assert.notEqual(o2.parts[1].id, p.id)
  assert.ok(o2.parts[1].id > p.id)
  const big = (BigInt(Date.now() + 5) * 4096n + 4000n) & ((1n << 48n) - 1n)
  const hex = big.toString(16).padStart(12, "0")
  const o3 = { message: { id: "m5" }, parts: [{ id: "prt_" + hex + "AAAAAAAAAAAAAA", type: "text", text: "q" }] }
  await hooks["chat.message"]({ sessionID: S, agent: "ps-orchestrator" }, o3)
  assert.ok(o3.parts[1].id > o3.parts[0].id, `${o3.parts[1].id} must sort after ${o3.parts[0].id}`)
  assert.equal(o3.parts[1].id.slice(4, 16), (big + 1n).toString(16).padStart(12, "0"))
  // profile 未填：提醒改成「不要 connect」
  const dir2 = tempProject({ connectionName: "FILL_ME" })
  const h2 = await PsOraclePreflightGate({ directory: dir2, client: fakeClient() })
  const u2 = userMsg("m1")
  await h2["chat.message"]({ sessionID: S, agent: "ps-deep-research" }, u2)
  assert.match(u2.parts[1].text, /未填/)
  assert.match(u2.parts[1].text, /Oracle 連線未設定/)
  // 提醒不查 /mcp 狀態（不影響狀態機、不消耗 status 呼叫）：未掛載的處置寫成靜態條款
  const h3 = await PsOraclePreflightGate({ directory: dir, client: fakeClient({ mcp: "throw" }) })
  const u3 = userMsg("m1")
  await h3["chat.message"]({ sessionID: "ses_down", agent: "ps-audit-orchestrator" }, u3)
  assert.equal(u3.parts.length, 2)
  assert.match(u3.parts[1].text, /未掛載.*ORACLE_MCP_DOWN/)
  // 關閉：env 優先
  process.env.PS_ORACLE_GATE_REMINDER = "off"
  try {
    const u4 = userMsg("m4")
    await hooks["chat.message"]({ sessionID: S, agent: "ps-orchestrator" }, u4)
    assert.equal(u4.parts.length, 1)
    assert.equal(last(dir, S).reminder, false)
  } finally {
    delete process.env.PS_ORACLE_GATE_REMINDER
  }
  // 關閉：profile
  const dir4 = tempProject({ connectionName: "HR_DEV", reminder: "off" })
  const h4 = await PsOraclePreflightGate({ directory: dir4, client: fakeClient() })
  const u5 = userMsg("m1")
  await h4["chat.message"]({ sessionID: S, agent: "ps-orchestrator" }, u5)
  assert.equal(u5.parts.length, 1)
  // 提醒不影響閘門本身：沒做前置照擋
  await expectBlock(() => task(hooks, S, "t1"), "NEED_LIST")
})

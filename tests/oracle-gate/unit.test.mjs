// unit.test.mjs — ps-oracle-preflight-gate 的狀態機單元測試（node --test；零相依）
// 用法：node --test tests/oracle-gate/unit.test.mjs   （repo 根目錄執行）
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

// 假 client：閘門只用 mcp.status。statusSeq 依序回不同狀態（驗「每次即時查、不快取」）；
// session.get 一律炸——閘門不得查祖先 session（v1 不變量沒有祖先放行）
function fakeClient({ mcp = "connected", statusSeq } = {}) {
  return {
    mcp: {
      status: async () => {
        const cur = statusSeq && statusSeq.length ? statusSeq.shift() : mcp
        if (cur === "throw") throw new Error("boom")
        if (cur === "http-error") return { error: { name: "x" }, response: { status: 500 } }
        return { data: cur === "absent" ? {} : { oracleMCP: { status: cur } } }
      },
    },
    session: { get: async () => { throw new Error("session.get must not be called by the gate") } },
  }
}

function tempProject({ profileGate } = {}) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "gate-unit-"))
  fs.mkdirSync(path.join(dir, ".opencode", "agent"), { recursive: true })
  fs.mkdirSync(path.join(dir, ".opencode", "peoplesoft"), { recursive: true })
  for (const f of fs.readdirSync(path.join(repoRoot, ".opencode", "agent"))) {
    fs.copyFileSync(path.join(repoRoot, ".opencode", "agent", f), path.join(dir, ".opencode", "agent", f))
  }
  const profile = "searchPolicy:\n  defaultMode: CUSTOM_FIRST\noracle:\n  currentSchema: FILL_ME\n  connectionName: FILL_ME\n" + (profileGate ? `  preflightGate: ${profileGate}\n` : "") + "businessDomainMap: business-domain-map.yaml\n"
  fs.writeFileSync(path.join(dir, ".opencode", "peoplesoft", "customization-profile.yaml"), profile)
  return dir
}

const mcpOk = (text) => ({ content: [{ type: "text", text }] })
const taskArgs = (target) => ({ args: { description: "d", prompt: "p", subagent_type: target } })
const userMsg = (id, text = "q") => ({ message: { id }, parts: [{ type: "text", text }] })
const S = "ses_primary"

async function expectBlock(fn, state) {
  await assert.rejects(fn, (e) => /PS_ORACLE_PREFLIGHT_REQUIRED/.test(e.message) && new RegExp("目前狀態＝" + state).test(e.message))
}

function readLog(dir, session) {
  const file = path.join(dir, "auto-loop-logs", "ps-oracle-gate", session + ".jsonl")
  return fs.readFileSync(file, "utf8").trim().split("\n").map((l) => JSON.parse(l))
}

test("agent 目錄分類：只有 run_sql 開的 subagent 過閘門；不認識的名字保守視為會查 DB", async () => {
  const dir = tempProject()
  const hooks = await PsOraclePreflightGate({ directory: dir, client: fakeClient() })
  await hooks["chat.message"]({ sessionID: S, agent: "ps-orchestrator" }, userMsg("m1"))
  for (const t of ["ps-ui-flow", "ps-metadata-flow", "ps-ae-flow", "ps-auditor", "some-unknown-agent"]) {
    await expectBlock(() => hooks["tool.execute.before"]({ tool: "task", sessionID: S, callID: "c" }, taskArgs(t)), "NEED_LIST")
  }
  for (const t of ["ps-peoplecode-flow", "ps-sql-flow", "ps-sqr-flow", "explore", "general", "scout"]) {
    await hooks["tool.execute.before"]({ tool: "task", sessionID: S, callID: "c" }, taskArgs(t))
  }
  const log = readLog(dir, S)
  assert.equal(log.filter((l) => l.decision === "block").length, 5)
  assert.equal(log.filter((l) => l.decision === "allow" && l.basis === "run_sql:disabled").length, 6)
  assert.ok(log.some((l) => l.basis === "unknown-agent(default:DB)"))
  assert.ok(log.filter((l) => l.hook === "before").every((l) => l.turnId === "m1" && l.callID === "c"))
})

test("狀態機：list → connect → READY 才放行；connect 先於 list 不算；connect 回錯誤樣式不前進", async () => {
  const dir = tempProject()
  const hooks = await PsOraclePreflightGate({ directory: dir, client: fakeClient() })
  await hooks["chat.message"]({ sessionID: S, agent: "ps-orchestrator" })
  // 先 connect（跳過 list）→ 仍 NEED_LIST
  await hooks["tool.execute.after"]({ tool: "oracleMCP_connect", sessionID: S, callID: "c", args: {} }, mcpOk("Successfully connected to HR"))
  await expectBlock(() => hooks["tool.execute.before"]({ tool: "task", sessionID: S, callID: "c" }, taskArgs("ps-ui-flow")), "NEED_LIST")
  await hooks["tool.execute.after"]({ tool: "oracleMCP_list_connections", sessionID: S, callID: "c", args: {} }, mcpOk("- HR"))
  await expectBlock(() => hooks["tool.execute.before"]({ tool: "task", sessionID: S, callID: "c" }, taskArgs("ps-ui-flow")), "NEED_CONNECT")
  // connect 回錯誤樣式 → 不前進
  await hooks["tool.execute.after"]({ tool: "oracleMCP_connect", sessionID: S, callID: "c", args: {} }, mcpOk("ORA-12541: TNS:no listener"))
  await expectBlock(() => hooks["tool.execute.before"]({ tool: "task", sessionID: S, callID: "c" }, taskArgs("ps-ui-flow")), "NEED_CONNECT")
  await hooks["tool.execute.after"]({ tool: "oracleMCP_connect", sessionID: S, callID: "c", args: {} }, mcpOk("Already connected to HR"))
  await hooks["tool.execute.before"]({ tool: "task", sessionID: S, callID: "c" }, taskArgs("ps-ui-flow"))
  // READY 之後再 list／connect 一次（模型多做）不影響
  await hooks["tool.execute.after"]({ tool: "oracleMCP_list_connections", sessionID: S, callID: "c", args: {} }, mcpOk("- HR"))
  await hooks["tool.execute.after"]({ tool: "oracleMCP_connect", sessionID: S, callID: "c", args: {} }, mcpOk("Already connected to HR"))
  await hooks["tool.execute.before"]({ tool: "task", sessionID: S, callID: "c" }, taskArgs("ps-ui-flow"))
  const log = readLog(dir, S)
  const blocks = log.filter((l) => l.decision === "block")
  assert.equal(blocks.length, 3)
  assert.equal(blocks[2].blocked, 3)
  assert.ok(log.some((l) => l.tool === "oracleMCP_connect" && l.hook === "after" && l.note === "connect before list_connections: list still required"))
  assert.ok(log.some((l) => l.tool === "oracleMCP_connect" && l.ok === false && l.failureMatch))
  assert.deepEqual(log.filter((l) => l.decision === "allow").map((l) => l.state), ["READY", "READY"])
})

test("subagent 回 NOT_CONNECTED → 重派前必須再 connect；disconnect → 從頭；新訊息 → 重置（turnId＝訊息 id）", async () => {
  const dir = tempProject()
  const hooks = await PsOraclePreflightGate({ directory: dir, client: fakeClient() })
  await hooks["chat.message"]({ sessionID: S, agent: "ps-orchestrator" }, userMsg("m1"))
  await hooks["tool.execute.after"]({ tool: "oracleMCP_list_connections", sessionID: S, callID: "c", args: {} }, mcpOk("- HR"))
  await hooks["tool.execute.after"]({ tool: "oracleMCP_connect", sessionID: S, callID: "c", args: {} }, mcpOk("Successfully connected to HR"))
  await hooks["tool.execute.before"]({ tool: "task", sessionID: S, callID: "t1" }, taskArgs("ps-ui-flow"))
  await hooks["tool.execute.after"]({ tool: "task", sessionID: S, callID: "t1", args: taskArgs("ps-ui-flow").args }, { title: "t", metadata: {}, output: '<task_result>{"status":"BLOCKED","blockedReason":"NOT_CONNECTED"}</task_result>' })
  await expectBlock(() => hooks["tool.execute.before"]({ tool: "task", sessionID: S, callID: "t2" }, taskArgs("ps-ui-flow")), "NEED_CONNECT")
  await hooks["tool.execute.after"]({ tool: "oracleMCP_connect", sessionID: S, callID: "c", args: {} }, mcpOk("Successfully connected to HR"))
  await hooks["tool.execute.before"]({ tool: "task", sessionID: S, callID: "t3" }, taskArgs("ps-ui-flow"))
  await hooks["tool.execute.after"]({ tool: "oracleMCP_disconnect", sessionID: S, callID: "c", args: {} }, mcpOk("Disconnected"))
  await expectBlock(() => hooks["tool.execute.before"]({ tool: "task", sessionID: S, callID: "t4" }, taskArgs("ps-ui-flow")), "NEED_LIST")
  await hooks["tool.execute.after"]({ tool: "oracleMCP_list_connections", sessionID: S, callID: "c", args: {} }, mcpOk("- HR"))
  await hooks["tool.execute.after"]({ tool: "oracleMCP_connect", sessionID: S, callID: "c", args: {} }, mcpOk("Successfully connected to HR"))
  await hooks["tool.execute.before"]({ tool: "task", sessionID: S, callID: "t5" }, taskArgs("ps-ui-flow"))
  await hooks["chat.message"]({ sessionID: S, agent: "ps-orchestrator" }, userMsg("m2"))
  await expectBlock(() => hooks["tool.execute.before"]({ tool: "task", sessionID: S, callID: "t6" }, taskArgs("ps-ui-flow")), "NEED_LIST")
  const log = readLog(dir, S)
  assert.ok(log.some((l) => l.hook === "after" && l.tool === "task" && l.notConnected === true && l.next === "NEED_CONNECT" && l.state === "READY" && l.admitted === "allow"))
  const chats = log.filter((l) => l.hook === "chat.message")
  assert.equal(chats.length, 2)
  assert.deepEqual(chats.map((c) => [c.turn, c.turnId, c.state, c.next]), [[1, "m1", "NEED_LIST", "NEED_LIST"], [2, "m2", "READY", "NEED_LIST"]])
  assert.equal(log.at(-1).turnId, "m2")
})

test("observe 模式（env 優先、其次 profile）只記錄不擋；after 列標 admitted=observe-would-block", async () => {
  const dir = tempProject({ profileGate: "observe" })
  const hooks = await PsOraclePreflightGate({ directory: dir, client: fakeClient() })
  await hooks["chat.message"]({ sessionID: S, agent: "ps-orchestrator" }, userMsg("m1"))
  await hooks["tool.execute.before"]({ tool: "task", sessionID: S, callID: "t1" }, taskArgs("ps-ui-flow"))
  assert.equal(readLog(dir, S).at(-1).decision, "observe-would-block")
  await hooks["tool.execute.after"]({ tool: "task", sessionID: S, callID: "t1", args: taskArgs("ps-ui-flow").args }, { output: '{"status":"BLOCKED","blockedReason":"NOT_CONNECTED"}' })
  const row = readLog(dir, S).at(-1)
  assert.equal(row.executed, true)
  assert.equal(row.admitted, "observe-would-block")
  assert.equal(row.state, "NEED_LIST")
  process.env.PS_ORACLE_GATE_MODE = "enforce"
  try {
    await expectBlock(() => hooks["tool.execute.before"]({ tool: "task", sessionID: S, callID: "t2" }, taskArgs("ps-ui-flow")), "NEED_LIST")
  } finally {
    delete process.env.PS_ORACLE_GATE_MODE
  }
})

test("oracleMCP 未掛載（absent／disabled／failed／needs_auth）→ 退讓；查不到（例外／非 2xx）→ 保守擋；每次即時查不快取", async () => {
  const dir = tempProject()
  for (const [mcp, expectAllow] of [["absent", true], ["disabled", true], ["failed", true], ["needs_auth", true], ["throw", false], ["http-error", false], ["connected", false]]) {
    const hooks = await PsOraclePreflightGate({ directory: dir, client: fakeClient({ mcp }) })
    const sid = "ses_" + mcp
    await hooks["chat.message"]({ sessionID: sid, agent: "ps-orchestrator" }, userMsg("m1"))
    if (expectAllow) {
      await hooks["tool.execute.before"]({ tool: "task", sessionID: sid, callID: "c" }, taskArgs("ps-ui-flow"))
      assert.match(readLog(dir, sid).at(-1).note, /^gate stands down: mcp-status:/)
    } else {
      await expectBlock(() => hooks["tool.execute.before"]({ tool: "task", sessionID: sid, callID: "c" }, taskArgs("ps-ui-flow")), "NEED_LIST")
    }
  }
  assert.match(readLog(dir, "ses_http-error").at(-1).note, /mcp-status:error\(500\)/)
  assert.match(readLog(dir, "ses_throw").at(-1).note, /mcp-status:unavailable\(boom\)/)
  // 不快取：failed 之後馬上 connected → 第二次就擋
  const hooks = await PsOraclePreflightGate({ directory: dir, client: fakeClient({ statusSeq: ["failed", "connected"] }) })
  await hooks["chat.message"]({ sessionID: S, agent: "ps-orchestrator" }, userMsg("m1"))
  await hooks["tool.execute.before"]({ tool: "task", sessionID: S, callID: "c1" }, taskArgs("ps-ui-flow"))
  assert.match(readLog(dir, S).at(-1).note, /gate stands down: mcp-status:failed/)
  await expectBlock(() => hooks["tool.execute.before"]({ tool: "task", sessionID: S, callID: "c2" }, taskArgs("ps-ui-flow")), "NEED_LIST")
  // 不查 DB 的委派與 READY 的 session 不查 mcp 狀態（statusSeq 用光後若再查會回 connected → 這裡不該被擋）
  await hooks["tool.execute.before"]({ tool: "task", sessionID: S, callID: "c3" }, taskArgs("ps-peoplecode-flow"))
  assert.equal(readLog(dir, S).at(-1).decision, "allow")
})

test("全部 part 都 synthetic 的 user 訊息不重置；同一訊息 id 重複到達不重置；真實新訊息才重置", async () => {
  const dir = tempProject()
  const hooks = await PsOraclePreflightGate({ directory: dir, client: fakeClient() })
  await hooks["chat.message"]({ sessionID: S, agent: "ps-orchestrator" }, userMsg("msg_1"))
  await hooks["tool.execute.after"]({ tool: "oracleMCP_list_connections", sessionID: S, callID: "l", args: {} }, mcpOk("- HR"))
  await hooks["tool.execute.after"]({ tool: "oracleMCP_connect", sessionID: S, callID: "c", args: {} }, mcpOk("Connected"))
  await hooks["chat.message"]({ sessionID: S, agent: "ps-orchestrator" }, { message: { id: "msg_synth" }, parts: [{ type: "text", text: "<task_result>…</task_result>", synthetic: true }] })
  await hooks["tool.execute.before"]({ tool: "task", sessionID: S, callID: "t1" }, taskArgs("ps-ui-flow"))
  let log = readLog(dir, S)
  assert.equal(log.at(-1).decision, "allow")
  assert.equal(log.at(-1).turnId, "msg_1")
  assert.ok(log.some((l) => l.hook === "chat.message" && l.synthetic === true && l.state === "READY" && l.next === "READY"))
  await hooks["chat.message"]({ sessionID: S, agent: "ps-orchestrator" }, userMsg("msg_1"))
  assert.match(readLog(dir, S).at(-1).note, /same message id: no reset/)
  await hooks["tool.execute.before"]({ tool: "task", sessionID: S, callID: "t2" }, taskArgs("ps-ui-flow"))
  assert.equal(readLog(dir, S).at(-1).decision, "allow")
  await hooks["chat.message"]({ sessionID: S, agent: "ps-orchestrator" }, userMsg("msg_2"))
  await expectBlock(() => hooks["tool.execute.before"]({ tool: "task", sessionID: S, callID: "t3" }, taskArgs("ps-ui-flow")), "NEED_LIST")
  log = readLog(dir, S)
  assert.equal(log.at(-1).turnId, "msg_2")
  assert.equal(log.filter((l) => l.hook === "chat.message" && l.mode).length, 2)
})

test("task 執行中使用者送下一題：after 列用入場時的 turn／state（admitted 快照），不被錯標到新題", async () => {
  const dir = tempProject()
  const hooks = await PsOraclePreflightGate({ directory: dir, client: fakeClient() })
  await hooks["chat.message"]({ sessionID: S, agent: "ps-orchestrator" }, userMsg("m1"))
  await hooks["tool.execute.after"]({ tool: "oracleMCP_list_connections", sessionID: S, callID: "l", args: {} }, mcpOk("- HR"))
  await hooks["tool.execute.after"]({ tool: "oracleMCP_connect", sessionID: S, callID: "c", args: {} }, mcpOk("Connected"))
  await hooks["tool.execute.before"]({ tool: "task", sessionID: S, callID: "t1" }, taskArgs("ps-ui-flow"))
  // 下一題到了（狀態重置），然後 t1 才完成
  await hooks["chat.message"]({ sessionID: S, agent: "ps-orchestrator" }, userMsg("m2"))
  await hooks["tool.execute.after"]({ tool: "task", sessionID: S, callID: "t1", args: taskArgs("ps-ui-flow").args }, { title: "t", metadata: {}, output: '<task_result>{"status":"COMPLETE"}</task_result>' })
  const row = readLog(dir, S).at(-1)
  assert.equal(row.executed, true)
  assert.equal(row.turnId, "m1")
  assert.equal(row.turn, 1)
  assert.equal(row.state, "READY")
  assert.equal(row.admitted, "allow")
  assert.equal(row.next, "NEED_LIST")
  // 快照用完即刪：沒有入場紀錄的 after 列標 admitted=unknown
  await hooks["tool.execute.after"]({ tool: "task", sessionID: S, callID: "t1", args: taskArgs("ps-ui-flow").args }, { output: "x" })
  assert.equal(readLog(dir, S).at(-1).admitted, "unknown")
})

test("沒有 fail-open：connect／list 一直失敗，會查 DB 的 task 一律擋（第 0 步規則：本題不派 DB 委派）", async () => {
  const dir = tempProject()
  const hooks = await PsOraclePreflightGate({ directory: dir, client: fakeClient() })
  await hooks["chat.message"]({ sessionID: S, agent: "ps-deep-research" }, userMsg("m1"))
  await hooks["tool.execute.after"]({ tool: "oracleMCP_list_connections", sessionID: S, callID: "l", args: {} }, mcpOk("- HR"))
  // connect 回 MCP isError → 只有 before（after 不會觸發）
  await hooks["tool.execute.before"]({ tool: "oracleMCP_connect", sessionID: S, callID: "c1" }, { args: { connection_name: "HR" } })
  await expectBlock(() => hooks["tool.execute.before"]({ tool: "task", sessionID: S, callID: "t1" }, taskArgs("ps-auditor")), "NEED_CONNECT")
  // connect 回錯誤文字
  await hooks["tool.execute.before"]({ tool: "oracleMCP_connect", sessionID: S, callID: "c2" }, { args: { connection_name: "HR" } })
  await hooks["tool.execute.after"]({ tool: "oracleMCP_connect", sessionID: S, callID: "c2", args: {} }, mcpOk("ORA-12541: TNS:no listener"))
  await expectBlock(() => hooks["tool.execute.before"]({ tool: "task", sessionID: S, callID: "t2" }, taskArgs("ps-auditor")), "NEED_CONNECT")
  await hooks["tool.execute.before"]({ tool: "oracleMCP_connect", sessionID: S, callID: "c3" }, { args: { connection_name: "HR" } })
  await assert.rejects(() => hooks["tool.execute.before"]({ tool: "task", sessionID: S, callID: "t3" }, taskArgs("ps-auditor")), (e) => /目前狀態＝NEED_CONNECT/.test(e.message) && /已被擋 3 次/.test(e.message) && /DB 連線建立失敗/.test(e.message))
  let log = readLog(dir, S)
  assert.equal(log.filter((l) => l.hook === "before" && l.tool === "task" && l.decision === "allow").length, 0)
  assert.deepEqual(log.filter((l) => l.decision === "block").map((l) => l.blocked), [1, 2, 3])
  // list 一直失敗：前兩次 isError（無 after）、第三次回錯誤文字 → 仍 NEED_LIST、仍擋
  const S2 = "ses_nolist"
  await hooks["chat.message"]({ sessionID: S2, agent: "ps-deep-research" }, userMsg("m9"))
  await hooks["tool.execute.before"]({ tool: "oracleMCP_list_connections", sessionID: S2, callID: "a" }, { args: {} })
  await hooks["tool.execute.before"]({ tool: "oracleMCP_list_connections", sessionID: S2, callID: "b" }, { args: {} })
  await hooks["tool.execute.after"]({ tool: "oracleMCP_list_connections", sessionID: S2, callID: "b", args: {} }, mcpOk("Error: cannot list"))
  await expectBlock(() => hooks["tool.execute.before"]({ tool: "task", sessionID: S2, callID: "t" }, taskArgs("ps-auditor")), "NEED_LIST")
  log = readLog(dir, S2)
  assert.equal(log.filter((l) => l.decision === "allow").length, 0)
  assert.ok(log.some((l) => l.tool === "oracleMCP_list_connections" && l.hook === "after" && l.ok === false))
})

test("沒有祖先放行：父 session READY 不代表子 session READY；閘門不查 session.get", async () => {
  const dir = tempProject()
  const hooks = await PsOraclePreflightGate({ directory: dir, client: fakeClient() })
  await hooks["chat.message"]({ sessionID: "ses_root", agent: "ps-deep-research" }, userMsg("m1"))
  await hooks["tool.execute.after"]({ tool: "oracleMCP_list_connections", sessionID: "ses_root", callID: "l", args: {} }, mcpOk("- HR"))
  await hooks["tool.execute.after"]({ tool: "oracleMCP_connect", sessionID: "ses_root", callID: "c", args: {} }, mcpOk("Connected"))
  await hooks["tool.execute.before"]({ tool: "task", sessionID: "ses_root", callID: "t" }, taskArgs("ps-auditor"))
  await hooks["chat.message"]({ sessionID: "ses_child", agent: "ps-audit-orchestrator" }, userMsg("mc"))
  await expectBlock(() => hooks["tool.execute.before"]({ tool: "task", sessionID: "ses_child", callID: "t" }, taskArgs("ps-auditor")), "NEED_LIST")
  assert.equal(readLog(dir, "ses_root").at(-1).decision, "allow")
  assert.equal(readLog(dir, "ses_child").at(-1).decision, "block")
})

test("同一 callID 字串跨 session 不互撞（OpenAI 相容端點的 call_0）：入場快照各歸各的 session", async () => {
  const dir = tempProject()
  const hooks = await PsOraclePreflightGate({ directory: dir, client: fakeClient() })
  const X = "ses_X", Y = "ses_Y"
  for (const sid of [X, Y]) {
    await hooks["chat.message"]({ sessionID: sid, agent: "ps-orchestrator" }, userMsg("m" + sid))
    await hooks["tool.execute.after"]({ tool: "oracleMCP_list_connections", sessionID: sid, callID: "call_0", args: {} }, mcpOk("- HR"))
  }
  await hooks["tool.execute.after"]({ tool: "oracleMCP_connect", sessionID: X, callID: "call_0", args: { connection_name: "HR" } }, mcpOk("Connected"))
  await hooks["tool.execute.before"]({ tool: "task", sessionID: X, callID: "call_1" }, taskArgs("ps-ui-flow"))
  await expectBlock(() => hooks["tool.execute.before"]({ tool: "task", sessionID: Y, callID: "call_1" }, taskArgs("ps-ui-flow")), "NEED_CONNECT")
  await hooks["tool.execute.after"]({ tool: "oracleMCP_connect", sessionID: Y, callID: "call_0", args: { connection_name: "HR" } }, mcpOk("Connected"))
  await hooks["tool.execute.before"]({ tool: "task", sessionID: Y, callID: "call_1" }, taskArgs("ps-ui-flow"))
  await hooks["tool.execute.after"]({ tool: "task", sessionID: X, callID: "call_1", args: taskArgs("ps-ui-flow").args }, { output: "<task_result>ok</task_result>" })
  await hooks["tool.execute.after"]({ tool: "task", sessionID: Y, callID: "call_1", args: taskArgs("ps-ui-flow").args }, { output: "<task_result>ok</task_result>" })
  assert.equal(readLog(dir, X).at(-1).turnId, "mses_X")
  assert.equal(readLog(dir, X).at(-1).admitted, "allow")
  assert.equal(readLog(dir, Y).at(-1).turnId, "mses_Y")
  assert.equal(readLog(dir, Y).at(-1).admitted, "allow")
})

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

function fakeClient({ mcp = "connected", parents = {}, statusSeq } = {}) {
  return {
    mcp: { status: async () => {
      const cur = statusSeq && statusSeq.length ? statusSeq.shift() : mcp
      return cur === "throw" ? Promise.reject(new Error("boom")) : { data: cur === "absent" ? {} : { oracleMCP: { status: cur } } }
    } },
    session: { get: async ({ path: { id } }) => ({ data: { id, parentID: parents[id] } }) },
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
const S = "ses_primary"

async function expectBlock(fn, state) {
  await assert.rejects(fn, (e) => /PS_ORACLE_PREFLIGHT_REQUIRED/.test(e.message) && new RegExp("目前狀態＝" + state).test(e.message))
}

function readLog(dir, session) {
  const file = path.join(dir, "auto-loop-logs", "ps-oracle-gate", session + ".jsonl")
  return fs.readFileSync(file, "utf8").trim().split("\n").map((l) => JSON.parse(l))
}

test("agent 目錄分類：只有 run_sql 開的 subagent 過閘門", async () => {
  const dir = tempProject()
  const hooks = await PsOraclePreflightGate({ directory: dir, client: fakeClient() })
  await hooks["chat.message"]({ sessionID: S, agent: "ps-orchestrator" })
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
})

test("狀態機：list → connect → READY 才放行；connect 先於 list 不算", async () => {
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
  const log = readLog(dir, S)
  const blocks = log.filter((l) => l.decision === "block")
  assert.equal(blocks.length, 3)
  assert.equal(blocks[2].blocked, 3)
  assert.ok(log.some((l) => l.tool === "oracleMCP_connect" && l.ok === false && l.failureMatch))
  assert.equal(log.at(-1).decision, "allow")
})

test("subagent 回 NOT_CONNECTED → 重派前必須再 connect；disconnect → 從頭；新訊息 → 重置", async () => {
  const dir = tempProject()
  const hooks = await PsOraclePreflightGate({ directory: dir, client: fakeClient() })
  await hooks["chat.message"]({ sessionID: S, agent: "ps-orchestrator" })
  await hooks["tool.execute.after"]({ tool: "oracleMCP_list_connections", sessionID: S, callID: "c", args: {} }, mcpOk("- HR"))
  await hooks["tool.execute.after"]({ tool: "oracleMCP_connect", sessionID: S, callID: "c", args: {} }, mcpOk("Successfully connected to HR"))
  await hooks["tool.execute.before"]({ tool: "task", sessionID: S, callID: "c" }, taskArgs("ps-ui-flow"))
  await hooks["tool.execute.after"]({ tool: "task", sessionID: S, callID: "c", args: taskArgs("ps-ui-flow").args }, { title: "t", metadata: {}, output: '<task_result>{"status":"BLOCKED","blockedReason":"NOT_CONNECTED"}</task_result>' })
  await expectBlock(() => hooks["tool.execute.before"]({ tool: "task", sessionID: S, callID: "c" }, taskArgs("ps-ui-flow")), "NEED_CONNECT")
  await hooks["tool.execute.after"]({ tool: "oracleMCP_connect", sessionID: S, callID: "c", args: {} }, mcpOk("Successfully connected to HR"))
  await hooks["tool.execute.before"]({ tool: "task", sessionID: S, callID: "c" }, taskArgs("ps-ui-flow"))
  await hooks["tool.execute.after"]({ tool: "oracleMCP_disconnect", sessionID: S, callID: "c", args: {} }, mcpOk("Disconnected"))
  await expectBlock(() => hooks["tool.execute.before"]({ tool: "task", sessionID: S, callID: "c" }, taskArgs("ps-ui-flow")), "NEED_LIST")
  await hooks["tool.execute.after"]({ tool: "oracleMCP_list_connections", sessionID: S, callID: "c", args: {} }, mcpOk("- HR"))
  await hooks["tool.execute.after"]({ tool: "oracleMCP_connect", sessionID: S, callID: "c", args: {} }, mcpOk("Successfully connected to HR"))
  await hooks["tool.execute.before"]({ tool: "task", sessionID: S, callID: "c" }, taskArgs("ps-ui-flow"))
  await hooks["chat.message"]({ sessionID: S, agent: "ps-orchestrator" })
  await expectBlock(() => hooks["tool.execute.before"]({ tool: "task", sessionID: S, callID: "c" }, taskArgs("ps-ui-flow")), "NEED_LIST")
  const log = readLog(dir, S)
  assert.ok(log.some((l) => l.hook === "after" && l.tool === "task" && l.notConnected === true && l.next === "NEED_CONNECT"))
  assert.equal(log.filter((l) => l.hook === "chat.message").length, 2)
  assert.equal(log.filter((l) => l.hook === "chat.message").at(-1).turn, 2)
})

test("observe 模式（env 優先、其次 profile）只記錄不擋", async () => {
  const dir = tempProject({ profileGate: "observe" })
  const hooks = await PsOraclePreflightGate({ directory: dir, client: fakeClient() })
  await hooks["chat.message"]({ sessionID: S, agent: "ps-orchestrator" })
  await hooks["tool.execute.before"]({ tool: "task", sessionID: S, callID: "c" }, taskArgs("ps-ui-flow"))
  assert.equal(readLog(dir, S).at(-1).decision, "observe-would-block")
  process.env.PS_ORACLE_GATE_MODE = "enforce"
  try {
    await expectBlock(() => hooks["tool.execute.before"]({ tool: "task", sessionID: S, callID: "c" }, taskArgs("ps-ui-flow")), "NEED_LIST")
  } finally {
    delete process.env.PS_ORACLE_GATE_MODE
  }
})

test("oracleMCP 未掛載／disabled → 閘門退讓；狀態查不到 → 保守仍擋；祖先 READY → 放行", async () => {
  const dir = tempProject()
  for (const [mcp, expectAllow] of [["absent", true], ["disabled", true], ["failed", true], ["throw", false], ["connected", false]]) {
    const hooks = await PsOraclePreflightGate({ directory: dir, client: fakeClient({ mcp }) })
    const sid = "ses_" + mcp
    await hooks["chat.message"]({ sessionID: sid, agent: "ps-orchestrator" })
    if (expectAllow) {
      await hooks["tool.execute.before"]({ tool: "task", sessionID: sid, callID: "c" }, taskArgs("ps-ui-flow"))
      assert.match(readLog(dir, sid).at(-1).note, /gate stands down/)
    } else {
      await expectBlock(() => hooks["tool.execute.before"]({ tool: "task", sessionID: sid, callID: "c" }, taskArgs("ps-ui-flow")), "NEED_LIST")
    }
  }
  const hooks = await PsOraclePreflightGate({ directory: dir, client: fakeClient({ parents: { ses_child: "ses_root" } }) })
  await hooks["chat.message"]({ sessionID: "ses_root", agent: "ps-deep-research" })
  await hooks["tool.execute.after"]({ tool: "oracleMCP_list_connections", sessionID: "ses_root", callID: "c", args: {} }, mcpOk("- HR"))
  await hooks["tool.execute.after"]({ tool: "oracleMCP_connect", sessionID: "ses_root", callID: "c", args: {} }, mcpOk("Connected"))
  await hooks["chat.message"]({ sessionID: "ses_child", agent: "ps-audit-orchestrator" })
  await hooks["tool.execute.before"]({ tool: "task", sessionID: "ses_child", callID: "c" }, taskArgs("ps-auditor"))
  assert.match(readLog(dir, "ses_child").at(-1).note, /ancestor READY ses_root/)
})

test("連線身分：別的 session 同名重連不作廢；換名 connect／disconnect／外部改檔才作廢，退回 NEED_CONNECT 且訊息標來源", async () => {
  const dir = tempProject()
  const hooks = await PsOraclePreflightGate({ directory: dir, client: fakeClient() })
  const A = "ses_A", B = "ses_B"
  for (const sid of [A, B]) await hooks["chat.message"]({ sessionID: sid, agent: "ps-orchestrator" })
  const preflight = async (sid, name, tag) => {
    await hooks["tool.execute.after"]({ tool: "oracleMCP_list_connections", sessionID: sid, callID: "l" + tag, args: {} }, mcpOk("- HR\n- OTHER"))
    await hooks["tool.execute.before"]({ tool: "oracleMCP_connect", sessionID: sid, callID: "c" + tag }, { args: { connection_name: name } })
    await hooks["tool.execute.after"]({ tool: "oracleMCP_connect", sessionID: sid, callID: "c" + tag, args: { connection_name: name } }, mcpOk("Connected to " + name))
  }
  await preflight(A, "HR", "a1")
  await hooks["tool.execute.before"]({ tool: "task", sessionID: A, callID: "t1" }, taskArgs("ps-ui-flow"))
  // B 同名重連（每題第 0 步的常態）→ A 不受影響
  await preflight(B, "HR", "b1")
  await hooks["tool.execute.before"]({ tool: "task", sessionID: A, callID: "t2" }, taskArgs("ps-ui-flow"))
  assert.equal(readLog(dir, A).at(-1).decision, "allow")
  // B 換名 connect → A 作廢：退回 NEED_CONNECT、不計入 blocked、訊息標來源
  await hooks["tool.execute.before"]({ tool: "oracleMCP_connect", sessionID: B, callID: "cb2" }, { args: { connection_name: "OTHER" } })
  await hooks["tool.execute.after"]({ tool: "oracleMCP_connect", sessionID: B, callID: "cb2", args: { connection_name: "OTHER" } }, mcpOk("Connected to OTHER"))
  await assert.rejects(() => hooks["tool.execute.before"]({ tool: "task", sessionID: A, callID: "t3" }, taskArgs("ps-ui-flow")), (e) => /共用的 Oracle 連線已被改動過/.test(e.message) && /目前是「OTHER」/.test(e.message) && /oracleMCP_connect by session ses_B/.test(e.message) && /目前狀態＝NEED_CONNECT/.test(e.message))
  let row = readLog(dir, A).at(-1)
  assert.match(row.note, /shared connection changed since preflight \(now "OTHER", expected "HR"/)
  assert.equal(row.blocked, 0)
  assert.equal(row.staleBlocks, 1)
  // A 只需再 connect（不必 list）→ 放行；此時 B 反過來作廢（兩邊要不同的庫＝真衝突）
  await hooks["tool.execute.before"]({ tool: "oracleMCP_connect", sessionID: A, callID: "ca2" }, { args: { connection_name: "HR" } })
  await hooks["tool.execute.after"]({ tool: "oracleMCP_connect", sessionID: A, callID: "ca2", args: { connection_name: "HR" } }, mcpOk("Connected to HR"))
  await hooks["tool.execute.before"]({ tool: "task", sessionID: A, callID: "t4" }, taskArgs("ps-ui-flow"))
  assert.equal(readLog(dir, A).at(-1).decision, "allow")
  await expectBlock(() => hooks["tool.execute.before"]({ tool: "task", sessionID: B, callID: "tb" }, taskArgs("ps-ui-flow")), "NEED_CONNECT")
  // 跨行程：外部改檔（另一個 OpenCode 行程 connect 到別的名字）→ A 作廢
  const stateFile = path.join(dir, "auto-loop-logs", "ps-oracle-gate", "connection-state.json")
  assert.ok(fs.existsSync(stateFile), "state file written")
  fs.writeFileSync(stateFile, JSON.stringify({ name: "UAT", changed: "foreign-1", by: { tool: "oracleMCP_connect", sessionID: "ses_other", pid: 0 } }))
  await assert.rejects(() => hooks["tool.execute.before"]({ tool: "task", sessionID: A, callID: "t5" }, taskArgs("ps-ui-flow")), (e) => /目前是「UAT」/.test(e.message) && /pid 0/.test(e.message))
  // 外部同名 → 不作廢
  await hooks["tool.execute.before"]({ tool: "oracleMCP_connect", sessionID: A, callID: "ca3" }, { args: { connection_name: "HR" } })
  await hooks["tool.execute.after"]({ tool: "oracleMCP_connect", sessionID: A, callID: "ca3", args: { connection_name: "HR" } }, mcpOk("Connected to HR"))
  fs.writeFileSync(stateFile, JSON.stringify({ name: "HR", changed: "foreign-2", by: { tool: "oracleMCP_connect", sessionID: "ses_other", pid: 0 } }))
  await hooks["tool.execute.before"]({ tool: "task", sessionID: A, callID: "t6" }, taskArgs("ps-ui-flow"))
  assert.equal(readLog(dir, A).at(-1).decision, "allow")
  // B disconnect → A 作廢（目前沒有連線）
  await hooks["tool.execute.before"]({ tool: "oracleMCP_disconnect", sessionID: B, callID: "d" }, { args: {} })
  await hooks["tool.execute.after"]({ tool: "oracleMCP_disconnect", sessionID: B, callID: "d", args: {} }, mcpOk("Disconnected"))
  await assert.rejects(() => hooks["tool.execute.before"]({ tool: "task", sessionID: A, callID: "t7" }, taskArgs("ps-ui-flow")), (e) => /已被 disconnect/.test(e.message) && /oracleMCP_disconnect by session ses_B/.test(e.message))
})

test("mcp 狀態不快取：failed 之後馬上 connected → 第二次就擋", async () => {
  const dir = tempProject()
  const hooks = await PsOraclePreflightGate({ directory: dir, client: fakeClient({ statusSeq: ["failed", "connected"] }) })
  await hooks["chat.message"]({ sessionID: S, agent: "ps-orchestrator" })
  await hooks["tool.execute.before"]({ tool: "task", sessionID: S, callID: "c" }, taskArgs("ps-ui-flow"))
  assert.match(readLog(dir, S).at(-1).note, /gate stands down: mcp-status:failed/)
  await expectBlock(() => hooks["tool.execute.before"]({ tool: "task", sessionID: S, callID: "c" }, taskArgs("ps-ui-flow")), "NEED_LIST")
})

test("全部 part 都 synthetic 的 user 訊息（背景結果回灌／compaction 續行）不重置", async () => {
  const dir = tempProject()
  const hooks = await PsOraclePreflightGate({ directory: dir, client: fakeClient() })
  await hooks["chat.message"]({ sessionID: S, agent: "ps-orchestrator" }, { message: { id: "msg_1" }, parts: [{ type: "text", text: "Q1" }] })
  await hooks["tool.execute.after"]({ tool: "oracleMCP_list_connections", sessionID: S, callID: "c", args: {} }, mcpOk("- HR"))
  await hooks["tool.execute.before"]({ tool: "oracleMCP_connect", sessionID: S, callID: "c" }, { args: {} })
  await hooks["tool.execute.after"]({ tool: "oracleMCP_connect", sessionID: S, callID: "c", args: {} }, mcpOk("Connected"))
  await hooks["chat.message"]({ sessionID: S, agent: "ps-orchestrator" }, { message: { id: "msg_synth" }, parts: [{ type: "text", text: "<task_result>…</task_result>", synthetic: true }] })
  await hooks["tool.execute.before"]({ tool: "task", sessionID: S, callID: "c" }, taskArgs("ps-ui-flow"))
  let log = readLog(dir, S)
  assert.equal(log.at(-1).decision, "allow")
  assert.equal(log.at(-1).turnId, "msg_1")
  assert.ok(log.some((l) => l.hook === "chat.message" && l.synthetic === true && l.state === "READY" && l.next === "READY"))
  await hooks["chat.message"]({ sessionID: S, agent: "ps-orchestrator" }, { message: { id: "msg_2" }, parts: [{ type: "text", text: "Q2" }] })
  await expectBlock(() => hooks["tool.execute.before"]({ tool: "task", sessionID: S, callID: "c" }, taskArgs("ps-ui-flow")), "NEED_LIST")
  log = readLog(dir, S)
  assert.equal(log.at(-1).turnId, "msg_2")
  assert.equal(log.filter((l) => l.hook === "chat.message" && l.synthetic !== true).length, 2)
})

test("connect 交錯：A 起跑後 B connect 到別的名字，A 完成時不算 READY，B 算；同名交錯兩邊都算", async () => {
  const dir = tempProject()
  const hooks = await PsOraclePreflightGate({ directory: dir, client: fakeClient() })
  const A = "ses_A2", B = "ses_B2"
  for (const sid of [A, B]) {
    await hooks["chat.message"]({ sessionID: sid, agent: "ps-orchestrator" })
    await hooks["tool.execute.after"]({ tool: "oracleMCP_list_connections", sessionID: sid, callID: "l" + sid, args: {} }, mcpOk("- HR\n- OTHER"))
  }
  await hooks["tool.execute.before"]({ tool: "oracleMCP_connect", sessionID: A, callID: "cA" }, { args: { connection_name: "HR" } })
  await hooks["tool.execute.before"]({ tool: "oracleMCP_connect", sessionID: B, callID: "cB" }, { args: { connection_name: "OTHER" } })
  await hooks["tool.execute.after"]({ tool: "oracleMCP_connect", sessionID: A, callID: "cA", args: { connection_name: "HR" } }, mcpOk("Connected to HR"))
  await hooks["tool.execute.after"]({ tool: "oracleMCP_connect", sessionID: B, callID: "cB", args: { connection_name: "OTHER" } }, mcpOk("Connected to OTHER"))
  await expectBlock(() => hooks["tool.execute.before"]({ tool: "task", sessionID: A, callID: "t" }, taskArgs("ps-ui-flow")), "NEED_CONNECT")
  await hooks["tool.execute.before"]({ tool: "task", sessionID: B, callID: "t" }, taskArgs("ps-ui-flow"))
  assert.ok(readLog(dir, A).some((l) => l.tool === "oracleMCP_connect" && l.hook === "after" && /interleaved/.test(l.note ?? "") && l.next === "NEED_CONNECT"))
  assert.equal(readLog(dir, B).at(-1).decision, "allow")
  // 同名交錯：C 與 D 都 connect HR → 兩邊都 READY
  const C = "ses_C", D = "ses_D"
  for (const sid of [C, D]) {
    await hooks["chat.message"]({ sessionID: sid, agent: "ps-orchestrator" })
    await hooks["tool.execute.after"]({ tool: "oracleMCP_list_connections", sessionID: sid, callID: "l" + sid, args: {} }, mcpOk("- HR"))
  }
  await hooks["tool.execute.before"]({ tool: "oracleMCP_connect", sessionID: C, callID: "cC" }, { args: { connection_name: "HR" } })
  await hooks["tool.execute.before"]({ tool: "oracleMCP_connect", sessionID: D, callID: "cD" }, { args: { connection_name: "HR" } })
  await hooks["tool.execute.after"]({ tool: "oracleMCP_connect", sessionID: C, callID: "cC", args: { connection_name: "HR" } }, mcpOk("Connected to HR"))
  await hooks["tool.execute.after"]({ tool: "oracleMCP_connect", sessionID: D, callID: "cD", args: { connection_name: "HR" } }, mcpOk("Connected to HR"))
  await hooks["tool.execute.before"]({ tool: "task", sessionID: C, callID: "t" }, taskArgs("ps-ui-flow"))
  await hooks["tool.execute.before"]({ tool: "task", sessionID: D, callID: "t" }, taskArgs("ps-ui-flow"))
  assert.equal(readLog(dir, C).at(-1).decision, "allow")
  assert.equal(readLog(dir, D).at(-1).decision, "allow")
})

test("task 執行中使用者送下一題：after 列用入場時的 turn／state，不被錯標", async () => {
  const dir = tempProject()
  const hooks = await PsOraclePreflightGate({ directory: dir, client: fakeClient() })
  await hooks["chat.message"]({ sessionID: S, agent: "ps-orchestrator" }, { message: { id: "m1" }, parts: [{ type: "text", text: "Q1" }] })
  await hooks["tool.execute.after"]({ tool: "oracleMCP_list_connections", sessionID: S, callID: "l", args: {} }, mcpOk("- HR"))
  await hooks["tool.execute.before"]({ tool: "oracleMCP_connect", sessionID: S, callID: "c" }, { args: {} })
  await hooks["tool.execute.after"]({ tool: "oracleMCP_connect", sessionID: S, callID: "c", args: {} }, mcpOk("Connected"))
  await hooks["tool.execute.before"]({ tool: "task", sessionID: S, callID: "t1" }, taskArgs("ps-ui-flow"))
  // 下一題到了（狀態重置），然後 t1 才完成
  await hooks["chat.message"]({ sessionID: S, agent: "ps-orchestrator" }, { message: { id: "m2" }, parts: [{ type: "text", text: "Q2" }] })
  await hooks["tool.execute.after"]({ tool: "task", sessionID: S, callID: "t1", args: taskArgs("ps-ui-flow").args }, { title: "t", metadata: {}, output: '<task_result>{"status":"COMPLETE"}</task_result>' })
  const row = readLog(dir, S).at(-1)
  assert.equal(row.executed, true)
  assert.equal(row.turnId, "m1")
  assert.equal(row.state, "READY")
  assert.equal(row.admitted, "allow")
  assert.equal(row.next, "NEED_LIST")
  // 同一則訊息 id 再來一次不重置
  await hooks["chat.message"]({ sessionID: S, agent: "ps-orchestrator" }, { message: { id: "m2" }, parts: [{ type: "text", text: "Q2" }] })
  assert.match(readLog(dir, S).at(-1).note, /same message id/)
})

test("第 0 步誠實做過但連不上：list 成功、connect 失敗 2 次後閘門退讓（交 NOT_CONNECTED 協定）", async () => {
  const dir = tempProject()
  const hooks = await PsOraclePreflightGate({ directory: dir, client: fakeClient() })
  await hooks["chat.message"]({ sessionID: S, agent: "ps-deep-research" }, { message: { id: "m1" }, parts: [{ type: "text", text: "audit" }] })
  await hooks["tool.execute.after"]({ tool: "oracleMCP_list_connections", sessionID: S, callID: "l", args: {} }, mcpOk("- HR"))
  // 第一次 connect：MCP isError → 只有 before（after 不會觸發）
  await hooks["tool.execute.before"]({ tool: "oracleMCP_connect", sessionID: S, callID: "c1" }, { args: { connection_name: "HR" } })
  await expectBlock(() => hooks["tool.execute.before"]({ tool: "task", sessionID: S, callID: "t1" }, taskArgs("ps-auditor")), "NEED_CONNECT")
  // 第二次 connect：回錯誤文字
  await hooks["tool.execute.before"]({ tool: "oracleMCP_connect", sessionID: S, callID: "c2" }, { args: { connection_name: "HR" } })
  await hooks["tool.execute.after"]({ tool: "oracleMCP_connect", sessionID: S, callID: "c2", args: {} }, mcpOk("ORA-12541: TNS:no listener"))
  await hooks["tool.execute.before"]({ tool: "task", sessionID: S, callID: "t2" }, taskArgs("ps-auditor"))
  const row = readLog(dir, S).at(-1)
  assert.equal(row.decision, "allow")
  assert.match(row.note, /connect failed x2 after list_connections/)
  // 沒做 list 就 connect 失敗兩次 → 不退讓（順序沒誠實做）
  const S2 = "ses_nolist"
  await hooks["chat.message"]({ sessionID: S2, agent: "ps-deep-research" }, { message: { id: "m9" }, parts: [{ type: "text", text: "x" }] })
  await hooks["tool.execute.before"]({ tool: "oracleMCP_connect", sessionID: S2, callID: "a" }, { args: {} })
  await hooks["tool.execute.before"]({ tool: "oracleMCP_connect", sessionID: S2, callID: "b" }, { args: {} })
  await expectBlock(() => hooks["tool.execute.before"]({ tool: "task", sessionID: S2, callID: "t" }, taskArgs("ps-auditor")), "NEED_LIST")
  // 新的一題重新計數
  await hooks["chat.message"]({ sessionID: S, agent: "ps-deep-research" }, { message: { id: "m2" }, parts: [{ type: "text", text: "next" }] })
  await hooks["tool.execute.after"]({ tool: "oracleMCP_list_connections", sessionID: S, callID: "l2", args: {} }, mcpOk("- HR"))
  await hooks["tool.execute.before"]({ tool: "oracleMCP_connect", sessionID: S, callID: "c3" }, { args: {} })
  await expectBlock(() => hooks["tool.execute.before"]({ tool: "task", sessionID: S, callID: "t3" }, taskArgs("ps-auditor")), "NEED_CONNECT")
})

test("list 連失敗兩次也退讓；NOT_CONNECTED 後計數歸零讓退讓還能再觸發", async () => {
  const dir = tempProject()
  const hooks = await PsOraclePreflightGate({ directory: dir, client: fakeClient() })
  await hooks["chat.message"]({ sessionID: S, agent: "ps-deep-research" }, { message: { id: "m1" }, parts: [{ type: "text", text: "audit" }] })
  await hooks["tool.execute.before"]({ tool: "oracleMCP_list_connections", sessionID: S, callID: "l1" }, { args: {} })
  await expectBlock(() => hooks["tool.execute.before"]({ tool: "task", sessionID: S, callID: "t1" }, taskArgs("ps-auditor")), "NEED_LIST")
  await hooks["tool.execute.before"]({ tool: "oracleMCP_list_connections", sessionID: S, callID: "l2" }, { args: {} })
  await hooks["tool.execute.after"]({ tool: "oracleMCP_list_connections", sessionID: S, callID: "l2", args: {} }, mcpOk("Error: cannot list"))
  await hooks["tool.execute.before"]({ tool: "task", sessionID: S, callID: "t2" }, taskArgs("ps-auditor"))
  assert.match(readLog(dir, S).at(-1).note, /list_connections failed x2/)
  // 新的一題：前置成功 → task → 回 NOT_CONNECTED → 再 connect 失敗兩次 → 退讓
  await hooks["chat.message"]({ sessionID: S, agent: "ps-deep-research" }, { message: { id: "m2" }, parts: [{ type: "text", text: "next" }] })
  await hooks["tool.execute.after"]({ tool: "oracleMCP_list_connections", sessionID: S, callID: "l3", args: {} }, mcpOk("- HR"))
  await hooks["tool.execute.before"]({ tool: "oracleMCP_connect", sessionID: S, callID: "c1" }, { args: { connection_name: "HR" } })
  await hooks["tool.execute.after"]({ tool: "oracleMCP_connect", sessionID: S, callID: "c1", args: { connection_name: "HR" } }, mcpOk("Connected to HR"))
  await hooks["tool.execute.before"]({ tool: "task", sessionID: S, callID: "t3" }, taskArgs("ps-auditor"))
  await hooks["tool.execute.after"]({ tool: "task", sessionID: S, callID: "t3", args: taskArgs("ps-auditor").args }, { title: "t", metadata: {}, output: '{"status":"BLOCKED","blockedReason":"NOT_CONNECTED"}' })
  await hooks["tool.execute.before"]({ tool: "oracleMCP_connect", sessionID: S, callID: "c2" }, { args: { connection_name: "HR" } })
  await expectBlock(() => hooks["tool.execute.before"]({ tool: "task", sessionID: S, callID: "t4" }, taskArgs("ps-auditor")), "NEED_CONNECT")
  await hooks["tool.execute.before"]({ tool: "oracleMCP_connect", sessionID: S, callID: "c3" }, { args: { connection_name: "HR" } })
  await hooks["tool.execute.before"]({ tool: "task", sessionID: S, callID: "t5" }, taskArgs("ps-auditor"))
  assert.match(readLog(dir, S).at(-1).note, /connect failed x2/)
})

test("command 驅動的 subtask（callID 是 prt_ 開頭）退讓不 throw；同一 callID 字串跨 session 不互撞", async () => {
  const dir = tempProject()
  const hooks = await PsOraclePreflightGate({ directory: dir, client: fakeClient() })
  await hooks["chat.message"]({ sessionID: S, agent: "ps-deep-research" }, { message: { id: "m1" }, parts: [{ type: "text", text: "x" }] })
  await hooks["tool.execute.before"]({ tool: "task", sessionID: S, callID: "prt_0123" }, taskArgs("ps-ui-flow"))
  assert.match(readLog(dir, S).at(-1).note, /command-driven subtask/)
  // 兩個 session 都用 call_0：入場快照與 pending 不能互相覆蓋
  const X = "ses_X", Y = "ses_Y"
  for (const sid of [X, Y]) {
    await hooks["chat.message"]({ sessionID: sid, agent: "ps-orchestrator" }, { message: { id: "m" + sid }, parts: [{ type: "text", text: "q" }] })
    await hooks["tool.execute.after"]({ tool: "oracleMCP_list_connections", sessionID: sid, callID: "call_0", args: {} }, mcpOk("- HR"))
  }
  await hooks["tool.execute.before"]({ tool: "oracleMCP_connect", sessionID: X, callID: "call_0" }, { args: { connection_name: "HR" } })
  await hooks["tool.execute.before"]({ tool: "oracleMCP_connect", sessionID: Y, callID: "call_0" }, { args: { connection_name: "HR" } })
  await hooks["tool.execute.after"]({ tool: "oracleMCP_connect", sessionID: X, callID: "call_0", args: { connection_name: "HR" } }, mcpOk("Connected"))
  await hooks["tool.execute.after"]({ tool: "oracleMCP_connect", sessionID: Y, callID: "call_0", args: { connection_name: "HR" } }, mcpOk("Connected"))
  await hooks["tool.execute.before"]({ tool: "task", sessionID: X, callID: "call_1" }, taskArgs("ps-ui-flow"))
  await hooks["tool.execute.before"]({ tool: "task", sessionID: Y, callID: "call_1" }, taskArgs("ps-ui-flow"))
  await hooks["tool.execute.after"]({ tool: "task", sessionID: X, callID: "call_1", args: taskArgs("ps-ui-flow").args }, { output: "<task_result>ok</task_result>" })
  await hooks["tool.execute.after"]({ tool: "task", sessionID: Y, callID: "call_1", args: taskArgs("ps-ui-flow").args }, { output: "<task_result>ok</task_result>" })
  assert.equal(readLog(dir, X).at(-1).turnId, "mses_X")
  assert.equal(readLog(dir, Y).at(-1).turnId, "mses_Y")
  assert.equal(readLog(dir, Y).at(-1).admitted, "allow")
})

test("event hook：SQLcl 對已連線再 connect 回 isError「already connected」→ 視為成功；其他 isError 記 failureMatch=isError；mcp.status 回 error 物件 → 保守擋", async () => {
  const dir = tempProject()
  const hooks = await PsOraclePreflightGate({ directory: dir, client: fakeClient() })
  await hooks["chat.message"]({ sessionID: S, agent: "ps-orchestrator" }, { message: { id: "m1" }, parts: [{ type: "text", text: "q" }] })
  await hooks["tool.execute.after"]({ tool: "oracleMCP_list_connections", sessionID: S, callID: "l", args: {} }, mcpOk("- HR"))
  await hooks["tool.execute.before"]({ tool: "oracleMCP_connect", sessionID: S, callID: "c1" }, { args: { connection_name: "HR" } })
  await hooks.event({ event: { type: "message.part.updated", properties: { part: { type: "tool", tool: "oracleMCP_connect", sessionID: S, callID: "c1", state: { status: "error", error: "Error: Already connected to HR", input: { connection_name: "HR" } } } } } })
  await hooks["tool.execute.before"]({ tool: "task", sessionID: S, callID: "t1" }, taskArgs("ps-ui-flow"))
  assert.equal(readLog(dir, S).at(-1).decision, "allow")
  assert.ok(readLog(dir, S).some((l) => l.viaEvent === true && l.ok === true))
  await hooks["chat.message"]({ sessionID: S, agent: "ps-orchestrator" }, { message: { id: "m2" }, parts: [{ type: "text", text: "q2" }] })
  await hooks["tool.execute.after"]({ tool: "oracleMCP_list_connections", sessionID: S, callID: "l2", args: {} }, mcpOk("- HR"))
  await hooks["tool.execute.before"]({ tool: "oracleMCP_connect", sessionID: S, callID: "c2" }, { args: { connection_name: "HR" } })
  await hooks.event({ event: { type: "message.part.updated", properties: { part: { type: "tool", tool: "oracleMCP_connect", sessionID: S, callID: "c2", state: { status: "error", error: "ORA-12541: TNS:no listener", input: { connection_name: "HR" } } } } } })
  await expectBlock(() => hooks["tool.execute.before"]({ tool: "task", sessionID: S, callID: "t2" }, taskArgs("ps-ui-flow")), "NEED_CONNECT")
  assert.ok(readLog(dir, S).some((l) => l.viaEvent === true && l.ok === false && l.failureMatch === "isError"))
  const bad = { mcp: { status: async () => ({ error: { name: "x" }, response: { status: 500 } }) }, session: { get: async () => ({ data: {} }) } }
  const hooks2 = await PsOraclePreflightGate({ directory: dir, client: bad })
  await hooks2["chat.message"]({ sessionID: "ses_bad", agent: "ps-orchestrator" }, { message: { id: "mb" }, parts: [{ type: "text", text: "q" }] })
  await expectBlock(() => hooks2["tool.execute.before"]({ tool: "task", sessionID: "ses_bad", callID: "t" }, taskArgs("ps-ui-flow")), "NEED_LIST")
  assert.match(readLog(dir, "ses_bad").at(-1).note, /mcp-status:error\(500\)/)
})

test("純 subagent 的 session 不建紀錄檔；run_sql 不記列", async () => {
  const dir = tempProject()
  const hooks = await PsOraclePreflightGate({ directory: dir, client: fakeClient() })
  await hooks["chat.message"]({ sessionID: "ses_child", agent: "ps-ui-flow" }, { message: { id: "mc" }, parts: [{ type: "text", text: "sub" }] })
  await hooks["tool.execute.before"]({ tool: "oracleMCP_run_sql", sessionID: "ses_child", callID: "q" }, { args: { sql: "SELECT 1" } })
  await hooks["tool.execute.after"]({ tool: "oracleMCP_run_sql", sessionID: "ses_child", callID: "q", args: {} }, mcpOk("1"))
  assert.ok(!fs.existsSync(path.join(dir, "auto-loop-logs", "ps-oracle-gate", "ses_child.jsonl")))
})

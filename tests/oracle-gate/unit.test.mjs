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

test("連線 epoch：別的 session connect／disconnect 後 READY 過期，必須重做前置；同 session 重連恢復", async () => {
  const dir = tempProject()
  const hooks = await PsOraclePreflightGate({ directory: dir, client: fakeClient() })
  const A = "ses_A", B = "ses_B"
  for (const sid of [A, B]) await hooks["chat.message"]({ sessionID: sid, agent: "ps-orchestrator" })
  // A 完成前置
  await hooks["tool.execute.before"]({ tool: "oracleMCP_list_connections", sessionID: A, callID: "c" }, { args: {} })
  await hooks["tool.execute.after"]({ tool: "oracleMCP_list_connections", sessionID: A, callID: "c", args: {} }, mcpOk("- HR"))
  await hooks["tool.execute.before"]({ tool: "oracleMCP_connect", sessionID: A, callID: "c" }, { args: { connection_name: "HR" } })
  await hooks["tool.execute.after"]({ tool: "oracleMCP_connect", sessionID: A, callID: "c", args: {} }, mcpOk("Connected to HR"))
  await hooks["tool.execute.before"]({ tool: "task", sessionID: A, callID: "c" }, taskArgs("ps-ui-flow"))
  // B 只是「嘗試」connect（before 就推進 epoch，失敗的 connect 也可能改動全域連線）
  await hooks["tool.execute.before"]({ tool: "oracleMCP_connect", sessionID: B, callID: "c" }, { args: { connection_name: "OTHER" } })
  await assert.rejects(() => hooks["tool.execute.before"]({ tool: "task", sessionID: A, callID: "c" }, taskArgs("ps-ui-flow")), (e) => /共用的 Oracle 連線已被改動過/.test(e.message) && /目前狀態＝NEED_LIST/.test(e.message))
  let log = readLog(dir, A)
  assert.match(log.at(-1).note, /shared connection changed since preflight/)
  // A 重做 list→connect → 放行
  await hooks["tool.execute.after"]({ tool: "oracleMCP_list_connections", sessionID: A, callID: "c", args: {} }, mcpOk("- HR"))
  await hooks["tool.execute.before"]({ tool: "oracleMCP_connect", sessionID: A, callID: "c" }, { args: { connection_name: "HR" } })
  await hooks["tool.execute.after"]({ tool: "oracleMCP_connect", sessionID: A, callID: "c", args: {} }, mcpOk("Connected to HR"))
  await hooks["tool.execute.before"]({ tool: "task", sessionID: A, callID: "c" }, taskArgs("ps-ui-flow"))
  // 跨行程：外部改寫 epoch 檔 → A 再派就過期
  const epochFile = path.join(dir, "auto-loop-logs", "ps-oracle-gate", "connection-epoch.json")
  assert.ok(fs.existsSync(epochFile), "epoch file written")
  fs.writeFileSync(epochFile, JSON.stringify({ epoch: "foreign-1", pid: 0 }))
  await expectBlock(() => hooks["tool.execute.before"]({ tool: "task", sessionID: A, callID: "c" }, taskArgs("ps-ui-flow")), "NEED_LIST")
  // B 的 disconnect 也推進 epoch；A 完成前置後 B disconnect → A 過期
  await hooks["tool.execute.after"]({ tool: "oracleMCP_list_connections", sessionID: A, callID: "c", args: {} }, mcpOk("- HR"))
  await hooks["tool.execute.before"]({ tool: "oracleMCP_connect", sessionID: A, callID: "c" }, { args: {} })
  await hooks["tool.execute.after"]({ tool: "oracleMCP_connect", sessionID: A, callID: "c", args: {} }, mcpOk("Connected to HR"))
  await hooks["tool.execute.before"]({ tool: "task", sessionID: A, callID: "c" }, taskArgs("ps-ui-flow"))
  await hooks["tool.execute.before"]({ tool: "oracleMCP_disconnect", sessionID: B, callID: "c" }, { args: {} })
  await hooks["tool.execute.after"]({ tool: "oracleMCP_disconnect", sessionID: B, callID: "c", args: {} }, mcpOk("Disconnected"))
  await expectBlock(() => hooks["tool.execute.before"]({ tool: "task", sessionID: A, callID: "c" }, taskArgs("ps-ui-flow")), "NEED_LIST")
  log = readLog(dir, A)
  assert.equal(log.filter((l) => l.decision === "block").length, 3)
  assert.ok(log.filter((l) => l.decision === "block").every((l) => /shared connection changed/.test(l.note)))
  assert.equal(log.filter((l) => l.decision === "allow" && l.tool === "task").length, 3)
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

test("connect 交錯：A 起跑後 B 也 connect，A 完成時不算 READY，B 算", async () => {
  const dir = tempProject()
  const hooks = await PsOraclePreflightGate({ directory: dir, client: fakeClient() })
  const A = "ses_A2", B = "ses_B2"
  for (const sid of [A, B]) {
    await hooks["chat.message"]({ sessionID: sid, agent: "ps-orchestrator" })
    await hooks["tool.execute.after"]({ tool: "oracleMCP_list_connections", sessionID: sid, callID: "l" + sid, args: {} }, mcpOk("- HR"))
  }
  await hooks["tool.execute.before"]({ tool: "oracleMCP_connect", sessionID: A, callID: "cA" }, { args: { connection_name: "HR" } })
  await hooks["tool.execute.before"]({ tool: "oracleMCP_connect", sessionID: B, callID: "cB" }, { args: { connection_name: "OTHER" } })
  await hooks["tool.execute.after"]({ tool: "oracleMCP_connect", sessionID: A, callID: "cA", args: {} }, mcpOk("Connected to HR"))
  await hooks["tool.execute.after"]({ tool: "oracleMCP_connect", sessionID: B, callID: "cB", args: {} }, mcpOk("Connected to OTHER"))
  await expectBlock(() => hooks["tool.execute.before"]({ tool: "task", sessionID: A, callID: "t" }, taskArgs("ps-ui-flow")), "NEED_CONNECT")
  await hooks["tool.execute.before"]({ tool: "task", sessionID: B, callID: "t" }, taskArgs("ps-ui-flow"))
  const logA = readLog(dir, A)
  assert.ok(logA.some((l) => l.tool === "oracleMCP_connect" && l.hook === "after" && /interleaved/.test(l.note ?? "") && l.next === "NEED_CONNECT"))
  assert.equal(readLog(dir, B).at(-1).decision, "allow")
  // A 再 connect 一次（沒人插隊）→ READY
  await hooks["tool.execute.before"]({ tool: "oracleMCP_connect", sessionID: A, callID: "cA2" }, { args: {} })
  await hooks["tool.execute.after"]({ tool: "oracleMCP_connect", sessionID: A, callID: "cA2", args: {} }, mcpOk("Connected to HR"))
  await hooks["tool.execute.before"]({ tool: "task", sessionID: A, callID: "t2" }, taskArgs("ps-ui-flow"))
  assert.equal(readLog(dir, A).at(-1).decision, "allow")
  // 過期訊息要標明來源
  await hooks["tool.execute.before"]({ tool: "oracleMCP_disconnect", sessionID: B, callID: "d" }, { args: {} })
  await assert.rejects(() => hooks["tool.execute.before"]({ tool: "task", sessionID: A, callID: "t3" }, taskArgs("ps-ui-flow")), (e) => /oracleMCP_disconnect by session ses_B2/.test(e.message))
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

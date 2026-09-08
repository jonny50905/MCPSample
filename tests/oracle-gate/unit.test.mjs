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

function fakeClient({ mcp = "connected", parents = {} } = {}) {
  return {
    mcp: { status: async () => (mcp === "throw" ? Promise.reject(new Error("boom")) : { data: mcp === "absent" ? {} : { oracleMCP: { status: mcp } } }) },
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

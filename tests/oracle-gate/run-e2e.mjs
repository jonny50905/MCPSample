// run-e2e.mjs — 用真 OpenCode（預設 PATH 上的 opencode；或 OPENCODE_BIN）＋假 oracleMCP＋假模型，
// 端到端驗證 ps-oracle-preflight-gate 在 opencode run（headless）路徑的行為。只給維護沙箱用。
// 用法：node tests/oracle-gate/run-e2e.mjs [--repeat N] [--only <scenario>] [--keep]
//   scenario：task-first | connect-first | compliant | stubborn | nodb | observe | mcp-down
// 每個情境：建臨時專案（複製 .opencode＋AGENTS.md）、寫 opencode.json、跑 opencode run --agent ps-orchestrator、
//   讀閘門 jsonl、opencode export 取正式 transcript 交叉比對、斷言。
import fs from "node:fs"
import os from "node:os"
import path from "node:path"
import { spawn, spawnSync } from "node:child_process"
import { fileURLToPath } from "node:url"

const here = path.dirname(fileURLToPath(import.meta.url))
const repoRoot = path.resolve(here, "..", "..")
const argv = process.argv.slice(2)
const arg = (name, def) => { const i = argv.indexOf(name); return i >= 0 ? argv[i + 1] : def }
const repeat = Number(arg("--repeat", "1"))
const only = arg("--only", "")
const keep = argv.includes("--keep")
const OPENCODE = process.env.OPENCODE_BIN || "opencode"
const MODEL_PORT = Number(process.env.MOCK_MODEL_PORT || 18081)

const SCENARIOS = {
  "task-first": { model: "task-first", mode: "enforce", mcp: true },
  "connect-first": { model: "connect-first", mode: "enforce", mcp: true },
  compliant: { model: "compliant", mode: "enforce", mcp: true },
  stubborn: { model: "stubborn", mode: "enforce", mcp: true },
  nodb: { model: "nodb", mode: "enforce", mcp: true },
  observe: { model: "task-first", mode: "observe", mcp: true },
  "mcp-down": { model: "task-first", mode: "enforce", mcp: false },
}

function copyDir(src, dst) {
  fs.mkdirSync(dst, { recursive: true })
  for (const e of fs.readdirSync(src, { withFileTypes: true })) {
    const s = path.join(src, e.name), d = path.join(dst, e.name)
    if (e.isDirectory()) { if (e.name === "node_modules") continue; copyDir(s, d) } else fs.copyFileSync(s, d)
  }
}

function makeProject(base, sc, name) {
  const project = path.join(base, name, "project")
  copyDir(path.join(repoRoot, ".opencode"), path.join(project, ".opencode"))
  fs.copyFileSync(path.join(repoRoot, "AGENTS.md"), path.join(project, "AGENTS.md"))
  fs.mkdirSync(path.join(project, "docs", "ps-research", "wiki"), { recursive: true })
  const mcpLog = path.join(base, name, "mcp.jsonl")
  const config = {
    $schema: "https://opencode.ai/config.json",
    model: "mock/scripted",
    small_model: "mock/scripted",
    autoupdate: false,
    provider: {
      mock: {
        npm: "@ai-sdk/openai-compatible",
        name: "Mock",
        options: { baseURL: `http://127.0.0.1:${MODEL_PORT}/v1`, apiKey: "mock" },
        models: { scripted: { name: "scripted", tool_call: true, limit: { context: 128000, output: 8192 } } },
      },
    },
    mcp: {
      oracleMCP: {
        type: "local",
        command: ["node", path.join(here, "mock-oracle-mcp.mjs")],
        enabled: sc.mcp,
        environment: { MOCK_ORACLE_LOG: mcpLog },
      },
    },
    permission: { doom_loop: "allow", external_directory: "allow" },
  }
  fs.writeFileSync(path.join(project, "opencode.json"), JSON.stringify(config, null, 2))
  return { project, mcpLog }
}

function startModel(scenario, logFile) {
  return new Promise((resolve, reject) => {
    const p = spawn("node", [path.join(here, "mock-model.mjs")], {
      env: { ...process.env, MOCK_MODEL_PORT: String(MODEL_PORT), MOCK_MODEL_SCENARIO: scenario, MOCK_MODEL_LOG: logFile },
      stdio: ["ignore", "pipe", "inherit"],
    })
    p.stdout.on("data", (d) => { if (/listening/.test(String(d))) resolve(p) })
    p.on("exit", (c) => reject(new Error("mock-model exited " + c)))
    setTimeout(() => reject(new Error("mock-model start timeout")), 5000)
  })
}

function runOpencode(project, env, args) {
  const started = Date.now()
  const r = spawnSync(OPENCODE, args, { cwd: project, env, encoding: "utf8", timeout: 180000, maxBuffer: 64 * 1024 * 1024 })
  return { stdout: r.stdout ?? "", stderr: r.stderr ?? "", status: r.status, signal: r.signal, ms: Date.now() - started }
}

function jsonl(file) {
  if (!fs.existsSync(file)) return []
  return fs.readFileSync(file, "utf8").split("\n").filter((l) => l.trim()).map((l) => { try { return JSON.parse(l) } catch { return { raw: l } } })
}

function toolParts(exported, sessionID) {
  const parts = []
  const msgs = exported?.messages ?? exported?.info?.messages ?? []
  for (const m of msgs) {
    const info = m.info ?? m
    if (info.sessionID && sessionID && info.sessionID !== sessionID) continue
    for (const p of m.parts ?? []) if (p.type === "tool") parts.push(p)
  }
  return parts
}

function assertEq(actual, expected, label, failures) {
  if (JSON.stringify(actual) !== JSON.stringify(expected)) failures.push(`${label}: expected ${JSON.stringify(expected)} got ${JSON.stringify(actual)}`)
}
function assertOk(cond, label, failures) { if (!cond) failures.push(label) }

async function runScenario(name, sc, base, iteration) {
  const tag = `${name}-${iteration}`
  const { project, mcpLog } = makeProject(base, sc, tag)
  const xdg = path.join(base, tag, "xdg")
  for (const d of ["data", "cache", "config", "state"]) fs.mkdirSync(path.join(xdg, d), { recursive: true })
  const env = {
    ...process.env,
    XDG_DATA_HOME: path.join(xdg, "data"), XDG_CACHE_HOME: path.join(xdg, "cache"),
    XDG_CONFIG_HOME: path.join(xdg, "config"), XDG_STATE_HOME: path.join(xdg, "state"),
    OPENCODE_DISABLE_AUTOUPDATE: "1", OPENCODE_DISABLE_MODELS_FETCH: "1",
    PS_ORACLE_GATE_MODE: sc.mode,
    // OpenCode 以 PWD 環境變數決定專案目錄（run.ts：process.env.PWD ?? process.cwd()），spawn 的 cwd 不夠
    PWD: project,
  }
  const modelLog = path.join(base, tag, "model.jsonl")
  const model = await startModel(sc.model, modelLog)
  let result, exported = null, sessionID = ""
  try {
    result = runOpencode(project, env, ["run", "--print-logs", "--log-level", "INFO", "--agent", "ps-orchestrator", "--model", "mock/scripted", "--format", "json", "--title", "gate-e2e-" + tag, "兵役狀態欄位有哪些選項？"])
    fs.writeFileSync(path.join(base, tag, "run.stdout.txt"), result.stdout)
    fs.writeFileSync(path.join(base, tag, "run.stderr.txt"), result.stderr)
    const events = result.stdout.split("\n").filter((l) => l.trim().startsWith("{")).map((l) => { try { return JSON.parse(l) } catch { return null } }).filter(Boolean)
    sessionID = events.find((e) => e.sessionID)?.sessionID ?? ""
    if (sessionID) {
      const ex = runOpencode(project, env, ["export", sessionID])
      try { exported = JSON.parse(ex.stdout) } catch { exported = null }
    }
  } finally {
    model.kill()
  }
  const gateFile = path.join(project, "auto-loop-logs", "ps-oracle-gate", sessionID + ".jsonl")
  const gate = sessionID ? jsonl(gateFile) : []
  const mcp = jsonl(mcpLog)
  const parts = exported ? toolParts(exported, sessionID) : []
  const taskParts = parts.filter((p) => p.tool === "task")
  const failures = []
  assertOk(result.status === 0, `exit code ${result.status} signal ${result.signal}; stderr tail: ${result.stderr.slice(-600)}`, failures)
  assertOk(sessionID !== "", "no sessionID in --format json output", failures)
  assertOk(exported !== null, "export failed", failures)
  const before = gate.filter((g) => g.hook === "before" && g.tool === "task")
  const blocks = before.filter((g) => g.decision === "block")
  const allows = before.filter((g) => g.decision === "allow")
  const executed = gate.filter((g) => g.hook === "after" && g.tool === "task" && g.executed)
  const stateSeq = gate.filter((g) => g.hook === "after" && /^oracleMCP_/.test(g.tool)).map((g) => `${g.tool.replace("oracleMCP_", "")}:${g.state}->${g.next}`)
  const mcpSeq = mcp.map((m) => m.tool)
  const runSqlBeforeConnect = mcp.some((m) => m.tool === "run_sql" && !m.connectedBefore)
  // P1 等價：閘門看到的 task 次數 ＝ 正式 transcript 的 task 工具件數
  assertEq(before.length, taskParts.length, "task before-hook count vs exported task parts", failures)
  const errParts = taskParts.filter((p) => p.state?.status === "error")
  const okParts = taskParts.filter((p) => p.state?.status === "completed")
  switch (name) {
    case "task-first":
      assertEq(blocks.map((b) => b.state), ["NEED_LIST"], "blocks", failures)
      assertEq(stateSeq, ["list_connections:NEED_LIST->NEED_CONNECT", "connect:NEED_CONNECT->READY"], "state sequence", failures)
      assertEq(allows.length, 1, "allowed task", failures); assertEq(executed.length, 1, "executed task", failures)
      assertOk(errParts.length === 1 && /PS_ORACLE_PREFLIGHT_REQUIRED/.test(errParts[0].state.error), "first task part is error with gate code; got " + JSON.stringify(errParts.map((p) => p.state.error?.slice(0, 120))), failures)
      assertEq(okParts.length, 1, "completed task parts", failures)
      assertEq(mcpSeq, ["list_connections", "connect", "run_sql"], "mcp call order", failures)
      assertOk(!runSqlBeforeConnect, "run_sql before connect", failures)
      break
    case "connect-first":
      assertEq(blocks.map((b) => b.state), ["NEED_LIST"], "blocks", failures)
      assertEq(stateSeq, ["connect:NEED_LIST->NEED_LIST", "list_connections:NEED_LIST->NEED_CONNECT", "connect:NEED_CONNECT->READY"], "state sequence", failures)
      assertEq(executed.length, 1, "executed task", failures)
      assertEq(mcpSeq, ["connect", "list_connections", "connect", "run_sql"], "mcp call order", failures)
      break
    case "compliant":
      assertEq(blocks.length, 0, "blocks", failures)
      assertEq(stateSeq, ["list_connections:NEED_LIST->NEED_CONNECT", "connect:NEED_CONNECT->READY"], "state sequence", failures)
      assertEq(executed.length, 1, "executed task", failures)
      assertEq(mcpSeq, ["list_connections", "connect", "run_sql"], "mcp call order", failures)
      break
    case "stubborn":
      assertEq(blocks.length, 4, "blocks", failures); assertEq(executed.length, 0, "executed task", failures)
      assertEq(mcpSeq, [], "no mcp calls", failures); assertEq(errParts.length, 4, "error task parts", failures)
      assertOk(blocks[3]?.blocked === 4 && blocks.every((b) => b.state === "NEED_LIST"), "block counter", failures)
      break
    case "nodb":
      assertEq(blocks.length, 0, "blocks", failures)
      assertOk(allows.length === 1 && allows[0].target === "ps-peoplecode-flow" && allows[0].basis === "run_sql:disabled", "nodb target allowed by basis", failures)
      assertEq(mcpSeq, [], "no mcp calls", failures); assertEq(okParts.length, 1, "completed task parts", failures)
      break
    case "observe": {
      const would = before.filter((g) => g.decision === "observe-would-block")
      assertEq(would.length, 1, "observe-would-block", failures); assertEq(blocks.length, 0, "blocks", failures)
      assertOk(executed.length >= 1 && executed[0].notConnected === true, "task executed before preflight and subagent reported NOT_CONNECTED (probe evidence)", failures)
      assertOk(runSqlBeforeConnect, "run_sql happened before connect (observe lets the wrong order through)", failures)
      break
    }
    case "mcp-down":
      assertEq(blocks.length, 0, "blocks", failures)
      assertOk(allows.length >= 1 && /gate stands down: mcp-status:(disabled|absent)/.test(allows[0].note ?? ""), "stands down note; got " + JSON.stringify(allows.map((a) => a.note)), failures)
      break
  }
  const summary = { scenario: name, iteration, ms: result.ms, exit: result.status, sessionID, blocks: blocks.length, allows: allows.length, executed: executed.length, stateSeq, mcpSeq, taskParts: taskParts.map((p) => p.state?.status), failures }
  console.log(JSON.stringify(summary))
  if (failures.length && !keep) {
    console.log("--- stderr tail ---\n" + result.stderr.slice(-2000))
    console.log("--- gate log ---\n" + gate.map((g) => JSON.stringify(g)).join("\n"))
  }
  return failures.length === 0
}

const base = fs.mkdtempSync(path.join(os.tmpdir(), "gate-e2e-"))
console.log("workdir " + base + " opencode=" + OPENCODE)
let ok = true
for (const [name, sc] of Object.entries(SCENARIOS)) {
  if (only && only !== name) continue
  for (let i = 1; i <= repeat; i++) ok = (await runScenario(name, sc, base, i)) && ok
}
if (!keep) fs.rmSync(base, { recursive: true, force: true })
console.log(ok ? "E2E PASS" : "E2E FAIL")
process.exit(ok ? 0 : 1)

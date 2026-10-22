// run-e2e.mjs — 用真 OpenCode（預設 PATH 上的 opencode；或 OPENCODE_BIN）＋假 oracleMCP（仿 @vdeserto/oracle-mcp-server）＋假模型，
// 端到端驗證 ps-runtime-guard 在 opencode run（headless）與 opencode serve（同行程多 session、兩個 host）路徑的行為。只給維護沙箱用。
// 用法：node tests/runtime-guard/run-e2e.mjs [--repeat N] [--only <scenario>] [--keep]
//   沒有派工閘門、沒有 connect：主 agent 看不到 oracleMCP 工具，查詢只由 subagent 以 oracleMCP_oracle_execute_query 做。驗的是——
//   compliant        task → subagent oracle_execute_query → COMPLETE（可用的定義：報告 COMPLETE 且子 session 有成功的查詢）；工具允許清單
//   db-flaky         DB 前兩次查詢失敗：subagent 業務查詢與 SELECT 1 AS OK FROM DUAL 都回 Database query failed → BLOCKED(NOT_CONNECTED)
//                    → 主 agent 重派一次 → COMPLETE
//   db-down          DB 一直連不上：NOT_CONNECTED → 重派一次 → 又 NOT_CONNECTED → 回報「DB 連線失敗」、不再派（不迴圈）；不觸發重掛
//   nodb             派 ps-peoplecode-flow：零 oracleMCP 呼叫、報告 COMPLETE（dbCapable=false 只是紀錄）
//   stale-connect    主 agent 憑記憶呼叫 SQLcl 時代的 oracleMCP_connect → OpenCode 判 invalid（guard 記「多半是錯名」、不重掛、不擋）→ 照常完成
//   mcp-down         oracleMCP enabled:false → subagent 看不到 oracleMCP_ 工具 → 回 ORACLE_MCP_DOWN、不猜名；主 agent 不重派、回報 DOWN
//   mcp-failed       oracleMCP 指令不存在（/mcp 狀態 failed）→ 同上
//   skill-as-agent   task(subagent_type=ps-security-flow) 執行前被擋（PS_TASK_TARGET_INVALID，指出 ps-metadata-flow）→ 改派 ps-metadata-flow → COMPLETE；不觸發重掛
//   suggested-skill  subagent 報告 suggestedNext 帶 ps-security-flow → task 回覆末尾附 guard 註記 → 主 agent 改派 ps-metadata-flow
//   vanish-auto      （serve；自動重掛 on；host A＋host B）A1 正常後假 MCP 工具目錄變空（list_changed）→ A2 新 session 的 subagent 看不到工具、
//                    憑記憶呼叫查詢 → OpenCode 判 invalid → guard 以 host 證據重掛一次 → A3 新 session 恢復、第一個查詢回覆附「已重掛」註記；
//                    host B 全程正常、從未重掛
//   vanish-observe   （serve；自動重掛 off）同上但只記 would-remount；A3 仍看不到工具、回報 DOWN；假 MCP 只起過一次
//   transport-close  （serve；自動重掛 on）假 MCP 行程結束（狀態 failed: Connection closed）→ 事件觸發重掛 → A2 新 session 恢復
// 每個情境：建臨時專案（複製 .opencode＋AGENTS.md）、寫 opencode.json、跑 opencode（run 或 serve）、
//   讀 guard 的 jsonl／_mcp-diag.jsonl、opencode export 取正式 transcript 交叉比對（task 件數、訊息 id 歸屬）、斷言。
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
const LOG_DIR = path.join("auto-loop-logs", "ps-runtime-guard")

const Q = "oracleMCP_oracle_execute_query"
const SCENARIOS = {
  compliant: { model: "compliant", mcp: true },
  "db-flaky": { model: "redispatch-once", mcp: true, dbDownCalls: 2 },
  "db-down": { model: "redispatch-once", mcp: true, dbDown: true },
  nodb: { model: "nodb", mcp: true },
  "stale-connect": { model: "stale-connect", mcp: true },
  "mcp-down": { model: "down-aware", mcp: false },
  "mcp-failed": { model: "down-aware", mcp: true, mcpBroken: true },
  "skill-as-agent": { model: "skill-as-agent", mcp: true },
  "suggested-skill": { model: "suggested-skill", mcp: true, suggestSkill: true },
  "vanish-auto": { model: "down-probe", mcp: true, vanishAfter: 1, autoRecover: "on", hostB: true, serve: ["A:A1", "B:B1", "A:wait:tools-changed", "A:A2", "A:wait:remount-ok", "A:A3", "B:B2"] },
  "vanish-observe": { model: "down-probe", mcp: true, vanishAfter: 1, autoRecover: "off", serve: ["A:A1", "A:wait:tools-changed", "A:A2", "A:wait:would-remount", "A:A3"] },
  "transport-close": { model: "down-probe", mcp: true, exitAfter: 1, autoRecover: "on", serve: ["A:A1", "A:wait:remount-ok", "A:A2"] },
}

function copyDir(src, dst) {
  fs.mkdirSync(dst, { recursive: true })
  for (const e of fs.readdirSync(src, { withFileTypes: true })) {
    const s = path.join(src, e.name), d = path.join(dst, e.name)
    if (e.isDirectory()) { if (e.name === "node_modules") continue; copyDir(s, d) } else fs.copyFileSync(s, d)
  }
}

function makeProject(base, sc, name, { fault = true } = {}) {
  const project = path.join(base, name, "project")
  copyDir(path.join(repoRoot, ".opencode"), path.join(project, ".opencode"))
  fs.copyFileSync(path.join(repoRoot, "AGENTS.md"), path.join(project, "AGENTS.md"))
  fs.mkdirSync(path.join(project, "docs", "ps-research", "wiki"), { recursive: true })
  const profilePath = path.join(project, ".opencode", "peoplesoft", "customization-profile.yaml")
  const profile = fs.readFileSync(profilePath, "utf8")
  if (/^\s*connectionName:/m.test(profile)) throw new Error("profile still has oracle.connectionName (the new oracleMCP has no connect)")
  fs.writeFileSync(profilePath, profile.replace(/^(\s*currentSchema:)\s*\S+/m, "$1 DEMOOWN"))
  const mcpLog = path.join(base, name, "mcp.jsonl")
  // 真 server 讀這三個環境變數（假 server 不檢查，寫上是為了讓 opencode.json 的形狀與公司機一致）
  const mcpEnv = { MOCK_ORACLE_LOG: mcpLog, ORACLE_USER: "ps_readonly", ORACLE_PASSWORD: "mock", ORACLE_CONNECTION_STRING: "localhost:1521/MOCK" }
  if (sc.dbDown) mcpEnv.MOCK_ORACLE_DB_DOWN = "1"
  if (sc.dbDownCalls) mcpEnv.MOCK_ORACLE_DB_DOWN_CALLS = String(sc.dbDownCalls)
  if (fault && sc.vanishAfter) { mcpEnv.MOCK_ORACLE_VANISH_AFTER_CALLS = String(sc.vanishAfter); mcpEnv.MOCK_ORACLE_FAULT_MARKER = path.join(base, name, "fault.marker") }
  if (fault && sc.exitAfter) { mcpEnv.MOCK_ORACLE_EXIT_AFTER_CALLS = String(sc.exitAfter); mcpEnv.MOCK_ORACLE_FAULT_MARKER = path.join(base, name, "fault.marker") }
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
        command: sc.mcpBroken ? ["node", path.join(here, "does-not-exist.mjs")] : ["node", path.join(here, "mock-oracle-mcp.mjs")],
        enabled: sc.mcp,
        environment: mcpEnv,
      },
    },
    permission: { doom_loop: "allow", external_directory: "allow" },
  }
  fs.writeFileSync(path.join(project, "opencode.json"), JSON.stringify(config, null, 2))
  return { project, mcpLog }
}

function startModel(scenario, logFile, extraEnv) {
  return new Promise((resolve, reject) => {
    const p = spawn("node", [path.join(here, "mock-model.mjs")], {
      env: { ...process.env, MOCK_MODEL_PORT: String(MODEL_PORT), MOCK_MODEL_SCENARIO: scenario, MOCK_MODEL_LOG: logFile, ...extraEnv },
      stdio: ["ignore", "pipe", "inherit"],
    })
    p.stdout.on("data", (d) => { if (/listening/.test(String(d))) resolve(p) })
    p.on("exit", (c) => reject(new Error("mock-model exited " + c)))
    setTimeout(() => reject(new Error("mock-model start timeout")), 5000)
  })
}

function jsonl(file) {
  if (!fs.existsSync(file)) return []
  return fs.readFileSync(file, "utf8").split("\n").filter((l) => l.trim()).map((l) => { try { return JSON.parse(l) } catch { return { raw: l } } })
}
const wait = (ms) => new Promise((r) => setTimeout(r, ms))
const diagOf = (project) => jsonl(path.join(project, LOG_DIR, "_mcp-diag.jsonl"))
const sessionLog = (project, id) => (id ? jsonl(path.join(project, LOG_DIR, id + ".jsonl")) : [])

function hostEnv(project, xdg, sc) {
  for (const d of ["data", "cache", "config", "state"]) fs.mkdirSync(path.join(xdg, d), { recursive: true })
  return {
    ...process.env,
    XDG_DATA_HOME: path.join(xdg, "data"), XDG_CACHE_HOME: path.join(xdg, "cache"),
    XDG_CONFIG_HOME: path.join(xdg, "config"), XDG_STATE_HOME: path.join(xdg, "state"),
    OPENCODE_DISABLE_AUTOUPDATE: "1", OPENCODE_DISABLE_MODELS_FETCH: "1",
    PS_ORACLE_MCP_AUTO_RECOVER: sc.autoRecover ?? "off",
    PS_GUARD_REMOUNT_VERIFY_MS: "8000", PS_GUARD_REMOUNT_POLL_MS: "300",
    // OpenCode 以 PWD 環境變數決定專案目錄（run.ts：process.env.PWD ?? process.cwd()），spawn 的 cwd 不夠
    PWD: project,
  }
}

// opencode serve：一或兩個 host（各自行程、埠、專案、XDG），依步驟送題（每個 label 一個新 session）、等待 guard 診斷列
async function runHosts(hosts, steps, tag, base) {
  const started = Date.now()
  let out = "", err = "", status = 0
  const sessions = {}
  const procs = {}
  const urlOf = (h, p) => `http://127.0.0.1:${h.port}${p}?directory=${encodeURIComponent(h.project)}`
  try {
    for (const [name, h] of Object.entries(hosts)) {
      sessions[name] = {}
      const server = spawn(OPENCODE, ["serve", "--port", String(h.port), "--hostname", "127.0.0.1", "--print-logs", "--log-level", "INFO"], { cwd: h.project, env: h.env, stdio: ["ignore", "pipe", "pipe"] })
      server.stdout.on("data", (d) => (out += `[${name}] ` + d))
      server.stderr.on("data", (d) => (err += `[${name}] ` + d))
      procs[name] = server
      let ready = false, lastErr = ""
      for (let i = 0; i < 100 && !ready; i++) {
        await wait(300)
        try { const r = await fetch(urlOf(h, "/session"), { signal: AbortSignal.timeout(20000) }); ready = r.ok; lastErr = "HTTP " + r.status } catch (e) { lastErr = String(e?.cause?.code ?? e?.message ?? e) }
      }
      if (!ready) throw new Error(`host ${name} serve not ready; last: ${lastErr}; stderr tail: ${err.slice(-800)}`)
      out += `[harness] host ${name} ready after ${Date.now() - started}ms\n`
    }
    for (const step of steps) {
      const [host, kind, what] = step.split(":")
      const h = hosts[host]
      if (kind === "wait") {
        const deadline = Date.now() + 20000
        let found = false
        while (Date.now() < deadline && !found) {
          const rows = diagOf(h.project)
          found = rows.some((r) => (what === "tools-changed" ? r.kind === "event" && r.type === "mcp.tools.changed" : r.kind === "recovery" && r.decision === what))
          if (!found) await wait(250)
        }
        out += `[harness] host ${host} wait ${what}: ${found ? "seen" : "TIMEOUT"} t+${Date.now() - started}ms\n`
        if (!found) { status = 1; err += `\n--- wait ${what} on host ${host} timed out ---\n` }
        continue
      }
      const label = kind
      const created = await fetch(urlOf(h, "/session"), { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ title: `guard-e2e-${tag}-${label}` }) })
      const cj = await created.json()
      sessions[host][label] = cj.id
      const text = `${label} 題：兵役狀態欄位有哪些選項？`
      const r = await fetch(urlOf(h, `/session/${cj.id}/message`), { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ agent: "ps-orchestrator", model: { providerID: "mock", modelID: "scripted" }, parts: [{ type: "text", text }] }) })
      const body = await r.text()
      out += `[harness] host ${host} ${label} session ${cj.id} HTTP ${r.status} t+${Date.now() - started}ms\n`
      fs.writeFileSync(path.join(base, tag, `serve-${host}-${label}.response.json`), body)
      if (!r.ok) { status = 1; err += `\n--- ${host}:${label} HTTP ${r.status} ---\n${body.slice(0, 2000)}` }
    }
  } catch (e) {
    status = 1
    err += "\n--- harness error ---\n" + String(e)
  } finally {
    for (const p of Object.values(procs)) p.kill()
    await wait(800)
  }
  fs.writeFileSync(path.join(base, tag, "serve.stdout.txt"), out)
  fs.writeFileSync(path.join(base, tag, "serve.stderr.txt"), err)
  return { sessions, result: { stdout: out, stderr: err, status, signal: null, ms: Date.now() - started } }
}

function runOpencode(project, env, args) {
  const started = Date.now()
  const r = spawnSync(OPENCODE, args, { cwd: project, env, encoding: "utf8", timeout: 180000, maxBuffer: 64 * 1024 * 1024 })
  return { stdout: r.stdout ?? "", stderr: r.stderr ?? "", status: r.status, signal: r.signal, ms: Date.now() - started }
}

function exportSession(project, env, sessionID) {
  if (!sessionID) return null
  const ex = runOpencode(project, env, ["export", sessionID])
  try { return JSON.parse(ex.stdout) } catch { return null }
}

// export 裡的 tool part（含所屬 assistant 訊息的 parentID＝觸發它的 user 訊息 id）
function toolParts(exported, sessionID) {
  const parts = []
  for (const m of exported?.messages ?? []) {
    const info = m.info ?? m
    if ((info.sessionID ?? sessionID) !== sessionID) continue
    for (const p of m.parts ?? []) if (p.type === "tool") parts.push({ ...p, parentID: info.parentID })
  }
  return parts
}
const REAL_PART_TYPES = ["text", "file", "agent", "subtask"]
function realPrompt(m) { return (m.parts ?? []).some((p) => REAL_PART_TYPES.includes(p.type) && p.synthetic !== true) }
function userMessages(exported, sessionID) {
  return (exported?.messages ?? []).filter((m) => (m.info ?? m).role === "user" && ((m.info ?? m).sessionID ?? sessionID) === sessionID)
}
function assistantText(exported, sessionID) {
  return (exported?.messages ?? []).filter((m) => (m.info ?? m).role === "assistant" && ((m.info ?? m).sessionID ?? sessionID) === sessionID)
    .flatMap((m) => (m.parts ?? []).filter((p) => p.type === "text").map((p) => p.text ?? "")).join("\n")
}

function assertEq(actual, expected, label, failures) {
  if (JSON.stringify(actual) !== JSON.stringify(expected)) failures.push(`${label}: expected ${JSON.stringify(expected)} got ${JSON.stringify(actual)}`)
}
function assertOk(cond, label, failures) { if (!cond) failures.push(label) }

// 可用的定義：已執行的 DB task 列 reportStatus=COMPLETE、reportValid、childSessionID 指向子 session，且子 session 的 jsonl 有成功的查詢
function childSqlOk(project, child) {
  if (!child) return 0
  return sessionLog(project, child).filter((g) => g.hook === "after" && g.tool === Q && g.ok === true).length
}
function assertCompleted(project, executed, failures, label = "") {
  assertOk(executed.length >= 1 && executed.every((e) => e.reportValid === true && e.reportStatus === "COMPLETE" && e.blockedReason === "NOT_APPLICABLE" && typeof e.childSessionID === "string" && e.childSessionID.startsWith("ses_") && e.taskState === "completed"),
    `${label}executed DB task rows carry a parsed COMPLETE report and child session id; got ` + JSON.stringify(executed.map((e) => [e.reportStatus, e.blockedReason, e.childSessionID, e.taskState])), failures)
  assertOk(executed.every((e) => childSqlOk(project, e.childSessionID) >= 1), `${label}every completed DB task has a successful oracle_execute_query in its child session log`, failures)
}

// 允許清單：假模型記下每次請求可見的工具名；沒有 task 的請求＝subagent（Oracle 只有 oracle_execute_query）；主 agent（有 task）看不到任何 oracleMCP_ 工具
function assertToolLists(modelLog, failures) {
  const rows = jsonl(modelLog).filter((r) => Array.isArray(r.tools))
  const sub = rows.filter((r) => !r.tools.includes("task") && r.tools.some((t) => t.startsWith("oracleMCP_")))
  const oracle = (r) => r.tools.filter((t) => t.startsWith("oracleMCP_")).sort()
  assertOk(sub.length >= 1 && sub.every((r) => JSON.stringify(oracle(r)) === JSON.stringify([Q])), "subagent sees only oracleMCP_oracle_execute_query (allowlist); got " + JSON.stringify(sub.map(oracle)), failures)
  const primary = rows.filter((r) => r.tools.includes("task"))
  assertOk(primary.length >= 1 && primary.every((r) => oracle(r).length === 0), "primary agent sees no oracleMCP_ tool; got " + JSON.stringify(primary.map(oracle)), failures)
}

// 一個 session 的共通斷言：紀錄列沒有派工狀態；task hook 覆蓋率；訊息 id 歸屬；沒有 synthetic 提醒 part
function commonSessionChecks(project, sessionID, exported, failures, label) {
  const g = sessionLog(project, sessionID)
  const parts = exported ? toolParts(exported, sessionID) : []
  const taskParts = parts.filter((p) => p.tool === "task")
  const before = g.filter((x) => x.hook === "before" && x.tool === "task")
  const chats = g.filter((x) => x.hook === "chat.message" && x.synthetic !== true)
  const users = exported ? userMessages(exported, sessionID) : []
  const real = users.filter(realPrompt)
  assertOk(exported !== null, `${label}export failed`, failures)
  assertOk(g.every((x) => !("state" in x) && !("next" in x) && !("turnId" in x) && !("gen" in x)), `${label}guard rows carry no dispatch state (state/next/turnId/gen)`, failures)
  assertEq(before.length, taskParts.length, `${label}task before-hook count vs exported task parts`, failures)
  if (exported) {
    assertEq(chats.map((c) => c.messageID).sort(), real.map((m) => (m.info ?? m).id).sort(), `${label}chat.message ids vs real prompt ids`, failures)
    for (const b of before) { const tp = taskParts.find((p) => p.callID === b.callID); if (tp && tp.parentID) assertOk(tp.parentID === b.messageID, `${label}task ${b.callID} attributed to message ${b.messageID}, export says ${tp.parentID}`, failures) }
    assertOk(real.every((m) => (m.parts ?? []).every((p) => p.synthetic !== true)), `${label}no synthetic parts injected into user messages`, failures)
  }
  return { g, parts, taskParts, before, chats, real }
}

async function runScenario(name, sc, base, iteration) {
  const tag = `${name}-${iteration}`
  const { project, mcpLog } = makeProject(base, sc, tag)
  const env = hostEnv(project, path.join(base, tag, "xdg"), sc)
  const modelLog = path.join(base, tag, "model.jsonl")
  const model = await startModel(sc.model, modelLog, sc.suggestSkill ? { MOCK_MODEL_SUGGEST_SKILL: "1" } : {})
  const failures = []
  let result, exported = null, sessionID = ""
  const hosts = {}
  let sessions = {}
  try {
    if (sc.serve) {
      hosts.A = { project, env, port: MODEL_PORT + 100, mcpLog }
      if (sc.hostB) {
        const b = makeProject(base, sc, tag + "-hostB", { fault: false })
        hosts.B = { project: b.project, env: hostEnv(b.project, path.join(base, tag + "-hostB", "xdg"), sc), port: MODEL_PORT + 200, mcpLog: b.mcpLog }
      }
      const sv = await runHosts(hosts, sc.serve, tag, base)
      result = sv.result
      sessions = sv.sessions
    } else {
      result = runOpencode(project, env, ["run", "--print-logs", "--log-level", "INFO", "--agent", "ps-orchestrator", "--model", "mock/scripted", "--format", "json", "--title", "guard-e2e-" + tag, "兵役狀態欄位有哪些選項？"])
      fs.writeFileSync(path.join(base, tag, "run.stdout.txt"), result.stdout)
      fs.writeFileSync(path.join(base, tag, "run.stderr.txt"), result.stderr)
      const events = result.stdout.split("\n").filter((l) => l.trim().startsWith("{")).map((l) => { try { return JSON.parse(l) } catch { return null } }).filter(Boolean)
      sessionID = events.find((e) => e.sessionID)?.sessionID ?? ""
      exported = exportSession(project, env, sessionID)
      if (exported) fs.writeFileSync(path.join(base, tag, "export.json"), JSON.stringify(exported, null, 1))
    }
  } finally {
    model.kill()
  }
  assertOk(result.status === 0, `exit code ${result.status} signal ${result.signal}; stderr tail: ${result.stderr.slice(-800)}`, failures)
  const mcp = jsonl(mcpLog)
  const mcpSeq = mcp.filter((m) => m.tool).map((m) => m.tool)
  const diag = diagOf(project)
  const recoveries = diag.filter((d) => d.kind === "recovery")

  if (!sc.serve) {
    assertOk(sessionID !== "", "no sessionID in --format json output", failures)
    const v = commonSessionChecks(project, sessionID, exported, failures, "")
    const executed = v.g.filter((x) => x.hook === "after" && x.tool === "task" && x.executed)
    const blocks = v.before.filter((b) => b.decision === "block")
    const invalids = v.g.filter((x) => x.hook === "invalid")
    const errParts = v.taskParts.filter((p) => p.state?.status === "error")
    const okParts = v.taskParts.filter((p) => p.state?.status === "completed")
    const text = exported ? assistantText(exported, sessionID) : ""
    const noConnectRows = () => assertOk(v.g.every((x) => !("connection" in x) && !("profileConnection" in x) && !("mode" in x)), "guard rows carry no connect-target fields", failures)
    switch (name) {
      case "compliant": {
        assertEq(blocks.length, 0, "task blocks", failures)
        assertEq(mcpSeq, ["oracle_execute_query"], "mcp call order (no connect; the subagent queries directly)", failures)
        assertEq(executed.map((e) => [e.target, e.dbCapable, e.basis, e.reportStatus]), [["ps-ui-flow", true, "execute_query:enabled", "COMPLETE"]], "executed task rows", failures)
        assertCompleted(project, executed, failures)
        assertToolLists(modelLog, failures)
        assertEq(invalids.length, 0, "no invalid tool calls", failures)
        assertEq(recoveries.length, 0, "no recovery rows", failures)
        noConnectRows()
        assertOk(/^DONE/.test(text.trim()), "model finished normally; got " + text.slice(0, 120), failures)
        break
      }
      case "db-flaky":
      case "db-down": {
        const flaky = name === "db-flaky"
        assertEq(blocks.length, 0, "no task blocks (there is no dispatch gate)", failures)
        assertEq(mcpSeq, flaky ? ["oracle_execute_query", "oracle_execute_query", "oracle_execute_query"] : ["oracle_execute_query", "oracle_execute_query", "oracle_execute_query", "oracle_execute_query"], "mcp calls: business query + SELECT 1 AS OK FROM DUAL probe per failed attempt", failures)
        const probes = mcp.filter((m) => m.tool === "oracle_execute_query" && /SELECT 1 AS OK FROM DUAL/.test(m.args?.sql ?? ""))
        assertEq(probes.length, flaky ? 1 : 2, "the subagent probed the connection with SELECT 1 AS OK FROM DUAL after Database query failed", failures)
        const expected = flaky ? [["BLOCKED", "NOT_CONNECTED", true], ["COMPLETE", "NOT_APPLICABLE", false]] : [["BLOCKED", "NOT_CONNECTED", true], ["BLOCKED", "NOT_CONNECTED", true]]
        assertEq(executed.map((e) => [e.reportStatus, e.blockedReason, e.notConnected]), expected, "task after rows (redispatched exactly once)", failures)
        if (flaky) assertCompleted(project, [executed[1]].filter(Boolean), failures)
        const childErr = executed.length ? sessionLog(project, executed[0].childSessionID).filter((g) => g.hook === "after" && g.tool === Q) : []
        assertOk(childErr.length === 2 && childErr.every((g) => g.ok === false && /error/i.test(g.failureMatch ?? "")), "the failed attempt's child session logged two ok:false queries (Error: …); got " + JSON.stringify(childErr.map((g) => [g.ok, g.failureMatch])), failures)
        assertEq(okParts.length, 2, "both task parts completed (a BLOCKED report is still a completed tool call)", failures)
        if (flaky) assertOk(/^DONE/.test(text.trim()), "model finished after one redispatch; got " + text.slice(0, 120), failures)
        else assertOk(/DB 連線失敗/.test(text) && /SOP-21/.test(text), "model reported the DB connection failure after one redispatch; got " + text.slice(0, 160), failures)
        assertEq(recoveries.length, 0, "a DB-level failure is never MCP recovery evidence", failures)
        noConnectRows()
        break
      }
      case "nodb": {
        assertOk(v.before.length === 1 && v.before[0].target === "ps-peoplecode-flow" && v.before[0].dbCapable === false && v.before[0].basis === "execute_query:disabled" && v.before[0].decision === "allow", "nodb target recorded as not DB-capable; got " + JSON.stringify(v.before), failures)
        assertEq(mcpSeq, [], "no mcp calls", failures)
        assertEq(executed.map((e) => e.reportStatus), ["COMPLETE"], "report", failures)
        assertEq(okParts.length, 1, "completed task parts", failures)
        break
      }
      case "stale-connect": {
        assertOk(invalids.length === 1 && invalids[0].attempted === "oracleMCP_connect" && invalids[0].seenBefore === false && /wrong name/.test(invalids[0].note ?? ""), "the remembered SQLcl connect became invalid = likely a wrong name (not an MCP fault); got " + JSON.stringify(invalids), failures)
        assertEq(v.g.filter((x) => x.hook === "before" && x.tool === "oracleMCP_connect").length, 0, "the guard never saw an executed connect", failures)
        assertEq(mcpSeq, ["oracle_execute_query"], "mock MCP got only the subagent query (no connect tool exists)", failures)
        assertEq(executed.map((e) => [e.target, e.reportStatus]), [["ps-ui-flow", "COMPLETE"]], "the question still completed", failures)
        assertCompleted(project, executed, failures)
        assertEq(recoveries.length, 0, "a wrong tool name is not recovery evidence", failures)
        assertOk(/staleRejected":true/.test(text), "model saw the stale call rejected; got " + text.slice(0, 160), failures)
        break
      }
      case "mcp-down":
      case "mcp-failed": {
        const rows = jsonl(modelLog).filter((r) => Array.isArray(r.tools))
        assertOk(rows.length >= 1 && rows.every((r) => !r.tools.some((t) => t.startsWith("oracleMCP_"))), "no agent saw oracleMCP_ tools", failures)
        assertEq(mcpSeq, [], "no mcp calls", failures)
        assertEq(executed.map((e) => [e.target, e.reportStatus, e.blockedReason]), [["ps-ui-flow", "BLOCKED", "ORACLE_MCP_DOWN"]], "the DB subagent reported ORACLE_MCP_DOWN once and was not redispatched", failures)
        assertEq(invalids.length, 0, "model did not guess a tool name", failures)
        assertOk(/ORACLE_MCP_DOWN/.test(text) && /不猜工具名/.test(text), "model reported ORACLE_MCP_DOWN and stopped; got " + text.slice(0, 160), failures)
        assertEq(recoveries.length, 0, "nothing to recover automatically (never mounted / disabled): no recovery rows", failures)
        break
      }
      case "skill-as-agent": {
        assertEq(v.taskParts.map((p) => p.state?.status), ["error", "completed"], "task parts: mis-routed task errored, corrected task completed", failures)
        assertOk(errParts.length === 1 && /^PS_TASK_TARGET_INVALID/.test(errParts[0].state?.error ?? "") && /ps-metadata-flow/.test(errParts[0].state?.error ?? "") && /skills\/ps-security-flow\/SKILL\.md/.test(errParts[0].state?.error ?? "") && !/ORACLE_MCP_DOWN/.test(errParts[0].state?.error ?? ""), "error names the carrier agent and the skill path; got " + JSON.stringify(errParts.map((p) => (p.state?.error ?? "").slice(0, 160))), failures)
        assertEq(blocks.map((b) => [b.target, b.note, b.carrier]), [["ps-security-flow", "PS_TASK_TARGET_INVALID:skill", "ps-metadata-flow"]], "guard block row", failures)
        assertEq(executed.map((e) => [e.target, e.reportStatus]), [["ps-metadata-flow", "COMPLETE"]], "corrected dispatch executed", failures)
        assertCompleted(project, executed, failures)
        assertEq(mcpSeq, ["oracle_execute_query"], "routing error caused no extra oracleMCP call", failures)
        assertEq(recoveries.length, 0, "routing error caused no recovery", failures)
        assertOk(/^DONE/.test(text.trim()), "model finished; got " + text.slice(0, 120), failures)
        break
      }
      case "suggested-skill": {
        assertEq(v.taskParts.map((p) => [p.state?.status, p.state?.input?.subagent_type]), [["completed", "ps-ui-flow"], ["completed", "ps-metadata-flow"]], "task parts: ui-flow then the carrier agent (never ps-security-flow)", failures)
        const first = executed[0]
        assertOk(first && Array.isArray(first.suggestedNextInvalid) && first.suggestedNextInvalid[0]?.agent === "ps-security-flow" && first.suggestedNextInvalid[0]?.carrier === "ps-metadata-flow", "first task row flags the invalid suggestedNext; got " + JSON.stringify(first?.suggestedNextInvalid), failures)
        const firstPart = v.taskParts[0]
        assertOk(firstPart && /\[ps-runtime-guard\] 報告的 suggestedNext 含無效委派目標/.test(firstPart.state?.output ?? "") && /改派 ps-metadata-flow/.test(firstPart.state?.output ?? ""), "task tool output carries the guard annotation the model can read", failures)
        assertCompleted(project, executed, failures)
        assertOk(/annotated":true/.test(text), "model acted on the annotation; got " + text.slice(0, 160), failures)
        assertEq(recoveries.length, 0, "no recovery", failures)
        break
      }
    }
    const summary = { scenario: name, iteration, ms: result.ms, exit: result.status, sessionID, mcpSeq, taskParts: v.taskParts.map((p) => p.state?.status), failures }
    console.log(JSON.stringify(summary))
    if (failures.length && !keep) console.log("--- stderr tail ---\n" + result.stderr.slice(-2000) + "\n--- guard log ---\n" + v.g.map((x) => JSON.stringify(x)).join("\n") + "\n--- diag ---\n" + diag.map((x) => JSON.stringify(x)).join("\n"))
    return failures.length === 0
  }

  // serve 情境：host A（故障注入）＋可選 host B（正常）；每個 label 一個新 session
  const views = {}
  for (const [host, h] of Object.entries(hosts)) {
    views[host] = {}
    for (const [label, id] of Object.entries(sessions[host] ?? {})) {
      const ex = exportSession(h.project, h.env, id)
      if (ex) fs.writeFileSync(path.join(base, tag, `export-${host}-${label}.json`), JSON.stringify(ex, null, 1))
      const v = commonSessionChecks(h.project, id, ex, failures, `${host}:${label}: `)
      const executed = v.g.filter((x) => x.hook === "after" && x.tool === "task" && x.executed)
      // 子 session（subagent）的紀錄：查詢的 after 列與 invalid 列都在子 session 的 jsonl
      const childRows = executed.flatMap((e) => sessionLog(h.project, e.childSessionID))
      const childParts = executed.flatMap((e) => (ex ? toolParts(exportSession(h.project, h.env, e.childSessionID) ?? {}, e.childSessionID) : []))
      views[host][label] = { ...v, id, ex, text: ex ? assistantText(ex, id) : "", executed, invalids: childRows.filter((x) => x.hook === "invalid"), queryA: childRows.filter((x) => x.hook === "after" && x.tool === Q), childParts }
    }
  }
  const initA = mcp.filter((m) => m.event === "initialize")
  const modelRows = jsonl(modelLog).filter((r) => Array.isArray(r.tools) && r.tools.includes("task"))
  // 該題的 subagent 請求（沒有 task 工具、委派 prompt 含 [DB]）有沒有看到 oracleMCP_ 工具：主 agent 請求的 userText 定位題號，其後的 subagent 請求屬於該題
  const allRows = jsonl(modelLog).filter((r) => Array.isArray(r.tools))
  const sawOracle = (label) => {
    const out = []
    let inLabel = false
    for (const r of allRows) {
      if (r.tools.includes("task")) { inLabel = (r.userText ?? "").includes(`${label} 題`); continue }
      if (inLabel && /\[DB\]/.test(r.userText ?? "")) out.push(r.tools.some((t) => t.startsWith("oracleMCP_")))
    }
    return out
  }
  const A = views.A ?? {}
  switch (name) {
    case "vanish-auto":
    case "vanish-observe": {
      const auto = name === "vanish-auto"
      assertOk(A.A1 && A.A1.executed.length === 1, "A1 executed one task", failures)
      if (A.A1) assertCompleted(project, A.A1.executed, failures, "A1: ")
      assertOk(mcp.some((m) => m.fault === "vanish"), "mock MCP injected the vanish fault once", failures)
      assertOk(diag.some((d) => d.kind === "event" && d.type === "mcp.tools.changed") && diag.some((d) => d.kind === "snapshot" && d.reason === "tools-changed" && d.runtimeStatus === "connected") && diag.some((d) => /marked suspect/.test(d.note ?? "")), "guard saw the tools.changed event while connected and marked the catalog suspect", failures)
      // A2 的 subagent 第一個請求看不到工具；auto on 時重掛在同一題內完成，後續請求可能已看得到（劇本仍回報 DOWN、不重試）
      assertOk(A.A2 && sawOracle("A2").length >= 1 && sawOracle("A2")[0] === false, "A2 (new session, same host): the subagent saw no oracleMCP_ tools on its first request; got " + JSON.stringify(sawOracle("A2")), failures)
      assertOk(A.A2 && A.A2.invalids.length === 1 && A.A2.invalids[0].attempted === Q && A.A2.invalids[0].seenBefore === true && A.A2.invalids[0].allowedByAgent !== false && /catalog loss/.test(A.A2.invalids[0].note), "A2: the remembered query call became invalid = host-side catalog loss; got " + JSON.stringify(A.A2?.invalids), failures)
      assertOk(A.A2 && A.A2.executed.length === 1 && A.A2.executed[0].blockedReason === "ORACLE_MCP_DOWN" && A.A2.queryA.length === 0 && /ORACLE_MCP_DOWN/.test(A.A2.text), "A2: subagent reported ORACLE_MCP_DOWN, the main agent did not redispatch; got " + (A.A2?.text ?? "").slice(0, 160), failures)
      const cand = recoveries.find((r) => r.faultReason === "catalog-lost")
      assertOk(cand && cand.evidence?.attempted === Q, "recovery candidate carries the evidence; got " + JSON.stringify(recoveries.map((r) => [r.faultReason, r.decision])), failures)
      if (auto) {
        assertEq(recoveries.filter((r) => r.decision !== "merged").map((r) => r.decision), ["remount-start", "remount-ok", "verified-by-call"], "recovery decisions (exactly one remount, verified by A3's first call)", failures)
        assertOk(initA.length === 2 && new Set(initA.map((m) => m.pid)).size === 2, "mock MCP mounted twice on host A (new process after remount); got " + JSON.stringify(initA.map((m) => m.pid)), failures)
        assertOk(A.A3 && sawOracle("A3").length >= 1 && sawOracle("A3").every((x) => x === true), "A3 saw oracleMCP_ tools again", failures)
        if (A.A3) { assertCompleted(project, A.A3.executed, failures, "A3: ") }
        assertOk(A.A3 && A.A3.queryA.length >= 1 && A.A3.queryA[0].recoveryNotice === true && A.A3.queryA[0].recoveryGen === 1, "A3: the first query reply carries the recovery notice; got " + JSON.stringify(A.A3?.queryA), failures)
        const a3q = A.A3 ? A.A3.childParts.find((p) => p.tool === Q) : null
        assertOk(a3q && /恢復世代 1/.test(a3q.state?.output ?? "") && /SELECT 1 AS OK FROM DUAL/.test(a3q.state?.output ?? "") && !/connect/.test(a3q.state?.output ?? ""), "A3: the notice is in the tool output the subagent reads (verify with SELECT 1 AS OK FROM DUAL, no connect)", failures)
        // host B：全程正常、從未重掛
        const B = views.B ?? {}
        const initB = jsonl(hosts.B?.mcpLog ?? "").filter((m) => m.event === "initialize")
        assertOk(B.B1 && B.B2 && B.B1.executed.length === 1 && B.B2.executed.length === 1, "host B ran both turns", failures)
        if (B.B1 && B.B2) { assertCompleted(hosts.B.project, [...B.B1.executed, ...B.B2.executed], failures, "B: ") }
        assertEq(initB.length, 1, "host B mounted its MCP exactly once (never remounted)", failures)
        assertEq(diagOf(hosts.B?.project ?? "").filter((d) => d.kind === "recovery").length, 0, "host B has no recovery rows", failures)
      } else {
        assertOk(recoveries.length >= 1 && recoveries.every((r) => r.decision === "would-remount"), "auto off: only would-remount rows (one per probe), never a remount; got " + JSON.stringify(recoveries.map((r) => r.decision)), failures)
        assertEq(initA.length, 1, "mock MCP mounted once (no remount)", failures)
        assertOk(A.A3 && sawOracle("A3").length >= 1 && sawOracle("A3").every((x) => x === false) && /ORACLE_MCP_DOWN/.test(A.A3.text) && A.A3.taskParts.length === 1, "A3 still sees no tools and reports DOWN without redispatching", failures)
      }
      break
    }
    case "transport-close": {
      assertOk(A.A1 && A.A1.executed.length === 1, "A1 executed one task", failures)
      if (A.A1) assertCompleted(project, A.A1.executed, failures, "A1: ")
      assertOk(mcp.some((m) => m.fault === "exit"), "mock MCP exited once", failures)
      assertOk(diag.some((d) => d.kind === "snapshot" && d.runtimeStatus === "failed" && /Connection closed/.test(d.statusError ?? "")), "guard snapshot saw status failed: Connection closed; got " + JSON.stringify(diag.filter((d) => d.kind === "snapshot").map((d) => [d.reason, d.runtimeStatus, d.statusError])), failures)
      const decisions = recoveries.filter((r) => r.decision !== "merged").map((r) => [r.faultReason, r.decision])
      assertEq(decisions, [["transport-closed", "remount-start"], ["transport-closed", "remount-ok"], [undefined, "verified-by-call"]], "recovery decisions", failures)
      assertOk(initA.length === 2 && new Set(initA.map((m) => m.pid)).size === 2, "mock MCP mounted twice (new process after remount)", failures)
      assertOk(A.A2 && sawOracle("A2").every((x) => x === true) && A.A2.invalids.length === 0, "A2 (new session) saw the tools without any invalid call", failures)
      if (A.A2) assertCompleted(project, A.A2.executed, failures, "A2: ")
      assertOk(A.A2 && A.A2.queryA.length >= 1 && A.A2.queryA[0].recoveryNotice === true, "A2: the first query reply carries the recovery notice", failures)
      break
    }
  }
  const summary = { scenario: name, iteration, ms: result.ms, exit: result.status, sessions, mcpSeq, recoveries: recoveries.map((r) => r.decision), failures }
  console.log(JSON.stringify(summary))
  if (failures.length && !keep) console.log("--- stderr tail ---\n" + result.stderr.slice(-2000) + "\n--- diag ---\n" + diag.map((x) => JSON.stringify(x)).join("\n"))
  return failures.length === 0
}

const base = fs.mkdtempSync(path.join(os.tmpdir(), "guard-e2e-"))
console.log("workdir " + base + " opencode=" + OPENCODE)
let ok = true
for (const [name, sc] of Object.entries(SCENARIOS)) {
  if (only && only !== name) continue
  for (let i = 1; i <= repeat; i++) ok = (await runScenario(name, sc, base, i)) && ok
}
if (!keep) fs.rmSync(base, { recursive: true, force: true })
console.log(ok ? "E2E PASS" : "E2E FAIL")
process.exit(ok ? 0 : 1)

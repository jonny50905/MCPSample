// run-e2e.mjs — 用真 OpenCode（預設 PATH 上的 opencode；或 OPENCODE_BIN）＋假 oracleMCP＋假模型，
// 端到端驗證 ps-oracle-preflight-gate 在 opencode run（headless）與 opencode serve（同行程多輪）路徑的行為。只給維護沙箱用。
// 用法：node tests/oracle-gate/run-e2e.mjs [--repeat N] [--only <scenario>] [--keep]
//   scenario：task-first | connect-first | compliant | stubborn | nodb | observe | mcp-down | mcp-failed | connect-fail | empty-connect |
//             multi-turn | multi-turn-serve | compaction-serve | stale-connect-serve
//   mcp-down／mcp-failed：oracleMCP 停用／指令不存在（/mcp 狀態 disabled／failed）→ 會查 DB 的 task 一樣被擋，錯誤訊息走 ORACLE_MCP_DOWN 協定、零 SQL
//   connect-fail：假 oracleMCP 的 connect 一律失敗（isError），驗證閘門沒有「失敗幾次就放行」——三次 task 全擋、零 SQL、模型依第 0 步規則放棄 DB 委派
//   empty-connect：connect「成功」但回空 content → 閘門判未知（ok:"unknown"）不前進，三次 task 全擋、零 SQL
//   multi-turn：同一 session 兩個 turn（第二 turn 用 opencode run --session <id>＝新行程），驗證每 turn 都有 chat.message、turnId 不同、各自重做前置
//   multi-turn-serve：opencode serve 同一行程內對同一 session 連送兩題（HTTP API），驗證 READY 的 session 真的被第二則訊息重置
//   compaction-serve：同上，但兩題之間做一次 session.summarize（compaction）——插入的 user 訊息只有 compaction part、不觸發 chat.message
//   stale-connect-serve：第一題的 connect 還沒回（假 MCP 延遲 5 秒）就送第二題——第一題的 connect 回覆晚到：閘門標 stale、歸第一題、
//                        不替第二題完成前置；第二題自己 list→connect 才放行；export 裡該 connect 也屬第一題（parentID）
//   wrong-target：profile oracle.connectionName=HR_UAT、模型 connect(HR_DEV) → connect 在執行前被擋（ORACLE_CONNECTION_MISMATCH），假 MCP 沒收到 connect、零 SQL
//   not-configured：profile 是 FILL_ME → connect 在執行前被擋（ORACLE_CONNECTION_NOT_CONFIGURED）
//   reconnect-fail：list→connect（READY）後再 connect 一次但假 MCP 從第 2 次起 isError → 嘗試開始就作廢 READY，之後的 task 全擋、零 SQL
//   每個情境另驗：已執行的 DB task 列帶 reportStatus／childSessionID，且子 session 的交易紀錄裡有成功的 run_sql（可用的定義）
// 每個情境：建臨時專案（複製 .opencode＋AGENTS.md）、寫 opencode.json、跑 opencode run --agent ps-orchestrator、
//   讀閘門 jsonl、opencode export 取正式 transcript 交叉比對（task 件數、真實題目 id、每個 task 所屬題目）、斷言。
//   另驗 subagent 的 Oracle 允許清單：假模型記下每次請求可見的工具名，subagent 只能看到 oracleMCP_run_sql。
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
  "mcp-failed": { model: "task-first", mode: "enforce", mcp: true, mcpBroken: true },
  "connect-fail": { model: "connect-fail", mode: "enforce", mcp: true, connectFail: true },
  "empty-connect": { model: "connect-fail", mode: "enforce", mcp: true, emptyConnect: true },
  "multi-turn": { model: "task-first", mode: "enforce", mcp: true, turns: 2 },
  "multi-turn-serve": { model: "task-first", mode: "enforce", mcp: true, serve: 2 },
  "compaction-serve": { model: "task-first", mode: "enforce", mcp: true, serve: 2, summarize: true },
  "stale-connect-serve": { model: "stale-probe", mode: "enforce", mcp: true, serve: 2, overlap: true, connectDelayFirst: 5000 },
  "wrong-target": { model: "connect-fail", mode: "enforce", mcp: true, profileConnection: "HR_UAT" },
  "not-configured": { model: "connect-fail", mode: "enforce", mcp: true, profileConnection: "FILL_ME" },
  "reconnect-fail": { model: "reconnect-probe", mode: "enforce", mcp: true, connectFailFrom: 2 },
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
  // profile 的 oracle.connectionName：閘門在 connect 執行前比對它；假 MCP 的清單是 HR_DEV／HR_UAT，模型劇本挑清單第一個（HR_DEV）
  const profilePath = path.join(project, ".opencode", "peoplesoft", "customization-profile.yaml")
  const profile = fs.readFileSync(profilePath, "utf8")
  if (!/^\s*connectionName:/m.test(profile)) throw new Error("profile has no oracle.connectionName")
  fs.writeFileSync(profilePath, profile.replace(/^(\s*connectionName:)\s*\S+/m, `$1 ${sc.profileConnection ?? "HR_DEV"}`))
  const mcpLog = path.join(base, name, "mcp.jsonl")
  const mcpEnv = { MOCK_ORACLE_LOG: mcpLog }
  if (sc.connectFail) mcpEnv.MOCK_ORACLE_CONNECT_FAIL = "1"
  if (sc.emptyConnect) mcpEnv.MOCK_ORACLE_EMPTY_CONNECT = "1"
  if (sc.connectDelayFirst) mcpEnv.MOCK_ORACLE_CONNECT_DELAY_FIRST_MS = String(sc.connectDelayFirst)
  if (sc.connectFailFrom) mcpEnv.MOCK_ORACLE_CONNECT_FAIL_FROM = String(sc.connectFailFrom)
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

function jsonl(file) {
  if (!fs.existsSync(file)) return []
  return fs.readFileSync(file, "utf8").split("\n").filter((l) => l.trim()).map((l) => { try { return JSON.parse(l) } catch { return { raw: l } } })
}

// opencode serve：同一行程內對同一 session 送多題（真正的互動式多 turn）
// overlap＝第一題的 connect 一開始（假 MCP 在呼叫開始就寫 log）就送第二題，不等第一題結束
async function runServe(project, env, turns, tag, base, summarize, overlap, mcpLog) {
  const port = MODEL_PORT + 100
  const started = Date.now()
  const server = spawn(OPENCODE, ["serve", "--port", String(port), "--hostname", "127.0.0.1", "--print-logs", "--log-level", "INFO"], { cwd: project, env, stdio: ["ignore", "pipe", "pipe"] })
  let out = "", err = ""
  server.stdout.on("data", (d) => (out += d))
  server.stderr.on("data", (d) => (err += d))
  const url = (p) => `http://127.0.0.1:${port}${p}?directory=${encodeURIComponent(project)}`
  const wait = (ms) => new Promise((r) => setTimeout(r, ms))
  let sessionID = ""
  let status = 0
  const post = async (t) => {
    const text = t === 1 ? "兵役狀態欄位有哪些選項？" : `第 ${t} 題：免役的條件是什麼？`
    const r = await fetch(url(`/session/${sessionID}/message`), { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ agent: "ps-orchestrator", model: { providerID: "mock", modelID: "scripted" }, parts: [{ type: "text", text }] }) })
    const body = await r.text()
    out += `[harness] turn ${t} HTTP ${r.status} t+${Date.now() - started}ms\n`
    fs.writeFileSync(path.join(base, tag, `serve-turn${t}.response.json`), body)
    if (!r.ok) { status = 1; err += `\n--- turn ${t} HTTP ${r.status} ---\n${body.slice(0, 2000)}` }
  }
  try {
    let ready = false
    let lastErr = ""
    for (let i = 0; i < 100 && !ready; i++) {
      await wait(300)
      const t0 = Date.now()
      try { const r = await fetch(url("/session"), { signal: AbortSignal.timeout(20000) }); ready = r.ok; lastErr = "HTTP " + r.status } catch (e) { lastErr = String(e?.cause?.code ?? e?.message ?? e) }
      out += `[harness] ready-probe ${i} ${lastErr} ${Date.now() - t0}ms t+${Date.now() - started}ms\n`
    }
    if (!ready) throw new Error("serve not ready; last: " + lastErr + "; stderr tail: " + err.slice(-800))
    out += `[harness] ready after ${Date.now() - started}ms\n`
    const created = await fetch(url("/session"), { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ title: "gate-e2e-" + tag }) })
    const cj = await created.json()
    sessionID = cj.id
    if (overlap) {
      const p1 = post(1)
      const t0 = Date.now()
      while (Date.now() - t0 < 20000 && !jsonl(mcpLog).some((m) => m.tool === "connect")) await wait(100)
      out += `[harness] turn-1 connect in flight after ${Date.now() - t0}ms; sending turn 2 now\n`
      const p2 = post(2)
      await Promise.all([p1, p2])
    } else {
      for (let t = 1; t <= turns; t++) {
        await post(t)
        if (summarize && t < turns) {
          // 兩題之間做一次 compaction（session.summarize）：會插入一則只有 compaction part 的 user 訊息，不觸發 chat.message
          const sr = await fetch(url(`/session/${sessionID}/summarize`), { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ providerID: "mock", modelID: "scripted" }) })
          const sb = await sr.text()
          out += `[harness] summarize HTTP ${sr.status} t+${Date.now() - started}ms ${sb.slice(0, 120)}\n`
          if (!sr.ok) { status = 1; err += `\n--- summarize HTTP ${sr.status} ---\n${sb.slice(0, 2000)}` }
        }
      }
    }
  } catch (e) {
    status = 1
    err += "\n--- harness error ---\n" + String(e)
  } finally {
    server.kill()
    await wait(500)
  }
  fs.writeFileSync(path.join(base, tag, "serve.stdout.txt"), out)
  fs.writeFileSync(path.join(base, tag, "serve.stderr.txt"), err)
  return { sessionID, result: { stdout: out, stderr: err, status, signal: null, ms: Date.now() - started } }
}

function runOpencode(project, env, args) {
  const started = Date.now()
  const r = spawnSync(OPENCODE, args, { cwd: project, env, encoding: "utf8", timeout: 180000, maxBuffer: 64 * 1024 * 1024 })
  return { stdout: r.stdout ?? "", stderr: r.stderr ?? "", status: r.status, signal: r.signal, ms: Date.now() - started }
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

// 每個 tool part 所屬的題目：含它的 assistant 訊息的 parentID（＝觸發它的 user 訊息 id）
function partParents(exported, sessionID) {
  const map = new Map()
  for (const m of exported?.messages ?? []) {
    const info = m.info ?? m
    if (info.role !== "assistant" || (info.sessionID && info.sessionID !== sessionID)) continue
    for (const p of m.parts ?? []) if (p.type === "tool" && p.callID && info.parentID) map.set(p.callID, info.parentID)
  }
  return map
}

// 真實題目＝role=user 且至少有一個非 synthetic 的 text／file／agent／subtask part（compaction／續行／背景回灌不算）
const REAL_PART_TYPES = ["text", "file", "agent", "subtask"]
function realPrompt(m) { return (m.parts ?? []).some((p) => REAL_PART_TYPES.includes(p.type) && p.synthetic !== true) }
function userMessages(exported, sessionID) {
  return (exported?.messages ?? []).filter((m) => (m.info ?? m).role === "user" && ((m.info ?? m).sessionID ?? sessionID) === sessionID)
}
function assistantText(exported, sessionID) {
  return (exported?.messages ?? []).filter((m) => (m.info ?? m).role === "assistant" && ((m.info ?? m).sessionID ?? sessionID) === sessionID)
    .flatMap((m) => (m.parts ?? []).filter((p) => p.type === "text").map((p) => p.text ?? "")).join("\n")
}

// 可用的定義：已執行的 DB task 列 reportStatus=COMPLETE、reportValid、childSessionID 指向子 session，且子 session 的 jsonl 有成功的 run_sql
function childSqlOk(project, child) {
  if (!child) return 0
  return jsonl(path.join(project, "auto-loop-logs", "ps-oracle-gate", child + ".jsonl")).filter((g) => g.hook === "after" && g.tool === "oracleMCP_run_sql" && g.ok === true).length
}
function assertCompleted(project, executed, failures) {
  assertOk(executed.length >= 1 && executed.every((e) => e.reportValid === true && e.reportStatus === "COMPLETE" && e.blockedReason === "NOT_APPLICABLE" && typeof e.childSessionID === "string" && e.childSessionID.startsWith("ses_") && e.taskState === "completed"),
    "executed DB task rows carry a parsed COMPLETE report and child session id; got " + JSON.stringify(executed.map((e) => [e.reportStatus, e.blockedReason, e.childSessionID, e.taskState])), failures)
  assertOk(executed.every((e) => childSqlOk(project, e.childSessionID) >= 1), "every completed DB task has a successful run_sql in its child session log", failures)
}

function assertEq(actual, expected, label, failures) {
  if (JSON.stringify(actual) !== JSON.stringify(expected)) failures.push(`${label}: expected ${JSON.stringify(expected)} got ${JSON.stringify(actual)}`)
}
function assertOk(cond, label, failures) { if (!cond) failures.push(label) }

// subagent 的 Oracle 允許清單：假模型記下每次請求可見的工具名；沒有 task 工具的請求＝subagent，Oracle 工具必須只有 run_sql；
// 主 agent（有 task）只能看到 list_connections＋connect
function assertToolLists(modelLog, failures) {
  const rows = jsonl(modelLog).filter((r) => Array.isArray(r.tools))
  const sub = rows.filter((r) => !r.tools.includes("task") && r.tools.some((t) => t.startsWith("oracleMCP_")))
  const oracle = (r) => r.tools.filter((t) => t.startsWith("oracleMCP_")).sort()
  assertOk(sub.length >= 1 && sub.every((r) => JSON.stringify(oracle(r)) === JSON.stringify(["oracleMCP_run_sql"])), "subagent sees only oracleMCP_run_sql (allowlist); got " + JSON.stringify(sub.map(oracle)), failures)
  const primary = rows.filter((r) => r.tools.includes("task"))
  assertOk(primary.length >= 1 && primary.every((r) => JSON.stringify(oracle(r)) === JSON.stringify(["oracleMCP_connect", "oracleMCP_list_connections"])), "primary agent sees list_connections + connect only; got " + JSON.stringify(primary.map(oracle)), failures)
}

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
    if (sc.serve) {
      const sv = await runServe(project, env, sc.serve, tag, base, sc.summarize === true, sc.overlap === true, mcpLog)
      result = sv.result
      sessionID = sv.sessionID
    } else {
      result = runOpencode(project, env, ["run", "--print-logs", "--log-level", "INFO", "--agent", "ps-orchestrator", "--model", "mock/scripted", "--format", "json", "--title", "gate-e2e-" + tag, "兵役狀態欄位有哪些選項？"])
      fs.writeFileSync(path.join(base, tag, "run.stdout.txt"), result.stdout)
      fs.writeFileSync(path.join(base, tag, "run.stderr.txt"), result.stderr)
      const events = result.stdout.split("\n").filter((l) => l.trim().startsWith("{")).map((l) => { try { return JSON.parse(l) } catch { return null } }).filter(Boolean)
      sessionID = events.find((e) => e.sessionID)?.sessionID ?? ""
    }
    for (let t = 2; sessionID && !sc.serve && t <= (sc.turns ?? 1); t++) {
      const r2 = runOpencode(project, env, ["run", "--print-logs", "--log-level", "INFO", "--session", sessionID, "--agent", "ps-orchestrator", "--model", "mock/scripted", "--format", "json", `第 ${t} 題：免役的條件是什麼？`])
      fs.writeFileSync(path.join(base, tag, `run-turn${t}.stdout.txt`), r2.stdout)
      fs.writeFileSync(path.join(base, tag, `run-turn${t}.stderr.txt`), r2.stderr)
      if (r2.status !== 0) result = { ...result, status: r2.status, stderr: result.stderr + "\n--- turn " + t + " ---\n" + r2.stderr }
    }
    if (sessionID) {
      const ex = runOpencode(project, env, ["export", sessionID])
      try { exported = JSON.parse(ex.stdout) } catch { exported = null }
      if (exported) fs.writeFileSync(path.join(base, tag, "export.json"), JSON.stringify(exported, null, 1))
    }
  } finally {
    model.kill()
  }
  const gateFile = path.join(project, "auto-loop-logs", "ps-oracle-gate", sessionID + ".jsonl")
  const gate = sessionID ? jsonl(gateFile) : []
  const mcp = jsonl(mcpLog)
  const parts = exported ? toolParts(exported, sessionID) : []
  const parents = exported ? partParents(exported, sessionID) : new Map()
  const taskParts = parts.filter((p) => p.tool === "task")
  const failures = []
  assertOk(result.status === 0, `exit code ${result.status} signal ${result.signal}; stderr tail: ${result.stderr.slice(-600)}`, failures)
  assertOk(sessionID !== "", "no sessionID in --format json output", failures)
  assertOk(exported !== null, "export failed", failures)
  const before = gate.filter((g) => g.hook === "before" && g.tool === "task")
  const blocks = before.filter((g) => g.decision === "block")
  const allows = before.filter((g) => g.decision === "allow")
  const executed = gate.filter((g) => g.hook === "after" && g.tool === "task" && g.executed)
  const chats = gate.filter((g) => g.hook === "chat.message" && g.synthetic !== true)
  const users = exported ? userMessages(exported, sessionID) : []
  const realPrompts = users.filter(realPrompt)
  const stateSeq = gate.filter((g) => g.hook === "after" && /^oracleMCP_/.test(g.tool)).map((g) => `${g.tool.replace("oracleMCP_", "")}:${g.state}->${g.next}`)
  const mcpSeq = mcp.map((m) => m.tool)
  const runSqlBeforeConnect = mcp.some((m) => m.tool === "run_sql" && !m.connectedBefore)
  const stale = gate.filter((g) => g.stale === true)
  // P1 等價：閘門看到的 task 次數 ＝ 正式 transcript 的 task 工具件數；每一則真實題目都有同 id 的 chat.message
  assertEq(before.length, taskParts.length, "task before-hook count vs exported task parts", failures)
  if (exported) assertEq(chats.map((c) => c.turnId).sort(), realPrompts.map((m) => (m.info ?? m).id).sort(), "chat.message turnIds vs real prompt ids", failures)
  // 呼叫歸屬：閘門列的 turnId ＝ export 裡該 tool part 所屬 assistant 訊息的 parentID（before／after 都比；after 用入場快照）
  if (exported) {
    for (const b of before) if (parents.has(b.callID)) assertOk(parents.get(b.callID) === b.turnId, `before-hook attribution: task ${b.callID} gate=${b.turnId} export=${parents.get(b.callID)}`, failures)
    for (const e of executed) assertOk(parents.get(e.callID) === e.turnId, `after-hook attribution: task ${e.callID} gate=${e.turnId} export=${parents.get(e.callID)}`, failures)
    for (const g of gate.filter((x) => x.hook === "before" && /^oracleMCP_/.test(x.tool))) if (parents.has(g.callID)) assertOk(parents.get(g.callID) === g.turnId, `oracle call attribution: ${g.tool} ${g.callID} gate=${g.turnId} export=${parents.get(g.callID)}`, failures)
  }
  // 第 0 步提醒：每則真實題目在 export 裡多一個 synthetic text part（使用者文字保持原樣），模型的請求看得到它；chat.message 列 reminder=true
  if (exported) {
    for (const m of realPrompts) {
      const ps = m.parts ?? []
      assertOk(ps.some((p) => p.type === "text" && p.synthetic !== true) && ps.some((p) => p.type === "text" && p.synthetic === true && /oracleMCP_list_connections → oracleMCP_connect/.test(p.text ?? "") && /^prt_/.test(p.id ?? "")),
        "real user message keeps its own text and carries the synthetic step-0 reminder part; parts=" + JSON.stringify(ps.map((p) => [p.type, p.synthetic, (p.id ?? "").slice(0, 8)])), failures)
    }
  }
  const primaryRows = jsonl(modelLog).filter((r) => Array.isArray(r.tools) && r.tools.includes("task"))
  assertOk(primaryRows.length >= 1 && primaryRows.every((r) => /【Oracle 第 0 步（執行期閘門提醒）】[\s\S]*不查 DB 的部分照常作答。$/.test(r.userText ?? "")), "every primary-agent model request sees the reminder at the end of the last user message; got " + JSON.stringify(primaryRows.slice(0, 2).map((r) => (r.userText ?? "").slice(-80))), failures)
  assertOk(chats.length >= 1 && chats.every((c) => c.reminder === true), "chat.message rows record reminder=true", failures)
  // 不變量（無豁免；只有 observe 探測例外）：每個已執行的會查 DB 的 task 入場時必須 READY——oracleMCP 未掛載時也一樣（被擋，不放行）
  const earlyDb = executed.filter((e) => e.dbCapable === true && e.state !== "READY")
  if (name !== "observe") assertEq(earlyDb.length, 0, "DB task executed before READY", failures)
  assertOk(before.every((b) => typeof b.dbCapable === "boolean") && executed.every((e) => typeof e.dbCapable === "boolean"), "every task row carries dbCapable", failures)
  const errParts = taskParts.filter((p) => p.state?.status === "error")
  const okParts = taskParts.filter((p) => p.state?.status === "completed")
  switch (name) {
    case "task-first": {
      assertEq(blocks.map((b) => b.state), ["NEED_LIST"], "blocks", failures)
      assertEq(stateSeq, ["list_connections:NEED_LIST->NEED_CONNECT", "connect:NEED_CONNECT->READY"], "state sequence", failures)
      assertEq(allows.length, 1, "allowed task", failures); assertEq(executed.length, 1, "executed task", failures)
      assertOk(errParts.length === 1 && /PS_ORACLE_PREFLIGHT_REQUIRED/.test(errParts[0].state.error), "first task part is error with gate code; got " + JSON.stringify(errParts.map((p) => p.state.error?.slice(0, 120))), failures)
      assertEq(okParts.length, 1, "completed task parts", failures)
      assertEq(mcpSeq, ["list_connections", "connect", "run_sql"], "mcp call order", failures)
      assertOk(!runSqlBeforeConnect, "run_sql before connect", failures)
      assertOk(executed[0]?.admitted === "allow" && executed[0]?.turnId === chats[0]?.turnId && executed[0]?.callID && executed[0]?.attribution === "current", "executed row carries admission snapshot (turnId＝chat.message id, callID, attribution=current)", failures)
      assertOk(gate.filter((g) => g.hook === "after" && /^oracleMCP_/.test(g.tool)).every((g) => g.attribution === "current" && g.ok === true), "list/connect after rows paired to their before (attribution=current, ok=true)", failures)
      assertToolLists(modelLog, failures)
      assertCompleted(project, executed, failures)
      const cb = gate.find((g) => g.hook === "before" && g.tool === "oracleMCP_connect")
      assertOk(cb && cb.decision === "allow" && cb.gen === 1 && cb.profileConnection === "HR_DEV" && cb.connection === "HR_DEV", "connect before row: validated against profile (decision=allow, gen=1); got " + JSON.stringify(cb), failures)
      break
    }
    case "connect-first": {
      assertEq(blocks.map((b) => b.state), ["NEED_LIST"], "blocks", failures)
      assertEq(stateSeq, ["connect:NEED_LIST->NEED_LIST", "list_connections:NEED_LIST->NEED_CONNECT", "connect:NEED_CONNECT->READY"], "state sequence", failures)
      assertEq(executed.length, 1, "executed task", failures)
      assertEq(mcpSeq, ["connect", "list_connections", "connect", "run_sql"], "mcp call order", failures)
      break
    }
    case "compliant": {
      assertEq(blocks.length, 0, "blocks", failures)
      assertEq(stateSeq, ["list_connections:NEED_LIST->NEED_CONNECT", "connect:NEED_CONNECT->READY"], "state sequence", failures)
      assertEq(executed.length, 1, "executed task", failures)
      assertEq(mcpSeq, ["list_connections", "connect", "run_sql"], "mcp call order", failures)
      assertToolLists(modelLog, failures)
      assertCompleted(project, executed, failures)
      break
    }
    case "stubborn": {
      assertEq(blocks.length, 4, "blocks", failures); assertEq(executed.length, 0, "executed task", failures)
      assertEq(mcpSeq, [], "no mcp calls", failures); assertEq(errParts.length, 4, "error task parts", failures)
      assertOk(blocks[3]?.blocked === 4 && blocks.every((b) => b.state === "NEED_LIST"), "block counter", failures)
      break
    }
    case "nodb": {
      assertEq(blocks.length, 0, "blocks", failures)
      assertOk(allows.length === 1 && allows[0].target === "ps-peoplecode-flow" && allows[0].basis === "run_sql:disabled" && allows[0].dbCapable === false, "nodb target allowed by capability", failures)
      assertEq(mcpSeq, [], "no mcp calls", failures); assertEq(okParts.length, 1, "completed task parts", failures)
      break
    }
    case "observe": {
      const would = before.filter((g) => g.decision === "observe-would-block")
      assertEq(would.length, 1, "observe-would-block", failures); assertEq(blocks.length, 0, "blocks", failures)
      assertOk(executed.length >= 1 && executed[0].notConnected === true && executed[0].admitted === "observe-would-block" && executed[0].reportStatus === "BLOCKED" && executed[0].blockedReason === "NOT_CONNECTED", "task executed before preflight and subagent reported NOT_CONNECTED (probe evidence; parsed report)", failures)
      assertOk(childSqlOk(project, executed[0]?.childSessionID) === 0, "no successful run_sql in the child session (it ran before connect)", failures)
      assertOk(runSqlBeforeConnect, "run_sql happened before connect (observe lets the wrong order through)", failures)
      break
    }
    case "mcp-down":
    case "mcp-failed": {
      const rx = name === "mcp-down" ? /^oracleMCP not mounted \(mcp-status:(disabled|absent)\)/ : /^oracleMCP not mounted \(mcp-status:failed\)/
      assertEq(blocks.length, 1, "one block", failures); assertEq(allows.length, 0, "no allowed task", failures); assertEq(executed.length, 0, "no executed task", failures)
      assertOk(blocks[0] && rx.test(blocks[0].note ?? ""), "block note names the mcp status; got " + JSON.stringify(blocks.map((b) => b.note)), failures)
      assertEq(mcpSeq, [], "no mcp calls", failures)
      assertOk(errParts.length === 1 && /ORACLE_MCP_DOWN/.test(errParts[0].state.error ?? "") && /oracleMCP 未掛載/.test(errParts[0].state.error ?? ""), "task part error carries the ORACLE_MCP_DOWN protocol", failures)
      assertOk(exported && /ORACLE_MCP_DOWN/.test(assistantText(exported, sessionID)), "model reported ORACLE_MCP_DOWN instead of dispatching", failures)
      break
    }
    case "connect-fail": {
      assertEq(blocks.map((b) => b.state), ["NEED_LIST", "NEED_CONNECT", "NEED_CONNECT"], "blocks", failures)
      assertEq(blocks.map((b) => b.blocked), [1, 2, 3], "block counter", failures)
      assertEq(allows.length, 0, "no allowed task", failures); assertEq(executed.length, 0, "no executed task", failures)
      assertEq(stateSeq, ["list_connections:NEED_LIST->NEED_CONNECT"], "state sequence (connect after never fires on isError)", failures)
      assertEq(mcpSeq, ["list_connections", "connect", "connect"], "mcp call order (no run_sql)", failures)
      assertEq(taskParts.map((p) => p.state?.status), ["error", "error", "error"], "task parts", failures)
      assertOk(errParts.length === 3 && /已被擋 3 次/.test(errParts[2].state.error ?? ""), "third block message carries the give-up hint", failures)
      assertOk(exported && /DB 連線建立失敗/.test(assistantText(exported, sessionID)), "model answered with 'DB 連線建立失敗' instead of dispatching", failures)
      break
    }
    case "empty-connect": {
      assertEq(blocks.map((b) => b.state), ["NEED_LIST", "NEED_CONNECT", "NEED_CONNECT"], "blocks", failures)
      assertEq(allows.length, 0, "no allowed task", failures); assertEq(executed.length, 0, "no executed task", failures)
      assertEq(stateSeq, ["list_connections:NEED_LIST->NEED_CONNECT", "connect:NEED_CONNECT->NEED_CONNECT", "connect:NEED_CONNECT->NEED_CONNECT"], "state sequence (empty connect output never advances)", failures)
      const conns = gate.filter((g) => g.hook === "after" && g.tool === "oracleMCP_connect")
      assertOk(conns.length === 2 && conns.every((c) => c.ok === "unknown" && /empty tool output/.test(c.note ?? "")), "connect after rows are ok:unknown; got " + JSON.stringify(conns.map((c) => [c.ok, c.note])), failures)
      assertEq(mcpSeq, ["list_connections", "connect", "connect"], "mcp call order (no run_sql)", failures)
      assertOk(exported && /DB 連線建立失敗/.test(assistantText(exported, sessionID)), "model gave up DB dispatch", failures)
      break
    }
    case "multi-turn":
    case "multi-turn-serve":
    case "compaction-serve": {
      const ids = chats.map((c) => c.turnId)
      assertOk(ids.length === 2 && ids[0] && ids[1] && ids[0] !== ids[1], "two chat.message rows with distinct turnId; got " + JSON.stringify(ids), failures)
      assertEq(realPrompts.length, 2, "exported real user prompts", failures)
      assertEq(blocks.map((b) => `${ids.indexOf(b.turnId) + 1}:${b.state}`), ["1:NEED_LIST", "2:NEED_LIST"], "one block per turn, both from NEED_LIST", failures)
      assertEq(executed.map((e) => `${ids.indexOf(e.turnId) + 1}:${e.state}`), ["1:READY", "2:READY"], "one executed DB task per turn, both READY", failures)
      if (name !== "multi-turn") {
        assertOk(chats[1]?.state === "READY" && chats[1]?.next === "NEED_LIST" && chats[1]?.turn === 2, "second chat.message resets a READY session in the same process; got " + JSON.stringify(chats[1]), failures)
      }
      if (name === "compaction-serve") {
        const compactionMsgs = users.filter((m) => (m.parts ?? []).some((p) => p.type === "compaction"))
        assertOk(compactionMsgs.length === 1 && !compactionMsgs.some(realPrompt), "one compaction user message without real prompt parts; users=" + users.length, failures)
        assertEq(users.length, 3, "user messages in export (2 real + 1 compaction)", failures)
      }
      assertEq(stateSeq, ["list_connections:NEED_LIST->NEED_CONNECT", "connect:NEED_CONNECT->READY", "list_connections:NEED_LIST->NEED_CONNECT", "connect:NEED_CONNECT->READY"], "state sequence per turn", failures)
      assertEq(mcpSeq, ["list_connections", "connect", "run_sql", "list_connections", "connect", "run_sql"], "mcp call order", failures)
      assertEq(taskParts.map((p) => p.state?.status), ["error", "completed", "error", "completed"], "task parts across turns", failures)
      assertEq(stale.length, 0, "no stale replies in sequential turns", failures)
      assertCompleted(project, executed, failures)
      break
    }
    case "stale-connect-serve": {
      const ids = chats.map((c) => c.turnId)
      assertOk(ids.length === 2 && ids[0] && ids[1] && ids[0] !== ids[1], "two chat.message rows with distinct turnId; got " + JSON.stringify(ids), failures)
      assertEq(realPrompts.length, 2, "exported real user prompts", failures)
      const c1 = gate.find((g) => g.hook === "after" && g.tool === "oracleMCP_connect" && g.attribution === "stale")
      assertOk(c1 && c1.turnId === ids[0] && c1.replyTurnId === ids[1] && c1.ok === true && c1.next !== "READY" && /stale reply/.test(c1.note ?? ""), "turn-1 connect reply arrives after turn 2 started: attributed to turn 1, stale, not counted; got " + JSON.stringify(c1), failures)
      assertOk(c1 && parents.get(c1.callID) === ids[0], "stale connect part belongs to turn 1 in the export (parentID); got " + JSON.stringify(c1 && parents.get(c1.callID)), failures)
      assertOk(chats[1]?.state === "NEED_CONNECT" && chats[1]?.next === "NEED_LIST", "second message arrived while turn 1 was mid-preflight (NEED_CONNECT→NEED_LIST); got " + JSON.stringify(chats[1]), failures)
      assertEq(stateSeq, ["list_connections:NEED_LIST->NEED_CONNECT", "connect:NEED_LIST->NEED_LIST", "list_connections:NEED_LIST->NEED_CONNECT", "connect:NEED_CONNECT->READY"], "state sequence", failures)
      assertEq(blocks.map((b) => `${ids.indexOf(b.turnId) + 1}:${b.state}`), ["2:NEED_CONNECT"], "turn-2 task blocked until turn 2 connects itself", failures)
      assertEq(executed.map((e) => `${ids.indexOf(e.turnId) + 1}:${e.state}`), ["2:READY"], "one executed DB task, in turn 2, READY", failures)
      assertEq(mcpSeq, ["list_connections", "connect", "list_connections", "connect", "run_sql"], "mcp call order", failures)
      assertEq(taskParts.map((p) => p.state?.status), ["error", "completed"], "task parts", failures)
      assertCompleted(project, executed, failures)
      break
    }
    case "wrong-target":
    case "not-configured": {
      const code = name === "wrong-target" ? "ORACLE_CONNECTION_MISMATCH" : "ORACLE_CONNECTION_NOT_CONFIGURED"
      const cbs = gate.filter((g) => g.hook === "before" && g.tool === "oracleMCP_connect")
      assertOk(cbs.length >= 2 && cbs.every((g) => g.decision === "block" && g.note === code), `connect blocked before execution (${code}); got ` + JSON.stringify(cbs.map((g) => [g.decision, g.note, g.connection, g.profileConnection])), failures)
      if (name === "wrong-target") assertOk(cbs.every((g) => g.connection === "HR_DEV" && g.profileConnection === "HR_UAT"), "mismatch rows name both sides", failures)
      assertEq(mcpSeq, ["list_connections"], "mock MCP never received connect", failures)
      assertEq(blocks.map((b) => b.state), ["NEED_LIST", "NEED_CONNECT", "NEED_CONNECT"], "task blocks", failures)
      assertEq(allows.length, 0, "no allowed task", failures); assertEq(executed.length, 0, "no executed task", failures)
      assertEq(gate.filter((g) => g.hook === "after" && g.tool === "oracleMCP_connect").length, 0, "no connect after rows (tool never ran)", failures)
      const connParts = parts.filter((p) => p.tool === "oracleMCP_connect")
      assertOk(connParts.length >= 2 && connParts.every((p) => p.state?.status === "error" && new RegExp(code).test(p.state?.error ?? "")), "connect tool parts are errors carrying the code; got " + JSON.stringify(connParts.map((p) => [p.state?.status, (p.state?.error ?? "").slice(0, 60)])), failures)
      assertOk(exported && /Oracle 連線未設定/.test(assistantText(exported, sessionID)), "model reported the configuration error instead of guessing a connection", failures)
      break
    }
    case "reconnect-fail": {
      assertEq(stateSeq, ["list_connections:NEED_LIST->NEED_CONNECT", "connect:NEED_CONNECT->READY"], "only the first connect ever produced an after row", failures)
      const cbs = gate.filter((g) => g.hook === "before" && g.tool === "oracleMCP_connect")
      assertOk(cbs.length === 4 && cbs[0].state === "NEED_CONNECT" && cbs[1].state === "READY" && cbs[1].next === "NEED_CONNECT" && /invalidates READY/.test(cbs[1].note ?? "") && cbs.map((g) => g.gen).join(",") === "1,2,3,4", "second connect attempt invalidated READY at attempt start; got " + JSON.stringify(cbs.map((g) => [g.state, g.next, g.gen, g.note])), failures)
      assertEq(blocks.map((b) => b.state), ["NEED_CONNECT", "NEED_CONNECT", "NEED_CONNECT"], "all tasks blocked after the failed reconnect", failures)
      assertEq(allows.length, 0, "no allowed task", failures); assertEq(executed.length, 0, "no executed task", failures)
      assertEq(mcpSeq, ["list_connections", "connect", "connect", "connect", "connect"], "mcp call order (no run_sql)", failures)
      assertOk(exported && /DB 連線建立失敗/.test(assistantText(exported, sessionID)), "model gave up DB dispatch", failures)
      break
    }
  }
  const summary = { scenario: name, iteration, ms: result.ms, exit: result.status, sessionID, turns: chats.length, realPrompts: realPrompts.length, blocks: blocks.length, allows: allows.length, executed: executed.length, earlyDb: earlyDb.length, stale: stale.length, stateSeq, mcpSeq, taskParts: taskParts.map((p) => p.state?.status), failures }
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

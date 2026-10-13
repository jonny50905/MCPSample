// 真 OpenCode + localhost 劇本模型：驗 Spec 文件流程（ps-sdoc -Cli opencode）四個外環 agent 的啟動與工具權限。
// 外環的叫法：opencode run --agent <agent> --model <model.yaml 的值> "<jobId>/<attemptId>"。不驗模型理解或企業功能；
// 只用合成檔，不連 MCP。OPENCODE_BIN=<exe> node tests/runtime-guard/run-sdoc-smoke.mjs
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import http from 'node:http'
import assert from 'node:assert/strict'
import { spawn, spawnSync } from 'node:child_process'
import { fileURLToPath } from 'node:url'

const self = fileURLToPath(import.meta.url)
if (process.argv[2] === '--model') {
  const plan = JSON.parse(fs.readFileSync(process.argv[4], 'utf8'))
  let count = 0
  http.createServer((req, res) => {
    let raw = ''
    req.on('data', d => raw += d)
    req.on('end', () => {
      const body = JSON.parse(raw || '{}')
      const names = (body.tools || []).map(t => t.function.name)
      let next = { text: '已寫工單指定產物' }
      if (names.length) {
        const calls = (body.messages || []).filter(m => m.role === 'assistant').flatMap(m => m.tool_calls || [])
        next = plan.steps[calls.length] || next
        fs.appendFileSync(process.argv[4] + '.log', JSON.stringify({ names, next, claudeMd: raw.includes('SDOC-SMOKE-CLAUDE-MD-MARKER') }) + '\n')
      }
      const id = 'sdoc-smoke-' + ++count
      const delta = next.text !== undefined ? { role: 'assistant', content: next.text } : {
        role: 'assistant', tool_calls: [{ index: 0, id, type: 'function', function: { name: next.name, arguments: JSON.stringify(next.args) } }],
      }
      if (body.stream === false) {
        res.writeHead(200, { 'Content-Type': 'application/json' })
        res.end(JSON.stringify({ id, choices: [{ index: 0, message: delta, finish_reason: next.text !== undefined ? 'stop' : 'tool_calls' }], usage: { prompt_tokens: 1, completion_tokens: 1 } }))
        return
      }
      res.writeHead(200, { 'Content-Type': 'text/event-stream' })
      for (const [d, finish] of [[delta, null], [{}, next.text !== undefined ? 'stop' : 'tool_calls']]) {
        res.write('data: ' + JSON.stringify({ id, object: 'chat.completion.chunk', created: 0, model: body.model, choices: [{ index: 0, delta: d, finish_reason: finish }] }) + '\n\n')
      }
      res.end('data: [DONE]\n\n')
    })
  }).listen(Number(process.argv[3]), '127.0.0.1', () => process.stdout.write('ready\n'))
} else {
  const repo = path.resolve(path.dirname(self), '../..')
  const base = fs.mkdtempSync(path.join(os.tmpdir(), 'sdoc-smoke-'))
  const project = path.join(base, 'project')
  const oc = process.env.OPENCODE_BIN || 'opencode'
  const port = Number(process.env.SDOC_SMOKE_PORT || 18191)
  fs.mkdirSync(project)
  for (const name of ['.opencode', 'scripts']) fs.cpSync(path.join(repo, name), path.join(project, name), { recursive: true, filter: p => !/[\\/]node_modules(?:[\\/]|$)/.test(p) })
  fs.copyFileSync(path.join(repo, 'AGENTS.md'), path.join(project, 'AGENTS.md'))
  const write = (p, text) => { fs.mkdirSync(path.dirname(p), { recursive: true }); fs.writeFileSync(p, text) }
  // 合成的 OpenCode 版工作目錄（*-opencode）；家目錄另放 Claude Code 的 ~/.claude/CLAUDE.md，外環以 OPENCODE_DISABLE_CLAUDE_CODE=1 啟動時不該被載入
  const job = 'clone-0000000000000000'
  const rt = path.join(project, '.ps-runtime/sdoc-opencode', job)
  const inbox = path.join(rt, 'inbox')
  const attempt = path.join(rt, 'attempts/a0004')
  const status = path.join(project, '.ps-private/sdoc-opencode', job, 'status.md')
  const decisions = path.join(project, '.ps-private/sdoc-opencode', job, 'decisions.md')
  const receipt = path.join(rt, 'receipts/r0001/x.json')
  const research = path.join(project, 'docs/ps-research/wiki/TW_DEMO_A.md')
  write(path.join(inbox, 'manifest.md'), '# 合成工單\n')
  write(path.join(inbox, 'input.json'), '{"synthetic":true}')
  write(path.join(inbox, 'docs/00-index.md'), '# 合成文件\n')
  write(path.join(attempt, 'manifest.md'), '# 合成工單\n')
  write(path.join(attempt, 'input.json'), '{"synthetic":true,"questions":"標準答案"}')
  write(status, '```mermaid\nstateDiagram-v2\n  [*] --> 010\n```\n')
  write(decisions, '# 人工裁決\n')
  write(receipt, '{"synthetic":true}')
  write(research, '# 合成研究\n')
  write(path.join(rt, 'work/r0001/md/04-workflow.md'), '# 合成工作中文件\n')
  const home = path.join(base, 'home')
  write(path.join(home, '.claude/CLAUDE.md'), 'SDOC-SMOKE-CLAUDE-MD-MARKER\n')
  const config = {
    model: 'mock/scripted', small_model: 'mock/scripted', autoupdate: false,
    provider: { mock: { npm: '@ai-sdk/openai-compatible', options: { baseURL: `http://127.0.0.1:${port}/v1`, apiKey: 'mock' }, models: { scripted: { name: 'scripted', tool_call: true, limit: { context: 128000, output: 8192 } } } } },
    permission: { doom_loop: 'deny', external_directory: 'allow' },
  }
  write(path.join(project, 'opencode.json'), JSON.stringify(config))
  const env = { ...process.env, HOME: home, USERPROFILE: home, PWD: project, OPENCODE_DISABLE_MODELS_FETCH: '1', OPENCODE_DISABLE_AUTOUPDATE: '1', OPENCODE_DISABLE_CLAUDE_CODE: '1' }
  for (const name of ['DATA', 'CACHE', 'CONFIG', 'STATE']) { env[`XDG_${name}_HOME`] = path.join(base, name); fs.mkdirSync(env[`XDG_${name}_HOME`]) }
  const run = args => spawnSync(oc, args, { cwd: project, env, encoding: 'utf8', timeout: 120000, maxBuffer: 32 * 1024 * 1024 })
  const read = p => ({ name: 'read', args: { filePath: p } })
  const writeStep = (p, content) => ({ name: 'write', args: { filePath: p, content } })
  async function scenario(agent, steps, want, check) {
    const planPath = path.join(base, agent + '.json')
    write(planPath, JSON.stringify({ steps }))
    const model = spawn(process.execPath, [self, '--model', String(port), planPath], { stdio: ['ignore', 'pipe', 'inherit'] })
    try {
      await new Promise((resolve, reject) => { model.stdout.once('data', resolve); model.once('error', reject); model.once('exit', c => reject(new Error('model exit ' + c))) })
      // 外環的形狀：--agent <名> --model <provider/model> --title "auto-<tag>" "<jobId>/<attemptId>"
      const r = run(['run', '--format', 'json', '--model', 'mock/scripted', '--agent', agent, '--title', 'auto-' + job + '-a0004', job + '/a0004'])
      write(path.join(base, agent + '.stdout'), r.stdout || '')
      write(path.join(base, agent + '.stderr'), r.stderr || '')
      assert.equal(r.status, 0, r.stderr)
      assert.ok(!/is a subagent, not a primary agent|Falling back to default agent/.test((r.stdout || '') + (r.stderr || '')), agent + '：--agent 沒有被退回預設 agent')
      const events = (r.stdout || '').split('\n').flatMap(l => { try { return [JSON.parse(l)] } catch { return [] } })
      const sid = events.find(e => e.sessionID)?.sessionID
      assert.ok(sid, 'missing sessionID')
      const ex = run(['export', sid])
      const exported = JSON.parse(ex.stdout)
      write(path.join(base, agent + '.export.json'), JSON.stringify(exported, null, 2))
      const asst = exported.messages.filter(m => m.info?.role === 'assistant')
      assert.ok(asst.length > 0 && asst.every(m => m.info.agent === agent && m.info.modelID === 'scripted' && m.info.providerID === 'mock'), agent + '：每則回覆都由這個 agent、--model 指定的模型產生')
      const parts = exported.messages.flatMap(m => m.parts || []).filter(p => p.type === 'tool')
      assert.deepEqual(parts.map(p => p.state.status), want, agent + '：每一步放行／擋下')
      const logs = fs.readFileSync(planPath + '.log', 'utf8').trim().split('\n').map(JSON.parse)
      for (const row of logs) { assert.ok(!row.names.includes('skill'), agent + '：skill 工具關閉'); assert.ok(!row.claudeMd, agent + '：沒有載入 ~/.claude/CLAUDE.md') }
      check(parts, logs)
      console.log('PASS ' + agent)
    } finally { model.kill() }
  }
  // write 與 edit 共用 OpenCode 的 edit 權限：開了 write 就看得到 edit，兩者都只能改 permission.edit 放行的檔
  const only = (logs, allowed) => { for (const row of logs) { for (const n of row.names) assert.ok(allowed.includes(n), '多出工具 ' + n + '（只准 ' + allowed.join(',') + '）') } }
  const editStep = (p, oldString, newString) => ({ name: 'edit', args: { filePath: p, oldString, newString } })
  console.log('synthetic workdir: ' + base)

  await scenario('ps-status-reader', [
    read(path.join(inbox, 'manifest.md')),
    read(status),
    read(path.join(project, '.opencode/peoplesoft/sdoc/status-reading-contract.md')),
    read(research),
    read(path.join(attempt, 'input.json')),
    writeStep(path.join(inbox, 'output-part-01.json'), '{"part":1}'),
    writeStep(path.join(inbox, 'output-part-x.json'), '{}'),
    writeStep(path.join(inbox, 'output.json'), '{"synthetic":true}'),
    writeStep(path.join(inbox, 'manifest.md'), 'x'),
    writeStep(path.join(attempt, 'output.json'), '{}'),
    editStep(path.join(inbox, 'manifest.md'), '合成', '竄改'),
  ], ['completed', 'completed', 'completed', 'error', 'error', 'completed', 'error', 'completed', 'error', 'error', 'error'], (parts, logs) => {
    only(logs, ['read', 'write', 'edit', 'invalid'])
    assert.ok(fs.existsSync(path.join(inbox, 'output-part-01.json')) && fs.existsSync(path.join(inbox, 'output.json')))
    assert.ok(!fs.existsSync(path.join(inbox, 'output-part-x.json')) && !fs.existsSync(path.join(attempt, 'output.json')))
    assert.equal(fs.readFileSync(path.join(inbox, 'manifest.md'), 'utf8'), '# 合成工單\n')
  })

  await scenario('ps-sdoc-worker', [
    read(path.join(attempt, 'manifest.md')),
    read(path.join(project, '.opencode/peoplesoft/sdoc/research-contract.md')),
    read(research),
    read(receipt),
    read(status),
    read(decisions),
    read(path.join(project, '.opencode/peoplesoft/customization-profile.yaml')),
    writeStep(path.join(attempt, 'output.json'), '{"synthetic":true}'),
    writeStep(path.join(attempt, 'candidate.json'), '{}'),
    writeStep(path.join(path.dirname(receipt), 'forged.json'), '{}'),
    writeStep(research, 'x'),
  ], ['completed', 'completed', 'completed', 'completed', 'completed', 'error', 'completed', 'completed', 'error', 'error', 'error'], (parts, logs) => {
    for (const row of logs) {
      for (const n of ['read', 'write', 'grep', 'glob', 'task']) assert.ok(row.names.includes(n), 'sdoc-worker 要有 ' + n)
      for (const n of ['bash', 'webfetch', 'websearch', 'skill', 'todowrite', 'list']) assert.ok(!row.names.includes(n), 'sdoc-worker 不該有 ' + n)
    }
    assert.ok(fs.existsSync(path.join(attempt, 'output.json')) && !fs.existsSync(path.join(attempt, 'candidate.json')) && !fs.existsSync(path.join(path.dirname(receipt), 'forged.json')))
    assert.equal(fs.readFileSync(research, 'utf8'), '# 合成研究\n')
  })

  fs.rmSync(path.join(inbox, 'output.json'), { force: true })
  await scenario('ps-spec-reader', [
    read(path.join(inbox, 'manifest.md')),
    read(path.join(inbox, 'docs')),
    read(path.join(inbox, 'docs/00-index.md')),
    read(path.join(project, '.opencode/peoplesoft/sdoc/reader-contract.md')),
    read(path.join(attempt, 'input.json')),
    read(receipt),
    read(research),
    writeStep(path.join(inbox, 'output.json'), '{"synthetic":true}'),
    writeStep(path.join(inbox, 'docs/00-index.md'), 'x'),
  ], ['completed', 'completed', 'completed', 'completed', 'error', 'error', 'error', 'completed', 'error'], (parts, logs) => {
    only(logs, ['read', 'write', 'edit', 'invalid'])
    assert.match(parts[1].state.output, /00-index\.md/)
    assert.equal(fs.readFileSync(path.join(inbox, 'docs/00-index.md'), 'utf8'), '# 合成文件\n')
  })

  fs.rmSync(path.join(inbox, 'output.json'), { force: true })
  await scenario('ps-spec-judge', [
    read(path.join(inbox, 'input.json')),
    read(path.join(project, '.opencode/peoplesoft/sdoc/judge-contract.md')),
    read(path.join(rt, 'work/r0001/md/04-workflow.md')),
    read(path.join(attempt, 'input.json')),
    writeStep(path.join(inbox, 'output.json'), '{"synthetic":true}'),
    writeStep(path.join(attempt, 'output.json'), '{}'),
  ], ['completed', 'completed', 'error', 'error', 'completed', 'error'], (parts, logs) => {
    only(logs, ['read', 'write', 'edit', 'invalid'])
  })
  console.log('SDOC SMOKE PASS (synthetic artifacts retained for diagnosis)')
}

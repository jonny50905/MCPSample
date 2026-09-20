// 真 OpenCode + localhost 劇本模型：驗 /ps-spec、工單 command、工具權限。
// 不驗模型理解或企業功能；只用 TW_DEMO_A 合成資料，不連 MCP。
// OPENCODE_BIN=<exe> node tests/runtime-guard/run-clone-smoke.mjs
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
      let next = { text: '測試完成。' }
      if (names.length) {
        const calls = (body.messages || []).filter(m => m.role === 'assistant').flatMap(m => m.tool_calls || [])
        next = plan.steps[calls.length] || next
        fs.appendFileSync(process.argv[4] + '.log', JSON.stringify({ names, next }) + '\n')
      }
      const id = 'clone-smoke-' + ++count
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
  const base = fs.mkdtempSync(path.join(os.tmpdir(), 'clone-smoke-'))
  const project = path.join(base, 'project')
  const oc = process.env.OPENCODE_BIN || 'opencode'
  const port = Number(process.env.CLONE_SMOKE_PORT || 18189)
  fs.mkdirSync(project)
  for (const name of ['.opencode', 'scripts']) fs.cpSync(path.join(repo, name), path.join(project, name), { recursive: true, filter: p => !/[\\/]node_modules(?:[\\/]|$)/.test(p) })
  fs.copyFileSync(path.join(repo, 'AGENTS.md'), path.join(project, 'AGENTS.md'))
  const write = (p, text) => { fs.mkdirSync(path.dirname(p), { recursive: true }); fs.writeFileSync(p, text) }
  const job = 'clone-0000000000000000'
  const attempt = path.join(project, '.ps-runtime/clone-spec', job, 'attempts/a0001')
  const receipt = path.join(project, '.ps-runtime/clone-spec', job, 'receipts/r0001/example.json')
  write(path.join(attempt, 'manifest.md'), '# 合成工單\nComponent: TW_DEMO_A\n')
  write(receipt, '{"synthetic":true}')
  const config = {
    model: 'mock/scripted', small_model: 'mock/scripted', autoupdate: false,
    provider: { mock: { npm: '@ai-sdk/openai-compatible', options: { baseURL: `http://127.0.0.1:${port}/v1`, apiKey: 'mock' }, models: { scripted: { name: 'scripted', tool_call: true, limit: { context: 128000, output: 8192 } } } } },
    permission: { doom_loop: 'allow', external_directory: 'allow' },
  }
  write(path.join(project, 'opencode.json'), JSON.stringify(config))
  const env = { ...process.env, PWD: project, OPENCODE_DISABLE_MODELS_FETCH: '1', OPENCODE_DISABLE_AUTOUPDATE: '1' }
  for (const name of ['DATA', 'CACHE', 'CONFIG', 'STATE']) { env[`XDG_${name}_HOME`] = path.join(base, name); fs.mkdirSync(env[`XDG_${name}_HOME`]) }
  const run = args => spawnSync(oc, args, { cwd: project, env, encoding: 'utf8', timeout: 120000, maxBuffer: 32 * 1024 * 1024 })
  async function scenario(name, args, steps, check) {
    const planPath = path.join(base, name + '.json')
    write(planPath, JSON.stringify({ steps }))
    const model = spawn(process.execPath, [self, '--model', String(port), planPath], { stdio: ['ignore', 'pipe', 'inherit'] })
    try {
      await new Promise((resolve, reject) => { model.stdout.once('data', resolve); model.once('error', reject); model.once('exit', c => reject(new Error('model exit ' + c))) })
      const r = run(['run', '--format', 'json', ...args])
      write(path.join(base, name + '.stdout'), r.stdout || '')
      write(path.join(base, name + '.stderr'), r.stderr || '')
      assert.equal(r.status, 0, r.stderr)
      const events = (r.stdout || '').split('\n').flatMap(l => { try { return [JSON.parse(l)] } catch { return [] } })
      const sid = events.find(e => e.sessionID)?.sessionID
      assert.ok(sid, 'missing sessionID')
      const ex = run(['export', sid])
      const exported = JSON.parse(ex.stdout)
      write(path.join(base, name + '.export.json'), JSON.stringify(exported, null, 2))
      const parts = exported.messages.flatMap(m => m.parts || []).filter(p => p.type === 'tool')
      const logs = fs.readFileSync(planPath + '.log', 'utf8').trim().split('\n').map(JSON.parse)
      check(parts, logs)
      console.log('PASS ' + name)
    } finally { model.kill() }
  }
  console.log('synthetic workdir: ' + base)
  await scenario('author-command', ['--command', 'ps-spec', '狀態 TW_DEMO_A'], [
    { name: 'bash', args: { command: "powershell -NoProfile -File scripts/ps-spec-build.ps1 -Components 'TW_DEMO_A' -Status", description: '合成規格狀態', timeout: 7200000 } },
  ], (parts, logs) => {
    assert.equal(parts.length, 1)
    assert.equal(parts[0].tool, 'bash')
    assert.equal(parts[0].state.status, 'completed')
    assert.match(parts[0].state.output, /CLONE1-0-02/)
    for (const row of logs) { assert.ok(row.names.includes('bash')); assert.ok(!row.names.includes('write')); assert.ok(!row.names.includes('task')) }
  })
  await scenario('worker-command', ['--command', 'ps-clone-batch', job + '/a0001'], [
    { name: 'read', args: { filePath: path.join(attempt, 'manifest.md') } },
    { name: 'read', args: { filePath: receipt } },
    { name: 'write', args: { filePath: path.join(attempt, 'packet.json'), content: '{"synthetic":true}' } },
    { name: 'write', args: { filePath: path.join(path.dirname(receipt), 'forged.json'), content: '{"forged":true}' } },
  ], (parts, logs) => {
    assert.equal(parts.length, 4)
    assert.deepEqual(parts.slice(0, 3).map(p => p.state.status), ['completed', 'completed', 'completed'])
    assert.equal(parts[3].state.status, 'error')
    assert.ok(fs.existsSync(path.join(attempt, 'packet.json')))
    assert.ok(!fs.existsSync(path.join(path.dirname(receipt), 'forged.json')))
    for (const row of logs) { assert.ok(row.names.includes('write')); assert.ok(row.names.includes('task')); assert.ok(!row.names.includes('bash')); assert.ok(!row.names.includes('webfetch')) }
  })
  console.log('CLONE SMOKE PASS (synthetic artifacts retained for diagnosis)')
}

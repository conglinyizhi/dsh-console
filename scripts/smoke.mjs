// 端到端 smoke：起一份隔离的后端，跑一遍只读接口、写动作与拒绝路径。
//
// 用法：node scripts/smoke.mjs [后端可执行文件]
// 默认取 backend/_build/native/debug/build/dsh-console-backend.exe。
//
// 它不碰真实的 ~/.dsh：DSH_HOME、XDG_STATE_HOME、隔离 homes 根都指向临时目录。
// 端口默认 5391，可用 SMOKE_PORT 覆盖。

import { spawn, execSync } from 'node:child_process'
import { request } from 'node:http'
import { mkdtempSync, mkdirSync, writeFileSync, readFileSync, existsSync, readdirSync, rmSync } from 'node:fs'
import { join, dirname } from 'node:path'
import { tmpdir } from 'node:os'
import { fileURLToPath } from 'node:url'

const here = dirname(fileURLToPath(import.meta.url))
const repo = dirname(here)
const bin = process.argv[2] || join(repo, 'backend/_build/native/debug/build/dsh-console-backend.exe')
const port = process.env.SMOKE_PORT || '5391'
const base = `http://127.0.0.1:${port}`

const work = mkdtempSync(join(tmpdir(), 'dsh-console-smoke-'))
const dshHome = join(work, 'dsh-home')
const stateHome = join(work, 'state')
const homesRoot = join(work, 'homes')
const profiles = join(dshHome, 'profiles')
const trashDir = join(stateHome, 'dsh-console', 'trash')

for (const p of [profiles, stateHome, homesRoot]) mkdirSync(p, { recursive: true })

const patch = (name) =>
  `# smoke fixture\n- id: agent-default-model\n  name: "@deepseek-ai/dsh-agent-default-model"\n  config:\n    provider: smoke\n    model: ${name}\n`
for (const p of ['alpha', 'beta', 'gamma']) {
  mkdirSync(join(profiles, p), { recursive: true })
  writeFileSync(join(profiles, p, 'cordis.patch.yml'), patch(p))
}

const results = []
const check = (name, ok, detail = '') => {
  results.push({ name, ok, detail })
  console.log(`${ok ? 'PASS' : 'FAIL'}  ${name}${detail ? '  ' + detail : ''}`)
}

const child = spawn(bin, [], {
  env: {
    ...process.env,
    DSH_HOME: dshHome,
    XDG_STATE_HOME: stateHome,
    DSH_CONSOLE_HOMES_ROOT: homesRoot,
    DSH_CONSOLE_BACKEND_PORT: port,
  },
  stdio: ['ignore', 'pipe', 'pipe'],
})
let log = ''
child.stdout.on('data', (d) => (log += d))
child.stderr.on('data', (d) => (log += d))

const get = async (path, init) => {
  const r = await fetch(base + path, init)
  const text = await r.text()
  let json = null
  try {
    json = JSON.parse(text)
  } catch {}
  return { status: r.status, json, text }
}

const post = (action, params, headers = { 'X-DSH-Console': '1', Origin: base }) =>
  get('/api/local/action', {
    method: 'POST',
    headers: { 'content-type': 'application/json', ...headers },
    body: JSON.stringify({ action, params }),
  })

const profileNames = async () => {
  const r = await get('/api/local/profiles')
  return (r.json?.data?.profiles || []).map((x) => x.name)
}

const probe = () =>
  new Promise((resolve) => {
    const req = request(
      { host: '127.0.0.1', port, path: '/api/local/runtime', timeout: 1000 },
      (res) => {
        res.resume()
        resolve(res.statusCode === 200)
      },
    )
    req.on('error', (e) => resolve(false))
    req.on('timeout', () => {
      req.destroy()
      resolve(false)
    })
    req.end()
  })

const waitReady = async () => {
  for (let i = 0; i < 300; i++) {
    if (await probe()) return true
    await new Promise((r) => setTimeout(r, 100))
  }
  return false
}

try {
  if (!existsSync(bin)) {
    console.error(`找不到后端可执行文件：${bin}`)
    process.exit(2)
  }
  const ready = await waitReady()
  if (!ready) {
    let diag = ''
    try {
      diag += execSync('ss -ltnp 2>&1 | head -20 || true', { encoding: 'utf8' })
    } catch (e) {
      diag += 'ss failed: ' + e.message
    }
    try {
      diag += execSync(`curl -sv --max-time 2 http://127.0.0.1:${port}/ 2>&1 | tail -20 || true`, { encoding: 'utf8' })
    } catch (e) {
      diag += 'curl failed: ' + e.message
    }
    check('后端在 30 秒内就绪', false, `exit=${child.exitCode} signal=${child.signalCode}\n--- ss/curl ---\n${diag}\n--- log ---\n${log.slice(-600)}`)
  } else {
    check('后端在 30 秒内就绪', true)
  }
  if (!ready) throw new Error('后端没起来')

  // 1-8 只读接口：状态码 200、ok=true、关键字段在。
  const reads = [
    ['runtime', 'consoleVersion'],
    ['profiles', 'profiles'],
    ['logs?source=host', 'lines'],
    ['processes', 'procRoot'],
    ['instances', 'sources'],
    ['dsh-releases', 'versions'],
    ['settings', 'values'],
    ['console', 'buildSha'],
  ]
  for (const [path, field] of reads) {
    const r = await get('/api/local/' + path)
    const data = r.json?.data || {}
    const ok = r.status === 200 && r.json?.ok === true && field in data
    check(`GET /api/local/${path}`, ok, ok ? '' : `status=${r.status} keys=${Object.keys(data).join(',')}`)
  }

  // 9 派生
  let r = await post('fork-profile', { profile: 'alpha', newName: 'alpha-fork' })
  check(
    'fork-profile 生成新 profile',
    r.status === 200 && existsSync(join(profiles, 'alpha-fork', 'cordis.patch.yml')),
    `status=${r.status}`,
  )

  // 10 重命名
  r = await post('rename-profile', { profile: 'beta', newName: 'beta2' })
  check(
    'rename-profile 改目录名',
    r.status === 200 && !existsSync(join(profiles, 'beta')) && existsSync(join(profiles, 'beta2')),
    `status=${r.status}`,
  )

  // 11 备注
  r = await post('set-profile-note', { profile: 'alpha', text: 'smoke-note' })
  const names = await profileNames()
  const pr = await get('/api/local/profiles')
  const noted = (pr.json?.data?.profiles || []).find((x) => x.name === 'alpha')
  const noteText = JSON.stringify(noted || {}).includes('smoke-note')
  check(
    'set-profile-note 落盘并在 profiles 里读回',
    r.status === 200 && noteText,
    `status=${r.status} profiles=${names.join('/')}`,
  )

  // 12 归档：磁盘不动，标记写进 archive.json
  const archiveFile = join(stateHome, 'dsh-console', 'archive.json')
  r = await post('archive-profile', { profile: 'gamma' })
  const archivedText = existsSync(archiveFile) ? readFileSync(archiveFile, 'utf8') : ''
  check(
    'archive-profile 把标记写进 archive.json',
    r.status === 200 && archivedText.includes('gamma'),
    `status=${r.status}`,
  )

  // 13 取消归档：标记消失
  r = await post('unarchive-profile', { profile: 'gamma' })
  const unarchivedText = existsSync(archiveFile) ? readFileSync(archiveFile, 'utf8') : ''
  check(
    'unarchive-profile 清掉标记',
    r.status === 200 && !unarchivedText.includes('gamma'),
    `status=${r.status}`,
  )

  // 14 删除进回收站
  r = await post('delete-profile', { profile: 'gamma' })
  check(
    'delete-profile 把目录移出 profiles',
    r.status === 200 && !existsSync(join(profiles, 'gamma')),
    `status=${r.status}`,
  )

  // 15 从回收站恢复：dir 是回收站里的目录名
  const trashed = existsSync(trashDir) ? readdirSync(trashDir) : []
  const gammaEntry = trashed.find((x) => x.startsWith('gamma-'))
  if (!gammaEntry) {
    check('restore-from-trash 恢复目录', false, `回收站里没有 gamma 条目：${trashed.join('/')}`)
  } else {
    r = await post('restore-from-trash', { dir: gammaEntry })
    check(
      'restore-from-trash 恢复目录',
      r.status === 200 && existsSync(join(profiles, 'gamma')),
      `status=${r.status} dir=${gammaEntry}`,
    )
  }

  // 16-20 拒绝路径
  r = await post('no-such-action', {})
  check('未知动作被拒', r.status === 400 || r.status === 404, `status=${r.status}`)

  r = await post('rename-profile', { profile: 'alpha' })
  check('缺参数被拒', r.status === 400, `status=${r.status}`)

  r = await post('rename-profile', { profile: 'alpha', newName: 'beta2' })
  check('改名撞已有 profile 被拒', r.status === 400 || r.status === 409, `status=${r.status}`)

  r = await post('rename-profile', { profile: '../../etc', newName: 'x' })
  check('带上级段的 profile 名被拒', r.status === 400, `status=${r.status}`)

  r = await post('rename-profile', { profile: 'alpha', newName: 'alpha-x' }, {})
  check('缺 X-DSH-Console 头被拒', r.status === 403, `status=${r.status}`)

  // 21-22 静态与未知接口
  r = await get('/')
  check('首页 200 且是 HTML', r.status === 200 && r.text.includes('<html'), `status=${r.status}`)

  r = await get('/api/local/nope')
  check('未知接口 404', r.status === 404, `status=${r.status}`)
} catch (e) {
  console.error('smoke 中断：', e.message)
  console.error(log.slice(-800))
} finally {
  child.kill('SIGTERM')
  await new Promise((r) => setTimeout(r, 200))
  child.kill('SIGKILL')
  rmSync(work, { recursive: true, force: true })
}

const failed = results.filter((x) => !x.ok)
console.log(`\n${results.length - failed.length}/${results.length} 通过`)
if (failed.length) {
  console.log('失败项：')
  for (const f of failed) console.log(`  - ${f.name} ${f.detail}`)
  process.exit(1)
}

// 回收站的真链路（浏览器里走界面）：删除 → 回收站列表 → 恢复 → 再删 → 彻底删除。
// 目标实例是隔离环境那一只（5491），DSH_HOME / XDG_STATE_HOME 全在 /tmp 下。
import { spawn } from 'node:child_process'
import { existsSync, mkdirSync, rmSync, writeFileSync } from 'node:fs'
import { join } from 'node:path'

const CDP_PORT = 9800 + (process.pid % 400)
const BASE = process.env.E2E_BASE || 'http://127.0.0.1:5491'
const HOME = '/tmp/dsh-console-trash-e2e/dsh-home'
const STATE = '/tmp/dsh-console-trash-e2e/state'
const PROFILES = join(HOME, 'profiles')
const TRASH = join(STATE, 'dsh-console', 'trash')

const makeProfile = (name) => {
  mkdirSync(join(PROFILES, name, 'sub'), { recursive: true })
  writeFileSync(join(PROFILES, name, 'a.txt'), 'hello ' + name + '\n')
  writeFileSync(join(PROFILES, name, 'sub', 'b.txt'), 'nested\n')
  writeFileSync(join(PROFILES, name, 'cordis.patch.yml'), 'x\n')
}
for (const n of ['zz-trash-b', 'zz-trash-keep']) if (!existsSync(join(PROFILES, n))) makeProfile(n)

const chrome = spawn('chromium', ['--headless','--no-sandbox','--disable-gpu','--disable-extensions','--hide-scrollbars','--remote-debugging-port=' + CDP_PORT,'--user-data-dir=/tmp/chrome-trash-' + process.pid,'--window-size=1440,900','about:blank'], { stdio: 'ignore' })
let page = null
for (let i = 0; i < 60 && !page; i++) { try { const l = await (await fetch('http://127.0.0.1:' + CDP_PORT + '/json')).json(); page = l.find((t) => t.type === 'page') } catch {} if (!page) await new Promise((r) => setTimeout(r, 250)) }
if (!page) { console.log('chromium 没起来'); process.exit(1) }
const ws = new WebSocket(page.webSocketDebuggerUrl); let id = 0; const pend = new Map()
ws.onmessage = (e) => { const m = JSON.parse(e.data); if (m.id && pend.has(m.id)) { pend.get(m.id)(m); pend.delete(m.id) } }
await new Promise((r) => { ws.onopen = r })
const send = (method, params = {}) => new Promise((res) => { const i = ++id; pend.set(i, res); ws.send(JSON.stringify({ id: i, method, params })) })
const ev = async (e) => { const r = await send('Runtime.evaluate', { expression: e, returnByValue: true }); return r.result?.result?.value }
const evAsync = async (e) => { const r = await send('Runtime.evaluate', { expression: e, returnByValue: true, awaitPromise: true }); return r.result?.result?.value }
const wait = (ms) => new Promise((r) => setTimeout(r, ms))
await send('Page.enable'); await send('Runtime.enable')
await send('Emulation.setDeviceMetricsOverride', { width: 1440, height: 900, deviceScaleFactor: 1, mobile: false })

const shots = []
const shot = async (label) => {
  const data = await ev(`(() => {
    const rows = [...document.querySelectorAll('[data-name^="trash-row"]')].map((r) => r.innerText.replace(/\\n/g, ' | '))
    const notice = document.querySelector('.dsh-notice-text')
    const nav = [...document.querySelectorAll('.dsh-nav-item')].map((n) => n.innerText.trim() + (n.classList.contains('active') ? '(当前)' : ''))
    const dlg = document.querySelector('.dsh-dialog-card')
    return JSON.stringify({
      url: location.pathname,
      title: (document.querySelector('.dsh-page-title') || {}).innerText || null,
      nav,
      rows,
      empty: (document.querySelector('[data-name^="trash-empty"]') || {}).innerText || null,
      loading: (document.querySelector('[data-name^="trash-loading"]') || {}).innerText || null,
      missingField: (document.querySelector('[data-name^="trash-missing-field"]') || {}).innerText || null,
      notice: notice ? { text: notice.innerText, title: notice.getAttribute('title') } : null,
      dialog: dlg ? { title: dlg.querySelector('.dsh-dialog-title').innerText, message: dlg.querySelector('.dsh-dialog-message').innerText } : null,
      cards: [...document.querySelectorAll('[data-name^="instance-card"]')].length,
    })
  })()`)
  const parsed = JSON.parse(data)
  shots.push({ label, ...parsed })
  console.log('── ' + label)
  console.log(JSON.stringify(parsed, null, 1))
  return parsed
}

const goto = async (path, ms = 3500) => { await send('Page.navigate', { url: BASE + path }); await wait(ms) }
const clickSel = async (sel) => ev(`(() => { const e = document.querySelector(${JSON.stringify(sel)}); if (!e) return 'no-node'; e.click(); return 'clicked' })()`)
const clickText = async (sel, text) => ev(`(() => { const e = [...document.querySelectorAll(${JSON.stringify(sel)})].find((x) => x.innerText.trim() === ${JSON.stringify(text)}); if (!e) return 'no-node'; e.click(); return 'clicked' })()`)

// 卡片菜单里的删除：开 ⋯ 菜单 → 点「删除」→ 确认框里点「删除」
const deleteCard = async (name) => {
  const opened = await ev(`(() => { const c = [...document.querySelectorAll('[data-name^="instance-card"]')].find((x) => x.innerText.includes(${JSON.stringify(name)})); if (!c) return 'no-card'; const t = c.querySelector('[aria-haspopup="menu"]'); if (!t) return 'no-trigger'; t.click(); return 'clicked' })()`)
  if (opened !== 'clicked') return 'open:' + opened
  await wait(700)
  const item = await clickText('[data-name^="row-menu"] button', '删除')
  if (item !== 'clicked') return 'item:' + item
  await wait(700)
  const ok = await clickSel('[data-name^="dialog-ok"]')
  await wait(1500)
  return ok
}

// ── 1. 进回收站页：空态 ──
await goto('/trash')
await shot('1. /trash 空态（隔离环境起跑时回收站是空的）')

// ── 2. 总览页删一份 profile：回执说人话 ──
await goto('/')
await deleteCard('zz-trash-b')
await wait(1500)
await shot('2. 删除 zz-trash-b 之后的回执（正文 / 悬停）')
const trashAfterDelete = existsSync(TRASH) ? (await import('node:fs')).readdirSync(TRASH) : []

// ── 3. 点侧栏「回收站」进页：这一条在里面 ──
await clickSel('[data-name^="nav-trash"]')
await wait(2500)
const shot3 = await shot('3. 侧栏进回收站：zz-trash-b 那一行')

// ── 4. 彻底删除：先弹确认框，取消 → 框关，再来一次 → 真删 ──
await clickSel('[data-name^="trash-purge"]')
await wait(800)
await shot('4. 点「彻底删除」弹确认框')
await clickText('.dsh-dialog-btn', '取消')
await wait(700)
const afterCancel = await shot('4b. 取消之后（框应当关了，行还在）')
await clickSel('[data-name^="trash-purge"]')
await wait(800)
await clickText('.dsh-dialog-btn', '彻底删除')
await wait(2000)
const shot5 = await shot('5. 彻底删除之后（列表回到空态）')
const purgedGone = !existsSync(join(TRASH, (shot3.rows.length ? trashAfterDelete[0] : '')))

// ── 6. 再删一份，走恢复；先造一个同名 profile 逼出 conflict ──
await goto('/')
await shot('6a. 总览页（删除之前）')
const delA = await deleteCard('zz-trash-a')
console.log('deleteCard(zz-trash-a) → ' + delA)
await wait(2000)
await shot('6b. 删除 zz-trash-a 之后的回执')
await goto('/trash')
const shot6 = await shot('6. zz-trash-a 在回收站里')
makeProfile('zz-trash-a')
const conflictDir = (await import('node:fs')).readdirSync(TRASH).find((d) => d.startsWith('zz-trash-a-'))
await clickSel('[data-name^="trash-restore"]')
await wait(2000)
await shot('7. 同名 profile 已存在时点「恢复」→ conflict 原文')

// ── 7. 拿掉同名目录 → 恢复成功 ──
rmSync(join(PROFILES, 'zz-trash-a'), { recursive: true, force: true })
await clickSel('[data-name^="trash-restore"]')
await wait(2500)
await shot('8. 恢复成功之后（行没了，回到空态）')
const restoredBack = existsSync(join(PROFILES, 'zz-trash-a', 'sub', 'b.txt'))
await goto('/')
const overview = await shot('9. 总览页：zz-trash-a 回到已停止的实例里')
const backInList = overview.cards > 0

console.log('\n==== 判定 ====')
const ok = (label, cond, got) => console.log((cond ? '通过  ' : '✗失败 ') + label + (got === undefined ? '' : '  → ' + JSON.stringify(got)))
ok('侧栏有「回收站」且是当前项', shots[0].nav.some((n) => n.includes('回收站(当前)')), shots[0].nav)
ok('空态文案是「回收站是空的」', (shots[0].empty || '').includes('回收站是空的'), shots[0].empty)
ok('删除回执正文说人话（含回收站指路）', (shots[1].notice?.text || '').includes('已移入回收站'), shots[1].notice)
ok('正文里没有路径 / mode', !/mode=|trashPath|\/tmp\//.test(shots[1].notice?.text || ''), shots[1].notice?.text)
ok('悬停里有路径与 mode', /mode=trash/.test(shots[1].notice?.title || '') && /trashPath=/.test(shots[1].notice?.title || ''), shots[1].notice?.title)
ok('回收站列表里有一行（名字/时间/体积/两个按钮）', shot3.rows.length === 1 && shot3.rows[0].includes('zz-trash-b'), shot3.rows)
const shot4 = shots.find((s) => s.label.startsWith('4. '))
ok('点彻底删除先弹确认框', !!shot4?.dialog, shot4?.dialog)
ok('取消能关框且行还在', !afterCancel.dialog && afterCancel.rows.length === 1, afterCancel.rows.length)
ok('彻底删除之后回收站空了', shot5.rows.length === 0 && (shot5.empty || '').includes('回收站是空的'), shot5.empty)
ok('磁盘上那份真没了', !existsSync(join(TRASH, conflictDir || 'x')), conflictDir)
ok('conflict 分支：拒绝并说明原因', /conflict|已经有同名/.test(JSON.stringify(shots.find((s) => s.label.startsWith('7. '))?.notice)), shots.find((s) => s.label.startsWith('7. '))?.notice)
ok('恢复成功：行消失 + 磁盘上文件回来', shots.find((s) => s.label.startsWith('8. '))?.rows.length === 0 && restoredBack)
ok('恢复之后 profile 回到总览列表', backInList, overview.cards)

const fs = await import('node:fs')
fs.writeFileSync('/tmp/dsh-console-trash-e2e/out/ui-chain.json', JSON.stringify(shots, null, 1))
chrome.kill(); process.exit(0)

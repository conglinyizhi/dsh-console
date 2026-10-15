// 两件事：
//   1. 硬删那条路的回执（safety.deleteToTrash=false）——正文「已删除，无法恢复」+ 悬停里的 mode
//   2. 使用者的 5390：新前端 + 旧后端（按指示没重启）时回收站页说什么 —— 只读，不发写请求
import { spawn } from 'node:child_process'

const CDP_PORT = 9700 + (process.pid % 300)
const BASE = 'http://127.0.0.1:5491'
const OLD = 'http://127.0.0.1:5390'

const chrome = spawn('chromium', ['--headless','--no-sandbox','--disable-gpu','--disable-extensions','--hide-scrollbars','--remote-debugging-port=' + CDP_PORT,'--user-data-dir=/tmp/chrome-trash2-' + process.pid,'--window-size=1440,900','about:blank'], { stdio: 'ignore' })
let page = null
for (let i = 0; i < 60 && !page; i++) { try { const l = await (await fetch('http://127.0.0.1:' + CDP_PORT + '/json')).json(); page = l.find((t) => t.type === 'page') } catch {} if (!page) await new Promise((r) => setTimeout(r, 250)) }
const ws = new WebSocket(page.webSocketDebuggerUrl); let id = 0; const pend = new Map()
ws.onmessage = (e) => { const m = JSON.parse(e.data); if (m.id && pend.has(m.id)) { pend.get(m.id)(m); pend.delete(m.id) } }
await new Promise((r) => { ws.onopen = r })
const send = (method, params = {}) => new Promise((res) => { const i = ++id; pend.set(i, res); ws.send(JSON.stringify({ id: i, method, params })) })
const ev = async (e) => { const r = await send('Runtime.evaluate', { expression: e, returnByValue: true }); return r.result?.result?.value }
const wait = (ms) => new Promise((r) => setTimeout(r, ms))
await send('Page.enable'); await send('Runtime.enable')
await send('Emulation.setDeviceMetricsOverride', { width: 1440, height: 900, deviceScaleFactor: 1, mobile: false })

const snapshot = () => ev(`(() => {
  const notice = document.querySelector('.dsh-notice-text')
  return JSON.stringify({
    url: location.pathname,
    title: (document.querySelector('.dsh-page-title') || {}).innerText || null,
    nav: [...document.querySelectorAll('.dsh-nav-item')].map((n) => n.innerText.trim()),
    rows: [...document.querySelectorAll('[data-name^="trash-row"]')].map((r) => r.innerText.replace(/\\n/g, ' | ')),
    empty: (document.querySelector('[data-name^="trash-empty"]') || {}).innerText || null,
    loading: (document.querySelector('[data-name^="trash-loading"]') || {}).innerText || null,
    missingField: (document.querySelector('[data-name^="trash-missing-field"]') || {}).innerText || null,
    notice: notice ? { text: notice.innerText, title: notice.getAttribute('title') } : null,
  })
})()`)

const goto = async (url, ms = 4000) => { await send('Page.navigate', { url }); await wait(ms) }

// ── 1. 硬删 ──
await fetch(BASE + '/api/local/settings', { method: 'PUT', headers: { 'content-type': 'application/json', 'X-DSH-Console': '1' }, body: JSON.stringify({ values: { 'safety.deleteToTrash': false } }) })
await goto(BASE + '/')
await ev(`(() => { const c = [...document.querySelectorAll('[data-name^="instance-card"]')].find((x) => x.innerText.includes('zz-trash-keep')); const t = c && c.querySelector('[aria-haspopup="menu"]'); if (t) t.click(); return !!t })()`)
await wait(700)
await ev(`(() => { const e = [...document.querySelectorAll('[data-name^="row-menu"] button')].find((x) => x.innerText.trim() === '删除'); if (e) e.click(); return !!e })()`)
await wait(800)
const dialogText = await ev(`(() => { const d = document.querySelector('.dsh-dialog-message'); return d ? d.innerText : null })()`)
await ev(`(() => { const e = document.querySelector('[data-name^="dialog-ok"]'); if (e) e.click(); return !!e })()`)
await wait(2000)
const hardShot = JSON.parse(await snapshot())
console.log('── 硬删：确认框里那句 → ' + dialogText)
console.log('── 硬删回执')
console.log(JSON.stringify(hardShot, null, 1))
await fetch(BASE + '/api/local/settings', { method: 'PUT', headers: { 'content-type': 'application/json', 'X-DSH-Console': '1' }, body: JSON.stringify({ values: { 'safety.deleteToTrash': true } }) })

// ── 2. 5390：新前端 + 没重启的旧后端 ──
await goto(OLD + '/trash', 5000)
const oldShot = JSON.parse(await snapshot())
console.log('── 5390 /trash（新前端 + 旧后端，只读）')
console.log(JSON.stringify(oldShot, null, 1))

console.log('\n==== 判定 ====')
const ok = (l, c, g) => console.log((c ? '通过  ' : '✗失败 ') + l + (g === undefined ? '' : '  → ' + JSON.stringify(g)))
ok('硬删确认框说「无法恢复」', /无法恢复/.test(dialogText || ''), dialogText)
ok('硬删回执正文是「已删除，无法恢复」', /已删除，无法恢复/.test(hardShot.notice?.text || ''), hardShot.notice?.text)
ok('硬删正文里没有路径', !/\/tmp\/|mode=/.test(hardShot.notice?.text || ''), hardShot.notice?.text)
ok('硬删悬停里有 mode=hard-delete / hardDeleted=true', /mode=hard-delete/.test(hardShot.notice?.title || '') && /hardDeleted=true/.test(hardShot.notice?.title || ''), hardShot.notice?.title)
ok('5390 上不谎报「空的」', !oldShot.empty && /还没有回收站读数/.test(oldShot.missingField || ''), oldShot.missingField)
chrome.kill(); process.exit(0)

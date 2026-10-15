// 把 userscript 里的 collectPath / genPath 原样抽出来，在合成 DOM 上跑：
// 同角色的两个元素必须生成**不同**的路径（这正是使用者遇到的原始问题）
import { readFileSync } from 'node:fs'
import { spawn } from 'node:child_process'
const src = readFileSync(process.argv[3], 'utf8')
const a = src.indexOf('function collectPath')
const b = src.indexOf('function commonPrefix')
const fns = src.slice(a, b)
const CDP_PORT = 9300 + (process.pid % 600)
const chrome = spawn('chromium', ['--headless','--no-sandbox','--disable-gpu','--disable-extensions','--hide-scrollbars','--remote-debugging-port=' + CDP_PORT,'--user-data-dir=/tmp/chrome-probe-' + process.pid,'--window-size=1024,768','about:blank'], { stdio: 'ignore' })
let page = null
for (let i = 0; i < 40 && !page; i++) { try { const l = await (await fetch('http://127.0.0.1:' + CDP_PORT + '/json')).json(); page = l.find((t) => t.type === 'page') } catch {} if (!page) await new Promise((r) => setTimeout(r, 250)) }
const ws = new WebSocket(page.webSocketDebuggerUrl); let id = 0; const pend = new Map()
ws.onmessage = (e) => { const m = JSON.parse(e.data); if (m.id && pend.has(m.id)) { pend.get(m.id)(m); pend.delete(m.id) } }
await new Promise((r) => { ws.onopen = r })
const send = (m, p = {}) => new Promise((res) => { const i = ++id; pend.set(i, res); ws.send(JSON.stringify({ id: i, method: m, params: p })) })
await send('Page.enable'); await send('Runtime.enable')
await send('Page.navigate', { url: 'about:blank' })
await new Promise((r) => setTimeout(r, 600))
const html = '<div data-name="overview-page" data-uid="pg000001"><div class="dsh-section-head"><span data-name="source-badge" data-uid="m7q2w9de">运行中分组</span></div><div class="dsh-section-head"><span data-name="source-badge" data-uid="k3f9a2x1">已停止分组</span></div><span data-uid="onlyuid1">只有 uid</span><span class="plain-class">只有 class</span></div>'
await send('Runtime.evaluate', { expression: 'document.body.innerHTML = ' + JSON.stringify(html), returnByValue: true })
const expr = '(() => { ' + fns + ' ;' +
  ' const out = [];' +
  ' document.querySelectorAll("span").forEach((el) => { out.push({ text: el.textContent, path: genPath(collectPath(el)) }) });' +
  ' return JSON.stringify(out, null, 1) })()'
const res = await send('Runtime.evaluate', { expression: expr, returnByValue: true })
console.log(res.result?.result?.value)
const rows = JSON.parse(res.result?.result?.value || '[]')
const badges = rows.filter((r) => r.text.includes('分组'))
console.log('两个同角色徽标的路径是否不同:', badges.length === 2 && badges[0].path !== badges[1].path)
chrome.kill(); process.exit(0)
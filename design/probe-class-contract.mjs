const CDP_PORT = 9300 + (process.pid % 600) // 按进程取，并行跑不抢端口
// 类名契约探针：DOM 里用到的每个 class，在全部样式表里必须有对应规则。
// 浏览器侧代码在 class-contract-page.js，原样注入（避免多层转义把它弄坏）。
import { spawn } from 'node:child_process'
import { readFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'
const here = dirname(fileURLToPath(import.meta.url))
const baseUrl = process.argv[2]
const expr = readFileSync(join(here, 'class-contract-page.js'), 'utf8')
const chrome = spawn('chromium', ['--headless','--no-sandbox','--disable-gpu','--disable-extensions','--hide-scrollbars','--remote-debugging-port=' + CDP_PORT,'--user-data-dir=/tmp/chrome-probe-' + process.pid,'--window-size=1280,900','about:blank'], { stdio: 'ignore' })
let page = null
for (let i = 0; i < 40 && !page; i++) { try { const l = await (await fetch('http://127.0.0.1:' + CDP_PORT + '/json')).json(); page = l.find(t => t.type === 'page') } catch {} if (!page) await new Promise(r => setTimeout(r, 250)) }
const ws = new WebSocket(page.webSocketDebuggerUrl); let id = 0; const pend = new Map()
ws.onmessage = e => { const m = JSON.parse(e.data); if (m.id && pend.has(m.id)) { pend.get(m.id)(m); pend.delete(m.id) } }
await new Promise(r => { ws.onopen = r })
const send = (method, params = {}) => new Promise(res => { const i = ++id; pend.set(i, res); ws.send(JSON.stringify({ id: i, method, params })) })
const ev = async (e) => { const r = await send('Runtime.evaluate', { expression: e, returnByValue: true, awaitPromise: true }); if (r.result?.exceptionDetails) return 'EXCEPTION: ' + JSON.stringify(r.result.exceptionDetails).slice(0, 200); return r.result?.result?.value }
const wait = (ms) => new Promise(r => setTimeout(r, ms))
await send('Page.enable'); await send('Runtime.enable')
await send('Emulation.setDeviceMetricsOverride', { width: 1280, height: 900, deviceScaleFactor: 1, mobile: false })
await send('Page.navigate', { url: baseUrl }); await wait(4500)
for (const nav of ['日志', '关于', '实例总览']) {
  await ev("[...document.querySelectorAll('.dsh-nav-item')].find(e => e.textContent.trim() === '" + nav + "')?.click()")
  await wait(1800)
}
console.log(await ev(expr))
chrome.kill(); process.exit(0)

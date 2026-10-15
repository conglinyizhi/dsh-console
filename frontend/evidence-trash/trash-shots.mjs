// 出两张图：回收站列表（有一行）与「彻底删除」确认框。用完把这个临时条目清掉。
import { spawn } from 'node:child_process'
import { writeFileSync, mkdirSync } from 'node:fs'
const CDP_PORT = 9600 + (process.pid % 300)
const BASE = 'http://127.0.0.1:5491'
const OUT = '~/Public/deepseek-harness-project/dsh-console/frontend/evidence-trash'
const act = async (body) => (await (await fetch(BASE + '/api/local/action', { method: 'POST', headers: { 'content-type': 'application/json', 'X-DSH-Console': '1' }, body: JSON.stringify(body) })).json())
mkdirSync('/tmp/dsh-console-trash-e2e/dsh-home/profiles/zz-shot/sub', { recursive: true })
writeFileSync('/tmp/dsh-console-trash-e2e/dsh-home/profiles/zz-shot/a.txt', 'shot\n')
writeFileSync('/tmp/dsh-console-trash-e2e/dsh-home/profiles/zz-shot/sub/b.txt', 'shot\n')
await act({ action: 'delete-profile', params: { profile: 'zz-shot' } })
const chrome = spawn('chromium', ['--headless','--no-sandbox','--disable-gpu','--disable-extensions','--hide-scrollbars','--remote-debugging-port=' + CDP_PORT,'--user-data-dir=/tmp/chrome-shot-' + process.pid,'--window-size=1440,900','about:blank'], { stdio: 'ignore' })
let page = null
for (let i = 0; i < 60 && !page; i++) { try { const l = await (await fetch('http://127.0.0.1:' + CDP_PORT + '/json')).json(); page = l.find((t) => t.type === 'page') } catch {} if (!page) await new Promise((r) => setTimeout(r, 250)) }
const ws = new WebSocket(page.webSocketDebuggerUrl); let id = 0; const pend = new Map()
ws.onmessage = (e) => { const m = JSON.parse(e.data); if (m.id && pend.has(m.id)) { pend.get(m.id)(m); pend.delete(m.id) } }
await new Promise((r) => { ws.onopen = r })
const send = (m, p = {}) => new Promise((res) => { const i = ++id; pend.set(i, res); ws.send(JSON.stringify({ id: i, method: m, params: p })) })
const wait = (ms) => new Promise((r) => setTimeout(r, ms))
const ev = async (e) => (await send('Runtime.evaluate', { expression: e, returnByValue: true })).result?.result?.value
await send('Page.enable'); await send('Runtime.enable')
await send('Emulation.setDeviceMetricsOverride', { width: 1440, height: 900, deviceScaleFactor: 1, mobile: false })
const snap = async (file) => { const r = await send('Page.captureScreenshot', { format: 'png' }); writeFileSync(file, Buffer.from(r.result.data, 'base64')) }
await send('Page.navigate', { url: BASE + '/trash' }); await wait(4500)
await snap(OUT + '/trash-list.png')
await ev("(() => { const b = document.querySelector('[data-name^=\"trash-purge\"]'); if (b) b.click(); return !!b })()")
await wait(900)
await snap(OUT + '/trash-purge-dialog.png')
const dir = await (await (await fetch(BASE + '/api/local/console')).json()).data.trash.map((t) => t.dir)
console.log(JSON.stringify(dir))
if (dir.length) console.log(JSON.stringify(await act({ action: 'purge-trash-item', params: { dir: dir[0] }, confirm: 'PURGE' })))
chrome.kill(); process.exit(0)

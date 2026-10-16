// 顺序保存成功那条提示的文案探针（第十一轮）。
//   node probe-order-toast.mjs <baseUrl> [输出前缀]
//
// 真指针拖一次（CDP Input.dispatchMouseEvent：按下 → 分步移动 → 松开），回执到了之后读：
//   * toast 正文（.dsh-toast-text 的 textContent）—— 应当是「顺序已保存」
//   * 它的 title（悬停补充）—— 路径与条数应当收在这里，一个字都没丢
//   * order.json 的实际内容（确认这一枪真的写盘了，提示不是空话）
// 只往**隔离实例**的状态目录里写（XDG_STATE_HOME 指到 /tmp 下的 fixture）：不碰使用者那一份。
import { spawn } from 'node:child_process'
import { writeFileSync, readFileSync, existsSync } from 'node:fs'

const here = new URL('.', import.meta.url).pathname
const baseUrl = (process.argv[2] || 'http://127.0.0.1:5533/').replace(/\/$/, '')
const prefix = process.argv[3] || 'order-toast'
const CDP_PORT = 9540 + (process.pid % 400)
const VW = 1280, VH = 900

const chrome = spawn('chromium', ['--headless', '--no-sandbox', '--disable-gpu', '--disable-extensions',
  '--hide-scrollbars', '--remote-debugging-port=' + CDP_PORT, '--user-data-dir=/tmp/chrome-toast-' + process.pid,
  '--window-size=' + VW + ',' + VH, 'about:blank'], { stdio: 'ignore' })

let page = null
for (let i = 0; i < 60 && !page; i++) {
  try { const l = await (await fetch('http://127.0.0.1:' + CDP_PORT + '/json')).json(); page = l.find((t) => t.type === 'page') } catch {}
  if (!page) await new Promise((r) => setTimeout(r, 250))
}
if (!page) { console.log('chrome 没起来'); process.exit(1) }

const ws = new WebSocket(page.webSocketDebuggerUrl)
let id = 0
const pending = new Map()
const consoleIssues = []
const send = (method, params = {}) => new Promise((res) => {
  const i = ++id; pending.set(i, res); ws.send(JSON.stringify({ id: i, method, params }))
})
ws.onmessage = (e) => {
  const m = JSON.parse(e.data)
  if (m.method === 'Runtime.consoleAPICalled' && ['error', 'warning'].includes(m.params && m.params.type)) {
    consoleIssues.push(m.params.type + ': ' + (m.params.args || []).map((a) => a.value || a.description || '').join(' ').slice(0, 160))
  }
  if (m.id && pending.has(m.id)) { pending.get(m.id)(m); pending.delete(m.id) }
}
await new Promise((r) => { ws.onopen = r })

const ev = async (expression) => {
  const r = await send('Runtime.evaluate', { expression, returnByValue: true, awaitPromise: true })
  if (r.result && r.result.exceptionDetails) throw new Error('eval 出错: ' + JSON.stringify(r.result.exceptionDetails).slice(0, 300))
  return r.result && r.result.result ? r.result.result.value : undefined
}
const evJson = async (x) => JSON.parse(await ev(x))
const sleep = (ms) => new Promise((r) => setTimeout(r, ms))
const down = (x, y) => send('Input.dispatchMouseEvent', { type: 'mousePressed', x: Math.round(x), y: Math.round(y), button: 'left', buttons: 1, clickCount: 1 })
const move = (x, y) => send('Input.dispatchMouseEvent', { type: 'mouseMoved', x: Math.round(x), y: Math.round(y), button: 'none', buttons: 1 })
const up = (x, y) => send('Input.dispatchMouseEvent', { type: 'mouseReleased', x: Math.round(x), y: Math.round(y), button: 'left', buttons: 0, clickCount: 1 })

await send('Page.enable')
await send('Runtime.enable')
await send('Emulation.setDeviceMetricsOverride', { width: VW, height: VH, deviceScaleFactor: 1, mobile: false })
await send('Page.navigate', { url: baseUrl + '/' })
await sleep(5000)

const out = { baseUrl, viewport: { w: VW, h: VH }, consoleIssues: null }
try {
  const meta = await (await fetch(baseUrl + '/api/local/console')).json()
  out.orderPath = meta?.data?.orderPath ?? null
} catch (e) { out.orderPath = null }
const readOrderFile = () => (out.orderPath && existsSync(out.orderPath)) ? readFileSync(out.orderPath, 'utf8').trim() : null
out.orderFileBefore = readOrderFile()

const readCards = () => evJson(`JSON.stringify([...document.querySelectorAll('.dsh-case')].map((c) => { const r = c.getBoundingClientRect(); return { row: c.getAttribute('data-row'), group: (c.closest('[data-name="row-group"]') || {}).getAttribute ? c.closest('[data-name="row-group"]').getAttribute('data-group') : null, x: r.x, y: r.y, w: r.width, h: r.height } }))`)
const readToast = () => evJson(`(() => {
  const t = document.querySelector('[data-name="flash-toast"] .dsh-toast-text')
  const err = document.querySelector('[data-name="action-notice"] .dsh-notice-text')
  if (!t) return JSON.stringify({ text: null, title: null, err: err ? err.textContent : null })
  const r = t.getBoundingClientRect()
  return JSON.stringify({ text: t.textContent, title: t.getAttribute('title'), err: null, rect: { x: +r.x.toFixed(1), y: +r.y.toFixed(1), w: +r.width.toFixed(1), h: +r.height.toFixed(1) } })
})()`)

const cards = await readCards()
const group = cards.filter((c) => c.group === 'stopped')
const src = group[0], dst = group[group.length - 1]
out.drag = { group: 'stopped', from: src.row, to: dst.row, orderBefore: await evJson('JSON.stringify([...document.querySelectorAll("[data-name=\\"row-group\\"]")].map((g) => ({ group: g.getAttribute("data-group"), rows: [...g.querySelectorAll(".dsh-case")].map((c) => c.getAttribute("data-row")) })))') }
if (!src || !dst) throw new Error('没有可拖的两条（隔离实例里的读数对吗？）')

await down(src.x + src.w / 2, src.y + src.h / 2)
await sleep(150)
for (let i = 1; i <= 8; i++) {
  const x = src.x + src.w / 2 + (dst.x + dst.w / 2 - src.x - src.w / 2) * (i / 8)
  const y = src.y + src.h / 2 + (dst.y + dst.h * 0.8 - src.y - src.h / 2) * (i / 8)
  await move(x, y)
  await sleep(70)
}
await sleep(300)
await up(dst.x + dst.w / 2, dst.y + dst.h * 0.8)
await sleep(1500)
out.toast = await readToast()
out.orderFileAfter = readOrderFile()
if (out.toast && out.toast.rect) {
  const r = out.toast.rect
  const clip = { x: Math.max(0, r.x - 16), y: Math.max(0, r.y - 16), width: r.w + 32, height: r.h + 32, scale: 2 }
  const s = await send('Page.captureScreenshot', { format: 'png', clip })
  writeFileSync(here + prefix + '.png', Buffer.from(s.result.data, 'base64'))
  out.shot = prefix + '.png'
  // 悬停里那段（title 只在悬停时可见）：把鼠标移到 toast 上再拍一张，顺带读一次 DOM 里的 title
  await send('Input.dispatchMouseEvent', { type: 'mouseMoved', x: Math.round(r.x + r.w / 2), y: Math.round(r.y + r.h / 2), button: 'none', buttons: 0 })
  await sleep(400)
  out.toastAfterHover = await readToast()
  const s2 = await send('Page.captureScreenshot', { format: 'png', clip })
  writeFileSync(here + prefix + '-hover.png', Buffer.from(s2.result.data, 'base64'))
  out.shotHover = prefix + '-hover.png'
}
out.consoleIssues = consoleIssues
writeFileSync(here + prefix + '.json', JSON.stringify(out, null, 1))

console.log('隔离实例: ' + baseUrl + '，order.json = ' + out.orderPath)
console.log('拖前顺序: ' + JSON.stringify(out.drag.orderBefore))
console.log('提示正文: ' + JSON.stringify(out.toast ? out.toast.text : null))
console.log('提示悬停(title): ' + JSON.stringify(out.toast ? out.toast.title : null))
console.log('失败提示条: ' + JSON.stringify(out.toast ? out.toast.err : null))
console.log('order.json 拖后: ' + out.orderFileAfter)
console.log('截图: ' + out.shot + ' / ' + out.shotHover)
console.log('控制台问题: ' + (consoleIssues.length ? consoleIssues.join(' | ') : '无'))

ws.close()
try { chrome.kill() } catch (e) {}
process.exit(0)

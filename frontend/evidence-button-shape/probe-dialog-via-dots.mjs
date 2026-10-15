// 已停止卡的对话框链路复核：点 ⋯ → 重命名 → 量居中/层级 → 取消关 / 点遮罩关。
// 与 design/probe-dialog.mjs 同一套判定，只有一处不同：入口选择器用 [aria-haspopup="menu"]，
// 不再靠 '第二个按钮'（改后第二个按钮是「重启」）。
//
//   node probe-dialog-via-dots.mjs <baseUrl> <outPrefix>
import { spawn } from 'node:child_process'
import { writeFileSync } from 'node:fs'

const CDP_PORT = 9300 + (process.pid % 600)
const [baseUrl, outPrefix] = process.argv.slice(2)
const chrome = spawn('chromium', ['--headless', '--no-sandbox', '--disable-gpu', '--disable-extensions',
  '--hide-scrollbars', '--remote-debugging-port=' + CDP_PORT, '--user-data-dir=/tmp/chrome-dlg-' + process.pid,
  '--window-size=1440,1000', 'about:blank'], { stdio: 'ignore' })
let page = null
for (let i = 0; i < 40 && !page; i++) {
  try { const l = await (await fetch('http://127.0.0.1:' + CDP_PORT + '/json')).json(); page = l.find((t) => t.type === 'page') } catch {}
  if (!page) await new Promise((r) => setTimeout(r, 250))
}
const ws = new WebSocket(page.webSocketDebuggerUrl)
let id = 0
const pend = new Map()
ws.onmessage = (e) => { const m = JSON.parse(e.data); if (m.id && pend.has(m.id)) { pend.get(m.id)(m); pend.delete(m.id) } }
await new Promise((r) => { ws.onopen = r })
const send = (method, params = {}) => new Promise((res) => { const i = ++id; pend.set(i, res); ws.send(JSON.stringify({ id: i, method, params })) })
const ev = async (e) => { const r = await send('Runtime.evaluate', { expression: e, returnByValue: true, awaitPromise: true }); if (r.result?.exceptionDetails) return 'EXC ' + String(r.result.exceptionDetails.exception?.description).slice(0, 200); return r.result?.result?.value }
const wait = (ms) => new Promise((r) => setTimeout(r, ms))
const realClick = async (x, y) => { for (const type of ['mousePressed', 'mouseReleased']) await send('Input.dispatchMouseEvent', { type, x, y, button: 'left', clickCount: 1 }) }
await send('Page.enable'); await send('Runtime.enable')
await send('Emulation.setDeviceMetricsOverride', { width: 1440, height: 1000, deviceScaleFactor: 1, mobile: false })
await send('Page.navigate', { url: baseUrl }); await wait(4500)

// 入口：已停止卡的行尾 ⋯（真鼠标点）
const t = JSON.parse(await ev(`(() => {
  const c = [...document.querySelectorAll('[data-name="instance-card"]')].find((e) => e.querySelector('[data-name="sub-line"][data-status="stopped"]'))
  const b = c && c.querySelector('[aria-haspopup="menu"]')
  if (!b) return JSON.stringify({ diag: 'no-trigger' })
  const r = b.getBoundingClientRect()
  return JSON.stringify({ name: (c.querySelector('.dsh-name') || {}).textContent.trim(), cls: String(b.className), cx: r.x + r.width / 2, cy: r.y + r.height / 2 })
})()`))
const out = { baseUrl, trigger: t }
if (t.diag) { console.log('入口没取到: ' + JSON.stringify(t)); chrome.kill(); process.exit(1) }

const openRename = async () => {
  await realClick(t.cx, t.cy)
  await wait(700)
  const menuOpen = await ev("!!document.querySelector('[data-name=\"row-menu\"]')")
  const clicked = await ev(`(() => { const it = [...document.querySelectorAll('[data-name="row-menu"] [role=menuitem]')].find((e) => e.textContent.trim() === '重命名'); if (!it) return 'no-item'; it.click(); return 'clicked' })()`)
  await wait(800)
  return { menuOpen, clicked, dialog: await ev("!!document.querySelector('.dsh-dialog-card')") }
}
out.open1 = await openRename()
out.geometry = JSON.parse(await ev(`(() => {
  const dlg = document.querySelector('.dsh-dialog-card')
  if (!dlg) return JSON.stringify({ dialog: false })
  const r = dlg.getBoundingClientRect()
  const hit = document.elementFromPoint(r.x + r.width / 2, r.y + r.height / 2)
  const scrim = document.querySelector('.dsh-scrim')
  return JSON.stringify({
    dialog: true,
    rect: { x: +r.x.toFixed(1), y: +r.y.toFixed(1), w: +r.width.toFixed(1), h: +r.height.toFixed(1) },
    viewport: { vw: innerWidth, vh: innerHeight },
    centered: Math.abs((r.x + r.width / 2) - innerWidth / 2) < 8 && Math.abs((r.y + r.height / 2) - innerHeight / 2) < 8,
    hitInDialog: !!(hit && dlg.contains(hit)),
    scrimPresent: !!scrim,
    title: dlg.querySelector('.dsh-dialog-title')?.textContent.trim(),
    inputValue: dlg.querySelector('input')?.value,
  })
})()`))
await send('Page.captureScreenshot', { format: 'png' }).then((r) => { if (r.result?.data) writeFileSync(outPrefix + '-dialog.png', Buffer.from(r.result.data, 'base64')) })
// 取消关
out.closedByCancel = await ev(`(async () => {
  const wait = (ms) => new Promise((r) => setTimeout(r, ms))
  const cancel = [...document.querySelectorAll('.dsh-dialog-btn')].find((b) => b.textContent.trim() === '取消')
  if (!cancel) return 'no-cancel-btn'
  cancel.click(); await wait(700)
  return !document.querySelector('.dsh-dialog-card')
})()`)
// 再开一次，点遮罩关
out.open2 = await openRename()
out.closedByScrim = await ev(`(async () => {
  const wait = (ms) => new Promise((r) => setTimeout(r, ms))
  const scrim = document.querySelector('.dsh-scrim')
  if (!scrim) return 'no-scrim'
  scrim.click(); await wait(700)
  return !document.querySelector('.dsh-dialog-card')
})()`)
// 焦点回到触发元素（⋯）
out.focusBack = await ev(`(() => { const a = document.activeElement; return a ? (a.getAttribute('aria-haspopup') === 'menu' ? 'trigger' : a.tagName.toLowerCase() + '.' + String(a.className).slice(0, 30)) : null })()`)

writeFileSync(outPrefix + '.json', JSON.stringify(out, null, 1))
console.log(JSON.stringify(out, null, 1))
chrome.kill(); process.exit(0)

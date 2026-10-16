// 手动排序的探针：真指针事件（CDP Input.dispatchMouseEvent）按下一路拖到松开。
//
// node probe-drag-order.mjs <baseUrl> <outJson> [shotPrefix]
// 段落由 DRAG_SECTIONS 选（逗号分隔，缺省全跑）：
//   click     位移小于阈值的一次按下-松开 —— 应当开抽屉（拖动与点击不许打架）
//   drag      拖一次：贴落位提示、放下后的顺序、order.json 的实际内容
//   persist   刷新页面，顺序还在不在
//   narrow    360 宽下同样发一遍拖动：顺序必须不变
//   keyboard  Ctrl+↓ 换位
// 失败恢复那一趟用 DRAG_SECTIONS=drag 单独跑：把状态目录设成不可写即可。
import { spawn } from 'node:child_process'
import { writeFileSync, readFileSync, existsSync } from 'node:fs'

const CDP_PORT = 9300 + (process.pid % 600)
const [baseUrl, outJson, shotPrefix] = process.argv.slice(2)
const SECTIONS = (process.env.DRAG_SECTIONS || 'click,drag,persist,narrow,keyboard').split(',')
const VW = 1280, VH = 900
const chrome = spawn('chromium', ['--headless', '--no-sandbox', '--disable-gpu', '--disable-extensions',
  '--hide-scrollbars', '--remote-debugging-port=' + CDP_PORT, '--user-data-dir=/tmp/chrome-drag-' + process.pid,
  '--window-size=' + VW + ',' + VH, '--noerrdialogs', '--no-first-run', '--ozone-platform=headless',
  '--ozone-override-screen-size=800,600', '--use-angle=swiftshader-webgl', 'about:blank'], { stdio: 'ignore' })

let page = null
for (let i = 0; i < 40 && !page; i++) {
  try { const list = await (await fetch('http://127.0.0.1:' + CDP_PORT + '/json')).json(); page = list.find((t) => t.type === 'page') } catch {}
  if (!page) await new Promise((r) => setTimeout(r, 250))
}
if (!page) { console.log(JSON.stringify({ ok: false, error: 'chrome 没起来' })); process.exit(1) }
const ws = new WebSocket(page.webSocketDebuggerUrl)
let id = 0
const pending = new Map()
ws.onmessage = (e) => { const m = JSON.parse(e.data); if (m.id && pending.has(m.id)) { pending.get(m.id)(m); pending.delete(m.id) } }
await new Promise((r) => { ws.onopen = r })
const send = (method, params = {}) => new Promise((res) => { const i = ++id; pending.set(i, res); ws.send(JSON.stringify({ id: i, method, params })) })
const ev = async (expression) => { const r = await send('Runtime.evaluate', { expression, returnByValue: true, awaitPromise: true }); return r.result?.result?.value }
const wait = (ms) => new Promise((r) => setTimeout(r, ms))
await send('Page.enable'); await send('Runtime.enable')
await send('Emulation.setDeviceMetricsOverride', { width: VW, height: VH, deviceScaleFactor: 1, mobile: false })
await send('Page.navigate', { url: baseUrl })
await wait(5000)

// 真指针：按下 / 移动 / 松开。形状照 Puppeteer 的 mouse 走（move 用 button:none + buttons:1）
const down = (x, y) => send('Input.dispatchMouseEvent', { type: 'mousePressed', x: Math.round(x), y: Math.round(y), button: 'left', buttons: 1, clickCount: 1 })
const move = (x, y) => send('Input.dispatchMouseEvent', { type: 'mouseMoved', x: Math.round(x), y: Math.round(y), button: 'none', buttons: 1 })
const up = (x, y) => send('Input.dispatchMouseEvent', { type: 'mouseReleased', x: Math.round(x), y: Math.round(y), button: 'left', buttons: 0, clickCount: 1 })
// 没按键的划过：用来验「松手之后不许还在拖」
const hover = (x, y) => send('Input.dispatchMouseEvent', { type: 'mouseMoved', x: Math.round(x), y: Math.round(y), button: 'none', buttons: 0 })

const readOrder = () => ev(`JSON.stringify([...document.querySelectorAll('[data-name="row-group"]')].map((g) => ({ group: g.getAttribute('data-group'), rows: [...g.querySelectorAll('.dsh-case')].map((c) => c.getAttribute('data-row')) })))`).then((s) => JSON.parse(s || '[]'))
const readCards = () => ev(`JSON.stringify([...document.querySelectorAll('.dsh-case')].map((c) => { const r = c.getBoundingClientRect(); return { row: c.getAttribute('data-row'), group: (c.closest('[data-name="row-group"]') || {}).getAttribute ? c.closest('[data-name="row-group"]').getAttribute('data-group') : null, x: r.x, y: r.y, w: r.width, h: r.height } }))`).then((s) => JSON.parse(s || '[]'))
const readIndicator = () => ev(`(() => {
  const el = document.querySelector('.dsh-case.drop-before, .dsh-case.drop-after')
  const dragging = document.querySelector('.dsh-case.dragging')
  if (!el) return JSON.stringify({ present: false, dragging: !!dragging })
  const cs = getComputedStyle(el, '::after')
  return JSON.stringify({ present: true, row: el.getAttribute('data-row'), cls: el.className,
    dragging: !!dragging, draggingRow: dragging ? dragging.getAttribute('data-row') : null,
    content: cs.content, height: cs.height, background: cs.backgroundColor, top: cs.top, bottom: cs.bottom, left: cs.left, right: cs.right })
})()`).then((s) => JSON.parse(s || '{}'))
const readNotice = () => ev(`JSON.stringify({ err: (document.querySelector('[data-name="action-notice"] .dsh-notice-text') || {}).textContent || null, toast: (document.querySelector('[data-name="flash-toast"] .dsh-toast-text') || {}).textContent || null, drawer: !!document.querySelector('.dsh-drawer') })`).then((s) => JSON.parse(s || '{}'))
const shot = async (p) => { const s = await send('Page.captureScreenshot', { format: 'png' }); writeFileSync(p, Buffer.from(s.result.data, 'base64')) }

const report = { url: baseUrl, sections: SECTIONS }
const orderPath = await (async () => {
  try { const j = await (await fetch(baseUrl.replace(/\/$/, '') + '/api/local/console')).json(); return j?.data?.orderPath ?? null } catch { return null }
})()
report.orderPath = orderPath
const readOrderFile = () => (orderPath && existsSync(orderPath)) ? readFileSync(orderPath, 'utf8').trim() : null
report.orderFileBefore = readOrderFile()

// ── click：位移 0，应当开抽屉 ──
if (SECTIONS.includes('click')) {
  const before = await readOrder()
  const cards = await readCards()
  const target = cards.filter((c) => c.group === 'stopped')[1] || cards[1]
  await down(target.x + target.w / 2, target.y + target.h / 2)
  await wait(120)
  await up(target.x + target.w / 2, target.y + target.h / 2)
  await wait(900)
  const n = await readNotice()
  report.click = { target: target.row, orderBefore: before, orderAfter: await readOrder(), drawerOpen: n.drawer }
  await send('Input.dispatchKeyEvent', { type: 'rawKeyDown', key: 'Escape', code: 'Escape', windowsVirtualKeyCode: 27 })
  await send('Input.dispatchKeyEvent', { type: 'keyUp', key: 'Escape', code: 'Escape', windowsVirtualKeyCode: 27 })
  await wait(600)
}

// ── drag：把已停止组的第一条拖到最后一条下面 ──
if (SECTIONS.includes('drag')) {
  const cards = await readCards()
  const group = cards.filter((c) => c.group === 'stopped')
  const src = group[0], dst = group[group.length - 1]
  report.drag = { group: 'stopped', from: src.row, to: dst.row, orderBefore: await readOrder(), steps: [] }
  if (shotPrefix) await shot(shotPrefix + '-before.png')
  await down(src.x + src.w / 2, src.y + src.h / 2)
  await wait(150)
  // 分几步走完，中途至少有一拍能看见落位提示
  for (let i = 1; i <= 8; i++) {
    const x = src.x + src.w / 2 + (dst.x + dst.w / 2 - src.x - src.w / 2) * (i / 8)
    const y = src.y + src.h / 2 + (dst.y + dst.h * 0.8 - src.y - src.h / 2) * (i / 8)
    await move(x, y)
    await wait(70)
  }
  await wait(350)
  report.drag.indicator = await readIndicator()
  if (shotPrefix) await shot(shotPrefix + '-indicator.png')
  await up(dst.x + dst.w / 2, dst.y + dst.h * 0.8)
  await wait(1400)
  report.drag.orderAfter = await readOrder()
  report.drag.orderFileAfter = readOrderFile()
  report.drag.notice = await readNotice()
  if (shotPrefix) await shot(shotPrefix + '-after.png')
}

// ── stuck：拖到列表之外松手，之后划过列表不许还画着落位线 ──
if (SECTIONS.includes('stuck')) {
  const cards = await readCards()
  const group = cards.filter((c) => c.group === 'stopped')
  const src = group[0], other = group[1]
  const orderBefore = await readOrder()
  await down(src.x + src.w / 2, src.y + src.h / 2)
  await wait(150)
  // 先真拖到另一条上（落位提示出来），再把指针甩到列表之外
  await move(other.x + other.w / 2, other.y + other.h * 0.7)
  await wait(250)
  const duringDrag = await readIndicator()
  await move(src.x + src.w / 2, 820)
  await wait(250)
  const outsideDrag = await readIndicator()
  // 松手落在**列表之外**（页面下方的空白处）：组那一层收不到这一次抬起，
  // 靠外壳那一份 + 「位掩码为 0 就算松手」这两道保险
  await up(src.x + src.w / 2, 820)
  await wait(700)
  const afterRelease = await readIndicator()
  await hover(other.x + 20, other.y + 20)
  await wait(400)
  const afterHover = await readIndicator()
  report.stuck = { from: src.row, orderBefore, duringDrag, outsideDrag, afterRelease, afterHover, orderAfter: await readOrder(), notice: await readNotice() }
}

// ── persist：刷新之后顺序还在不在 ──
if (SECTIONS.includes('persist')) {
  const before = await readOrder()
  await send('Page.navigate', { url: baseUrl })
  await wait(5000)
  report.persist = { beforeReload: before, afterReload: await readOrder() }
}

// ── narrow：360 宽下再拖一遍，顺序不许变 ──
if (SECTIONS.includes('narrow')) {
  await send('Emulation.setDeviceMetricsOverride', { width: 360, height: 900, deviceScaleFactor: 1, mobile: false })
  await wait(1200)
  const cards = await readCards()
  const group = cards.filter((c) => c.group === 'stopped')
  const src = group[0], dst = group[group.length - 1]
  const before = await readOrder()
  await down(src.x + src.w / 2, src.y + src.h / 2)
  await wait(150)
  for (let i = 1; i <= 6; i++) {
    await move(src.x + src.w / 2, src.y + src.h / 2 + (dst.y + dst.h * 0.8 - src.y - src.h / 2) * (i / 6))
    await wait(70)
  }
  await wait(300)
  const indicator = await readIndicator()
  if (shotPrefix) await shot(shotPrefix + '-narrow.png')
  await up(dst.x + dst.w / 2, dst.y + dst.h * 0.8)
  await wait(1200)
  report.narrow = { viewport: 360, from: src.row, to: dst.row, orderBefore: before, orderAfter: await readOrder(), indicator, notice: await readNotice() }
  await send('Emulation.setDeviceMetricsOverride', { width: VW, height: VH, deviceScaleFactor: 1, mobile: false })
  await wait(1000)
}

// ── keyboard：Ctrl+↓ 换位 ──
if (SECTIONS.includes('keyboard')) {
  const cards = await readCards()
  const group = cards.filter((c) => c.group === 'stopped')
  const target = group[0]
  const before = await readOrder()
  await ev(`(() => { const el = document.querySelector('[data-row="' + ${JSON.stringify(target.row)} + '"]'); if (el) el.focus(); })()`)
  await wait(300)
  const focused = await ev('document.activeElement ? document.activeElement.getAttribute("data-row") : null')
  for (const type of ['rawKeyDown', 'keyUp']) {
    await send('Input.dispatchKeyEvent', { type, key: 'ArrowDown', code: 'ArrowDown', windowsVirtualKeyCode: 40, modifiers: 2 })
  }
  await wait(1400)
  report.keyboard = { row: target.row, focusedBefore: focused, orderBefore: before, orderAfter: await readOrder(), orderFileAfter: readOrderFile(), notice: await readNotice() }
  if (shotPrefix) await shot(shotPrefix + '-keyboard.png')
}

report.orderFileEnd = readOrderFile()
if (outJson) writeFileSync(outJson, JSON.stringify(report, null, 1))
console.log(JSON.stringify(report, null, 1))
chrome.kill()
process.exit(0)

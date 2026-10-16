// 抽屉那几条老行为在加了开合动画之后**一条都没退**的探针（第十一轮）。
//   node probe-drawer-behavior.mjs <baseUrl> [输出前缀]
//
// 逐条真跑一遍（真指针 / 真键盘）：
//   1. 点卡片开、焦点进关闭键、按钮都可达、宽屏 520 贴右
//   2. 点外部（遮罩）关：关完焦点回那张卡
//   3. 关闭键关：关完焦点回那张卡
//   4. Esc 关（时间线见 probe-drawer-motion.mjs）
//   5. **关闭动画还在跑的时候**：抽屉还在 DOM 里、但已经 pointer-events: none、
//      而且焦点已经在卡片上（这一条是本轮新加的时序要求）
//   6. 动画没走完又点一次卡片：抽屉重新打开，DOM 里**只有一个**抽屉节点（id 不撞）
//   7. 窄屏 360：抽屉占满整幅（宽 = 视口、x = 0），按钮照旧可达，Esc 照旧关得掉
import { spawn } from 'node:child_process'
import { writeFileSync } from 'node:fs'

const here = new URL('.', import.meta.url).pathname
const baseUrl = (process.argv[2] || 'http://127.0.0.1:5390/').replace(/\/$/, '')
const prefix = process.argv[3] || 'drawer-behavior'
const CDP_PORT = 9540 + (process.pid % 400)

const chrome = spawn('chromium', ['--headless', '--no-sandbox', '--disable-gpu', '--disable-extensions',
  '--hide-scrollbars', '--remote-debugging-port=' + CDP_PORT, '--user-data-dir=/tmp/chrome-beh-' + process.pid,
  '--window-size=1280,900', 'about:blank'], { stdio: 'ignore' })

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
const setViewport = (w, h) => send('Emulation.setDeviceMetricsOverride', { width: w, height: h, deviceScaleFactor: 1, mobile: false })
const click = async (x, y) => {
  await send('Input.dispatchMouseEvent', { type: 'mousePressed', x: Math.round(x), y: Math.round(y), button: 'left', buttons: 1, clickCount: 1 })
  await send('Input.dispatchMouseEvent', { type: 'mouseReleased', x: Math.round(x), y: Math.round(y), button: 'left', buttons: 0, clickCount: 1 })
}
const esc = async () => {
  await send('Input.dispatchKeyEvent', { type: 'keyDown', key: 'Escape', code: 'Escape', windowsVirtualKeyCode: 27 })
  await send('Input.dispatchKeyEvent', { type: 'keyUp', key: 'Escape', code: 'Escape', windowsVirtualKeyCode: 27 })
}
const SNAP = `(() => {
  const d = document.querySelector('.dsh-drawer')
  const ds = document.querySelectorAll('.dsh-drawer')
  const a = document.activeElement
  if (!d) return JSON.stringify({ open: false, drawerNodes: ds.length, active: a ? (a.id || a.tagName) : null })
  const r = d.getBoundingClientRect()
  const cs = getComputedStyle(d)
  const btns = [...d.querySelectorAll('button')]
  const reach = btns.map((b) => { const br = b.getBoundingClientRect(); const hit = document.elementFromPoint(br.x + br.width / 2, br.y + br.height / 2); return !!(hit && (hit === b || b.contains(hit))) })
  return JSON.stringify({
    open: true, drawerNodes: ds.length, state: d.getAttribute('data-state'),
    rect: { x: +r.x.toFixed(1), w: +r.width.toFixed(1), right: +r.right.toFixed(1) },
    vw: innerWidth, pointerEvents: cs.pointerEvents, anim: cs.animationName,
    buttonCount: btns.length, allReachable: btns.length > 0 && reach.every(Boolean),
    active: a ? (a.id || a.tagName) : null,
  })
})()`
const snap = () => evJson(SNAP)
const cardId = () => ev("(() => { const c = document.querySelector('.dsh-case'); return c ? c.id : null })()")
const clickCard = () => ev("(() => { const c = document.querySelector('.dsh-case'); if (!c) return 'no-card'; c.click(); return c.id })()")

await send('Page.enable')
await send('Runtime.enable')
const out = { baseUrl, steps: {}, consoleIssues: null }

const CARD = await cardId()
out.card = CARD

const run = async (tag, w, h) => {
  await setViewport(w, h)
  await send('Page.navigate', { url: baseUrl + '/' })
  await sleep(5000)
  const s = {}
  // 1. 点卡片开
  s.cardId = await clickCard()
  await sleep(500)
  s.openedByClick = await snap()
  // 2. 关闭动画还在跑的那一刻：抽屉还在、对指针关了、焦点已经回卡片
  await esc()
  await sleep(50)
  s.closingMidway = await snap()
  await sleep(700)
  s.afterEsc = await snap()
  // 3. 点外部（遮罩）关
  await clickCard()
  await sleep(500)
  const r0 = (await snap()).rect
  await click(120, 500)            // 抽屉左边那一大片 = 遮罩
  await sleep(700)
  s.afterScrimClick = await snap()
  // 4. 关闭键关
  await clickCard()
  await sleep(500)
  const closeBox = await evJson("(() => { const b = document.getElementById('dsh-drawer-close'); if (!b) return 'null'; const r = b.getBoundingClientRect(); return JSON.stringify({ x: +(r.x + r.width / 2).toFixed(1), y: +(r.y + r.height / 2).toFixed(1) }) })()" || 'null')
  s.closeButtonBox = closeBox
  if (closeBox) await click(closeBox.x, closeBox.y)
  await sleep(700)
  s.afterCloseButton = await snap()
  // 5. 收的那一段里又点一次卡片：重新打开，且 DOM 里只有一个抽屉
  await clickCard()
  await sleep(500)
  await esc()
  await sleep(60)
  await clickCard()
  await sleep(500)
  s.reopenDuringClosing = await snap()
  await esc()
  await sleep(700)
  s.afterReopenEsc = await snap()
  s.widthAtOpen = r0
  out.steps[tag] = s
}

await run('wide', 1280, 900)
await run('narrow', 360, 900)

out.consoleIssues = consoleIssues
writeFileSync(here + prefix + '.json', JSON.stringify(out, null, 1))

const show = (s) => JSON.stringify(s)
for (const tag of Object.keys(out.steps)) {
  const s = out.steps[tag]
  console.log('--- ' + tag + ' ---')
  console.log('  点卡片开        : ' + show(s.openedByClick) + '（卡片 ' + s.cardId + '）')
  console.log('  关的中途(50ms)  : ' + show(s.closingMidway))
  console.log('  Esc 之后        : ' + show(s.afterEsc))
  console.log('  点外部之后      : ' + show(s.afterScrimClick))
  console.log('  点关闭键之后    : ' + show(s.afterCloseButton) + '（关闭键 ' + JSON.stringify(s.closeButtonBox) + '）')
  console.log('  收的中途又开    : ' + show(s.reopenDuringClosing))
  console.log('  再 Esc 之后     : ' + show(s.afterReopenEsc))
}
console.log('--- 控制台问题 ---')
console.log('  ' + (consoleIssues.length ? consoleIssues.join(' | ') : '无'))

ws.close()
try { chrome.kill() } catch (e) {}
process.exit(0)

// 详情抽屉开合那一段的验收探针（第十一轮）。
//   node probe-drawer-motion.mjs <baseUrl> [输出前缀]
//
// 三趟，都在同一个浏览器会话里：
//   A 正常动效：点卡片开、Esc 关，**每 40ms 采一次**抽屉的 transform / x / opacity / 动画名 /
//     data-state / 焦点 —— 用来证明它是滑进滑出而不是瞬移，也用来证明
//     「关的那一段还在跑的时候，焦点已经回到卡片上了」。
//   B prefers-reduced-motion: reduce（CDP 模拟）：同一个查询下再走一遍 ——
//     不许有任何位移与淡入淡出（transform 恒为 none、opacity 恒为 1、无动画名），
//     开合本身照常（开得开、Esc 关得掉、节点当场撤）。
//   C 过程图：把动画播放速率调到 0.15 之后开 / 关各拍一张中途的帧
//     （**只影响截图这一趟**：A / B 两趟量的是真实时长下的数，播放速率最后调回 1）。
// 全部是 DOM 实测，不从截图里认数。
import { spawn } from 'node:child_process'
import { writeFileSync } from 'node:fs'

const here = new URL('.', import.meta.url).pathname
const baseUrl = (process.argv[2] || 'http://127.0.0.1:5390/').replace(/\/$/, '')
const prefix = process.argv[3] || 'drawer-motion'
const CDP_PORT = 9540 + (process.pid % 400)
const VW = 1280, VH = 900

const chrome = spawn('chromium', ['--headless', '--no-sandbox', '--disable-gpu', '--disable-extensions',
  '--hide-scrollbars', '--remote-debugging-port=' + CDP_PORT, '--user-data-dir=/tmp/chrome-motion-' + process.pid,
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
  if (r.result && r.result.exceptionDetails) throw new Error('eval 出错: ' + JSON.stringify(r.result.exceptionDetails).slice(0, 400))
  return r.result && r.result.result ? r.result.result.value : undefined
}
const evJson = async (expression) => JSON.parse(await ev(expression))
const sleep = (ms) => new Promise((r) => setTimeout(r, ms))
const shot = async (name) => {
  const s = await send('Page.captureScreenshot', { format: 'png' })
  writeFileSync(here + name, Buffer.from(s.result.data, 'base64'))
  return name
}
const esc = async () => {
  await send('Input.dispatchKeyEvent', { type: 'keyDown', key: 'Escape', code: 'Escape', windowsVirtualKeyCode: 27 })
  await send('Input.dispatchKeyEvent', { type: 'keyUp', key: 'Escape', code: 'Escape', windowsVirtualKeyCode: 27 })
}

// 页面里的采样器：每 40ms 记一格。t 是相对 __recStart() 的毫秒数。
const REC = `(() => {
  window.__rec = { t0: 0, samples: [] }
  window.__recStart = () => { window.__rec.t0 = performance.now(); window.__rec.samples = [] }
  window.__recSample = () => {
    const d = document.querySelector('.dsh-drawer')
    const s = document.querySelector('.dsh-drawer-scrim')
    const dc = d ? getComputedStyle(d) : null
    const sc = s ? getComputedStyle(s) : null
    const a = document.activeElement
    window.__rec.samples.push({
      t: Math.round(performance.now() - window.__rec.t0),
      drawer: !!d,
      state: d ? d.getAttribute('data-state') : null,
      x: d ? +d.getBoundingClientRect().x.toFixed(1) : null,
      w: d ? +d.getBoundingClientRect().width.toFixed(1) : null,
      opacity: dc ? +(+dc.opacity).toFixed(3) : null,
      transform: dc ? dc.transform : null,
      anim: dc ? dc.animationName : null,
      pointerEvents: dc ? dc.pointerEvents : null,
      scrimOpacity: sc ? +(+sc.opacity).toFixed(3) : null,
      active: a ? (a.id || a.tagName) : null,
    })
  }
  if (!window.__recTimer) window.__recTimer = setInterval(() => { if (window.__rec) window.__recSample() }, 40)
  return 'ok'
})()`

const samples = () => evJson('JSON.stringify(window.__rec.samples)')
const openDrawer = () => ev(`(() => { const c = document.querySelector('.dsh-case'); if (!c) return 'no-card'; c.click(); return c.id })()`)
const drawerPresent = () => ev("!!document.querySelector('.dsh-drawer')")
const activeId = () => ev("document.activeElement ? (document.activeElement.id || document.activeElement.tagName) : null")

await send('Page.enable')
await send('Runtime.enable')
await send('Emulation.setDeviceMetricsOverride', { width: VW, height: VH, deviceScaleFactor: 1, mobile: false })
await send('Page.navigate', { url: baseUrl + '/' })
await sleep(5000)
await ev(REC)

const out = { baseUrl, viewport: { w: VW, h: VH }, card: null, normal: {}, reduce: {}, shots: {}, consoleIssues: null }

// ── A 正常动效 ──
out.card = await openDrawer()   // 第一次点只是为了拿到卡 id，随后关掉重来
await sleep(700)
await esc()
await sleep(500)

await ev('window.__recStart()')
await openDrawer()
await sleep(700)
out.normal.open = await samples()
const openRect = await ev("(() => { const d = document.querySelector('.dsh-drawer'); if (!d) return null; const r = d.getBoundingClientRect(); return JSON.stringify({ x: +r.x.toFixed(1), w: +r.width.toFixed(1), right: +r.right.toFixed(1) }) })()")
out.normal.openEndRect = JSON.parse(openRect || 'null')

await ev('window.__recStart()')
await esc()
await sleep(700)
out.normal.close = await samples()
out.normal.afterClose = { drawerPresent: await drawerPresent(), active: await activeId() }

// ── B prefers-reduced-motion: reduce ──
await send('Emulation.setEmulatedMedia', { features: [{ name: 'prefers-reduced-motion', value: 'reduce' }] })
await sleep(300)
out.reduce.mediaMatches = await ev("window.matchMedia('(prefers-reduced-motion: reduce)').matches")

await ev('window.__recStart()')
await openDrawer()
await sleep(500)
out.reduce.open = await samples()
out.reduce.openStillOpen = await drawerPresent()

await ev('window.__recStart()')
await esc()
await sleep(500)
out.reduce.close = await samples()
out.reduce.afterClose = { drawerPresent: await drawerPresent(), active: await activeId() }

// 关掉模拟，回到正常动效
await send('Emulation.setEmulatedMedia', { features: [] })
await sleep(300)
out.mediaAfterReset = await ev("window.matchMedia('(prefers-reduced-motion: reduce)').matches")

// ── C 过程图（把播放速率调慢，只影响这两张图）──
//
// 为什么要调慢：截图本身要几十毫秒，真时长下很容易拍到动画之前或之后。
// **只影响这一趟**：A / B 两趟量的是真实时长下的数（播放速率最后调回 1）。
// 调 0.4 不是 0.15：收的那一段里，**撤节点的计时是 JS 的墙上时间**（drawer_anim_ms=220ms），
// 不受播放速率影响 —— 调得太慢，动画还没走多少节点就被撤了，拍不到在途的那一帧。
// 每张图都记下**拍之前 / 拍之后**抽屉的 x：两个数都在 [760, 1280) 之间才叫"拍到在途"。
await send('Animation.enable')
await send('Animation.setPlaybackRate', { playbackRate: 0.4 })
out.shots.playbackRate = 0.4
const rectOf = async () => JSON.parse(await ev("(() => { const d = document.querySelector('.dsh-drawer'); if (!d) return 'null'; const r = d.getBoundingClientRect(); return JSON.stringify({ x: +r.x.toFixed(1), w: +r.width.toFixed(1), opacity: +(+getComputedStyle(d).opacity).toFixed(3) }) })()") || 'null')
await ev('window.__recStart()')
await openDrawer()
await sleep(250)
out.shots.openMidBefore = await rectOf()
out.shots.openMid = await shot(prefix + '-open-mid.png')
out.shots.openMidAfter = await rectOf()
await sleep(1600)
await ev('window.__recStart()')
await esc()
await sleep(110)
out.shots.closeMidBefore = await rectOf()
out.shots.closeMid = await shot(prefix + '-close-mid.png')
out.shots.closeMidAfter = await rectOf()
await send('Animation.setPlaybackRate', { playbackRate: 1 })
await sleep(600)
out.shots.afterShotsDrawerGone = !(await drawerPresent())

out.consoleIssues = consoleIssues
writeFileSync(here + prefix + '.json', JSON.stringify(out, null, 1))

// ── 摘要 ──
const line = (s) => 't=' + String(s.t).padStart(4) + 'ms drawer=' + (s.drawer ? 'y' : 'n') +
  ' state=' + String(s.state) + ' x=' + String(s.x) + ' opacity=' + String(s.opacity) +
  ' anim=' + String(s.anim) + ' scrim=' + String(s.scrimOpacity) + ' active=' + String(s.active)
const brief = (arr) => arr.map(line).join('\n    ')
console.log('卡片: ' + out.card)
console.log('--- A 正常动效 · 开（点卡片）---')
console.log('    ' + brief(out.normal.open))
console.log('    开完的矩形: ' + JSON.stringify(out.normal.openEndRect))
console.log('--- A 正常动效 · 关（Esc）---')
console.log('    ' + brief(out.normal.close))
console.log('    关完: ' + JSON.stringify(out.normal.afterClose))
console.log('--- B reduced-motion: reduce（matchMedia=' + out.reduce.mediaMatches + '） · 开 ---')
console.log('    ' + brief(out.reduce.open))
console.log('    还开着: ' + out.reduce.openStillOpen)
console.log('--- B reduced-motion: reduce · 关 ---')
console.log('    ' + brief(out.reduce.close))
console.log('    关完: ' + JSON.stringify(out.reduce.afterClose) + ' 复位后 matchMedia=' + out.mediaAfterReset)
console.log('--- C 过程图（播放速率 ' + out.shots.playbackRate + '）---')
console.log('    开的中途: 拍前 ' + JSON.stringify(out.shots.openMidBefore) + ' 拍后 ' + JSON.stringify(out.shots.openMidAfter) + ' → ' + out.shots.openMid)
console.log('    关的中途: 拍前 ' + JSON.stringify(out.shots.closeMidBefore) + ' 拍后 ' + JSON.stringify(out.shots.closeMidAfter) + ' → ' + out.shots.closeMid)
console.log('    截完抽屉已撤: ' + out.shots.afterShotsDrawerGone)
console.log('--- 控制台问题 ---')
console.log('  ' + (consoleIssues.length ? consoleIssues.join(' | ') : '无'))

ws.close()
try { chrome.kill() } catch (e) {}
process.exit(0)

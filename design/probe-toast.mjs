// toast 探针：node probe-toast.mjs <baseUrl> <mode> <outJson>
//   mode = success  点一次会成功的动作（归档），按 250ms 采样提示文本，看它 4 秒后自己消失
//   mode = hover    同 success，但中途把鼠标停到 toast 上，看它不消失；移开之后再消失
//   mode = failure  点一次会失败的动作（重命名撞名），采样 8 秒，看它**不**自动消失
//
// 采样走 CDP 的 Runtime.evaluate：拿到的是页面里真实的文本与不透明度，不是猜的。
import { spawn } from 'node:child_process'
import { writeFileSync } from 'node:fs'

const CDP_PORT = 9300 + (process.pid % 600)
const [baseUrl, mode, outJson] = process.argv.slice(2)
const chrome = spawn('chromium', ['--headless', '--no-sandbox', '--disable-gpu', '--disable-extensions',
  '--hide-scrollbars', '--remote-debugging-port=' + CDP_PORT, '--user-data-dir=/tmp/chrome-toast-' + process.pid,
  '--window-size=1280,900', '--noerrdialogs', '--no-first-run', '--ozone-platform=headless',
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
const ev = async (expression) => {
  const r = await send('Runtime.evaluate', { expression, returnByValue: true })
  if (r.result?.exceptionDetails) console.log('EVAL ERROR: ' + JSON.stringify(r.result.exceptionDetails).slice(0, 300))
  return r.result?.result?.value
}
const sleep = (ms) => new Promise((r) => setTimeout(r, ms))
await send('Page.enable')
await send('Emulation.setDeviceMetricsOverride', { width: 1280, height: 900, deviceScaleFactor: 1, mobile: false })
await send('Page.navigate', { url: baseUrl })
await sleep(5000)

const SAMPLE = String.raw`(() => {
  const t = document.querySelector('[data-name="flash-toast"]')
  const e = document.querySelector('[data-name="action-notice"]')
  const pick = (n) => n ? {
    text: n.innerText.trim(),
    opacity: getComputedStyle(n).opacity,
    cls: n.className,
    rect: (() => { const r = n.getBoundingClientRect(); return { x: +r.x.toFixed(1), y: +r.y.toFixed(1), w: +r.width.toFixed(1), h: +r.height.toFixed(1) } })(),
  } : null
  return JSON.stringify({ toast: pick(t), notice: pick(e) })
})()`

const sample = async () => JSON.parse(await ev(SAMPLE) || '{}')

// 采样器：每 interval 毫秒取一次，记下相对开始时刻的毫秒数
// t0Base 是「这一轮动作开始」的时刻（时间线上的 0）；循环长度从**本段自己的**开始时刻算 ——
// 两段连着采的时候，用同一个 t0 判长度会让第二段一秒都不采（真踩过）
const sampler = async (durationMs, intervalMs, label, t0Base) => {
  const rows = []
  const start = Date.now()
  while (Date.now() - start < durationMs) {
    const s = await sample()
    rows.push({ t: Date.now() - t0Base, label, ...s })
    await sleep(intervalMs)
  }
  return rows
}

// 归档会写隔离状态目录里的 archive.json：每一次跑之前先取消归档，好让「归档」这条路是干净的
const callApi = async (action, profile) => ev(`(async () => {
  const r = await fetch('/api/local/action', { method: 'POST', headers: { 'content-type': 'application/json', 'X-DSH-Console': '1' },
    body: JSON.stringify({ action: ${JSON.stringify(action)}, params: { profile: ${JSON.stringify(profile)} } }) })
  return r.status
})()`)

const openMenuOf = async (cardIndex) => {
  await ev(`(() => { const c = document.querySelectorAll('.dsh-case')[${cardIndex}]; const t = c.querySelector('[data-name=menu-trigger]'); t.click(); return 'ok' })()`)
  await sleep(600)
}
const clickMenuItem = async (action) => ev(`(() => {
  const it = document.querySelector('[data-name=row-menu] [data-action=' + ${JSON.stringify(action)} + ']')
  if (!it) return 'missing'
  it.click(); return 'clicked'
})()`)

const result = { baseUrl, mode }
// 归档路径的先决条件：把两只 profile 的归档记录清掉（只动隔离状态目录）
await callApi('unarchive-profile', 'alpha')
await callApi('unarchive-profile', 'beta')

if (mode === 'success' || mode === 'hover') {
  const cards = JSON.parse(await ev(String.raw`JSON.stringify([...document.querySelectorAll('.dsh-case')].map((c,i)=>({i, name: c.querySelector('.dsh-name').textContent.trim(), status: c.querySelector('.dsh-sub').dataset.status})))`) || '[]')
  const idx = JSON.parse(await ev(String.raw`JSON.stringify([...document.querySelectorAll('.dsh-case')].map((c,i)=>({i, hasArchive: !!c.querySelector('[data-name=menu-trigger]')})).filter(x=>x.hasArchive).map(x=>x.i))`) || '[]')
  // 找到第一张「已停止」的卡（它的菜单里才有归档）
  const stopped = cards.filter((c) => c.status === 'stopped')
  result.cards = cards
  const target = stopped[0]
  result.target = target
  await openMenuOf(target.i)
  const clicked = await clickMenuItem('archive')
  result.clicked = clicked
  const t0 = Date.now()
  if (mode === 'success') {
    result.timeline = await sampler(7000, 250, 'sample', t0)
  } else {
    // 1.2 秒后把鼠标挪到 toast 上（用真实鼠标事件，走的是页面里那些监听器）
    await sleep(1200)
    const box = await ev(String.raw`(() => { const t = document.querySelector('[data-name="flash-toast"]'); if (!t) return ''; const r = t.getBoundingClientRect(); return JSON.stringify({ x: r.x + r.width/2, y: r.y + r.height/2 }) })()`)
    result.toastBox = box
    const p = JSON.parse(box || '{}')
    if (p.x) await send('Input.dispatchMouseEvent', { type: 'mouseMoved', x: p.x, y: p.y, buttons: 0 })
    result.timelineHover = await sampler(5000, 250, 'hover-on', t0)
    // 移开：再采 5 秒，看它是不是就自己走了
    await send('Input.dispatchMouseEvent', { type: 'mouseMoved', x: 5, y: 400, buttons: 0 })
    result.timelineAfterLeave = await sampler(5000, 250, 'hover-off', t0)
  }
} else if (mode === 'failure') {
  // 重命名撞名：把 beta 改成 alpha（隔离目录里已存在），后端会给 conflict
  const cards = JSON.parse(await ev(String.raw`JSON.stringify([...document.querySelectorAll('.dsh-case')].map((c,i)=>({i, name: c.querySelector('.dsh-name').textContent.trim(), status: c.querySelector('.dsh-sub').dataset.status})))`) || '[]')
  result.cards = cards
  const target = cards.find((c) => c.name === 'beta') || cards.find((c) => c.status === 'stopped')
  result.target = target
  await openMenuOf(target.i)
  result.clicked = await clickMenuItem('rename')
  await sleep(700)
  await ev(String.raw`(() => {
    const input = document.querySelector('[data-name="rename-input"]')
    if (!input) return 'no-input'
    input.focus(); input.select()
    return 'focused'
  })()`)
  await send('Input.insertText', { text: 'alpha' })
  await sleep(400)
  await ev(String.raw`(() => { const b = document.querySelector('[data-name="rename-dialog"] [data-name="dialog-ok"]') || document.querySelectorAll('.dsh-dialog-card button')[0]; if (!b) return 'no-ok'; b.click(); return 'ok' })()`)
  const t0 = Date.now()
  result.timeline = await sampler(8000, 250, 'sample', t0)
}
if (outJson) writeFileSync(outJson, JSON.stringify(result, null, 1))
// 控制台输出只留一条时间线摘要，便于直接贴
const tl = result.timeline || result.timelineHover
if (tl) {
  const first = tl.find((r) => (r.toast && r.toast.text) || (r.notice && r.notice.text))
  const last = [...tl].reverse().find((r) => (r.toast && r.toast.text) || (r.notice && r.notice.text))
  console.log('第一条出现 t=' + (first ? first.t : null) + 'ms 文本=' + JSON.stringify(first ? (first.toast ? first.toast.text : first.notice.text).slice(0, 60) : null))
  console.log('最后一条还在 t=' + (last ? last.t : null) + 'ms')
  console.log('采样尾：' + JSON.stringify(tl.slice(-8).map((r) => ({ t: r.t, toast: r.toast ? r.toast.text.slice(0, 12) : null, op: r.toast ? r.toast.opacity : null, notice: r.notice ? r.notice.text.slice(0, 12) : null }))))
}
chrome.kill()
process.exit(0)

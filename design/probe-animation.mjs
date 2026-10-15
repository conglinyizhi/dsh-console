const CDP_PORT = 9300 + (process.pid % 600) // 按进程取，并行跑不抢端口
// 动效探针（选择器无关）：node probe-animation.mjs <baseUrl> <outJson> [按钮文字]
// 点「启动」让卡片进入启动等待态，然后扫描全页哪些元素在跑动画。
import { spawn } from 'node:child_process'
import { writeFileSync } from 'node:fs'
const [baseUrl, outJson, btnText = '启动'] = process.argv.slice(2)

const chrome = spawn('chromium', ['--headless', '--no-sandbox', '--disable-gpu', '--disable-extensions',
  '--hide-scrollbars', '--remote-debugging-port=' + CDP_PORT, '--user-data-dir=/tmp/chrome-probe-' + process.pid,
  '--window-size=1280,900', 'about:blank'], { stdio: 'ignore' })
let page = null
for (let i = 0; i < 40 && !page; i++) {
  try { const l = await (await fetch('http://127.0.0.1:' + CDP_PORT + '/json')).json(); page = l.find((t) => t.type === 'page') } catch {}
  if (!page) await new Promise((r) => setTimeout(r, 250))
}
const ws = new WebSocket(page.webSocketDebuggerUrl)
let id = 0
const pending = new Map()
ws.onmessage = (e) => { const m = JSON.parse(e.data); if (m.id && pending.has(m.id)) { pending.get(m.id)(m); pending.delete(m.id) } }
await new Promise((r) => { ws.onopen = r })
const send = (method, params = {}) => new Promise((res) => { const i = ++id; pending.set(i, res); ws.send(JSON.stringify({ id: i, method, params })) })
// 求值助手：awaitPromise 让页面里的 async 体（收尾停实例那段）真的等到结果
const ev = async (expression) => {
  const r = await send('Runtime.evaluate', { expression, returnByValue: true, awaitPromise: true })
  return r.result?.result?.value
}
await send('Page.enable')
await send('Emulation.setDeviceMetricsOverride', { width: 1280, height: 900, deviceScaleFactor: 1, mobile: false })
await send('Page.navigate', { url: baseUrl })
await new Promise((r) => setTimeout(r, 4500))

const before = await send('Runtime.evaluate', { expression: `(() => {
  const anim = [...document.querySelectorAll('*')].filter((e) => { const cs = getComputedStyle(e); return cs.animationName && cs.animationName !== 'none' })
  const visible = anim.filter((e) => { const r = e.getBoundingClientRect(); return r.width > 0 && r.height > 0 })
  return JSON.stringify({
    count: anim.length,
    visibleCount: visible.length,
    visibleNames: visible.map((e) => getComputedStyle(e).animationName),
    names: anim.map((e) => getComputedStyle(e).animationName),
    items: anim.slice(0, 4).map((e) => { const cs = getComputedStyle(e); const r = e.getBoundingClientRect(); const pr = e.parentElement ? e.parentElement.getBoundingClientRect() : null; return { name: cs.animationName, cls: String(e.className).slice(0, 40), rect: { x: +r.x.toFixed(1), y: +r.y.toFixed(1), w: +r.width.toFixed(1), h: +r.height.toFixed(1) }, visible: cs.visibility, display: cs.display, opacity: cs.opacity, parentCls: String(e.parentElement && e.parentElement.className || '').slice(0, 40), parentRect: pr ? { x: +pr.x.toFixed(1), y: +pr.y.toFixed(1), w: +pr.width.toFixed(1), h: +pr.height.toFixed(1) } : null } }),
  })
})()`, returnByValue: true })

// 接上真引擎之后，点「启动」会真的拉起一只实例——先记下已有端口，测完把新起的停掉
const portsBefore = JSON.parse(await ev(`JSON.stringify((await (await fetch('/api/local/instances')).json()).data.instances.map((i) => i.port))`) || '[]')

const clicked = await send('Runtime.evaluate', { expression: `(() => {
  const b = [...document.querySelectorAll('button')].find((e) => e.textContent.trim().replace(/\s+/g, '').startsWith(${JSON.stringify(btnText)}))
  if (!b) return 'not-found'
  b.click(); return 'clicked:' + b.textContent.trim()
})()`, returnByValue: true })
await new Promise((r) => setTimeout(r, 900))

const after = await send('Runtime.evaluate', { expression: `(() => {
  const anim = [...document.querySelectorAll('*')].filter((e) => { const cs = getComputedStyle(e); return cs.animationName && cs.animationName !== 'none' })
  return JSON.stringify({
    count: anim.length,
    items: anim.map((e) => { const cs = getComputedStyle(e); const r = e.getBoundingClientRect(); return { tag: e.tagName.toLowerCase(), cls: String(e.className).slice(0, 60), name: cs.animationName, duration: cs.animationDuration, timing: cs.animationTimingFunction, iterations: cs.animationIterationCount, shadow: cs.boxShadow.slice(0, 60), rect: { x: +r.x.toFixed(1), y: +r.y.toFixed(1), w: +r.width.toFixed(1), h: +r.height.toFixed(1) }, visible: cs.visibility, display: cs.display, opacity: cs.opacity, parentCls: String(e.parentElement && e.parentElement.className || '').slice(0, 40) } }),
    disabledButtons: [...document.querySelectorAll('button')].filter((b) => b.disabled).length,
  })
})()`, returnByValue: true })

// 收尾：停掉本次新起的实例（只停新出现的端口，既有的一律不碰）
// 实例起来要 1~2 秒，点完立刻轮询会「看不到新实例」→ 它就留着不走了 ✗
// 这里等到「它真的出现」再停（有界 8 秒），才算真的收尾。
let cleanup = { stopped: [], waitedMs: 0, appeared: [] }
try {
  const t0 = Date.now()
  let now = []
  while (Date.now() - t0 < 8000) {
    now = JSON.parse(await ev(`JSON.stringify((await (await fetch('/api/local/instances')).json()).data.instances.map((i) => i.port))`) || '[]')
    if (now.some((p) => !portsBefore.includes(p))) break
    await new Promise((r) => setTimeout(r, 500))
  }
  cleanup.waitedMs = Date.now() - t0
  cleanup.appeared = now.filter((p) => !portsBefore.includes(p))
  for (const p of now) {
    if (portsBefore.includes(p)) continue
    const r = await ev(`(async () => {
      const res = await fetch('/api/local/action', {
        method: 'POST',
        headers: { 'content-type': 'application/json', 'X-DSH-Console': '1' },
        body: JSON.stringify({ action: 'stop-instance', params: { port: ${p} } }),
      })
      return res.status + ' ' + (await res.text()).slice(0, 120)
    })()`)
    cleanup.stopped.push({ port: p, result: r })
  }
} catch (e) { cleanup.error = String(e).slice(0, 120) }

const data = { baseUrl, portsBefore, cleanup, before: JSON.parse(before.result?.result?.value ?? '{}'), clicked: clicked.result?.result?.value, after: JSON.parse(after.result?.result?.value ?? '{}') }
writeFileSync(outJson, JSON.stringify(data, null, 1))
console.log(JSON.stringify(data, null, 1))
chrome.kill()
process.exit(0)
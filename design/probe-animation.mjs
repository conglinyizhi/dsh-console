// 动效探针（选择器无关）：node probe-animation.mjs <baseUrl> <outJson> [按钮文字]
// 点「启动」让卡片进入启动等待态，然后扫描全页哪些元素在跑动画。
import { spawn } from 'node:child_process'
import { writeFileSync } from 'node:fs'
const [baseUrl, outJson, btnText = '启动'] = process.argv.slice(2)

const chrome = spawn('chromium', ['--headless', '--no-sandbox', '--disable-gpu', '--disable-extensions',
  '--hide-scrollbars', '--remote-debugging-port=9337', '--user-data-dir=/tmp/chrome-anim',
  '--window-size=1280,900', 'about:blank'], { stdio: 'ignore' })
let page = null
for (let i = 0; i < 40 && !page; i++) {
  try { const l = await (await fetch('http://127.0.0.1:9337/json')).json(); page = l.find((t) => t.type === 'page') } catch {}
  if (!page) await new Promise((r) => setTimeout(r, 250))
}
const ws = new WebSocket(page.webSocketDebuggerUrl)
let id = 0
const pending = new Map()
ws.onmessage = (e) => { const m = JSON.parse(e.data); if (m.id && pending.has(m.id)) { pending.get(m.id)(m); pending.delete(m.id) } }
await new Promise((r) => { ws.onopen = r })
const send = (method, params = {}) => new Promise((res) => { const i = ++id; pending.set(i, res); ws.send(JSON.stringify({ id: i, method, params })) })
await send('Page.enable')
await send('Emulation.setDeviceMetricsOverride', { width: 1280, height: 900, deviceScaleFactor: 1, mobile: false })
await send('Page.navigate', { url: baseUrl })
await new Promise((r) => setTimeout(r, 4500))

const before = await send('Runtime.evaluate', { expression: `(() => {
  const anim = [...document.querySelectorAll('*')].filter((e) => { const cs = getComputedStyle(e); return cs.animationName && cs.animationName !== 'none' })
  return JSON.stringify({ count: anim.length, names: anim.map((e) => getComputedStyle(e).animationName) })
})()`, returnByValue: true })

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
    items: anim.map((e) => { const cs = getComputedStyle(e); return { tag: e.tagName.toLowerCase(), cls: String(e.className).slice(0, 60), name: cs.animationName, duration: cs.animationDuration, timing: cs.animationTimingFunction, iterations: cs.animationIterationCount, shadow: cs.boxShadow.slice(0, 60) } }),
    disabledButtons: [...document.querySelectorAll('button')].filter((b) => b.disabled).length,
  })
})()`, returnByValue: true })

const data = { baseUrl, before: JSON.parse(before.result?.result?.value ?? '{}'), clicked: clicked.result?.result?.value, after: JSON.parse(after.result?.result?.value ?? '{}') }
writeFileSync(outJson, JSON.stringify(data, null, 1))
console.log(JSON.stringify(data, null, 1))
chrome.kill()
process.exit(0)

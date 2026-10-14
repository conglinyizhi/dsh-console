// 独立验证器：node verify-frontend.mjs <baseUrl> [截图前缀]
// 用途：不依赖任何 worker 的自证，直接量页面。可对 Vue 版与新前端通用。
import { spawn } from 'node:child_process'
import { writeFileSync } from 'node:fs'

const [baseUrl, shotPrefix, jsonOut] = process.argv.slice(2)
const chrome = spawn('chromium', ['--headless', '--no-sandbox', '--disable-gpu', '--disable-extensions',
  '--hide-scrollbars', '--remote-debugging-port=9334', '--user-data-dir=/tmp/chrome-verify',
  '--window-size=1280,900', 'about:blank'], { stdio: 'ignore' })

let page = null
for (let i = 0; i < 40 && !page; i++) {
  try {
    const list = await (await fetch('http://127.0.0.1:9334/json')).json()
    page = list.find((t) => t.type === 'page')
  } catch {}
  if (!page) await new Promise((r) => setTimeout(r, 250))
}
if (!page) { console.log(JSON.stringify({ ok: false, error: 'chrome 没起来' })); process.exit(1) }

const ws = new WebSocket(page.webSocketDebuggerUrl)
let id = 0
const pending = new Map()
const consoleErrors = []
ws.onmessage = (e) => {
  const m = JSON.parse(e.data)
  if (m.method === 'Runtime.consoleAPICalled' && ['error', 'warning'].includes(m.params?.type)) {
    consoleErrors.push(m.params.type + ': ' + (m.params.args || []).map((a) => a.value ?? a.description ?? '').join(' ').slice(0, 200))
  }
  if (m.method === 'Log.entryAdded' && m.params?.entry?.level === 'error') {
    consoleErrors.push('log: ' + String(m.params.entry.text).slice(0, 200))
  }
  if (m.id && pending.has(m.id)) { pending.get(m.id)(m); pending.delete(m.id) }
}
await new Promise((r) => { ws.onopen = r })
const send = (method, params = {}) => new Promise((res) => { const i = ++id; pending.set(i, res); ws.send(JSON.stringify({ id: i, method, params })) })

await send('Runtime.enable')
await send('Log.enable')
await send('Page.enable')
await send('Emulation.setDeviceMetricsOverride', { width: 1280, height: 900, deviceScaleFactor: 1, mobile: false })
await send('Page.navigate', { url: baseUrl })
await new Promise((r) => setTimeout(r, 4500))

const probe = await send('Runtime.evaluate', {
  expression: `(() => {
    const de = document.documentElement
    const txt = document.body.innerText
    const q = (s) => document.querySelectorAll(s).length
    return JSON.stringify({
      title: document.title,
      scrollW: de.scrollWidth, clientW: de.clientWidth,
      overflowX: de.scrollWidth > de.clientWidth,
      textLen: txt.length,
      textHead: txt.slice(0, 220),
      markers: {
        真实数据: txt.includes('真实数据'),
        读取失败: txt.includes('读取失败'),
        实例总览: txt.includes('实例总览'),
      },
      counts: {
        buttons: q('button'), links: q('a[href]'), selects: q('select'),
        inputs: q('input'), cards: q('[class*=card]'), icons: q('[class*=mdi]'),
      },
    })
  })()`,
  returnByValue: true,
})
const data = JSON.parse(probe.result?.result?.value ?? '{}')
data.consoleIssues = consoleErrors.slice(0, 8)
data.consoleIssueCount = consoleErrors.length

if (shotPrefix) {
  const shot = await send('Page.captureScreenshot', { format: 'png' })
  writeFileSync(shotPrefix + '.png', Buffer.from(shot.result.data, 'base64'))
  data.shot = shotPrefix + '.png'
}
console.log(JSON.stringify(data, null, 1))
if (jsonOut) writeFileSync(jsonOut, JSON.stringify(data, null, 1))
chrome.kill()
process.exit(0)
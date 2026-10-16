// 打开回执探针：node probe-openpath.mjs <baseUrl> <outJson>
// 在总览页上点「卡片 ⋯ → 编辑配置」与「⋯ → 打开工作目录」，把回执原文读出来。
// 取的是界面上真实的文本（toast 或失败提示），不是拼出来的句子。
import { spawn } from 'node:child_process'
import { writeFileSync } from 'node:fs'

const CDP_PORT = 9300 + (process.pid % 600)
const [baseUrl, outJson] = process.argv.slice(2)
const chrome = spawn('chromium', ['--headless', '--no-sandbox', '--disable-gpu', '--disable-extensions',
  '--hide-scrollbars', '--remote-debugging-port=' + CDP_PORT, '--user-data-dir=/tmp/chrome-open-' + process.pid,
  '--window-size=1280,900', '--noerrdialogs', '--no-first-run', '--ozone-platform=headless',
  '--ozone-override-screen-size=800,600', '--use-angle=swiftshader-webgl', 'about:blank'], { stdio: 'ignore' })
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

const cards = JSON.parse(await ev(String.raw`JSON.stringify([...document.querySelectorAll('.dsh-case')].map((c,i)=>({i, name: c.querySelector('.dsh-name').textContent.trim(), status: c.querySelector('.dsh-sub').dataset.status})))`) || '[]')
const target = cards.find((c) => c.status === 'running') || cards[0]
const out = { baseUrl, cards, target, steps: [] }
for (const action of ['config', 'dir']) {
  await ev(`(() => { document.body.click(); const c = document.querySelectorAll('.dsh-case')[${target.i}]; c.querySelector('[data-name=menu-trigger]').click(); return 'ok' })()`)
  await sleep(700)
  const clicked = await ev(`(() => { const it = document.querySelector('[data-name=row-menu] [data-action=${action}]'); if (!it) return 'missing'; it.click(); return 'clicked' })()`)
  await sleep(1500)
  const read = await ev(String.raw`(() => {
    const t = document.querySelector('[data-name="flash-toast"]')
    const n = document.querySelector('[data-name="action-notice"]')
    return JSON.stringify({
      toast: t ? t.innerText.trim() : null,
      notice: n ? n.innerText.trim() : null,
      kind: t ? 'toast(成功)' : (n ? 'notice(失败)' : '无回执'),
    })
  })()`)
  out.steps.push({ action, clicked, ...JSON.parse(read || '{}') })
  await sleep(2500)
}
if (outJson) writeFileSync(outJson, JSON.stringify(out, null, 1))
console.log(JSON.stringify(out, null, 1))
chrome.kill()
process.exit(0)

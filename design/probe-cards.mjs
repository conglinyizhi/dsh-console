// 卡片读数探针：node probe-cards.mjs <baseUrl> [outJson] [shotPrefix]
// 一次量清四件事：全页文本扫描、每张卡的几何（卡 / 状态点 / 类型 pill / 备注行）、
// 备注行的文本与「有没有这个节点」。给「备注搬到底部」「删掉本地 profile 标签」两处改动
// 做前后逐像素对照用。
import { spawn } from 'node:child_process'
import { writeFileSync } from 'node:fs'

const CDP_PORT = 9300 + (process.pid % 600)
const [baseUrl, outJson, shotPrefix] = process.argv.slice(2)
const chrome = spawn('chromium', ['--headless', '--no-sandbox', '--disable-gpu', '--disable-extensions',
  '--hide-scrollbars', '--remote-debugging-port=' + CDP_PORT, '--user-data-dir=/tmp/chrome-cards-' + process.pid,
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
await send('Page.enable')
await send('Emulation.setDeviceMetricsOverride', { width: 1280, height: 900, deviceScaleFactor: 1, mobile: false })
await send('Page.navigate', { url: baseUrl })
await new Promise((r) => setTimeout(r, 4500))

const expr = `(() => {
  const R = (el) => { const r = el.getBoundingClientRect(); return { x: +r.x.toFixed(2), y: +r.y.toFixed(2), w: +r.width.toFixed(2), h: +r.height.toFixed(2), right: +r.right.toFixed(2), bottom: +r.bottom.toFixed(2) } }
  const cards = [...document.querySelectorAll('.dsh-case')].map((c) => {
    const name = c.querySelector('.dsh-name')
    const kind = c.querySelector('.dsh-kind')
    const dot = c.querySelector('.dsh-dot')
    const note = c.querySelector('.dsh-card-note')
    const fields = c.querySelector('.dsh-fields')
    return {
      name: name ? name.textContent.trim() : null,
      card: R(c),
      kindText: kind ? kind.textContent.trim() : null,
      kindRect: kind ? R(kind) : null,
      dotX: dot ? +R(dot).x.toFixed(2) : null,
      dotSlotX: c.querySelector('.dsh-dot-slot') ? +R(c.querySelector('.dsh-dot-slot')).x.toFixed(2) : null,
      noteNode: !!note,
      noteText: note ? note.textContent.trim() : null,
      noteRect: note ? R(note) : null,
      fieldsRect: fields ? R(fields) : null,
      childCount: c.children.length,
      subChildCount: c.querySelector('.dsh-sub') ? c.querySelector('.dsh-sub').children.length : null,
      subKinds: c.querySelector('.dsh-sub') ? [...c.querySelector('.dsh-sub').children].map((e) => e.className) : null,
      noteOuterHTML: note ? note.outerHTML.replace(/\s+/g, ' ').slice(0, 300) : null,
      html: c.outerHTML.replace(/\s+/g, ' ').slice(0, 120),
    }
  })
  const text = document.body.innerText
  const scan = (needle) => text.split(needle).length - 1
  return JSON.stringify({
    url: location.href,
    cards,
    textScan: { '本地 profile': scan('本地 profile'), '默认 profile': scan('默认 profile'), '真实数据': scan('真实数据') },
    bodyText: text,
  })
})()`
const out = await send('Runtime.evaluate', { expression: expr, returnByValue: true })
const data = JSON.parse(out.result?.result?.value ?? '{}')
if (shotPrefix) {
  const shot = await send('Page.captureScreenshot', { format: 'png', captureBeyondViewport: true })
  writeFileSync(shotPrefix + '.png', Buffer.from(shot.result.data, 'base64'))
  data.shot = shotPrefix + '.png'
}
if (outJson) writeFileSync(outJson, JSON.stringify(data, null, 1))
console.log(JSON.stringify({ cards: data.cards, textScan: data.textScan }, null, 1))
chrome.kill()
process.exit(0)

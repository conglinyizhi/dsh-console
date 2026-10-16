// 条目两行形态的探针：node probe-card-rows.mjs <baseUrl> [outJson] [shotPrefix]
//
// 第十轮：图标在左竖跨两行，右边第一行（名字 + 端口）、第二行（备注 / 上次启动 / 没有）。
// 一次量清四件事：
//   ① 每一条的几何（条目 / 图标位 / 两行），用来判「图标是不是真跨两行」
//   ② 第二行是哪一档（note / stamp / none）、那一行**有没有左侧那道细线**
//   ③ 两行的前后关系与间距（第二行确实在第一行下面）
//   ④ 全页文本（新增可见文案逐条数一遍）
import { spawn } from 'node:child_process'
import { writeFileSync } from 'node:fs'

const CDP_PORT = 9300 + (process.pid % 600)
const [baseUrl, outJson, shotPrefix] = process.argv.slice(2)
const VW = Number(process.env.PROBE_VIEWPORT_W || 1280)
const VH = Number(process.env.PROBE_VIEWPORT_H || 900)
const chrome = spawn('chromium', ['--headless', '--no-sandbox', '--disable-gpu', '--disable-extensions',
  '--hide-scrollbars', '--remote-debugging-port=' + CDP_PORT, '--user-data-dir=/tmp/chrome-rows-' + process.pid,
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
await send('Page.enable')
await send('Emulation.setDeviceMetricsOverride', { width: VW, height: VH, deviceScaleFactor: 1, mobile: false })
await send('Page.navigate', { url: baseUrl })
await new Promise((r) => setTimeout(r, 5000))

const expr = `(() => {
  const R = (el) => { const r = el.getBoundingClientRect(); return { x: +r.x.toFixed(1), y: +r.y.toFixed(1), w: +r.width.toFixed(1), h: +r.height.toFixed(1), right: +r.right.toFixed(1), bottom: +r.bottom.toFixed(1) } }
  const cards = [...document.querySelectorAll('.dsh-case')].map((c) => {
    const grid = c.closest('[data-name="row-group"]')
    const tile = c.querySelector('.dsh-tile')
    const body = c.querySelector('.dsh-case-body')
    const head = c.querySelector('.dsh-case-head')
    const name = c.querySelector('.dsh-name')
    const port = c.querySelector('.dsh-card-port')
    const note = c.querySelector('.dsh-card-note')
    const stamp = c.querySelector('.dsh-card-stamp')
    const second = note || stamp
    const secondKind = note ? 'note' : (stamp ? 'stamp' : 'none')
    const cs = second ? getComputedStyle(second) : null
    const inner = second ? second.firstElementChild : null
    const ics = inner ? getComputedStyle(inner) : null
    const ts = tile ? getComputedStyle(tile) : null
    return {
      rowId: c.getAttribute('data-row'),
      group: grid ? grid.getAttribute('data-group') : null,
      status: c.getAttribute('data-status'),
      light: c.getAttribute('data-light'),
      nameText: name ? name.textContent.trim() : null,
      portText: port ? port.textContent.trim() : null,
      portRect: port ? R(port) : null,
      secondKind,
      secondText: second ? second.textContent.trim() : null,
      secondBorderLeft: cs ? cs.borderLeftWidth : null,
      secondColor: cs ? cs.color : null,
      secondTextColor: ics ? ics.color : null,
      secondFontSize: cs ? cs.fontSize : null,
      card: R(c),
      tileSlot: c.querySelector('.dsh-tile-slot') ? R(c.querySelector('.dsh-tile-slot')) : null,
      tile: tile ? { ...R(tile), w: ts.width, h: ts.height } : null,
      body: body ? R(body) : null,
      head: head ? R(head) : null,
      name: name ? R(name) : null,
      second: second ? R(second) : null,
      articleChildren: c.children.length,
      bodyChildren: body ? body.children.length : null,
      // 图标是不是真跨两行：图标与右半那两行**同起同落**
      spansTwoRows: !!(tile && body) &&
        Math.abs(R(tile).y - R(body).y) <= 1 && Math.abs(R(tile).bottom - R(body).bottom) <= 1,
      // 第二行确实在第一行下面（不是在右边）
      secondBelowHead: !!(second && head) && R(second).y >= R(head).bottom - 1,
      // 两行的基线间距：第一行底 到 第二行顶
      rowGap: (second && head) ? +(R(second).y - R(head).bottom).toFixed(1) : null,
      html: c.outerHTML.replace(/\s+/g, ' ').slice(0, 400),
    }
  })
  const text = document.body.innerText
  const scan = (needle) => text.split(needle).length - 1
  return JSON.stringify({
    url: location.href,
    viewport: { w: innerWidth, h: innerHeight },
    cards,
    textScan: { '上次启动': scan('上次启动'), '备注': scan('备注'), '真实数据': scan('真实数据') },
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
console.log(JSON.stringify({
  viewport: data.viewport,
  cards: (data.cards || []).map((c) => ({
    row: c.rowId, group: c.group, name: c.nameText, port: c.portText, second: c.secondKind,
    secondText: c.secondText, borderLeft: c.secondBorderLeft, secondTextColor: c.secondTextColor,
    card: c.card ? [c.card.w, c.card.h] : null, tile: c.tile ? [c.tile.w, c.tile.h, c.tile.y, c.tile.bottom] : null,
    portRect: c.portRect,
    body: c.body ? [c.body.y, c.body.bottom] : null,
    spansTwoRows: c.spansTwoRows, secondBelowHead: c.secondBelowHead, rowGap: c.rowGap,
  })),
  textScan: data.textScan,
}, null, 1))
chrome.kill()
process.exit(0)

// 条目右上角那一格的探针：node probe-port-label.mjs <baseUrl> [outJson] [shotPrefix]
//
// 量的四件事：
//   ① 那一格**是不是只有知道端口才产出**（没有端口的那一行：节点一个都不许有）
//   ② 那一格的 DOM 文本（加了标签之后应当是「端口：3080」）
//   ③ 几何：名字左缘、那一串的右缘（应与条目内容盒右缘对齐）、第一行行高、条目宽高
//   ④ 挤不挤：名字仍是一行省略号、标签不换行、条目头不溢出、整页不横向滚动
//
// 视口用 PROBE_VIEWPORT_W / PROBE_VIEWPORT_H 覆盖（默认 1280×900）。
import { spawn } from 'node:child_process'
import { writeFileSync } from 'node:fs'

const CDP_PORT = 9300 + (process.pid % 600)
const [baseUrl, outJson, shotPrefix] = process.argv.slice(2)
const VW = Number(process.env.PROBE_VIEWPORT_W || 1280)
const VH = Number(process.env.PROBE_VIEWPORT_H || 900)
const chrome = spawn('chromium', ['--headless', '--no-sandbox', '--disable-gpu', '--disable-extensions',
  '--hide-scrollbars', '--remote-debugging-port=' + CDP_PORT, '--user-data-dir=/tmp/chrome-portlabel-' + process.pid,
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
await new Promise((r) => setTimeout(r, 6000))

const expr = `(() => {
  const R = (el) => { const r = el.getBoundingClientRect(); return { x:+r.x.toFixed(1), y:+r.y.toFixed(1), w:+r.width.toFixed(1), h:+r.height.toFixed(1), right:+r.right.toFixed(1), bottom:+r.bottom.toFixed(1) } }
  const contentBox = (el) => {
    const cs = getComputedStyle(el), r = el.getBoundingClientRect()
    const bl = parseFloat(cs.borderLeftWidth) || 0, br = parseFloat(cs.borderRightWidth) || 0
    const pl = parseFloat(cs.paddingLeft) || 0, pr = parseFloat(cs.paddingRight) || 0
    return { left: +(r.left + bl + pl).toFixed(1), right: +(r.right - br - pr).toFixed(1), paddingLeft: pl, paddingRight: pr, borderLeft: bl, borderRight: br }
  }
  const cards = [...document.querySelectorAll('.dsh-case')].map((c) => {
    const head = c.querySelector('.dsh-case-head')
    const name = c.querySelector('.dsh-name')
    const port = c.querySelector('.dsh-card-port')
    const label = port ? port.querySelector('.dsh-card-port-label') : null
    const box = contentBox(c)
    const rName = name ? R(name) : null
    const rPort = port ? R(port) : null
    const cs = (el) => el ? getComputedStyle(el) : null
    return {
      rowId: c.getAttribute('data-row'),
      status: c.getAttribute('data-status'),
      instance: c.getAttribute('data-instance'),
      nameText: name ? name.textContent : null,
      // ① 节点是否存在
      nodes: { port: !!port, portLabel: !!label, head: !!head, name: !!name },
      // ② DOM 文本
      portText: port ? port.textContent : null,
      portTextTrimmed: port ? port.textContent.trim() : null,
      labelText: label ? label.textContent : null,
      cardText: c.textContent,
      // ③ 几何
      card: R(c), content: box,
      head: head ? R(head) : null,
      name: rName ? Object.assign(rName, { lineBoxes: name.getClientRects().length,
        ellipsisActive: name.scrollWidth > name.clientWidth + 1, scrollW: name.scrollWidth, clientW: name.clientWidth }) : null,
      port: rPort ? Object.assign(rPort, { lineBoxes: port.getClientRects().length,
        color: cs(port).color, fontSize: cs(port).fontSize, whiteSpace: cs(port).whiteSpace }) : null,
      label: label ? Object.assign(R(label), { lineBoxes: label.getClientRects().length,
        color: cs(label).color, fontSize: cs(label).fontSize, whiteSpace: cs(label).whiteSpace }) : null,
      deltas: {
        nameLeft: rName ? +(rName.x - box.left).toFixed(1) : null,
        portRight: rPort ? +(rPort.right - box.right).toFixed(1) : null,
        portLeft: rPort ? +(rPort.x - box.left).toFixed(1) : null,
        portW: rPort ? rPort.w : null,
        labelW: label ? R(label).w : null,
        headH: head ? R(head).h : null,
        headTop: head ? +(R(head).y - c.getBoundingClientRect().y).toFixed(1) : null,
        bodyRight: +((c.getBoundingClientRect().right - box.borderRight - box.paddingRight) - box.right).toFixed(1),
      },
      headOverflow: head ? head.scrollWidth > head.clientWidth : null,
      headScrollW: head ? head.scrollWidth : null, headClientW: head ? head.clientWidth : null,
      cardOverflow: c.scrollWidth > c.clientWidth,
      html: c.outerHTML,
    }
  })
  const de = document.documentElement
  const portNodes = document.querySelectorAll('.dsh-card-port').length
  const labelNodes = document.querySelectorAll('.dsh-card-port-label').length
  // 全页扫「端口：」出现在哪几处（应当只出现在有端口那一格里）
  const hits = []
  for (const el of document.querySelectorAll('*')) {
    if (el.children.length === 0 && el.textContent.indexOf('端口：') >= 0) {
      hits.push({ cls: String(el.className), text: el.textContent, insidePort: !!(el.closest && el.closest('.dsh-card-port')) })
    }
  }
  return JSON.stringify({
    url: location.href,
    viewport: { w: innerWidth, h: innerHeight },
    overflowX: de.scrollWidth > de.clientWidth, scrollW: de.scrollWidth, clientW: de.clientWidth,
    counts: { portNodes, labelNodes },
    portHits: hits,
    bodyText: document.body.innerText,
    cards,
  })
})()`

const out = await send('Runtime.evaluate', { expression: expr, returnByValue: true })
const data = JSON.parse(out.result?.result?.value ?? '{}')
// 空白折叠放在 Node 这一侧做。理由是一条踩过的坑：页面表达式写在模板字符串里，
// 里面那条 [空白]+ 的正则反斜杠会被吞掉，变成「把字母 s 换成空格」——
// html 字段里每个 s 都变成了空格（class= → cla =），上一版实测抓到的。
// 这里用 charCode 拼字符类，绕开反斜杠，两层模板都不会再吃掉它。
const WS = String.fromCharCode(32, 9, 10, 13)
const collapse = (t) => String(t).split(new RegExp('[' + WS + ']+')).join(' ').trim()
for (const c of data.cards || []) {
  c.cardText = collapse(c.cardText)
  c.html = collapse(c.html).split('<!--[-->').join('').split('<!--]-->').join('')
}

// 出图：运行中那一条（有端口的）与一条没有端口的，各裁一张放大图
const shots = []
if (shotPrefix) {
  const pick = (pred) => (data.cards || []).find(pred)
  const targets = [
    ['running', pick((c) => c.nodes.port && c.status === 'running')],
    ['noport', pick((c) => !c.nodes.port)],
  ]
  for (const [tag, c] of targets) {
    if (!c) { shots.push({ tag, skipped: true }); continue }
    const pad = 6
    const clip = { x: Math.max(0, c.card.x - pad), y: Math.max(0, c.card.y - pad),
      width: c.card.w + pad * 2, height: c.card.h + pad * 2, scale: 3 }
    const shot = await send('Page.captureScreenshot', { format: 'png', captureBeyondViewport: true, clip })
    const path = shotPrefix + '-' + tag + '.png'
    writeFileSync(path, Buffer.from(shot.result.data, 'base64'))
    shots.push({ tag, card: c.card, rowId: c.rowId, portText: c.portTextTrimmed, path })
  }
  const full = await send('Page.captureScreenshot', { format: 'png', captureBeyondViewport: true })
  writeFileSync(shotPrefix + '-full.png', Buffer.from(full.result.data, 'base64'))
  shots.push({ tag: 'full', path: shotPrefix + '-full.png' })
}
// 名字长了会怎样：把那一格的名字换成一个长串，再量一次。
// 只改 DOM 文本、不发状态（rabbita 不重渲染），所以这是**同一个布局**下的实测，
// 不是另一份 fixture；带 data-injected 标记，与真名字分得开。
// 放在出图之后：上面那几张图要的是真名字，这一张才是注入后的样子。
const injExpr = `(() => {
  const R = (el) => { const r = el.getBoundingClientRect(); return { x:+r.x.toFixed(1), y:+r.y.toFixed(1), w:+r.width.toFixed(1), h:+r.height.toFixed(1), right:+r.right.toFixed(1), bottom:+r.bottom.toFixed(1) } }
  const c = document.querySelector('[data-name="instance-card"][data-row^="port:"]')
  if (!c) return JSON.stringify({ ok: false })
  const name = c.querySelector('.dsh-name')
  const port = c.querySelector('.dsh-card-port')
  const head = c.querySelector('.dsh-case-head')
  name.setAttribute('data-injected', 'true')
  name.textContent = 'a-very-long-profile-name-to-check-the-ellipsis'
  const cs = getComputedStyle(c), r = c.getBoundingClientRect()
  const boxRight = r.right - (parseFloat(cs.borderRightWidth) || 0) - (parseFloat(cs.paddingRight) || 0)
  const label = port ? port.querySelector('.dsh-card-port-label') : null
  const lr = label ? label.getBoundingClientRect() : null
  return JSON.stringify({
    ok: true,
    injectedText: 'a-very-long-profile-name-to-check-the-ellipsis',
    name: R(name), nameLineBoxes: name.getClientRects().length,
    nameEllipsis: name.scrollWidth > name.clientWidth + 1, nameScrollW: name.scrollWidth, nameClientW: name.clientWidth,
    portText: port ? port.textContent : null, port: port ? R(port) : null,
    portRightFromContentRight: port ? +(R(port).right - boxRight).toFixed(1) : null,
    labelShown: !!(lr && lr.width > 0), labelLineBoxes: label ? label.getClientRects().length : null,
    labelRect: lr ? R(label) : null,
    // 只判**横向**越界：行内盒的上下沿是字体自己的内容盒（CJK 兜底字体的内容盒比 16px 的
    // 行盒高一点点），那不是溢出、也没有任何可见的东西被画到格子外面（这一格没有背景与边框）。
    // 纵向真正会动的量是行高，而它由 line-height: 16px 定住 —— 上面 head/card 的高度已逐条量过。
    labelOutsidePortX: !!(lr && port && (lr.right > R(port).right + 0.5 || lr.left < R(port).left - 0.5)),
    head: R(head), headOverflow: head.scrollWidth > head.clientWidth,
    card: R(c), cardOverflow: c.scrollWidth > c.clientWidth,
    pageOverflowX: document.documentElement.scrollWidth > document.documentElement.clientWidth,
  })
})()`
const injOut = await send('Runtime.evaluate', { expression: injExpr, returnByValue: true })
try { data.injected = JSON.parse(injOut.result?.result?.value ?? '{}') } catch (e) { data.injected = { ok: false, error: 'CannotParse' } }
if (shotPrefix && data.injected && data.injected.card) {
  const pad = 6, r = data.injected.card
  const clip = { x: Math.max(0, r.x - pad), y: Math.max(0, r.y - pad), width: r.w + pad * 2, height: r.h + pad * 2, scale: 3 }
  const shot = await send('Page.captureScreenshot', { format: 'png', captureBeyondViewport: true, clip })
  const path = shotPrefix + '-longname.png'
  writeFileSync(path, Buffer.from(shot.result.data, 'base64'))
  shots.push({ tag: 'longname', card: r, path })
}
data.shots = shots
if (outJson) writeFileSync(outJson, JSON.stringify(data, null, 1))
console.log(JSON.stringify({
  ok: true,
  viewport: data.viewport, overflowX: data.overflowX, scrollW: data.scrollW, clientW: data.clientW,
  counts: data.counts, portHits: data.portHits, shots, injected: data.injected,
  cards: (data.cards || []).map((c) => ({
    row: c.rowId, status: c.status, name: c.nameText, portText: c.portTextTrimmed,
    nodes: c.nodes, labelText: c.labelText,
    card: [c.card.w, c.card.h], headH: c.deltas.headH,
    nameLeft: c.deltas.nameLeft, nameW: c.name ? c.name.w : null,
    portRight: c.deltas.portRight, portW: c.deltas.portW, labelW: c.deltas.labelW,
    nameEllipsis: c.name ? c.name.ellipsisActive : null, nameLineBoxes: c.name ? c.name.lineBoxes : null,
    labelLineBoxes: c.label ? c.label.lineBoxes : null, labelColor: c.label ? c.label.color : null,
    portColor: c.port ? c.port.color : null,
    headOverflow: c.headOverflow, cardOverflow: c.cardOverflow,
  })),
}, null, 1))
chrome.kill()
process.exit(0)

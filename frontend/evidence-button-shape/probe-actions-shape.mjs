// 已停止卡的按钮组形态探针：改前 / 改后跑同一份，拿到可直接对照的读数。
//
//   node probe-actions-shape.mjs <baseUrl> <outPrefix> [label]
//
// 只点「行尾 ⋯ / 分段 caret」这一个入口，绝不点菜单项与启动/停止 ——
// 那些会真的动实例。展开后按 Escape 收起。
import { spawn } from 'node:child_process'
import { writeFileSync, mkdirSync } from 'node:fs'
import { dirname } from 'node:path'

const CDP_PORT = 9300 + (process.pid % 600)
const [baseUrl, outPrefix, label = ''] = process.argv.slice(2)
if (!baseUrl || !outPrefix) { console.log('用法: node probe-actions-shape.mjs <baseUrl> <outPrefix> [label]'); process.exit(1) }
mkdirSync(dirname(outPrefix), { recursive: true })

const chrome = spawn('chromium', ['--headless', '--no-sandbox', '--disable-gpu', '--disable-extensions',
  '--hide-scrollbars', '--remote-debugging-port=' + CDP_PORT, '--user-data-dir=/tmp/chrome-shape-' + process.pid,
  '--window-size=1440,1000', 'about:blank'], { stdio: 'ignore' })
let page = null
for (let i = 0; i < 40 && !page; i++) {
  try { const l = await (await fetch('http://127.0.0.1:' + CDP_PORT + '/json')).json(); page = l.find((t) => t.type === 'page') } catch {}
  if (!page) await new Promise((r) => setTimeout(r, 250))
}
const ws = new WebSocket(page.webSocketDebuggerUrl)
let id = 0
const pend = new Map()
ws.onmessage = (e) => { const m = JSON.parse(e.data); if (m.id && pend.has(m.id)) { pend.get(m.id)(m); pend.delete(m.id) } }
await new Promise((r) => { ws.onopen = r })
const send = (method, params = {}) => new Promise((res) => { const i = ++id; pend.set(i, res); ws.send(JSON.stringify({ id: i, method, params })) })
const ev = async (e) => { const r = await send('Runtime.evaluate', { expression: e, returnByValue: true, awaitPromise: true }); if (r.result?.exceptionDetails) return 'EXC:' + String(r.result.exceptionDetails.exception?.description || JSON.stringify(r.result.exceptionDetails)).slice(0, 300); return r.result?.result?.value }
const wait = (ms) => new Promise((r) => setTimeout(r, ms))
const shot = async (file, clip) => {
  // CDP 的 clip 四个字段要 double：整数值会被 JSON 编成 int32 而遭拒
  // （"BINDINGS: double value expected"）。整数就补 0.5px，截图上看不出来。
  const dbl = (v) => (Number.isInteger(v) ? v + 0.5 : v)
  const c = clip ? { x: dbl(clip.x), y: dbl(clip.y), width: dbl(clip.width), height: dbl(clip.height), scale: 1 } : null
  const r = await send('Page.captureScreenshot', c ? { format: 'png', clip: c } : { format: 'png' })
  if (r.result?.data) { writeFileSync(file, Buffer.from(r.result.data, 'base64')); return true }
  console.log('！截图失败 ' + file + ' ' + JSON.stringify(r.error || r.result || {}).slice(0, 200))
  return false
}
const realClick = async (x, y) => {
  for (const type of ['mousePressed', 'mouseReleased']) {
    await send('Input.dispatchMouseEvent', { type, x, y, button: 'left', clickCount: 1 })
  }
}

await send('Page.enable'); await send('Runtime.enable')
await send('Emulation.setDeviceMetricsOverride', { width: 1440, height: 1000, deviceScaleFactor: 1, mobile: false })
await send('Page.navigate', { url: baseUrl }); await wait(4500)

// ── 一、按钮组的构成：每张实例卡里有哪些按钮（标签 / 类名 / 尺寸 / 圆角），
//        以及按钮组右缘与卡片内容盒右缘的差 ──
const layoutExpr = `(() => {
  const R = (el) => { const r = el.getBoundingClientRect(); return { x: +r.x.toFixed(1), y: +r.y.toFixed(1), w: +r.width.toFixed(1), h: +r.height.toFixed(1), right: +r.right.toFixed(1), bottom: +r.bottom.toFixed(1) } }
  const contentRight = (el) => { const cs = getComputedStyle(el); const r = el.getBoundingClientRect(); return +(r.right - parseFloat(cs.paddingRight) - parseFloat(cs.borderRightWidth)).toFixed(1) }
  const cards = [...document.querySelectorAll('[data-name="instance-card"]')].map((c) => {
    const actions = c.querySelector('.dsh-actions')
    // 直接子节点逐个摊平：子节点自己是按钮就收它，不是按钮（分段容器）就收它里面的按钮
    const raw = actions ? [...actions.children].map((ch) => ({
      tag: ch.tagName.toLowerCase(),
      cls: String(ch.className),
      text: ch.tagName === 'BUTTON' ? ch.textContent.trim() : null,
      buttons: ch.tagName === 'BUTTON' ? [ch.textContent.trim()] : [...ch.querySelectorAll('button')].map((b) => b.textContent.trim()),
    })) : []
    const btns = actions ? [...actions.children].flatMap((ch) => ch.tagName === 'BUTTON' ? [ch] : [...ch.querySelectorAll('button')]) : []
    return {
      name: (c.querySelector('.dsh-name') || {}).textContent?.trim() ?? null,
      status: c.querySelector('[data-name="sub-line"]')?.getAttribute('data-status') ?? null,
      actionsRight: actions ? R(actions).right : null,
      contentRight: contentRight(c),
      actionsDelta: actions ? +(R(actions).right - contentRight(c)).toFixed(1) : null,
      actionsChildren: raw,
      buttons: btns.map((b) => ({ tag: b.tagName.toLowerCase(), cls: String(b.className), text: b.textContent.trim(), aria: b.getAttribute('aria-label'), haspopup: b.getAttribute('aria-haspopup'), rect: R(b), radius: getComputedStyle(b).borderRadius, padding: getComputedStyle(b).padding, gapSiblingPx: actions ? getComputedStyle(actions).gap : null })),
    }
  })
  return JSON.stringify({ cards })
})()`
const layout = JSON.parse(await ev(layoutExpr) || '{}')

// ── 二、已停止卡：真实鼠标点行尾入口，量菜单锚点与菜单项顺序 ──
const trig = await ev(`(() => {
  const cards = [...document.querySelectorAll('[data-name="instance-card"]')]
  const c = cards.find((e) => e.querySelector('[data-name="sub-line"][data-status="stopped"]'))
  if (!c) return JSON.stringify({ diag: 'no-stopped-card', cards: cards.length })
  const t = c.querySelector('[aria-haspopup="menu"]')
  if (!t) return JSON.stringify({ diag: 'no-menu-trigger', html: c.querySelector('.dsh-actions').outerHTML.slice(0, 200) })
  const r = t.getBoundingClientRect()
  return JSON.stringify({ name: (c.querySelector('.dsh-name') || {}).textContent.trim(), cls: String(t.className), rect: { x: +r.x.toFixed(1), y: +r.y.toFixed(1), w: +r.width.toFixed(1), h: +r.height.toFixed(1), right: +r.right.toFixed(1), bottom: +r.bottom.toFixed(1) }, cx: +(r.x + r.width / 2).toFixed(1), cy: +(r.y + r.height / 2).toFixed(1), radius: getComputedStyle(t).borderRadius, padding: getComputedStyle(t).padding })
})()`)
const trigger = trig ? JSON.parse(trig) : null
if (trigger && trigger.diag) { console.log('！已停止卡的入口没取到: ' + JSON.stringify(trigger)); }
let opened = null
if (trigger) {
  await realClick(trigger.cx, trigger.cy)          // 真鼠标事件，不是 el.click()
  await wait(800)
  opened = JSON.parse(await ev(`(() => {
    const R = (el) => { const r = el.getBoundingClientRect(); return { x: +r.x.toFixed(1), y: +r.y.toFixed(1), w: +r.width.toFixed(1), h: +r.height.toFixed(1), right: +r.right.toFixed(1), bottom: +r.bottom.toFixed(1) } }
    const menu = document.querySelector('[data-name="row-menu"]')
    // 按钮组必须取**菜单所在那张卡**的：document.querySelector('.dsh-actions') 拿到的是第一张卡
    const card = [...document.querySelectorAll('[data-name="instance-card"]')].find((e) => e.querySelector('[data-name="row-menu"]'))
    const actions = card ? card.querySelector('.dsh-actions') : null
    if (!menu) return JSON.stringify({ opened: false })
    return JSON.stringify({
      opened: true,
      cardName: (card.querySelector('.dsh-name') || {}).textContent.trim(),
      triggerAriaExpanded: card.querySelector('[aria-haspopup="menu"]').getAttribute('aria-expanded'),
      rect: R(menu),
      deltaTop: actions ? +(R(menu).y - R(actions).bottom).toFixed(1) : null,
      deltaRight: actions ? +(R(menu).right - R(actions).right).toFixed(1) : null,
      activeIsFirstItem: (() => { const a = document.activeElement; const f = menu.querySelector('[role=menuitem]'); return a && f ? a === f : null })(),
      items: [...menu.children].map((e) => e.getAttribute('role') === 'separator' || String(e.className).includes('sep') ? '--- 分隔 ---' : e.textContent.trim()),
      cardRect: R(card),
    })
  })()`))
  const pad = 24
  const c = opened?.cardRect, m = opened?.rect
  const clip = c && m ? { x: Math.max(0, Math.min(c.x, m.x) - pad), y: Math.max(0, c.y - pad), width: Math.min(1440, Math.max(c.right, m.right) + pad) - Math.max(0, Math.min(c.x, m.x) - pad), height: (m.bottom - c.y) + 2 * pad } : null
  await shot(outPrefix + '-stopped-menu.png', clip)
  // 不 blur：菜单的 Escape 处理器挂在 .dsh-menu 上，靠聚焦项冒泡上来
  await send('Input.dispatchKeyEvent', { type: 'keyDown', key: 'Escape', code: 'Escape', windowsVirtualKeyCode: 27 })
  await send('Input.dispatchKeyEvent', { type: 'keyUp', key: 'Escape', code: 'Escape', windowsVirtualKeyCode: 27 })
  await wait(600)
  opened.menuClosedByEscape = JSON.parse(await ev("JSON.stringify({ open: !!document.querySelector('[data-name=\"row-menu\"]') })")).open === false
  // 收起之后再拍一张：只有卡片本身
  const c2 = opened.cardRect
  // 注意 R() 给的是 w / h（不是 width / height）：写错会得到 NaN，CDP 报的却是 "double value expected"
  await shot(outPrefix + '-stopped-card.png', c2 ? { x: Math.max(0, c2.x - 16), y: Math.max(0, c2.y - 16), width: c2.w + 32, height: c2.h + 32 } : null)
}
// 运行中卡：同样量一次入口（不点，运行中菜单里有「停止」）
const running = JSON.parse(await ev(`(() => {
  const c = [...document.querySelectorAll('[data-name="instance-card"]')].find((e) => e.querySelector('[data-name="sub-line"][data-status="running"]'))
  if (!c) return 'null'
  const t = c.querySelector('[aria-haspopup="menu"]')
  const r = t.getBoundingClientRect()
  return JSON.stringify({ name: (c.querySelector('.dsh-name') || {}).textContent.trim(), cls: String(t.className), rect: { x: +r.x.toFixed(1), y: +r.y.toFixed(1), w: +r.width.toFixed(1), h: +r.height.toFixed(1), right: +r.right.toFixed(1), bottom: +r.bottom.toFixed(1) }, radius: getComputedStyle(t).borderRadius, padding: getComputedStyle(t).padding })
})()`) || null)

const data = { label, baseUrl, url: await ev('location.href'), trigger, runningTrigger: running, layout, menu: opened }
writeFileSync(outPrefix + '.json', JSON.stringify(data, null, 1))

// ── 人读摘要 ──
console.log('== ' + label + ' @ ' + baseUrl + ' ==')
for (const c of layout.cards ?? []) {
  console.log('卡 [' + c.status + '] ' + c.name + '  actionsDelta=' + c.actionsDelta)
  for (const ch of c.actionsChildren) console.log('    子节点 <' + ch.tag + ' class="' + ch.cls + '"> 按钮: ' + JSON.stringify(ch.buttons))
}
console.log('已停止卡入口: ' + (trigger ? trigger.cls + ' ' + JSON.stringify(trigger.rect) + ' radius=' + trigger.radius : '无'))
console.log('运行中卡入口: ' + (running ? running.cls + ' ' + JSON.stringify(running.rect) + ' radius=' + running.radius : '无'))
if (running && trigger) {
  console.log('两个 ⋯ 对照: 类名同=' + (running.cls === trigger.cls) + ' 尺寸同=' + (running.rect.w === trigger.rect.w && running.rect.h === trigger.rect.h) + ' 圆角同=' + (running.radius === trigger.radius) + ' 内边距同=' + (running.padding === trigger.padding))
}
if (opened?.opened) {
  console.log('菜单 卡片=' + opened.cardName + ' deltaTop=' + opened.deltaTop + ' deltaRight=' + opened.deltaRight + ' 落焦第一项=' + opened.activeIsFirstItem + ' Esc 能关=' + opened.menuClosedByEscape)
  opened.items.forEach((t, i) => console.log('    ' + (i + 1) + '. ' + t))
}
chrome.kill(); process.exit(0)

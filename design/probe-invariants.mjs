// 几何不变量探针：node probe-invariants.mjs <baseUrl> <outJson> [选择器profile]
// 默认 profile=vue（现有 Vue 版的类名）。换栈后的新前端要另给一份选择器映射。
import { spawn } from 'node:child_process'
import { writeFileSync } from 'node:fs'

const [baseUrl, outJson, profile = 'vue'] = process.argv.slice(2)

const SEL = {
  vue: {
    card: '.row', actions: '.actions', dot: '.dot', dotSlot: '.dot-slot',
    kind: '.kind', name: '.name', splitMain: '.split-main', splitCaret: '.split-caret',
    menuTrigger: '.btn.icon-only', menu: '.menu',
  },
}[profile]
if (!SEL) { console.log('未知 profile: ' + profile); process.exit(1) }

const chrome = spawn('chromium', ['--headless', '--no-sandbox', '--disable-gpu', '--disable-extensions',
  '--hide-scrollbars', '--remote-debugging-port=9335', '--user-data-dir=/tmp/chrome-inv',
  '--window-size=1280,900', 'about:blank'], { stdio: 'ignore' })

let page = null
for (let i = 0; i < 40 && !page; i++) {
  try {
    const list = await (await fetch('http://127.0.0.1:9335/json')).json()
    page = list.find((t) => t.type === 'page')
  } catch {}
  if (!page) await new Promise((r) => setTimeout(r, 250))
}
const ws = new WebSocket(page.webSocketDebuggerUrl)
let id = 0
const pending = new Map()
ws.onmessage = (e) => {
  const m = JSON.parse(e.data)
  if (m.id && pending.has(m.id)) { pending.get(m.id)(m); pending.delete(m.id) }
}
await new Promise((r) => { ws.onopen = r })
const send = (method, params = {}) => new Promise((res) => { const i = ++id; pending.set(i, res); ws.send(JSON.stringify({ id: i, method, params })) })
await send('Page.enable')
await send('Emulation.setDeviceMetricsOverride', { width: 1280, height: 900, deviceScaleFactor: 1, mobile: false })
await send('Page.navigate', { url: baseUrl })
await new Promise((r) => setTimeout(r, 4500))

const expr = `(() => {
  const S = ${JSON.stringify(SEL)}
  const R = (el) => { const r = el.getBoundingClientRect(); return { x: +r.x.toFixed(1), y: +r.y.toFixed(1), w: +r.width.toFixed(1), h: +r.height.toFixed(1), right: +r.right.toFixed(1), bottom: +r.bottom.toFixed(1) } }
  const contentRight = (el) => { const cs = getComputedStyle(el); const r = el.getBoundingClientRect(); return +(r.right - parseFloat(cs.paddingRight) - parseFloat(cs.borderRightWidth)).toFixed(1) }
  const cards = [...document.querySelectorAll(S.card)].map((c, i) => {
    const a = c.querySelector(S.actions), d = c.querySelector(S.dot), k = c.querySelector(S.kind), n = c.querySelector(S.name)
    return {
      i, name: n ? n.textContent.trim() : null,
      card: R(c), contentRight: contentRight(c),
      actionsRight: a ? R(a).right : null,
      actionsDelta: a ? +(R(a).right - contentRight(c)).toFixed(1) : null,
      dot: d ? R(d) : null, kind: k ? R(k) : null,
    }
  })
  const sm = document.querySelector(S.splitMain), sc = document.querySelector(S.splitCaret)
  const split = (sm && sc) ? {
    main: { ...R(sm), radius: getComputedStyle(sm).borderRadius, bg: getComputedStyle(sm).backgroundColor },
    caret: { ...R(sc), radius: getComputedStyle(sc).borderRadius, borderLeft: getComputedStyle(sc).borderLeftWidth },
    gap: +(R(sc).x - R(sm).right).toFixed(1),
  } : null
  const trig = document.querySelector(S.menuTrigger)
  if (trig) trig.click()
  const menu = document.querySelector(S.menu)
  const actions = document.querySelector(S.actions)
  const menuInfo = menu ? {
    rect: R(menu),
    deltaTop: actions ? +(R(menu).y - R(actions).bottom).toFixed(1) : null,
    deltaRight: actions ? +(R(menu).right - R(actions).right).toFixed(1) : null,
  } : { opened: false, note: '同一次求值里还没渲染出来，见第二次求值' }
  const de = document.documentElement
  const bs = getComputedStyle(document.body)
  const dotXs = cards.map((c) => c.dot && c.dot.x).filter((x) => x != null)
  return JSON.stringify({
    url: location.href,
    overflow: { scrollW: de.scrollWidth, clientW: de.clientWidth, overflowX: de.scrollWidth > de.clientWidth },
    font: { size: bs.fontSize, family: bs.fontFamily.slice(0, 40) },
    cards,
    invariants: {
      dotXsAllEqual: dotXs.length > 1 ? new Set(dotXs).size === 1 : null,
      dotXs,
      allActionsMatchContentRight: cards.every((c) => c.actionsDelta === 0),
      actionsDeltas: cards.map((c) => c.actionsDelta),
    },
    split, menu: menuInfo,
  })
})()`
const out = await send('Runtime.evaluate', { expression: expr, returnByValue: true })
const data = JSON.parse(out.result?.result?.value ?? '{}')
// 菜单是异步渲染的：等一拍再单独量一次
await new Promise((r) => setTimeout(r, 500))
const menuExpr = `(() => {
  const S = ${JSON.stringify(SEL)}
  const R = (el) => { const r = el.getBoundingClientRect(); return { x: +r.x.toFixed(1), y: +r.y.toFixed(1), w: +r.width.toFixed(1), h: +r.height.toFixed(1), right: +r.right.toFixed(1), bottom: +r.bottom.toFixed(1) } }
  const menu = document.querySelector(S.menu), actions = document.querySelector(S.actions)
  if (!menu) return JSON.stringify({ opened: false })
  return JSON.stringify({
    opened: true, rect: R(menu),
    deltaTop: actions ? +(R(menu).y - R(actions).bottom).toFixed(1) : null,
    deltaRight: actions ? +(R(menu).right - R(actions).right).toFixed(1) : null,
    items: [...menu.querySelectorAll('[role=menuitem], .menu-item')].map((e) => e.textContent.trim()).slice(0, 10),
    activeIsFirstItem: (() => { const a = document.activeElement; const f = menu.querySelector('[role=menuitem], .menu-item'); return a && f ? a === f : null })(),
  })
})()`
const m2 = await send('Runtime.evaluate', { expression: menuExpr, returnByValue: true })
data.menu = JSON.parse(m2.result?.result?.value ?? '{}')
writeFileSync(outJson, JSON.stringify(data, null, 1))
console.log(JSON.stringify({ overflow: data.overflow, invariants: data.invariants, splitGap: data.split?.gap, menu: data.menu, cardCount: data.cards?.length }, null, 1))
chrome.kill()
process.exit(0)
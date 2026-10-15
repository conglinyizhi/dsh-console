// CDP 探针：量按钮元素清单与菜单 rect
const PORT = Number(process.argv[2] || 9346)
const PAGE = process.argv[3]
const OUT = process.argv[4]
const sleep = (ms) => new Promise((r) => setTimeout(r, ms))

const list = await (await fetch('http://127.0.0.1:' + PORT + '/json/list')).json()
const page = list.find((t) => t.type === 'page')
if (!page) { console.log('no page target'); process.exit(1) }
const ws = new WebSocket(page.webSocketDebuggerUrl)
let id = 0
const pending = new Map()
ws.addEventListener('message', (e) => {
  const m = JSON.parse(e.data)
  if (m.id && pending.has(m.id)) { pending.get(m.id)(m); pending.delete(m.id) }
})
await new Promise((r) => ws.addEventListener('open', r))
const send = (method, params = {}) => new Promise((res) => { const i = ++id; pending.set(i, res); ws.send(JSON.stringify({ id: i, method, params })) })

await send('Page.enable')
await send('Runtime.enable')
await send('Page.navigate', { url: PAGE })

const evalJs = async (expression) => {
  const r = await send('Runtime.evaluate', { expression, returnByValue: true, awaitPromise: true })
  if (r.result && r.result.exceptionDetails) throw new Error(JSON.stringify(r.result.exceptionDetails))
  return r.result && r.result.result ? r.result.result.value : undefined
}

let rows = 0
for (let i = 0; i < 40; i++) {
  await sleep(300)
  rows = await evalJs("document.querySelectorAll('.row').length") || 0
  if (rows >= 8) break
}
if (!rows) { console.log('page did not render'); process.exit(1) }

const expr = [
  "(() => {",
  "  const R = (el) => { const r = el.getBoundingClientRect(); return { x: +r.x.toFixed(1), y: +r.y.toFixed(1), w: +r.width.toFixed(1), h: +r.height.toFixed(1), right: +(r.x + r.width).toFixed(1) } }",
  "  const T = (el) => (el.innerText || '').split(String.fromCharCode(10)).join(' ').trim()",
  "  const out = { doc: { scrollW: document.documentElement.scrollWidth, scrollH: document.documentElement.scrollHeight, viewportW: innerWidth, viewportH: innerHeight }, cards: {}, menus: {}, overflow: [] }",
  "  const btnList = (root) => [...root.querySelectorAll('.actions > .btn, .actions > .split > .btn')].map((b) => {",
  "    const r = b.getBoundingClientRect()",
  "    return { probe: b.getAttribute('data-probe'), label: T(b), cls: b.className, w: +r.width.toFixed(1), h: +r.height.toFixed(1), x: +r.x.toFixed(1), right: +(r.x + r.width).toFixed(1), bg: getComputedStyle(b).backgroundColor, fs: getComputedStyle(b).fontSize }",
  "  })",
  "  for (const card of document.querySelectorAll('.row')) {",
  "    const key = card.getAttribute('data-card')",
  "    const c = R(card)",
  "    c.buttons = btnList(card)",
  "    c.actions = R(card.querySelector('.actions'))",
  "    c.rowHead = R(card.querySelector('.row-head'))",
  "    c.tile = R(card.querySelector('.tile'))",
  "    c.name = T(card.querySelector('.name'))",
  "    c.nameRect = R(card.querySelector('.name'))",
  "    c.nameStyle = getComputedStyle(card.querySelector('.name')).fontSize + '/' + getComputedStyle(card.querySelector('.name')).fontWeight",
  "    c.subLine = R(card.querySelector('.sub-line'))",
  "    c.subText = T(card.querySelector('.sub-line'))",
  "    out.cards[key] = c",
  "  }",
  "  for (const m of document.querySelectorAll('.menu')) {",
  "    const key = m.getAttribute('data-probe')",
  "    const r = R(m)",
  "    const trigger = m.parentElement.querySelector('.icon-only') || m.parentElement.querySelector('.split')",
  "    const tr = trigger ? R(trigger) : null",
  "    out.menus[key] = { probe: key, rect: r, anchorProbe: trigger ? (trigger.getAttribute('data-probe') || trigger.className) : null, triggerRect: tr,",
  "      gapBelowTrigger: tr ? +(r.y - (tr.y + tr.height)).toFixed(1) : null,",
  "      gapBelowActions: +(r.y - (R(m.parentElement).y + R(m.parentElement).height)).toFixed(1),",
  "      menuVsActionsRight: +(r.right - R(m.parentElement).right).toFixed(1),",
  "      menuVsActionsLeft: +(r.left - R(m.parentElement).x).toFixed(1),",
  "      rightVsTriggerRight: tr ? +(r.right - tr.right).toFixed(1) : null,",
  "      deltaToCardInnerRight: +(R(m.closest('.row')).right - 16 - r.right).toFixed(1),",
  "      items: [...m.querySelectorAll('.menu-item')].map((i) => T(i)),",
  "      itemHeights: [...m.querySelectorAll('.menu-item')].map((i) => +i.getBoundingClientRect().height.toFixed(1)) }",
  "  }",
  "  const sw = document.documentElement.scrollWidth",
  "  for (const el of document.querySelectorAll('.row, .reasons, .anchor-note, .lede, .verdict, p, li, .menu')) {",
  "    const r = el.getBoundingClientRect()",
  "    if (r.right > sw + 0.5 || r.left < -0.5) out.overflow.push({ cls: el.className || el.tagName, x: +r.x.toFixed(1), right: +r.right.toFixed(1), text: T(el).slice(0, 36) })",
  "  }",
  "  out.cardsOverlap = []",
  "  const menus = [...document.querySelectorAll('.menu')]",
  "  for (const m of menus) {",
  "    const mr = m.getBoundingClientRect()",
  "    for (const c of document.querySelectorAll('.row')) {",
  "      if (m.closest('.row') === c) continue",
  "      const cr = c.getBoundingClientRect()",
  "      if (mr.bottom > cr.top && mr.top < cr.bottom && mr.right > cr.left && mr.left < cr.right) out.cardsOverlap.push({ menu: m.getAttribute('data-probe'), over: c.getAttribute('data-card'), overlapPx: +(Math.min(mr.bottom, cr.bottom) - Math.max(mr.top, cr.top)).toFixed(1) })",
  "    }",
  "  }",
  "  return out",
  "})()",
].join('\n')

const report = await evalJs(expr)
const fs = await import('node:fs')
fs.writeFileSync(OUT, JSON.stringify(report, null, 1))
console.log('doc', JSON.stringify(report.doc))
console.log('overflow', report.overflow.length, JSON.stringify(report.overflow.slice(0, 8)))
console.log('cardsOverlap', JSON.stringify(report.cardsOverlap))
ws.close()
process.exit(0)

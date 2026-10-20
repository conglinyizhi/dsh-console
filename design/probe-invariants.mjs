const CDP_PORT = 9300 + (process.pid % 600) // 按进程取，并行跑不抢端口
// 几何不变量探针：node probe-invariants.mjs <baseUrl> <outJson> [profile]
//
// profile 可以是内置名（vue），也可以是一份 JSON 文件路径 —— 里面就是选择器映射，
// 形如 {"card":".dsh-case","actions":".dsh-actions", ...}。
// 换栈后的新前端类名不同，先 dump DOM 拿到真实类名，写一份 json 就能量，不用改代码。
import { spawn } from 'node:child_process'
import { writeFileSync, readFileSync } from 'node:fs'

const [baseUrl, outJson, profile = 'vue'] = process.argv.slice(2)

const BUILTIN = {
  vue: {
    card: '.row', actions: '.actions', dot: '.dot', dotSlot: '.dot-slot',
    kind: '.kind', name: '.name', splitMain: '.split-main', splitCaret: '.split-caret',
    menuTrigger: '.btn.icon-only', menu: '.menu',
  },
}
let SEL = BUILTIN[profile]
if (!SEL) {
  try {
    SEL = JSON.parse(readFileSync(profile, 'utf8'))
    console.log('用外部选择器映射: ' + profile)
  } catch (e) {
    console.log('既不是内置 profile 也读不到该 json: ' + profile)
    process.exit(1)
  }
}

// 视口可由环境变量给：宽屏那一趟用来覆盖「多列」这条代码路径（默认仍是 1280x900，行为不变）
const VW = Number(process.env.PROBE_VIEWPORT_W || 1280)
const VH = Number(process.env.PROBE_VIEWPORT_H || 900)

const chrome = spawn('chromium', ['--headless', '--no-sandbox', '--disable-gpu', '--disable-extensions',
  '--hide-scrollbars', '--remote-debugging-port=' + CDP_PORT, '--user-data-dir=/tmp/chrome-probe-' + process.pid,
  '--window-size=' + VW + ',' + VH, 'about:blank'], { stdio: 'ignore' })

let page = null
for (let i = 0; i < 40 && !page; i++) {
  try {
    const list = await (await fetch('http://127.0.0.1:' + CDP_PORT + '/json')).json()
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
await send('Emulation.setDeviceMetricsOverride', { width: VW, height: VH, deviceScaleFactor: 1, mobile: false })
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
  // 响应式多列之后，「跨卡对齐」要按列比：不同列的卡片起点不同，跨列比没有意义 ✗
  // 按卡片左缘（取整到 2px，容忍亚像素）分组，各看各列内部是否全等。
  // 列按**卡片**左缘分：已停止的卡没有灯（§26.1），按灯分组会把那些列整列漏掉，
  // 「多列」这一条就会在「只有一张卡在跑」时误判成 1 列。
  const byCol = {}
  for (const c of cards) {
    if (!c.card) continue
    const k = Math.round(c.card.x / 2) * 2
    ;(byCol[k] = byCol[k] || []).push(c.dot && c.dot.x != null ? c.dot.x : null)
  }
  const colResults = Object.entries(byCol).map(([k, xs]) => {
    const dots = xs.filter((x) => x != null)
    return { colX: Number(k), count: xs.length, allEqual: new Set(dots).size <= 1, dotXs: dots }
  })
  return JSON.stringify({
    columns: colResults.length,
    dotXsByColumn: colResults,
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
    position: getComputedStyle(menu).position,
    offsetParentCls: String((menu.offsetParent && menu.offsetParent.className) || '').slice(0, 60),
    parentCls: String((menu.parentElement && menu.parentElement.className) || '').slice(0, 60),
    activeIsFirstItem: (() => { const a = document.activeElement; const f = menu.querySelector('[role=menuitem], .menu-item'); return a && f ? a === f : null })(),
    // 每一项的中心点用 elementFromPoint 反查：拿到的必须是它自己或它的后代。
    // 这一条同时能抓「被祖先 overflow 裁掉」和「被别的元素盖住」——都是"看得见但点不到"。
    itemsReachable: [...menu.querySelectorAll('[role=menuitem], button')].map((e) => {
      const r = e.getBoundingClientRect()
      const hit = document.elementFromPoint(r.x + r.width / 2, r.y + r.height / 2)
      return { text: e.textContent.trim().slice(0, 10), reachable: !!(hit && (hit === e || e.contains(hit))) }
    }),
  })
})()`
const m2 = await send('Runtime.evaluate', { expression: menuExpr, returnByValue: true })
data.menu = JSON.parse(m2.result?.result?.value ?? '{}')

// ── 最后一个触发器的菜单 ──
// 「菜单往下展开」这个模式在**靠底部的卡**上会越出视口被截掉（使用者报过一次）。
// 只测第一张卡永远看不到这个问题 —— 同一模式要测到边界那一格。
await send('Runtime.evaluate', { expression: "(() => { document.body.click(); const t = [...document.querySelectorAll(" + JSON.stringify(SEL.menuTrigger) + ")]; if (t.length) t[t.length - 1].click(); return t.length })()", returnByValue: true })
await new Promise((r) => setTimeout(r, 800))
const lastExpr = `(() => {
  const S = ${JSON.stringify(SEL)}
  const R = (el) => { const r = el.getBoundingClientRect(); return { x: +r.x.toFixed(1), y: +r.y.toFixed(1), w: +r.width.toFixed(1), h: +r.height.toFixed(1), right: +r.right.toFixed(1), bottom: +r.bottom.toFixed(1) } }
  const menu = document.querySelector(S.menu)
  const acts = [...document.querySelectorAll(S.actions)]
  const actions = acts.length ? acts[acts.length - 1] : null
  if (!menu) return JSON.stringify({ opened: false })
  const m = R(menu), vh = innerHeight
  return JSON.stringify({
    opened: true, rect: m, viewportH: vh,
    insideViewport: m.y >= 0 && m.bottom <= vh,
    flipAttr: menu.getAttribute('data-flip') || '',
    deltaTop: actions ? +(m.y - R(actions).bottom).toFixed(1) : null,
    deltaBottom: actions ? +(R(actions).y - m.bottom).toFixed(1) : null,
    deltaRight: actions ? +(m.right - R(actions).right).toFixed(1) : null,
    itemsReachable: [...menu.querySelectorAll('[role=menuitem], button')].map((e) => {
      const r = e.getBoundingClientRect()
      const hit = document.elementFromPoint(r.x + r.width / 2, r.y + r.height / 2)
      return { text: e.textContent.trim().slice(0, 10), reachable: !!(hit && (hit === e || e.contains(hit))) }
    }),
  })
})()`
const m4 = await send('Runtime.evaluate', { expression: lastExpr, returnByValue: true })
data.menuLast = JSON.parse(m4.result?.result?.value ?? '{}')
writeFileSync(outJson, JSON.stringify(data, null, 1))
console.log(JSON.stringify({ overflow: data.overflow, invariants: data.invariants, splitGap: data.split?.gap, menu: data.menu, cardCount: data.cards?.length }, null, 1))
chrome.kill()
process.exit(0)
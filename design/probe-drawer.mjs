// 卡片变条目 + 详情抽屉：新形态的判定（旧的卡片字段/⋯菜单判定本轮退役）
// node probe-drawer.mjs <baseUrl> <outJson>
import { spawn } from 'node:child_process'
import { writeFileSync } from 'node:fs'
const CDP_PORT = 9300 + (process.pid % 600)
const VW = Number(process.env.PROBE_VIEWPORT_W || 1280)
const VH = Number(process.env.PROBE_VIEWPORT_H || 900)
const chrome = spawn('chromium', ['--headless','--no-sandbox','--disable-gpu','--disable-extensions','--hide-scrollbars','--remote-debugging-port=' + CDP_PORT,'--user-data-dir=/tmp/chrome-probe-' + process.pid,'--window-size=' + VW + ',' + VH,'about:blank'], { stdio: 'ignore' })
let page = null
for (let i = 0; i < 40 && !page; i++) { try { const l = await (await fetch('http://127.0.0.1:' + CDP_PORT + '/json')).json(); page = l.find((t) => t.type === 'page') } catch {} if (!page) await new Promise((r) => setTimeout(r, 250)) }
const ws = new WebSocket(page.webSocketDebuggerUrl); let id = 0; const pend = new Map()
ws.onmessage = (e) => { const m = JSON.parse(e.data); if (m.id && pend.has(m.id)) { pend.get(m.id)(m); pend.delete(m.id) } }
await new Promise((r) => { ws.onopen = r })
const send = (m, p = {}) => new Promise((res) => { const i = ++id; pend.set(i, res); ws.send(JSON.stringify({ id: i, method: m, params: p })) })
const ev = async (expression) => { const r = await send('Runtime.evaluate', { expression, returnByValue: true, awaitPromise: true }); return r.result?.result?.value }
const wait = (ms) => new Promise((r) => setTimeout(r, ms))
await send('Page.enable'); await send('Runtime.enable')
await send('Emulation.setDeviceMetricsOverride', { width: VW, height: VH, deviceScaleFactor: 1, mobile: false })
await send('Page.navigate', { url: process.argv[2] }); await wait(5000)
// 卡片：只剩三样？灯的颜色？
// §26.1：已停止那一档**不画灯**（DOM 里没有 .dsh-dot），状态词仍在第一行。
// 所以「灯」与「状态词」要分开取：状态词是每张卡都有的那一格（data-state 与灯上那格同源）。
const cards = JSON.parse(await ev(`JSON.stringify([...document.querySelectorAll('[data-name^=\"instance-card\"]')].map((c) => {
  const dot = c.querySelector('[data-name^=\"status-light\"]')
  // §44 之后状态词不再上卡：卡片根节点上留了 data-state 当机器可读的出口。
  const word = c.querySelector('.dsh-dot-state')
  const shown = dot || word || { getAttribute: () => c.getAttribute('data-state') }
  const cs = dot ? getComputedStyle(dot) : null
  return { id: c.id, text: c.textContent.trim().slice(0, 40), buttons: c.querySelectorAll('button').length, menus: c.querySelectorAll('[data-name^=\"row-menu\"]').length, fields: c.querySelectorAll('[data-name^=\"field\"]').length,
    state: (shown && shown.getAttribute('data-state')) || null, lightPresent: !!dot, lightBg: cs ? cs.backgroundColor : null, lightW: dot ? Math.round(dot.getBoundingClientRect().width) : null, word: word ? word.textContent.trim() : null }
}))`) || '[]')
// 抽屉：点第一张卡打开
const firstId = cards[0] && cards[0].id
await ev(`(() => { const c = document.getElementById(${JSON.stringify(firstId || '')}); if (c) c.click() })()`)
await wait(900)
const opened = JSON.parse(await ev(`(() => {
  // 注意：不能用 [data-name^="drawer"] —— 那会匹到 drawer-close 那个按钮本身 ✗（我踩过）
  const d = document.querySelector('.dsh-drawer')
  if (!d) return JSON.stringify({ open: false })
  const r = d.getBoundingClientRect()
  const btns = [...d.querySelectorAll('button')]
  // 抽屉正文可滚：按钮在折叠线以下时先滚到它再判可达。
  // 不滚就量等于在问「一屏装不装得下」，而不是「点不点得到」——抽屉内容只会越来越长。
  const reach = btns.map((b) => { b.scrollIntoView({ block: 'center' }); const br = b.getBoundingClientRect(); const hit = document.elementFromPoint(br.x + br.width / 2, br.y + br.height / 2); return !!(hit && (hit === b || b.contains(hit))) })
  const back = d.querySelector('.dsh-drawer-body'); if (back) back.scrollTop = 0
  return JSON.stringify({ open: true, rect: { x: Math.round(r.x), w: Math.round(r.width), right: Math.round(r.right) }, vw: innerWidth,
    buttonCount: btns.length,
    // 空集不许算过：按钮数为 0 时一律记 false（「没东西所以全可达」是假绿灯 ✗）
    allReachable: btns.length > 0 && reach.every(Boolean), unreachable: btns.length === 0 ? -1 : reach.filter((x) => !x).length,
    activeIsClose: !!(document.activeElement && (document.activeElement.getAttribute('data-name') || '').includes('close')),
    hasWhy: /为什么|成因|签名|缺/.test(d.textContent), overflow: d.scrollWidth > d.clientWidth })
})()`) || '{}')
// Esc 关 + 焦点回卡
await send('Input.dispatchKeyEvent', { type: 'keyDown', key: 'Escape', code: 'Escape', windowsVirtualKeyCode: 27 })
await send('Input.dispatchKeyEvent', { type: 'keyUp', key: 'Escape', code: 'Escape', windowsVirtualKeyCode: 27 })
await wait(700)
const afterEsc = JSON.parse(await ev(`JSON.stringify({ drawerGone: !document.querySelector('.dsh-drawer'), focusId: document.activeElement ? document.activeElement.id : null })`) || '{}')
const out = { viewport: { VW, VH }, cards, drawer: opened, afterEsc }
writeFileSync(process.argv[3], JSON.stringify(out, null, 1))
console.log(JSON.stringify({ cardCount: cards.length, cardButtons: cards.map((c) => c.buttons), lightStates: cards.map((c) => c.state), lightBgs: cards.map((c) => c.lightBg), drawerOpen: opened.open, drawerButtons: opened.buttonCount, drawerAllReachable: opened.allReachable, activeIsClose: opened.activeIsClose, escClosed: afterEsc.drawerGone, focusBack: afterEsc.focusId }, null, 1))
chrome.kill(); process.exit(0)
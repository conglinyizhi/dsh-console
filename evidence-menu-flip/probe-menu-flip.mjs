// 行菜单翻转（向上折）验收探针：node probe-menu-flip.mjs <baseUrl> [outDir]
// 量的是几何与命中，不是观感：每一条判定都打印实测数字。
import { spawn } from 'node:child_process'
import { writeFileSync, mkdirSync } from 'node:fs'
import { join } from 'node:path'

const CDP_PORT = 9300 + (process.pid % 600)
const [baseUrl, outDir = '.'] = process.argv.slice(2)
if (!baseUrl) { console.log('用法: node probe-menu-flip.mjs <baseUrl> [outDir]'); process.exit(1) }
mkdirSync(outDir, { recursive: true })

const wait = (ms) => new Promise((r) => setTimeout(r, ms))
const chrome = spawn('chromium', ['--headless','--no-sandbox','--disable-gpu','--disable-extensions','--hide-scrollbars','--remote-debugging-port=' + CDP_PORT,'--user-data-dir=/tmp/chrome-flip-' + process.pid,'--window-size=1280,900','about:blank'], { stdio: 'ignore' })
let page = null
for (let i = 0; i < 60 && !page; i++) { try { const l = await (await fetch('http://127.0.0.1:' + CDP_PORT + '/json')).json(); page = l.find((t) => t.type === 'page') } catch {} if (!page) await wait(250) }
const ws = new WebSocket(page.webSocketDebuggerUrl); let id = 0; const pend = new Map()
ws.onmessage = (e) => { const m = JSON.parse(e.data); if (m.id && pend.has(m.id)) { pend.get(m.id)(m); pend.delete(m.id) } }
await new Promise((r) => { ws.onopen = r })
const send = (method, params = {}) => new Promise((res) => { const i = ++id; pend.set(i, res); ws.send(JSON.stringify({ id: i, method, params })) })
const ev = async (e) => { const r = await send('Runtime.evaluate', { expression: e, returnByValue: true, awaitPromise: true }); if (r.result?.exceptionDetails) throw new Error(JSON.stringify(r.result.exceptionDetails).slice(0, 400)); return r.result?.result?.value }
const shot = async (file) => { const r = await send('Page.captureScreenshot', { format: 'png' }); writeFileSync(join(outDir, file), Buffer.from(r.result.data, 'base64')); return file }
const setSize = async (w, h) => { await send('Emulation.setDeviceMetricsOverride', { width: w, height: h, deviceScaleFactor: 1, mobile: false }); await wait(600) }

await send('Page.enable'); await send('Runtime.enable')
await send('Emulation.setDeviceMetricsOverride', { width: 1280, height: 900, deviceScaleFactor: 1, mobile: false })
await send('Page.navigate', { url: baseUrl }); await wait(5500)

const HELP = "\nconst R = (e) => { if (!e) return null; const r = e.getBoundingClientRect(); return { x:+r.x.toFixed(1), y:+r.y.toFixed(1), w:+r.width.toFixed(1), h:+r.height.toFixed(1), top:+r.top.toFixed(1), right:+r.right.toFixed(1), bottom:+r.bottom.toFixed(1) } }\nconst wait = (ms) => new Promise((r) => setTimeout(r, ms))\nconst cards = () => [...document.querySelectorAll('[data-name=\"instance-card\"]')]\nconst menuEl = () => document.querySelector('[data-name=\"row-menu\"]')\nconst scroller = () => document.querySelector('.dsh-main')\nconst closeAny = async () => { document.dispatchEvent(new KeyboardEvent('keydown')); const o = document.querySelector('[data-name=\"menu-overlay\"]'); if (o) o.click(); await wait(350) }\nconst nameOf = (c) => { const n = c.querySelector('.dsh-name'); return n ? n.textContent.trim() : '?' }\nconst reach = (e) => { const r = e.getBoundingClientRect(); const hit = document.elementFromPoint(r.x + r.width / 2, r.y + r.height / 2); return { reachable: !!(hit && (hit === e || e.contains(hit))), hit: hit ? (hit.tagName.toLowerCase() + '.' + String(hit.className || '').slice(0, 30)) : null } }\nconst measure = (which) => {\n  const list = cards()\n  const card = which === 'last' ? list[list.length - 1] : list[0]\n  const trig = card.querySelector('[aria-haspopup=\"menu\"]')\n  const menu = menuEl()\n  const actions = menu ? menu.parentElement : null\n  const vh = window.innerHeight, vw = window.innerWidth\n  const mr = menu ? R(menu) : null\n  const ar = actions ? R(actions) : null\n  const items = menu ? [...menu.querySelectorAll('[role=menuitem], .dsh-menu-item')].map((e) => ({ text: e.textContent.trim().slice(0, 12), rect: R(e), ...reach(e) })) : []\n  return {\n    which, cardName: nameOf(card), vh, vw,\n    flip: menu ? menu.dataset.flip : null,\n    trigger: R(trig), actions: ar, menu: mr,\n    deltaTop: (menu && actions) ? +(mr.top - ar.bottom).toFixed(1) : null,\n    deltaBottom: (menu && actions) ? +(ar.top - mr.bottom).toFixed(1) : null,\n    deltaRight: (menu && actions) ? +(mr.right - ar.right).toFixed(1) : null,\n    inlineMaxHeight: menu ? (menu.style.maxHeight || '(未设，走 CSS calc(100vh - 16px))') : null,\n    menuScroll: menu ? { scrollHeight: menu.scrollHeight, clientHeight: menu.clientHeight, scrollable: menu.scrollHeight > menu.clientHeight } : null,\n    insideViewport: mr ? (mr.top >= 0 && mr.bottom <= vh) : null,\n    itemCount: items.length,\n    unreachable: items.filter((i) => !i.reachable).map((i) => i.text),\n    items,\n    activeIsFirstItem: (() => { if (!menu) return null; const a = document.activeElement; const f = menu.querySelector('.dsh-menu-item'); return a && f ? a === f : null })(),\n    activeId: document.activeElement ? (document.activeElement.id || document.activeElement.tagName) : null,\n  }\n}\n"
const evh = async (body) => ev('(async () => {' + HELP + body + '})()')

const report = { url: baseUrl, steps: [] }
const fail = []
const check = (name, want, got, ok) => { report.steps.push({ name, want, got, ok }); if (!ok) fail.push(name + ' (期望 ' + want + '，实测 ' + got + ')') }

// ── 侦察：卡片数、滚动容器几何 ──
const recon = await evh("return JSON.stringify({ cards: cards().map((c) => ({ name: nameOf(c), rect: R(c), trigger: R(c.querySelector('[aria-haspopup=\"menu\"]')) })), scroller: R(scroller()), scroll: { scrollHeight: scroller().scrollHeight, clientHeight: scroller().clientHeight, scrollTop: scroller().scrollTop } })")
report.recon = JSON.parse(recon)

// ── A. 第一张卡：仍是向下（回归） ──
await evh("await closeAny(); const c = cards()[0]; c.querySelector('[aria-haspopup=\"menu\"]').click(); await wait(700); return 'ok'")
const A = await evh("return JSON.stringify(measure('first'))")
report.first = JSON.parse(A)
check('A 第一张卡 data-flip=down', 'down', report.first.flip, report.first.flip === 'down')
check('A 第一张卡 menu.top - 按钮组底 = 6', '6', String(report.first.deltaTop), report.first.deltaTop === 6)
check('A 第一张卡右缘对齐', '0', String(report.first.deltaRight), report.first.deltaRight === 0)
check('A 第一张卡落焦第一项', 'true', String(report.first.activeIsFirstItem), report.first.activeIsFirstItem === true)
report.steps.push({ name: 'A 截图', want: 'shot', got: await shot('1-first-card-down.png'), ok: true })

// ── B. 最后一张卡（默认 1280x900）：向下放不下 → 向上折 ──
await evh("await closeAny(); const s = scroller(); s.scrollTop = s.scrollHeight; await wait(500); const c = cards(); const last = c[c.length-1]; last.querySelector('[aria-haspopup=\"menu\"]').click(); await wait(700); return 'ok'")
const B = await evh("return JSON.stringify(measure('last'))")
report.last = JSON.parse(B)
check('B 最后一张卡 data-flip=up', 'up', report.last.flip, report.last.flip === 'up')
check('B menu.top ≥ 0', 'true', String(report.last.menu.top), report.last.menu.top >= 0)
check('B menu.bottom ≤ 视口高', 'true', String(report.last.menu.bottom + ' ≤ ' + report.last.vh), report.last.menu.bottom <= report.last.vh)
check('B 右缘仍对齐（翻上去不动右缘）', '0', String(report.last.deltaRight), report.last.deltaRight === 0)
check('B menu.bottom = 按钮组顶 - 6', '6', String(report.last.deltaBottom), report.last.deltaBottom === 6)
check('B 每项都可点到', '[]', JSON.stringify(report.last.unreachable), report.last.unreachable.length === 0)
report.steps.push({ name: 'B 截图', want: 'shot', got: await shot('2-last-card-flip-up.png'), ok: true })

// ── C. 页面滚动：菜单锚点是否跟得住 ──
const C = await evh("const before = measure('last'); const s = scroller(); s.scrollTop = s.scrollTop - 120; await wait(400); const after = measure('last'); s.scrollTop = s.scrollHeight; await wait(300); return JSON.stringify({ before: { deltaTop: before.deltaTop, deltaBottom: before.deltaBottom, deltaRight: before.deltaRight, flip: before.flip, menu: before.menu }, after: { deltaTop: after.deltaTop, deltaBottom: after.deltaBottom, deltaRight: after.deltaRight, flip: after.flip, menu: after.menu, insideViewport: after.insideViewport } })")
report.scroll = JSON.parse(C)
check('C 滚动后仍贴着按钮组（deltaBottom 不变）', String(report.scroll.before.deltaBottom), String(report.scroll.after.deltaBottom), report.scroll.after.deltaBottom === report.scroll.before.deltaBottom)
check('C 滚动后右缘不变', String(report.scroll.before.deltaRight), String(report.scroll.after.deltaRight), report.scroll.after.deltaRight === report.scroll.before.deltaRight)

// ── D. 交互回归：Esc 关 + 焦点回触发元素 / 点外部关 ──
await evh("await closeAny(); return 'ok'")
await evh("const last = cards().slice(-1)[0]; last.querySelector('[aria-haspopup=\"menu\"]').click(); await wait(600); return 'ok'")
await send('Input.dispatchKeyEvent', { type: 'keyDown', key: 'Escape', code: 'Escape', windowsVirtualKeyCode: 27, nativeVirtualKeyCode: 27 })
await send('Input.dispatchKeyEvent', { type: 'keyUp', key: 'Escape', code: 'Escape', windowsVirtualKeyCode: 27, nativeVirtualKeyCode: 27 })
await wait(600)
const D1 = await evh("const last = cards().slice(-1)[0]; const trig = last.querySelector('[aria-haspopup=\"menu\"]'); return JSON.stringify({ menuGone: !menuEl(), focusBackToTrigger: document.activeElement === trig, ariaExpanded: trig.getAttribute('aria-expanded') })")
report.esc = JSON.parse(D1)
check('D Esc 关闭', 'true', String(report.esc.menuGone), report.esc.menuGone === true)
check('D 焦点回触发元素', 'true', String(report.esc.focusBackToTrigger), report.esc.focusBackToTrigger === true)

await evh("const last = cards().slice(-1)[0]; last.querySelector('[aria-haspopup=\"menu\"]').click(); await wait(600); return 'ok'")
await send('Input.dispatchMouseEvent', { type: 'mousePressed', x: 6, y: 6, button: 'left', clickCount: 1 })
await send('Input.dispatchMouseEvent', { type: 'mouseReleased', x: 6, y: 6, button: 'left', clickCount: 1 })
await wait(600)
const D2 = await evh("return JSON.stringify({ menuGone: !menuEl(), overlayGone: !document.querySelector('[data-name=\"menu-overlay\"]') })")
report.outside = JSON.parse(D2)
check('D 点菜单外关闭', 'true', String(report.outside.menuGone), report.outside.menuGone === true)

// ── E. 矮窗口 500px：仍在视口内，且每项都能点到 ──
await evh("await closeAny(); return 'ok'")
await setSize(1280, 500)
const E = await evh("const s = scroller(); s.scrollTop = s.scrollHeight; await wait(500); const c = cards(); const last = c[c.length-1]; last.querySelector('[aria-haspopup=\"menu\"]').click(); await wait(700); return JSON.stringify(measure('last'))")
report.short500 = JSON.parse(E)
check('E(500) data-flip=up', 'up', report.short500.flip, report.short500.flip === 'up')
check('E(500) menu.top ≥ 0', 'true', String(report.short500.menu.top), report.short500.menu.top >= 0)
check('E(500) menu.bottom ≤ 视口高', 'true', String(report.short500.menu.bottom + ' ≤ ' + report.short500.vh), report.short500.menu.bottom <= report.short500.vh)
check('E(500) 每项都能点到', '[]', JSON.stringify(report.short500.unreachable), report.short500.unreachable.length === 0 && report.short500.itemCount > 0)
report.steps.push({ name: 'E 截图', want: 'shot', got: await shot('3-short-500-last-card.png'), ok: true })

// ── F. 极矮窗口 320px：内部滚动兜底，逐项滚到位后仍可点 ──
await evh("await closeAny(); return 'ok'")
await setSize(1280, 320)
const F = await evh("const s = scroller(); s.scrollTop = s.scrollHeight; await wait(500); const c = cards(); const last = c[c.length-1]; const trig = last.querySelector('[aria-haspopup=\"menu\"]'); trig.click(); await wait(700); const m = measure('last'); const menu = menuEl(); m.itemHeights = [...menu.querySelectorAll('.dsh-menu-item')].map((e) => +e.getBoundingClientRect().height.toFixed(1)); m.itemsNotSqueezed = m.itemHeights.every((h) => h === 30); const per = [...menu.querySelectorAll('.dsh-menu-item')].map((e) => { const top = e.offsetTop - menu.offsetTop; menu.scrollTop = Math.max(0, e.offsetTop - menu.offsetTop); const r = e.getBoundingClientRect(); const hit = document.elementFromPoint(r.x + r.width/2, r.y + r.height/2); return { text: e.textContent.trim().slice(0,10), reachable: !!(hit && (hit === e || e.contains(hit))) } }); m.perItemReachableAfterScroll = per; m.allReachableAfterScroll = per.every((x) => x.reachable); m.trig = R(trig); return JSON.stringify(m)")
report.tiny320 = JSON.parse(F)
check('F(320) menu.top ≥ 0', 'true', String(report.tiny320.menu.top), report.tiny320.menu.top >= 0)
check('F(320) menu.bottom ≤ 视口高', 'true', String(report.tiny320.menu.bottom + ' ≤ ' + report.tiny320.vh), report.tiny320.menu.bottom <= report.tiny320.vh)
check('F(320) 逐项滚到位后可点', 'true', String(report.tiny320.allReachableAfterScroll), report.tiny320.allReachableAfterScroll === true)
check('F(320) 菜单内部真能滚（不是把项压扁）', 'true', 'scrollable=' + report.tiny320.menuScroll.scrollable + ' 项高=' + JSON.stringify(report.tiny320.itemHeights), report.tiny320.menuScroll.scrollable === true && report.tiny320.itemsNotSqueezed === true)
report.steps.push({ name: 'F 截图', want: 'shot', got: await shot('4-tiny-320-internal-scroll.png'), ok: true })

// ── G. 菜单开着时来一次真实的 vdom 重渲染：data-flip 与内联钳制必须活下来 ──
await evh("await closeAny(); return 'ok'")
await setSize(1280, 900)
const G = await evh("const s = scroller(); s.scrollTop = s.scrollHeight; await wait(500); const list = cards(); const last = list[list.length-1]; last.querySelector('[aria-haspopup=\"menu\"]').click(); await wait(700); const before = measure('last'); history.pushState({}, '', location.href); window.dispatchEvent(new PopStateEvent('popstate')); await wait(1200); const after = measure('last'); return JSON.stringify({ menuStillOpen: !!menuEl(), before: { flip: before.flip, top: before.menu.top, bottom: before.menu.bottom, maxH: before.inlineMaxHeight }, after: { flip: after.flip, top: after.menu && after.menu.top, bottom: after.menu && after.menu.bottom, maxH: after.inlineMaxHeight, inside: after.insideViewport, unreachable: after.unreachable } })")
report.rerender = JSON.parse(G)
check('G 重渲染后菜单还开着', 'true', String(report.rerender.menuStillOpen), report.rerender.menuStillOpen === true)
check('G 重渲染后 data-flip 没被抹掉', 'up', String(report.rerender.after.flip), report.rerender.after.flip === 'up')
check('G 重渲染后仍在视口内', 'true', 'top=' + report.rerender.after.top + ' bottom=' + report.rerender.after.bottom + ' vh=900', report.rerender.after.inside === true && report.rerender.after.unreachable.length === 0)

report.failed = fail
report.verdict = fail.length === 0 ? 'PASS' : 'FAIL'
writeFileSync(join(outDir, 'menu-flip-report.json'), JSON.stringify(report, null, 1))
for (const s of report.steps) console.log((s.ok ? ' 通过  ' : ' ✗失败 ') + s.name.padEnd(34) + '  期望 ' + String(s.want).slice(0, 22).padEnd(22) + ' 实测 ' + String(s.got).slice(0, 120))
console.log()
console.log('判定 ' + report.steps.length + ' 项：通过 ' + report.steps.filter((s) => s.ok).length + '，失败 ' + fail.length)
if (fail.length) console.log('失败项: ' + fail.join(' / '))
console.log('SUMMARY ' + JSON.stringify({ verdict: report.verdict, failed: fail }))
chrome.kill()
process.exit(0)

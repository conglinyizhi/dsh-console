// 卡片 DOM + 抽屉开合与焦点：node probe-drawer.mjs <baseUrl> [outPrefix]
//
// 三件事：
//   1. 卡片是不是只剩三样 —— 贴卡片 DOM（文本、有没有按钮 / 菜单 / 读数节点）
//   2. 抽屉开合的四条路（点卡开、点外部关、Esc 关、关闭键关）与焦点进 / 回
//   3. 窄屏抽屉占满宽度；抽屉里每颗按钮用 elementFromPoint 反查可达
//
// 另外单独跑一趟「后端还没给 state」：不注入任何 fixture，直接看真后端 ——
// 实例卡必须走 unknown（空心灰环），抽屉里必须写着「这一版后端还没给 state」，**不猜颜色**。
import { launch, evalJson, setViewport, shot, sleep } from './cdp.mjs'
import { writeFileSync } from 'node:fs'

// 把 instances 响应里的 state / stateReason / profileHealth **摘掉**：
// 模拟「后端这一版还没给 state」的那种后端。前端这时必须走 unknown（空心灰环）
// 并把「这一版后端还没给 state 字段，颜色不猜」原样说出来 —— 不许拿签名探测的结果替它定色。
const STRIP_STATE = `(() => {
  const origFetch = window.fetch.bind(window);
  window.fetch = async (input, init) => {
    const url = typeof input === 'string' ? input : (input && input.url) || '';
    const res = await origFetch(input, init);
    if (!url.includes('/api/local/instances')) return res;
    let j;
    try { j = await res.clone().json() } catch (e) { return res }
    for (const it of (j && j.data && j.data.instances) || []) {
      delete it.state; delete it.stateReason; delete it.profileHealth;
    }
    return new Response(JSON.stringify(j), { status: res.status, headers: { 'content-type': 'application/json' } });
  };
})();`

const [baseUrl = 'http://127.0.0.1:5390/', prefix = 'drawer'] = process.argv.slice(2)

const cardDom = `(() => {
  const c = document.querySelector('[data-name="instance-card"]')
  if (!c) return JSON.stringify({ found: false })
  const inner = {
    buttons: c.querySelectorAll('button').length,
    menus: c.querySelectorAll('[data-name="row-menu"], [aria-haspopup="menu"], .dsh-menu').length,
    fields: c.querySelectorAll('[data-name="drawer-field"], .dsh-fields, .dsh-field').length,
    actionGroups: c.querySelectorAll('.dsh-actions').length,
    dots: c.querySelectorAll('.dsh-dot').length,
    names: c.querySelectorAll('.dsh-name').length,
    notes: c.querySelectorAll('[data-name="card-note"]').length,
    tiles: c.querySelectorAll('.dsh-tile').length,
  }
  return JSON.stringify({
    found: true, id: c.id, tag: c.tagName.toLowerCase(),
    role: c.getAttribute('role'), tabindex: c.getAttribute('tabindex'),
    ariaHaspopup: c.getAttribute('aria-haspopup'),
    text: c.textContent.replace(/\s+/g, ' ').trim(),
    childElementCount: c.children.length,
    inner, html: c.outerHTML.replace(/></g, '>\\n<').slice(0, 2600),
  })
})()`

const drawerState = `(() => {
  const d = document.querySelector('[data-name="detail-drawer"]')
  const scrim = document.querySelector('[data-name="drawer-scrim"]')
  const a = document.activeElement
  return JSON.stringify({
    open: !!d,
    scrim: !!scrim,
    activeId: a ? (a.id || '') : '',
    activeIsClose: !!(a && a.id === 'dsh-drawer-close'),
    activeIsCard: !!(a && a.id && a.id.startsWith('dsh-card-')),
    active: a ? (a.id || a.className || a.tagName) : null,
  })
})()`

const { send, close } = await launch({ width: 1440, height: 900, profile: 'drawer' })
await setViewport(send, 1440, 900)

const out = { baseUrl, steps: {} }

// ── 0. 先跑一趟「后端还没给 state 字段」的诚实显示 ──
const strip = await send('Page.addScriptToEvaluateOnNewDocument', { source: STRIP_STATE })
await send('Page.navigate', { url: baseUrl })
await sleep(5000)
await evalJson(send, "(() => { const c = document.querySelector('[data-name=\"instance-card\"]'); if (c) c.click(); return true })()")
await sleep(600)
out.steps.noStateField = await evalJson(send, `(() => {
  const c = document.querySelector('[data-name="instance-card"]')
  const d = document.querySelector('[data-name="detail-drawer"]')
  const dot = c && c.querySelector('.dsh-dot')
  return JSON.stringify({
    cardLight: c ? c.getAttribute('data-light') : null,
    cardDotClass: dot ? dot.className : null,
    cardDotBg: dot ? getComputedStyle(dot).backgroundColor : null,
    cardDotAria: dot ? dot.getAttribute('aria-label') : null,
    drawerLight: d ? d.getAttribute('data-light') : null,
    label: d ? d.querySelector('.dsh-drawer-light-label').textContent.trim() : null,
    why: d ? d.querySelector('[data-name="drawer-why"]').textContent.trim() : null,
    // 技术依据在悬停里（正文一个字不占）
    whyHover: d ? d.querySelector('[data-name="drawer-why"]').getAttribute('title') : null,
  })
})()`)
await shot(send, prefix + '-no-state-field.png')
await evalJson(send, "(() => { const b = document.getElementById('dsh-drawer-close'); if (b) b.click(); return true })()")
await sleep(400)
// 把那个脚本摘掉再重新载入：后面几步走真后端（state 已经落地的那一版）
await send('Page.removeScriptToEvaluateOnNewDocument', { identifier: strip.result.identifier })
await send('Page.navigate', { url: baseUrl })
await sleep(5000)

const cd = await evalJson(send, cardDom)
out.card = cd
out.steps.cardDom = cd

// ── 2. 抽屉开合的四条路 + 焦点 ──
const open = async () => { await evalJson(send, "(() => { document.querySelector('[data-name=\"instance-card\"]').click(); return true })()"); await sleep(500) }
const state = async () => await evalJson(send, drawerState)
const esc = async () => {
  await send('Input.dispatchKeyEvent', { type: 'keyDown', key: 'Escape', code: 'Escape', windowsVirtualKeyCode: 27, nativeVirtualKeyCode: 27 })
  await send('Input.dispatchKeyEvent', { type: 'keyUp', key: 'Escape', code: 'Escape', windowsVirtualKeyCode: 27, nativeVirtualKeyCode: 27 })
  await sleep(500)
}

await open()
out.steps.openByCard = await state()
await shot(send, prefix + '-wide.png')
await esc()
out.steps.closedByEsc = await state()

await open()
await evalJson(send, "(() => { const s = document.querySelector('[data-name=\"drawer-scrim\"]'); if (s) s.click(); return true })()")
await sleep(500)
out.steps.closedByOutside = await state()

await open()
await evalJson(send, "(() => { const b = document.getElementById('dsh-drawer-close'); if (b) b.click(); return true })()")
await sleep(500)
out.steps.closedByButton = await state()

// 键盘开：Tab 到卡片再按 Enter
await evalJson(send, "(() => { document.querySelector('[data-name=\"instance-card\"]').focus(); return true })()")
await send('Input.dispatchKeyEvent', { type: 'keyDown', key: 'Enter', code: 'Enter', windowsVirtualKeyCode: 13, nativeVirtualKeyCode: 13 })
await send('Input.dispatchKeyEvent', { type: 'keyUp', key: 'Enter', code: 'Enter', windowsVirtualKeyCode: 13, nativeVirtualKeyCode: 13 })
await sleep(500)
out.steps.openByKeyboard = await state()

// ── 3. 抽屉里每颗按钮的可达性（宽屏）+ 六格读数 ──
out.steps.reachWide = await evalJson(send, `(() => {
  const d = document.querySelector('[data-name="detail-drawer"]')
  // 反查前先把按钮滚进可视区：抽屉内容超出高度时下面的按钮在视口外，
  // elementFromPoint 对视口外的坐标恒返回 null —— 那是「还没滚到」，不是「点不到」。
  const hitOf = (b) => {
    const r0 = b.getBoundingClientRect()
    const inView = r0.top >= 0 && r0.bottom <= innerHeight
    if (!inView) b.scrollIntoView({ block: 'center' })
    const r = b.getBoundingClientRect()
    const hit = document.elementFromPoint(r.x + r.width / 2, r.y + r.height / 2)
    return { reachable: !!(hit && (hit === b || b.contains(hit))), neededScroll: !inView,
      hittag: hit ? hit.tagName.toLowerCase() + '.' + String(hit.className).slice(0, 24) : null }
  }
  const btns = [...d.querySelectorAll('button')]
  return JSON.stringify({
    buttons: btns.map((b) => Object.assign({ action: b.getAttribute('data-action') || 'close', text: b.textContent.trim(), disabled: b.disabled }, hitOf(b))),
    fieldCount: d.querySelectorAll('[data-name="drawer-field"]').length,
    fieldLabels: [...d.querySelectorAll('[data-name="drawer-field"]')].map((f) => f.querySelector('.dsh-field-label').textContent.trim()),
    scrollable: (() => { const b = d.querySelector('.dsh-drawer-body'); return { scrollH: b.scrollHeight, clientH: b.clientHeight, canScroll: b.scrollHeight > b.clientHeight, overflowY: getComputedStyle(b).overflowY } })(),
  })
})()`)
await shot(send, prefix + '-buttons-wide.png')

// ── 4. 窄屏：抽屉占满宽度 + 每颗按钮仍可达 ──
await setViewport(send, 400, 780)
await sleep(600)
// 先滚回顶部拍一张（上一段反查可达性时把内容滚下去了），再量可达性
await evalJson(send, "(() => { const b = document.querySelector('.dsh-drawer-body'); if (b) b.scrollTop = 0; return true })()")
await sleep(150)
await shot(send, prefix + '-narrow.png')
out.steps.narrow = await evalJson(send, `(() => {
  const d = document.querySelector('[data-name="detail-drawer"]')
  const r = d.getBoundingClientRect()
  const de = document.documentElement
  const hitOf = (b) => {
    const r0 = b.getBoundingClientRect()
    const inView = r0.top >= 0 && r0.bottom <= innerHeight
    if (!inView) b.scrollIntoView({ block: 'center' })
    const r = b.getBoundingClientRect()
    const hit = document.elementFromPoint(r.x + r.width / 2, r.y + r.height / 2)
    return { reachable: !!(hit && (hit === b || b.contains(hit))), neededScroll: !inView }
  }
  const btns = [...d.querySelectorAll('button')].map((b) => Object.assign({ text: b.textContent.trim() }, hitOf(b)))
  return JSON.stringify({
    drawerW: +r.width.toFixed(1), viewportW: innerWidth, left: +r.left.toFixed(1),
    fullWidth: Math.abs(r.width - innerWidth) <= 1,
    pageOverflowX: de.scrollWidth > de.clientWidth,
    drawerOverflowX: d.scrollWidth > d.clientWidth,
    buttons: btns.length, unreachable: btns.filter((b) => !b.reachable).map((b) => b.text),
  })
})()`)

writeFileSync(prefix + '.json', JSON.stringify(out, null, 1))
console.log(JSON.stringify(out, null, 1))
close()
process.exit(0)

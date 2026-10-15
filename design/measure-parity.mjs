const CDP_PORT = 9300 + (process.pid % 600) // 按进程取，并行跑不抢端口
// 逐条对账用：把验收清单里的几何不变量与交互在真实 DOM 上量一遍。
//   node design/measure-parity.mjs <baseUrl>
// 与 verify-frontend.mjs 的分工：那个管「有没有横向溢出 / 控制台报错 / 真数据在不在」，
// 这个量清单第五节那 12 条，以及导航、菜单、对话框、日志页、派生这些行为。
// 为了不依赖任何第三方浏览器库，这里直接用 CDP；探针写成单行表达式。
import { spawn } from 'node:child_process'

const baseUrl = process.argv[2] ?? 'http://127.0.0.1:5390'
const chrome = spawn('chromium', ['--headless', '--no-sandbox', '--disable-gpu', '--disable-extensions',
  '--hide-scrollbars', '--remote-debugging-port=' + CDP_PORT, '--user-data-dir=/tmp/chrome-probe-' + process.pid,
  '--window-size=1280,900', 'about:blank'], { stdio: 'ignore' })

let page = null
for (let i = 0; i < 40 && !page; i++) {
  try {
    const list = await (await fetch('http://127.0.0.1:' + CDP_PORT + '/json')).json()
    page = list.find((t) => t.type === 'page')
  } catch {}
  if (!page) await new Promise((r) => setTimeout(r, 250))
}
if (!page) { console.log(JSON.stringify({ ok: false, error: 'chrome 没起来' })); process.exit(1) }

const ws = new WebSocket(page.webSocketDebuggerUrl)
let id = 0
const pending = new Map()
const consoleIssues = []
ws.onmessage = (e) => {
  const m = JSON.parse(e.data)
  if (m.method === 'Runtime.consoleAPICalled' && ['error', 'warning'].includes(m.params?.type)) {
    consoleIssues.push(m.params.type + ': ' + (m.params.args || []).map((a) => a.value ?? a.description ?? '').join(' ').slice(0, 200))
  }
  if (m.method === 'Log.entryAdded' && m.params?.entry?.level === 'error') {
    consoleIssues.push('log: ' + String(m.params.entry.text).slice(0, 200))
  }
  if (m.id && pending.has(m.id)) { pending.get(m.id)(m); pending.delete(m.id) }
}
await new Promise((r) => { ws.onopen = r })
const send = (method, params = {}) => new Promise((res) => { const i = ++id; pending.set(i, res); ws.send(JSON.stringify({ id: i, method, params })) })
const sleep = (ms) => new Promise((r) => setTimeout(r, ms))
const NL = String.fromCharCode(10)

const evalJs = async (expression) => {
  const res = await send('Runtime.evaluate', { expression, returnByValue: true, awaitPromise: true })
  if (res.result?.exceptionDetails) return { __error: JSON.stringify(res.result.exceptionDetails).slice(0, 300) }
  return res.result?.result?.value
}
const press = async (keyName, keyCode) => {
  await send('Input.dispatchKeyEvent', { type: 'keyDown', key: keyName, code: keyName, windowsVirtualKeyCode: keyCode })
  await send('Input.dispatchKeyEvent', { type: 'keyUp', key: keyName, code: keyName, windowsVirtualKeyCode: keyCode })
  await sleep(150)
}
const clickSel = async (selector) => {
  const done = await evalJs('(() => { const el = document.querySelector(' + JSON.stringify(selector) + '); if (!el) return false; el.click(); return true })()')
  await sleep(220)
  return done
}
const flatten = (text) => String(text).split(NL).join(' / ')

await send('Runtime.enable')
await send('Log.enable')
await send('Page.enable')
await send('Emulation.setDeviceMetricsOverride', { width: 1280, height: 900, deviceScaleFactor: 1, mobile: false })
await send('Page.navigate', { url: baseUrl })
await sleep(3000)

const out = { url: baseUrl }

// ── 一、卡片几何：两行卡头 / 状态点槽位 / 类型标签列 / 按钮组右缘 ──
out.geometry = await evalJs("(() => { const round = n => Math.round(n * 100) / 100; const cards = [...document.querySelectorAll('[data-name=instance-card]')]; const rows = cards.map(card => { const box = card.getBoundingClientRect(); const cs = getComputedStyle(card); const contentRight = box.right - parseFloat(cs.paddingRight) - parseFloat(cs.borderRightWidth); const name = card.querySelector('.dsh-name').getBoundingClientRect(); const sub = card.querySelector('.dsh-sub').getBoundingClientRect(); const kind = card.querySelector('.dsh-kind').getBoundingClientRect(); const slot = card.querySelector('.dsh-dot-slot').getBoundingClientRect(); const dot = card.querySelector('.dsh-dot').getBoundingClientRect(); const actions = card.querySelector('.dsh-actions').getBoundingClientRect(); return { instance: card.dataset.instance, status: card.querySelector('.dsh-sub').dataset.status, nameLeft: round(name.left), nameTop: round(name.top), nameBottom: round(name.bottom), subLeft: round(sub.left), subTop: round(sub.top), kindWidth: round(kind.width), kindRight: round(kind.right), slotX: round(slot.left), slotW: round(slot.width), dotW: round(dot.width), gapKindDot: round(slot.left - kind.right), actionsRight: round(actions.right), contentRight: round(contentRight), deltaActionsRight: round(actions.right - contentRight) } }); const spread = vs => vs.length > 1 ? round(Math.max(...vs) - Math.min(...vs)) : null; return { cards: rows, dotSlotSpread: spread(rows.map(r => r.slotX)), nameLeftSpread: spread(rows.map(r => r.nameLeft)), subLeftSpread: spread(rows.map(r => r.subLeft)), nameSubGap: rows.length ? round(rows[0].subTop - rows[0].nameBottom) : null } })()")

// ── 二、不得有过渡动画（启动态状态点的 dot-pulse 是唯一例外） ──
out.motion = await evalJs("(() => { const hits = []; for (const el of document.querySelectorAll('*')) { const box = el.getBoundingClientRect(); if (box.width === 0 && box.height === 0) continue; const cs = getComputedStyle(el); const dur = cs.transitionDuration.split(',').map(s => parseFloat(s)); const hasTransition = cs.transitionProperty !== 'none' && dur.some(d => d > 0); const hasAnimation = cs.animationName !== 'none'; if (hasTransition || hasAnimation) hits.push(String(el.className).slice(0, 40) + ' | ' + cs.transitionProperty + ' ' + cs.transitionDuration + ' | ' + cs.animationName + ' ' + cs.animationDuration) } return { count: hits.length, hits: hits.slice(0, 10) } })()")

// ── 三、菜单：锚点 / 落焦第一项 / Esc 回触发元素 / 点外关闭 ──
out.menu = {}
await clickSel('.dsh-btn.icon-only')
out.menu.opened = await evalJs("(() => { const menu = document.querySelector('.dsh-menu'); if (!menu) return { open: false }; const actions = menu.closest('.dsh-actions'); const m = menu.getBoundingClientRect(); const a = actions.getBoundingClientRect(); const items = menu.querySelectorAll('.dsh-menu-item'); return { open: true, deltaTop: Math.round((m.top - a.bottom) * 100) / 100, deltaRight: Math.round((m.right - a.right) * 100) / 100, position: getComputedStyle(menu).position, activeIsFirstItem: document.activeElement === items[0], activeText: (document.activeElement ? document.activeElement.innerText : '').trim(), itemCount: items.length, separators: menu.querySelectorAll('.dsh-menu-sep').length, hasOverlay: !!document.querySelector('.dsh-menu-overlay'), actions: [...items].map(b => b.dataset.action) } })()")
await press('Escape', 27)
out.menu.afterEscape = await evalJs("(() => ({ menuOpen: !!document.querySelector('.dsh-menu'), focusOnTrigger: document.activeElement.classList.contains('icon-only') || document.activeElement.classList.contains('split-caret'), activeLabel: document.activeElement.getAttribute('aria-label') || '' }))()")
await clickSel('.dsh-btn.icon-only')
await clickSel('.dsh-menu-overlay')
out.menu.afterOutsideClick = await evalJs("({ menuOpen: !!document.querySelector('.dsh-menu') })")

// ── 四、重命名框：预填全选 / 空格禁用确定 / Esc 回触发元素 ──
out.rename = {}
await clickSel('.dsh-btn.icon-only')
await clickSel('.dsh-menu-item[data-action=rename]')
out.rename.opened = await evalJs("(() => { const input = document.querySelector('#dsh-rename-input'); if (!input) return { open: false }; return { open: true, value: input.value, selectionStart: input.selectionStart, selectionEnd: input.selectionEnd, length: input.value.length, focused: document.activeElement === input, confirmDisabled: document.querySelector('.dsh-dialog-btn.primary').disabled } })()")
const setDraft = async (text) => {
  await evalJs('(() => { const el = document.querySelector(' + JSON.stringify('#dsh-rename-input') + '); el.value = ' + JSON.stringify(text) + '; el.dispatchEvent(new Event(' + JSON.stringify('input') + ', { bubbles: true })); })()')
  await sleep(240)
  return evalJs("document.querySelector('.dsh-dialog-btn.primary').disabled")
}
out.rename.emptyDisabled = await setDraft('')
out.rename.spacesDisabled = await setDraft('   ')
await press('Escape', 27)
out.rename.afterEscape = await evalJs("({ dialogOpen: !!document.querySelector('#dsh-rename-input'), activeClass: document.activeElement.className, activeLabel: document.activeElement.getAttribute('aria-label') || '' })")


// ── 四点五、重命名：Enter 确认后名字真的换、焦点回到触发元素 ──
out.rename.flow = []
out.rename.flow.push({ step: 'click-trigger', found: await clickSel('.dsh-btn.icon-only'), menuOpen: await evalJs("!!document.querySelector('.dsh-menu')") })
out.rename.flow.push({ step: 'click-rename', found: await clickSel('.dsh-menu-item[data-action=rename]'), dialogOpen: await evalJs("!!document.querySelector('#dsh-rename-input')"), focused: await evalJs("document.activeElement && document.activeElement.id === 'dsh-rename-input'") })
out.rename.flow.push({ step: 'set-draft', disabled: await setDraft('renamed-dev') })
out.rename.flow.push({ step: 'draft-in-model', value: await evalJs("document.querySelector('#dsh-rename-input') ? document.querySelector('#dsh-rename-input').value : null"), disabled: await evalJs("document.querySelector('.dsh-dialog-btn.primary').disabled") })
await press('Enter', 13)
await sleep(350)
out.rename.afterEnter = await evalJs("(() => ({ dialogOpen: !!document.querySelector('#dsh-rename-input'), names: [...document.querySelectorAll('[data-name=instance-card]')].map(c => c.dataset.instance), activeLabel: document.activeElement.getAttribute('aria-label') || '' }))()")

// ── 四点六、两段式按钮几何 ── **已退役（2026-10-15，使用者决定）**
// 分段按钮撤了：「启动 ▾」的形状暗示有多种启动方式，而实际只有一种。
// 现在已停止卡是「启动」+「重启」+ 独立「⋯」（与运行中卡一致）。
// **这是有意识放弃的基线，不是回归** —— 不再量，也别拿它当红灯。
await forceHover('.dsh-field')
out.fieldHover = await evalJs("(() => { const f = document.querySelector('.dsh-field'); const card = f.closest('.dsh-case'); return { beforeBg: getComputedStyle(f, '::before').backgroundColor, beforeInset: getComputedStyle(f, '::before').inset, cardBg: getComputedStyle(card).backgroundColor } })()")
await clearHover('.dsh-field')
await forceHover('.dsh-btn.icon-only')
out.buttonHover = await evalJs("(() => { const b = document.querySelector('.dsh-btn.icon-only'); const cs = getComputedStyle(b); return { background: cs.backgroundColor, borderColor: cs.borderColor, filter: cs.filter } })()")
await clearHover('.dsh-btn.icon-only')

// 四点七 与悬停相关的量在下面统一用 forcePseudoState 做（见 hoverAdd 段）

// ── 五、删除确认框 ──
out.confirm = {}
await clickSel('.dsh-btn.icon-only')
out.confirm.menuHasDelete = await evalJs("!!document.querySelector('.dsh-menu-item[data-action=delete]')")
if (out.confirm.menuHasDelete) {
  await clickSel('.dsh-menu-item[data-action=delete]')
  out.confirm.opened = await evalJs("(() => { const card = document.querySelector('.dsh-dialog-card'); if (!card) return { open: false }; return { open: true, title: card.querySelector('.dsh-dialog-title').innerText, focusOnConfirm: document.activeElement.id === 'dsh-confirm-ok', buttons: [...card.querySelectorAll('button')].map(b => b.innerText.trim()) } })()")
  await clickSel('.dsh-dialog-btn:not(.primary)')
  out.confirm.afterCancel = await evalJs("({ dialogOpen: !!document.querySelector('.dsh-dialog-card'), activeLabel: document.activeElement.getAttribute('aria-label') || '' })")
}

// ── 六、启动等待态：整行禁用（含两段式两半） ──
out.starting = {}
out.starting.splitFound = await evalJs("(() => { const b = document.querySelector('.dsh-split-main'); if (!b) return false; b.click(); return true })()")
await sleep(320)
out.starting.duringWait = await evalJs("(() => { const card = [...document.querySelectorAll('[data-name=instance-card]')].find(c => c.querySelector('.dsh-sub').dataset.status === 'starting'); if (!card) return { found: false }; const buttons = [...card.querySelectorAll('.dsh-actions button')]; const dot = getComputedStyle(card.querySelector('.dsh-dot')); return { found: true, allDisabled: buttons.every(b => b.disabled), buttons: buttons.map(b => b.innerText.trim().slice(0, 10) + ':' + b.disabled), tail: card.querySelector('.dsh-tail').innerText, dotAnimation: dot.animationName + ' ' + dot.animationDuration } })()")
await sleep(2900)
out.starting.afterWait = await evalJs("(() => { const card = [...document.querySelectorAll('[data-name=instance-card]')].find(c => (c.dataset.instance || '').startsWith('staging')); return { statuses: [...document.querySelectorAll('.dsh-sub')].map(s => s.dataset.status), stagingStatus: card ? card.querySelector('.dsh-sub').dataset.status : null } })()")

// ── 七、归档区：折叠 / 展开 ──
out.archived = {}
out.archived.before = await evalJs("({ hasToggle: !!document.querySelector('.dsh-collapse'), rows: document.querySelectorAll('.dsh-archive-row').length, title: document.querySelector('.dsh-collapse').innerText.trim() })")
await clickSel('.dsh-collapse')
out.archived.collapsed = await evalJs("({ rows: document.querySelectorAll('.dsh-archive-row').length })")
await clickSel('.dsh-collapse')
out.archived.expanded = await evalJs("({ rows: document.querySelectorAll('.dsh-archive-row').length })")

// 取消归档：从归档区回到「已停止的实例」组
out.unarchive = {}
out.unarchive.before = await evalJs("({ archivedRows: document.querySelectorAll('.dsh-archive-row').length, stoppedStatuses: [...document.querySelectorAll('.dsh-sub')].filter(s => s.dataset.status === 'stopped').length })")
await clickSel('.dsh-archive-btn:not(.danger)')
out.unarchive.after = await evalJs("({ archivedRows: document.querySelectorAll('.dsh-archive-row').length, hasToggle: !!document.querySelector('.dsh-collapse'), instances: [...document.querySelectorAll('[data-name=instance-card]')].map(c => c.dataset.instance), archivedStopped: [...document.querySelectorAll('[data-name=instance-card]')].filter(c => (c.dataset.instance || '').indexOf('old-experiment') >= 0).map(c => c.querySelector('.dsh-sub').dataset.status) })")

// ── 七点五、归档行上的删除确认框（运行中实例不可删，删除入口在归档行） ──
out.confirmByArchive = {}
out.confirmByArchive.hasDeleteButton = await evalJs("!!document.querySelector('.dsh-archive-btn.danger')")
await clickSel('.dsh-archive-btn.danger')
out.confirmByArchive.opened = await evalJs("(() => { const card = document.querySelector('.dsh-dialog-card'); if (!card) return { open: false }; return { open: true, title: card.querySelector('.dsh-dialog-title').innerText, focusOnConfirm: document.activeElement.id === 'dsh-confirm-ok', buttons: [...card.querySelectorAll('button')].map(b => b.innerText.trim()) } })()")
await clickSel('.dsh-dialog-btn:not(.primary)')
out.confirmByArchive.afterCancel = await evalJs("({ dialogOpen: !!document.querySelector('.dsh-dialog-card'), focusBackId: document.activeElement.id, focusBackClass: document.activeElement.className.slice(0, 40) })")

// ── 八、导航切页 + 日志页 ──
out.nav = {}
const urlBefore = await evalJs('location.href')
await clickSel('[data-name=nav-logs]')
await sleep(1500)
out.nav.logs = await evalJs("(() => { const select = document.querySelector('#log-source'); const box = document.querySelector('.dsh-log-box'); const line = box ? box.querySelector('.dsh-log-line') : null; return { onLogs: !!select, url: location.href, selectValue: select ? select.value : null, options: select ? [...select.options].map(o => o.value + (o.disabled ? ' [disabled]' : '') + ' | ' + o.text) : [], meta: document.querySelector('.dsh-meta') ? document.querySelector('.dsh-meta').innerText : '', badge: document.querySelector('.dsh-badge-label') ? document.querySelector('.dsh-badge-label').innerText : '', lines: document.querySelectorAll('.dsh-log-line').length, fontFamily: line ? getComputedStyle(line).fontFamily : '', whiteSpace: line ? getComputedStyle(line).whiteSpace : '', atBottom: box ? Math.abs(box.scrollTop + box.clientHeight - box.scrollHeight) <= 2 : null, scrollTop: box ? box.scrollTop : null, scrollHeight: box ? box.scrollHeight : null, clientHeight: box ? box.clientHeight : null, levels: { error: document.querySelectorAll('.dsh-lv-error').length, warn: document.querySelectorAll('.dsh-lv-warn').length, none: document.querySelectorAll('.dsh-lv-none').length, errorColor: document.querySelector('.dsh-lv-error') ? getComputedStyle(document.querySelector('.dsh-lv-error')).color : null, errorText: document.querySelector('.dsh-lv-error') ? document.querySelector('.dsh-lv-error').innerText : null, noneColor: document.querySelector('.dsh-lv-none') ? getComputedStyle(document.querySelector('.dsh-lv-none')).color : null }, longestLineScrollW: box ? Math.max(0, ...[...box.querySelectorAll('.dsh-log-line')].map(l => l.scrollWidth)) : null, boxScrollWidth: box ? box.scrollWidth : null, boxClientWidth: box ? box.clientWidth : null } })()")
out.nav.urlUnchanged = urlBefore === (await evalJs('location.href'))
out.nav.picked = await evalJs("(() => { const s = document.querySelector('#log-source'); const o = [...s.options].find(x => x.value === 'host'); s.value = o.value; s.dispatchEvent(new Event('change', { bubbles: true })); return o.value })()")
await sleep(1500)
out.nav.afterSwitch = await evalJs("(() => { const box = document.querySelector('.dsh-log-box'); return { selectValue: document.querySelector('#log-source').value, lines: document.querySelectorAll('.dsh-log-line').length, atBottom: box ? Math.abs(box.scrollTop + box.clientHeight - box.scrollHeight) <= 2 : null, levels: { error: document.querySelectorAll('.dsh-lv-error').length, none: document.querySelectorAll('.dsh-lv-none').length, errorColor: document.querySelector('.dsh-lv-error') ? getComputedStyle(document.querySelector('.dsh-lv-error')).color : null }, meta: document.querySelector('.dsh-meta').innerText.slice(0, 200) } })()")
await clickSel('[data-name=nav-about]')
await sleep(500)
out.nav.about = await evalJs("(() => { const text = document.body.innerText; return { hasNodeVersion: text.indexOf('node 版本') >= 0, rows: [...document.querySelectorAll('.dsh-row')].map(r => r.innerText.split(String.fromCharCode(10)).join(' ')), foot: document.querySelector('.dsh-foot') ? document.querySelector('.dsh-foot').innerText : '' } })()")

// ── 九、派生开发副本 ──
await clickSel('[data-name=nav-overview]')
await sleep(500)
out.fork = {}
await clickSel('.dsh-btn.icon-only')
out.fork.clicked = await clickSel('.dsh-menu-item[data-action=fork]')
await sleep(700)
out.fork.immediately = await evalJs("(() => { const cards = [...document.querySelectorAll('[data-name=instance-card]')]; const card = cards.find(c => (c.dataset.instance || '').startsWith('plugin-dev')); return { instances: cards.map(c => c.dataset.instance), newCard: !!card, tail: card ? card.querySelector('.dsh-tail').innerText : '', allDisabled: card ? [...card.querySelectorAll('.dsh-actions button')].every(b => b.disabled) : null } })()")
await sleep(3500)
out.fork.afterWait = await evalJs("(() => { const card = [...document.querySelectorAll('[data-name=instance-card]')].find(c => (c.dataset.instance || '').startsWith('plugin-dev')); if (!card) return { found: false }; return { found: true, status: card.querySelector('.dsh-sub').dataset.status, fields: [...card.querySelectorAll('.dsh-field')].map(f => f.innerText.split(String.fromCharCode(10)).join(' ')), tail: card.querySelector('.dsh-tail').innerText } })()")


// ── 九点五、重启的自锁态 与 归档动作 ──
out.restart = {}
out.restart.triggered = await evalJs("(() => { const b = [...document.querySelectorAll('.dsh-actions button')].find(x => x.innerText.trim() === '重启'); if (!b) return false; b.click(); return true })()")
await sleep(250)
out.restart.duringLock = await evalJs("(() => { const b = [...document.querySelectorAll('.dsh-actions button')].find(x => x.innerText.indexOf('重启中') >= 0); return b ? { label: b.innerText.trim(), disabled: b.disabled } : { label: null } })()")
await sleep(1000)
out.restart.afterLock = await evalJs("(() => { const b = [...document.querySelectorAll('.dsh-actions button')].find(x => x.innerText.indexOf('重启') >= 0); return b ? { label: b.innerText.trim(), disabled: b.disabled } : { label: null } })()")
out.archiveAction = {}
out.archiveAction.before = await evalJs("({ archivedRows: document.querySelectorAll('.dsh-archive-row').length, stoppedNames: [...document.querySelectorAll('[data-name=instance-card]')].filter(c => c.querySelector('.dsh-sub').dataset.status === 'stopped').map(c => c.dataset.instance) })")
await clickSel('#dsh-trigger-profile-review-dev')
out.archiveAction.menuOpened = await evalJs("!!document.querySelector('.dsh-menu')")
await clickSel('.dsh-menu-item[data-action=archive]')
out.archiveAction.after = await evalJs("(() => ({ archivedRows: document.querySelectorAll('.dsh-archive-row').length, archivedNames: [...document.querySelectorAll('.dsh-archive-name')].map(n => n.innerText), stoppedNames: [...document.querySelectorAll('[data-name=instance-card]')].filter(c => c.querySelector('.dsh-sub').dataset.status === 'stopped').map(c => c.dataset.instance), menuClosed: !document.querySelector('.dsh-menu') }))()")

// ── 十、favicon 与刷新回总览 ──
out.favicon = await evalJs("(() => { const link = document.querySelector('link[rel~=icon]'); return link ? link.getAttribute('href').slice(0, 48) : null })()")
await send('Page.navigate', { url: baseUrl })
await sleep(2600)
out.afterReload = await evalJs("({ head: document.body.innerText.slice(0, 16), onOverview: document.body.innerText.indexOf('实例总览') >= 0 })")
out.overflow = await evalJs("({ scrollW: document.documentElement.scrollWidth, clientW: document.documentElement.clientWidth })")
out.consoleIssues = consoleIssues.slice(0, 10)
out.consoleIssueCount = consoleIssues.length
console.log(JSON.stringify(out, null, 1))
chrome.kill()
process.exit(0)
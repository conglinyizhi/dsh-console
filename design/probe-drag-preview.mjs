// 拖动的落点预览（第十二轮）：占位块就是将来那一格。
//
// node probe-drag-preview.mjs <baseUrl> <outJson> [shotPrefix]
//
// 判定项（每一条都把原始读数写进 outJson，结论不靠嘴说）：
//   ① 逐帧：真指针按下-移动-松开的全程，每一帧采一次
//      （虚影的位置 / 占位块所在的格子序号 / 其余条目各在哪一格）
//   ② 预览与结果逐格一致：三个不同落点各一次 —— 松手后的顺序 == 松手前占位块那一格
//   ③ 键盘 Ctrl+↓：先亮出占位块（预览那一拍）再落位，落点与预览同格
//   ④ 窄屏 360 不响应拖动
//   ⑤ 跨组拖动作废（顺序一个字节不动）
//   ⑥ 写回失败回滚（状态目录设成不可写那一趟）
//   ⑦ 点击不误触发（位移 0 的一次按下-松开：开抽屉、顺序不动）
//   ⑧ prefers-reduced-motion：占位块仍在、让位不做过渡（FLIP 返回 0）
//
// 隔离：跑之前把 XDG_STATE_HOME 指到一个临时目录（见 README），
// 这样 order.json 写在那儿，不碰使用者的状态目录。
import { spawn } from 'node:child_process'
import { writeFileSync, readFileSync, existsSync, mkdirSync, chmodSync } from 'node:fs'
import { dirname, join } from 'node:path'

const CDP_PORT = 9400 + (process.pid % 500)
const [baseUrl, outJson, shotPrefix] = process.argv.slice(2)
// 三个落点那几趟跑在 **810 宽**（两列）上：1280 下这一组只有一行 3 条，落点只可能
// 是第 0 格或第 1 格 —— 「三个不同落点」在单行里根本凑不出来。两列时这一组会折成
// 两行，于是第 0 / 1 / 2 格都够得着，多行那套格子算法也顺带被走到。
// 其余各段（点击、跨组、窄屏、reduced-motion）仍按 1280 跑。
const TRIAL_VW = 810
const VW = 1280, VH = 900
const stateDir = process.env.DRAG_STATE_DIR || ''
const orderFile = stateDir ? join(stateDir, 'dsh-console', 'order.json') : ''
const OUT = outJson || '/tmp/drag-preview.json'

const chrome = spawn('chromium', ['--headless', '--no-sandbox', '--disable-gpu', '--disable-extensions',
  '--hide-scrollbars', '--remote-debugging-port=' + CDP_PORT, '--user-data-dir=/tmp/chrome-preview-' + process.pid,
  '--window-size=' + VW + ',' + VH, '--noerrdialogs', '--no-first-run', '--ozone-platform=headless',
  '--ozone-override-screen-size=800,600', '--use-angle=swiftshader-webgl', 'about:blank'], { stdio: 'ignore' })

let page = null
for (let i = 0; i < 60 && !page; i++) {
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
const ev = async (expression) => { const r = await send('Runtime.evaluate', { expression, returnByValue: true, awaitPromise: true }); return r.result?.result?.value }
const wait = (ms) => new Promise((r) => setTimeout(r, ms))
await send('Page.enable'); await send('Runtime.enable')
await send('Emulation.setDeviceMetricsOverride', { width: VW, height: VH, deviceScaleFactor: 1, mobile: false })

const down = (x, y) => send('Input.dispatchMouseEvent', { type: 'mousePressed', x: Math.round(x), y: Math.round(y), button: 'left', buttons: 1, clickCount: 1 })
const move = (x, y) => send('Input.dispatchMouseEvent', { type: 'mouseMoved', x: Math.round(x), y: Math.round(y), button: 'none', buttons: 1 })
const up = (x, y) => send('Input.dispatchMouseEvent', { type: 'mouseReleased', x: Math.round(x), y: Math.round(y), button: 'left', buttons: 0, clickCount: 1 })
const shot = async (p) => { const s = await send('Page.captureScreenshot', { format: 'png' }); writeFileSync(p, Buffer.from(s.result.data, 'base64')) }

// 一帧一格：按顺序取（占位块 / 虚影 / 卡片），拼成一段可读的读数。
// 顺序与渲染顺序一致 —— 占位块在序列里的位次就是它的**格子序号**（栅格按序发格子）。
const FRAME_JS = `(() => {
  // **格子序号 = 栅格排布序号**，不是孩子序列里的位次：
  // 摆位靠每个元素自己的 order（见 view_overview 的 row_group），
  // 而虚拟 DOM 那一层会自己重排孩子，两者不是一回事。
  // 排序规则照 CSS 的 order-modified document order：order 升序，相同则保持孩子顺序。
  const orderOf = (n) => { const v = parseInt(getComputedStyle(n).order, 10); return Number.isFinite(v) ? v : 0 };
  // 两个分组各是一个栅格，各自从 0 数格子；占位块只会在其中一组里
  const places = [...document.querySelectorAll('[data-name="row-group"]')];
  const rows = [];
  const placed = [];
  let slotAt = -1, slotRow = null, slotGroup = null, slotNode = null, slotSortAt = -1, slotVisual = -1;
  for (const grid of places) {
    const g = grid.getAttribute('data-group');
    const kids = [...grid.children].map((n, i) => ({ n, i, o: orderOf(n) })).sort((a, b) => (a.o - b.o) || (a.i - b.i)).map((x) => x.n);
    kids.forEach((n, i) => {
      if (n.classList.contains('dsh-drop-slot')) {
        // 占位块自己在 DOM 上说「我在第几格」（data-slot-index）——
        // 这是它唯一的落点声明，样式按它给 order。**不按孩子位置数**：
        // 虚拟 DOM 那一层会重排孩子（实测把改动过的节点挪到末尾）。
        const declared = parseInt(n.getAttribute('data-slot-index') || '-1', 10);
        slotAt = Number.isFinite(declared) ? declared : -1;
        slotRow = n.getAttribute('data-slot-row');
        slotGroup = g;
        slotNode = n;
        slotSortAt = i;
      }
      if (n.getAttribute && n.getAttribute('data-row')) {
        const r = n.getBoundingClientRect();
        const id = n.getAttribute('data-row');
        rows.push({ row: id, group: g, slot: i, x: Math.round(r.x), y: Math.round(r.y) });
        if (n.classList.contains('drag-image')) placed.push({ row: id, x: Math.round(r.x), y: Math.round(r.y) });
      }
    });
    // **画面上**的格子序号：把这一格的每一块按「先 y 后 x」排一遍，看占位块排第几。
    // 这才是「预览就是结果」真正要比的那个数 —— 声明（data-slot-index）只是它的一半，
    // 另一半是样式真把它摆到了那一格。两半对不上就是差一格，这里如实记下来。
    const boxes = [...grid.children].map((n) => ({ n, r: n.getBoundingClientRect() }));
    const vis = boxes.slice().sort((a, b) => (Math.abs(a.r.top - b.r.top) > 5 ? a.r.top - b.r.top : a.r.left - b.r.left));
    const at = vis.findIndex((b) => b.n === slotNode);
    if (at >= 0) slotVisual = at;
  }
  // 虚影挂在页面那一层（fixed、不占文档流），不在这一组的序列里
  const gEl = document.querySelector('.dsh-drag-ghost');
  let ghost = null;
  if (gEl) { const r = gEl.getBoundingClientRect(); ghost = { x: r.x, y: r.y, w: r.width, h: r.height } }
  const slot = slotNode ? (() => { const r = slotNode.getBoundingClientRect(); return { index: slotAt, sortedAt: slotSortAt, visual: slotVisual, row: slotRow, group: slotGroup, x: Math.round(r.x), y: Math.round(r.y), w: Math.round(r.width), h: Math.round(r.height), cls: slotNode.className } })() : null;
  return JSON.stringify({ slot, slotAt, ghost, rows, placed });
})()`

const readOrder = () => ev(`JSON.stringify([...document.querySelectorAll('[data-name="row-group"]')].map((g) => ({ group: g.getAttribute('data-group'), rows: [...g.querySelectorAll('.dsh-case[data-row]')].map((c) => c.getAttribute('data-row')) })))`).then((s) => JSON.parse(s || '[]'))
const readNotice = () => ev(`JSON.stringify({ err: (document.querySelector('[data-name="action-notice"] .dsh-notice-text') || {}).textContent || null, drawer: !!document.querySelector('.dsh-drawer') })`).then((s) => JSON.parse(s || '{}'))
const groupRows = (order, g) => ((order.find((x) => x.group === g) || {}).rows || [])
const frame = async () => JSON.parse((await ev(FRAME_JS)) || '{}')

const report = { url: baseUrl, stateDir: stateDir || null, orderFile: orderFile || null, trials: [], checks: {} }
const consoleFacts = await (async () => { try { const j = await (await fetch(baseUrl.replace(/\/$/, '') + '/api/local/console')).json(); return j?.data ?? null } catch { return null } })()
report.orderPathFromApi = consoleFacts ? consoleFacts.orderPath : null
report.orderIsolated = !!(report.orderPathFromApi && stateDir && report.orderPathFromApi.startsWith(stateDir))
const readOrderFile = () => (orderFile && existsSync(orderFile)) ? readFileSync(orderFile, 'utf8').trim() : null
const clearOrderFile = () => { if (orderFile && existsSync(orderFile)) { try { chmodSync(dirname(orderFile), 0o755); chmodSync(orderFile, 0o644); writeFileSync(orderFile, '') } catch (e) {} } }

// 把一组条目当前的位置读出来（用于挑起点与落点）
const cardsOf = async (g) => {
  const f = await frame()
  return f.rows.filter((r) => true)
}
const groupCardBoxes = () => ev(`JSON.stringify([...document.querySelectorAll('[data-name="row-group"]')].map((g) => ({ group: g.getAttribute('data-group'), cards: [...g.querySelectorAll('.dsh-case[data-row]')].map((c) => { const r = c.getBoundingClientRect(); return { row: c.getAttribute('data-row'), cx: r.x + r.width / 2, cy: r.y + r.height / 2, x: r.x, y: r.y, w: r.width, h: r.height, top: r.top, bottom: r.bottom } }) })))`).then((s) => JSON.parse(s || '[]'))

// ── ① / ② 三个不同落点，每个都逐帧采一遍 ──
// 三个落点各证一次：目标那一条的上沿 / 下沿，以及**最后一条的下沿**。
// 为什么不是「同一个目标的上中下」：那三条算出来的格子序号可能落在同一格上，
// 三次都落在一格说明不了「逐格一致」（一次巧合不算）。
async function trial(name, targetIndex, half, shotName) {
  clearOrderFile()
  await send('Page.navigate', { url: baseUrl }); await wait(5200)
  const groups = await groupCardBoxes()
  const stopped = (groups.find((g) => g.group === 'stopped') || groups[0])
  const running = (groups.find((g) => g.group === 'running') || {})
  const cards = stopped.cards
  if (cards.length < 3) { report.trials.push({ name, skipped: '已停止组只有 ' + cards.length + ' 条' }); return }
  const src = cards[0]
  const dst = cards[Math.min(cards.length - 1, targetIndex)]
  // 松手点：贴目标那一条的上沿或下沿（离开中线 6px 以上，避免量到边界上的浮点数）
  const y = half === "top" ? dst.top + 6 : dst.bottom - 6
  const x = dst.cx
  const orderBefore = await readOrder()
  const t = { name, group: stopped.group, from: src.row, target: dst.row, releaseAt: { x: Math.round(x), y: Math.round(y) }, orderBefore: groupRows(orderBefore, stopped.group), frames: [] }
  if (shotPrefix) await shot(shotPrefix + '-' + shotName + '-before.png')
  await down(src.cx, src.cy)
  await wait(160)
  const steps = 10
  for (let i = 1; i <= steps; i++) {
    const px = src.cx + (x - src.cx) * (i / steps)
    const py = src.cy + (y - src.cy) * (i / steps)
    await move(px, py)
    await wait(55)
    const f = await frame()
    t.frames.push({ i, pointer: { x: Math.round(px), y: Math.round(py) }, slotIndex: f.slot ? f.slot.index : -1, slotVisual: f.slot ? f.slot.visual : -1, slotRow: f.slot ? f.slot.row : null, ghost: f.ghost ? { x: Math.round(f.ghost.x), y: Math.round(f.ghost.y), w: Math.round(f.ghost.w), h: Math.round(f.ghost.h) } : null, placed: f.placed, rows: f.rows })
  }
  const preview = t.frames[t.frames.length - 1]
  t.preview = { slotIndex: preview.slotIndex, slotVisual: preview.slotVisual, slotRow: preview.slotRow, ghost: preview.ghost, placed: preview.placed }
  if (shotPrefix) await shot(shotPrefix + '-' + shotName + '-preview.png')
  await up(x, y)
  await wait(1500)
  const orderAfter = await readOrder()
  t.orderAfter = groupRows(orderAfter, stopped.group)
  t.orderFileAfter = readOrderFile()
  t.landedAt = t.orderAfter.indexOf(src.row)
  // 逐格一致：**画面上**占位块所在的那一格 == 松手后被拖那一条排到的位置。
  t.consistent = t.preview.slotVisual >= 0 && t.landedAt === t.preview.slotVisual
  // 声明与摆位也得是同一个数：data-slot-index 说第 k 格，样式就得把它摆在第 k 格。
  t.declaredMatchesVisual = t.frames.every((f) => f.slotVisual < 0 || f.slotIndex === f.slotVisual)
  // 预览那一段：占位块每帧都在，虚影跟着指针
  t.slotEveryFrame = t.frames.every((f) => f.slotIndex >= 0)
  // 虚影是「往右下挪一点」跟着指针的（不是正压在指针上，那样会盖住占位块）：
  // 判据是「每一帧都保持同一个偏移」—— 它跟着指针走，且不抖。
  t.ghostFollows = t.frames.every((f) => f.ghost && Math.abs(f.ghost.x - f.pointer.x - 10) <= 2 && Math.abs(f.ghost.y - f.pointer.y - 14) <= 2)
  t.monotone = (() => { let last = -1, ok = true; for (const f of t.frames) { if (f.slotIndex < last) ok = false; last = f.slotIndex } return ok })()
  if (shotPrefix) await shot(shotPrefix + '-' + shotName + '-after.png')
  report.trials.push(t)
}

// 三个**互不相同**的落点：按「贴第 2 条上沿 / 下沿、贴第 3 条上沿 / 下沿」各拖一趟，
// 再从结果里挑出前三个互不相同的落点 —— 三次都落在同一格说明不了「逐格一致」
// （一次巧合不算）。挑不够就在判定表里如实报失败。
await send('Emulation.setDeviceMetricsOverride', { width: TRIAL_VW, height: VH, deviceScaleFactor: 1, mobile: false })
await wait(1200)
const made = []
const SWEEP = [[2, 'bottom'], [1, 'bottom'], [1, 'top'], [0, 'bottom'], [2, 'top'], [0, 'top']]
for (let i = 0; i < SWEEP.length; i++) {
  const [targetIndex, half] = SWEEP[i]
  await trial('t' + i + '-card' + targetIndex + '-' + half, targetIndex, half, 't' + i)
  const last = report.trials[report.trials.length - 1]
  if (last && last.preview && last.preview.slotVisual >= 0 && !made.includes(last.preview.slotVisual)) made.push(last.preview.slotVisual)
  if (made.length >= 3) break
}
report.distinctSpots = made
report.trialsViewport = TRIAL_VW
await send('Emulation.setDeviceMetricsOverride', { width: VW, height: VH, deviceScaleFactor: 1, mobile: false })
await wait(1200)

// ── ③ 键盘 Ctrl+↓：预览一拍 + 落位一拍 ──
{
  clearOrderFile()
  await send('Page.navigate', { url: baseUrl }); await wait(5200)
  const groups = await groupCardBoxes()
  const stopped = groups.find((g) => g.group === 'stopped') || groups[0]
  const first = stopped.cards[0]
  const orderBefore = groupRows(await readOrder(), stopped.group)
  await ev(`(() => { const el = document.querySelector('[data-row="' + ${JSON.stringify(first.row)} + '"]'); if (el) el.focus(); })()`)
  await wait(250)
  const key = async (type) => send('Input.dispatchKeyEvent', { type, key: 'ArrowDown', code: 'ArrowDown', windowsVirtualKeyCode: 40, modifiers: 2 })
  report.keyboard = { row: first.row, orderBefore, preview: null, orderAfter: null, orderFileAfter: null, notice: null }
  const seq = []
  // 换位挂在**抬起**那一拍（按一次键浏览器会送好几个键盘事件），所以：
  //   down 那一拍不该有任何动静；up 之后 ≈70ms 是「占位块亮着、顺序还没动」；
  //   再往后（190ms 那个计时到了）才是落位。三拍分开采，各证一件事。
  await key('rawKeyDown')
  await wait(90)
  seq.push({ at: 'down+90ms', frame: await frame(), order: groupRows(await readOrder(), stopped.group) })
  await key('keyUp')
  await wait(70)
  seq.push({ at: 'up+70ms', frame: await frame(), order: groupRows(await readOrder(), stopped.group) })
  await wait(80)
  seq.push({ at: 'up+150ms', frame: await frame(), order: groupRows(await readOrder(), stopped.group) })
  await wait(1200)
  seq.push({ at: 'up+1350ms', frame: await frame(), order: groupRows(await readOrder(), stopped.group) })
  report.keyboard.seq = seq.map((s) => ({ at: s.at, slotIndex: s.frame.slot ? s.frame.slot.index : -1, slotVisual: s.frame.slot ? s.frame.slot.visual : -1, order: s.order, placed: s.frame.placed, rows: s.frame.rows }))
  // 预览那一拍：占位块在、顺序还没动
  const prev = seq.find((s) => s.at === 'up+70ms')
  // 顺序**与那一帧同一个时刻**读：预览只亮 190ms，晚一点读就落到落位之后了
  report.keyboard.preview = { slotIndex: prev && prev.frame.slot ? prev.frame.slot.index : -1, slotVisual: prev && prev.frame.slot ? prev.frame.slot.visual : -1, orderDuringPreview: prev ? prev.order : null }
  report.keyboard.orderBeforeDuring = report.keyboard.preview.orderDuringPreview
  const orderAfter = groupRows(await readOrder(), stopped.group)
  report.keyboard.orderAfter = orderAfter
  report.keyboard.orderFileAfter = readOrderFile()
  report.keyboard.notice = await readNotice()
  report.keyboard.previewShown = report.keyboard.seq[2].slotIndex >= 0
  report.keyboard.previewKeptOrder = JSON.stringify(report.keyboard.orderBefore) === JSON.stringify(report.keyboard.preview.orderDuringPreview)
  report.keyboard.landedAt = orderAfter.indexOf(first.row)
  const up70 = report.keyboard.seq.find((s) => s.at === 'up+70ms')
  report.keyboard.previewSlot = up70 ? up70.slotVisual : -1
  report.keyboard.previewDeclared = up70 ? up70.slotIndex : -1
  report.keyboard.idleOnKeyDown = report.keyboard.seq[0].slotVisual < 0 && report.keyboard.seq[0].slotIndex < 0
  if (shotPrefix) await shot(shotPrefix + '-keyboard.png')
}

// ── ⑦ 点击不误触发 ──
{
  const groups = await groupCardBoxes()
  const stopped = groups.find((g) => g.group === 'stopped') || groups[0]
  const card = stopped.cards[1] || stopped.cards[0]
  const before = groupRows(await readOrder(), stopped.group)
  await down(card.cx, card.cy); await wait(120); await up(card.cx, card.cy)
  await wait(900)
  const n = await readNotice()
  const after = groupRows(await readOrder(), stopped.group)
  report.click = { row: card.row, drawerOpen: n.drawer, orderSame: JSON.stringify(before) === JSON.stringify(after) }
  await send('Input.dispatchKeyEvent', { type: 'rawKeyDown', key: 'Escape', code: 'Escape', windowsVirtualKeyCode: 27 })
  await send('Input.dispatchKeyEvent', { type: 'keyUp', key: 'Escape', code: 'Escape', windowsVirtualKeyCode: 27 })
  await wait(500)
}

// ── ⑤ 跨组拖动作废 ──
{
  const groups = await groupCardBoxes()
  const stopped = groups.find((g) => g.group === 'stopped') || groups[0]
  const running = groups.find((g) => g.group === 'running')
  if (running && running.cards.length) {
    const src = stopped.cards[0], dst = running.cards[0]
    const before = await readOrder()
    await down(src.cx, src.cy); await wait(160)
    for (let i = 1; i <= 8; i++) { await move(src.cx + (dst.cx - src.cx) * i / 8, src.cy + (dst.cy - src.cy) * i / 8); await wait(60) }
    await wait(200)
    const f = await frame()
    report.crossGroup = { from: src.row, to: dst.row, slotDuring: f.slot ? f.slot.index : -1, slotCount: (await ev('document.querySelectorAll(".dsh-drop-slot").length')) }
    await up(dst.cx, dst.cy)
    await wait(900)
    report.crossGroup.orderSame = JSON.stringify(before) === JSON.stringify(await readOrder())
    report.crossGroup.notice = await readNotice()
  } else report.crossGroup = { skipped: '没有运行中的实例可比' }
}

// ── ④ 窄屏 360 不响应 ──
{
  await send('Emulation.setDeviceMetricsOverride', { width: 360, height: 900, deviceScaleFactor: 1, mobile: false })
  await wait(1400)
  const groups = await groupCardBoxes()
  const stopped = groups.find((g) => g.group === 'stopped') || groups[0]
  const src = stopped.cards[0], dst = stopped.cards[Math.min(2, stopped.cards.length - 1)]
  const before = await readOrder()
  await down(src.cx, src.cy); await wait(140)
  for (let i = 1; i <= 6; i++) { await move(src.cx, src.cy + (dst.cy - src.cy) * i / 6); await wait(60) }
  await wait(200)
  const slots = await ev('document.querySelectorAll(".dsh-drop-slot").length')
  const ghost = await ev('document.querySelectorAll(".dsh-drag-ghost").length')
  await up(dst.cx, dst.cy)
  await wait(900)
  report.narrow = { viewport: 360, slotCount: slots, ghostCount: ghost, orderSame: JSON.stringify(before) === JSON.stringify(await readOrder()) }
  if (shotPrefix) await shot(shotPrefix + '-narrow-360.png')
  await send('Emulation.setDeviceMetricsOverride', { width: VW, height: VH, deviceScaleFactor: 1, mobile: false })
  await wait(1200)
}

// ── ⑧ prefers-reduced-motion：占位块仍在、让位不做过渡 ──
{
  await send('Emulation.setEmulatedMedia', { features: [{ name: 'prefers-reduced-motion', value: 'reduce' }] })
  await send('Page.navigate', { url: baseUrl }); await wait(5200)
  const groups = await groupCardBoxes()
  const stopped = groups.find((g) => g.group === 'stopped') || groups[0]
  const src = stopped.cards[0], dst = stopped.cards[Math.min(2, stopped.cards.length - 1)]
  const y = dst.bottom - 6
  await down(src.cx, src.cy); await wait(160)
  const samples = []
  for (let i = 1; i <= 8; i++) {
    await move(src.cx + (dst.cx - src.cx) * i / 8, src.cy + (y - src.cy) * i / 8)
    await wait(55)
    const f = await frame()
    samples.push({ i, slotIndex: f.slot ? f.slot.index : -1, rows: f.rows })
  }
  const media = await ev('JSON.stringify({ reduce: window.matchMedia("(prefers-reduced-motion: reduce)").matches, anims: [...document.querySelectorAll("[data-name=\'row-group\'] .dsh-case, [data-name=\'row-group\'] .dsh-drop-slot")].reduce((n, e) => n + (e.getAnimations ? e.getAnimations().length : 0), 0), transition: getComputedStyle(document.querySelector(".dsh-case")).transitionDuration })')
  const f = await frame()
  report.reduced = { media: JSON.parse(media || '{}'), slotPresent: !!f.slot, slotIndex: f.slot ? f.slot.index : -1, slotVisual: f.slot ? f.slot.visual : -1, samples }
  if (shotPrefix) await shot(shotPrefix + '-reduced.png')
  await up(dst.cx, y)
  await wait(1400)
  report.reduced.orderAfter = groupRows(await readOrder(), stopped.group)
  report.reduced.landedAt = report.reduced.orderAfter.indexOf(src.row)
  report.reduced.consistent = report.reduced.slotVisual >= 0 && report.reduced.landedAt === report.reduced.slotVisual
  await send('Emulation.setEmulatedMedia', { features: [] })
}

if (shotPrefix) await shot(shotPrefix + '-final.png')
report.orderFileEnd = readOrderFile()

// ── 判定表 ──
const ok = []
const push = (name, pass, detail) => ok.push({ name, pass: !!pass, detail })
for (const t of report.trials) {
  if (t.skipped) { push('落点 ' + t.name, false, t.skipped); continue }
  push('预览与结果逐格一致（' + t.name + '）', t.consistent, '占位块画在第 ' + t.preview.slotVisual + ' 格（声明 ' + t.preview.slotIndex + '）→ 落在第 ' + t.landedAt + ' 格')
  push('占位块的声明与摆位同格（' + t.name + '）', t.declaredMatchesVisual, 'data-slot-index 与画面上那一格')
  push('占位块每帧都在（' + t.name + '）', t.slotEveryFrame, t.frames.length + ' 帧')
  push('虚影跟着指针（固定偏移）', t.ghostFollows, t.frames.length + ' 帧（' + t.name + '）')
}
push('三个落点互不相同', (report.distinctSpots || []).length >= 3, JSON.stringify(report.distinctSpots))
push('键盘换位有预览', report.keyboard && report.keyboard.previewShown, report.keyboard && ('占位块第 ' + report.keyboard.previewSlot + ' 格'))
push('键盘预览期间顺序未动', report.keyboard && report.keyboard.previewKeptOrder, '预览那一拍（up+70ms）的顺序与按下前一致')
push('键盘按下那一拍不动（换位在抬起）', report.keyboard && report.keyboard.idleOnKeyDown, '')
push('键盘落位与预览同格', report.keyboard && report.keyboard.landedAt === report.keyboard.previewSlot, report.keyboard && ('画在第 ' + report.keyboard.previewSlot + ' 格（声明 ' + report.keyboard.previewDeclared + '）→ 落在第 ' + report.keyboard.landedAt + ' 格'))
push('点击不误触发', report.click && report.click.drawerOpen && report.click.orderSame, JSON.stringify(report.click))
push('跨组拖动作废', report.crossGroup && (report.crossGroup.skipped || (report.crossGroup.slotCount === 0 && report.crossGroup.orderSame)), JSON.stringify(report.crossGroup && (report.crossGroup.slotCount !== undefined ? { slotCount: report.crossGroup.slotCount, orderSame: report.crossGroup.orderSame } : report.crossGroup)))
push('窄屏 360 不响应拖动', report.narrow && report.narrow.slotCount === 0 && report.narrow.ghostCount === 0 && report.narrow.orderSame, JSON.stringify(report.narrow))
push('reduced-motion 下占位块仍在', report.reduced && report.reduced.slotPresent, JSON.stringify(report.reduced && report.reduced.media))
push('reduced-motion 下让位无过渡', report.reduced && report.reduced.media && report.reduced.media.anims === 0 && report.reduced.media.transition === '0s', JSON.stringify(report.reduced && report.reduced.media))
push('reduced-motion 下落点一致', report.reduced && report.reduced.consistent, report.reduced && ('第 ' + report.reduced.slotIndex + ' 格 → 第 ' + report.reduced.landedAt + ' 格'))
report.checks = ok
writeFileSync(OUT, JSON.stringify(report, null, 1))
const failed = ok.filter((x) => !x.pass)
console.log(ok.map((x) => (x.pass ? '通过  ' : '✗失败 ') + x.name + (x.detail ? '  —— ' + x.detail : '')).join('\n'))
console.log('\n判定 ' + ok.length + ' 项：通过 ' + (ok.length - failed.length) + '，失败 ' + failed.length)
if (failed.length) console.log('失败项: ' + failed.map((f) => f.name).join(' / '))
chrome.kill()
process.exit(failed.length ? 1 : 0)

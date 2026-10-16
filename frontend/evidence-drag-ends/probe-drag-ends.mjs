// 拖动到位：最后 / 最前那一格必须够得着（第十三轮，口径变更）。
//
// node probe-drag-ends.mjs <baseUrl> <outJson> [shotPrefix]
//
// 使用者报的原话：「现在的拖动似乎无法让用户轻松的将某个元素移动到最后面？」
// 病根：落点判定在列表上下各留 32px 宽容带、出带即作废 —— 而指针要**越过最后一块**
// 才能到最后一格，越过就已经出带。于是最后（同理最前）那一格永远够不着。
//
// 这一轮的判据（旧口径「拖到列表之外松手 = 作废」是**有意改掉**的，不是回归）：
//   ① 指针在最后一块下方（仍在这一组的横向范围内、没进另一组）→ 落点 = 最后一格
//   ② 指针在第一块上方（同上条件）→ 落点 = 第一格
//   ③ 多行时最后一格 = **最后一行的最后一格**（810 两列、条目多的分组）
//   ④ 作废只剩两种：指针横向拖出栅格很远 / 拖进另一组（跨组作废这条不退）
//   ⑤ 预览与结果逐格一致（松手前占位块那一格 == 松手后被拖那一条排到的那一格）
//   ⑥ 其余一条不退：6px 位移阈值（点击不误触发）、窄屏 726 不响应
//
// 隔离：必须给 DRAG_STATE_DIR（隔离的 XDG_STATE_HOME）。后端回的 orderPath 不在这棵树下
// 就直接退出 —— 这一轮会真写顺序表，绝不能写到使用者的状态目录里。
import { spawn } from 'node:child_process'
import { writeFileSync, readFileSync, existsSync, chmodSync } from 'node:fs'
import { dirname, join } from 'node:path'

const [baseUrl, outJson, shotPrefix] = process.argv.slice(2)
if (!baseUrl) { console.log('用法: DRAG_STATE_DIR=<隔离目录> node probe-drag-ends.mjs <baseUrl> <outJson> [shotPrefix]'); process.exit(1) }
const stateDir = process.env.DRAG_STATE_DIR || ''
const OUT = outJson || '/tmp/drag-ends.json'
const VW = 1280, VH = 900
const MVW = 810, MVH = 1100
const XVW = 1600

const CDP_PORT = 9100 + (process.pid % 400)
const chrome = spawn('chromium', ['--headless', '--no-sandbox', '--disable-gpu', '--disable-extensions',
  '--hide-scrollbars', '--remote-debugging-port=' + CDP_PORT, '--user-data-dir=/tmp/chrome-ends-' + process.pid,
  '--window-size=' + XVW + ',' + VH, '--noerrdialogs', '--no-first-run', '--ozone-platform=headless',
  '--ozone-override-screen-size=800,600', '--use-angle=swiftshader-webgl', 'about:blank'], { stdio: 'ignore' })

let page = null
for (let i = 0; i < 60 && !page; i++) {
  try { const list = await (await fetch('http://127.0.0.1:' + CDP_PORT + '/json')).json(); page = list.find((t) => t.type === 'page') } catch {}
  if (!page) await new Promise((r) => setTimeout(r, 250))
}
if (!page) { console.log('chrome 没起来'); process.exit(1) }
const ws = new WebSocket(page.webSocketDebuggerUrl)
let id = 0
const pending = new Map()
ws.onmessage = (e) => { const m = JSON.parse(e.data); if (m.id && pending.has(m.id)) { pending.get(m.id)(m); pending.delete(m.id) } }
await new Promise((r) => { ws.onopen = r })
const send = (method, params = {}) => new Promise((res) => { const i = ++id; pending.set(i, res); ws.send(JSON.stringify({ id: i, method, params })) })
const ev = async (expression) => { const r = await send('Runtime.evaluate', { expression, returnByValue: true, awaitPromise: true }); return r.result?.result?.value }
const wait = (ms) => new Promise((r) => setTimeout(r, ms))
await send('Page.enable'); await send('Runtime.enable')

const down = (x, y) => send('Input.dispatchMouseEvent', { type: 'mousePressed', x: Math.round(x), y: Math.round(y), button: 'left', buttons: 1, clickCount: 1 })
const move = (x, y) => send('Input.dispatchMouseEvent', { type: 'mouseMoved', x: Math.round(x), y: Math.round(y), button: 'none', buttons: 1 })
const up = (x, y) => send('Input.dispatchMouseEvent', { type: 'mouseReleased', x: Math.round(x), y: Math.round(y), button: 'left', buttons: 0, clickCount: 1 })
const shot = async (p) => { const s = await send('Page.captureScreenshot', { format: 'png' }); writeFileSync(p, Buffer.from(s.result.data, 'base64')) }
const viewport = (w, h) => send('Emulation.setDeviceMetricsOverride', { width: w, height: h, deviceScaleFactor: 1, mobile: false })

// 一帧：两组各自的格子（视觉序 = 先 y 后 x，栅格就按这个次序发格子）、虚影、占位块声明值。
const SNAP_JS = `(() => {
  const groups = [];
  for (const grid of document.querySelectorAll('[data-name="row-group"]')) {
    const kids = [...grid.children].filter((n) => n.classList && (n.classList.contains('dsh-case') || n.classList.contains('dsh-drop-slot')));
    const boxes = kids.map((n) => { const r = n.getBoundingClientRect(); return {
      row: n.getAttribute('data-row'), slot: n.classList.contains('dsh-drop-slot'),
      // 被拖的那一条留在原地不动、还看不见（drag-image），它不占可见格子 —— 计数与排序都要摘掉它
      dragged: n.classList.contains('drag-image'),
      declared: n.classList.contains('dsh-drop-slot') ? parseInt(n.getAttribute('data-slot-index') || '-1', 10) : -1,
      x: Math.round(r.left), y: Math.round(r.top), w: Math.round(r.width), h: Math.round(r.height) } });
    const visual = boxes.filter((b) => !b.dragged).sort((a, b) => (Math.abs(a.y - b.y) > 5 ? a.y - b.y : a.x - b.x));
    const gr = grid.getBoundingClientRect();
    const slotBox = visual.find((b) => b.slot) || null;
    const rows = [];
    for (const b of visual) {
      const last = rows[rows.length - 1];
      if (last && Math.abs(last.y - b.y) <= 5) { last.cells.push(b) } else { rows.push({ y: b.y, cells: [b] }) }
    }
    const slotAt = visual.findIndex((b) => b.slot);
    groups.push({ group: grid.getAttribute('data-group'), grid: { left: Math.round(gr.left), right: Math.round(gr.right), top: Math.round(gr.top), bottom: Math.round(gr.bottom) },
      count: visual.length, draggedRow: (boxes.find((b) => b.dragged) || {}).row || null,
      cells: visual.map((b, i) => ({ cell: i, row: b.row, slot: b.slot, x: b.x, y: b.y, w: b.w, h: b.h })),
      slotVisual: slotAt, slotDeclared: slotBox ? slotBox.declared : -1,
      slotIsLastCell: !!slotBox && slotAt === visual.length - 1,
      slotInLastRow: !!slotBox && rows.length > 0 && Math.abs(slotBox.y - rows[rows.length - 1].y) <= 5,
      slotIsLastOfLastRow: !!slotBox && rows.length > 0 && (() => { const lr = rows[rows.length - 1]; return Math.abs(slotBox.y - lr.y) <= 5 && lr.cells[lr.cells.length - 1] === slotBox })(),
      rowCounts: rows.map((r) => r.cells.length) });
  }
  const gEl = document.querySelector('.dsh-drag-ghost');
  const ghost = gEl ? (() => { const r = gEl.getBoundingClientRect(); return { x: Math.round(r.left), y: Math.round(r.top) } })() : null;
  return JSON.stringify({ groups: groups, ghost: ghost, slots: document.querySelectorAll('.dsh-drop-slot').length,
    ghosts: document.querySelectorAll('.dsh-drag-ghost').length, dragActive: !!document.querySelector('.dsh-drag-active'),
    drawer: !!document.querySelector('.dsh-drawer') });
})()`
const snap = () => ev(SNAP_JS).then((s) => JSON.parse(s || '{}'))
const readOrder = () => ev(`JSON.stringify([...document.querySelectorAll('[data-name="row-group"]')].map((g) => ({ group: g.getAttribute('data-group'), rows: [...g.querySelectorAll('.dsh-case[data-row]')].map((c) => c.getAttribute('data-row')) })))`).then((s) => JSON.parse(s || '[]'))
const notice = () => ev(`JSON.stringify({ text: (document.querySelector('[data-name="action-notice"] .dsh-notice-text') || {}).textContent || null, drawer: !!document.querySelector('.dsh-drawer') })`).then((s) => JSON.parse(s || '{}'))
const groupRows = (order, g) => ((order.find((x) => x.group === g) || {}).rows || [])
const escKey = async () => {
  for (const type of ['rawKeyDown', 'keyUp']) await send('Input.dispatchKeyEvent', { type, key: 'Escape', code: 'Escape', windowsVirtualKeyCode: 27 })
  await wait(400)
}
// 格子读数 → 可下手的盒子（中心 + 上下沿）
const C = (c) => ({ row: c.row, cx: c.x + c.w / 2, cy: c.y + c.h / 2, top: c.y, bottom: c.y + c.h, left: c.x, right: c.x + c.w })
const cardsOf = (s, g) => (((s.groups.find((x) => x.group === g) || {}).cells) || []).filter((c) => !c.slot).map(C)
const gridOf = (s, g) => (s.groups.find((x) => x.group === g) || {}).grid || null
const slotOf = (s, g) => (s.groups.find((x) => x.group === g) || {})

const report = { url: baseUrl, stateDir: stateDir || null, trials: [], voids: [], regressions: {} }
const facts = await (async () => { try { const j = await (await fetch(baseUrl.replace(/\/$/, '') + '/api/local/console')).json(); return j?.data ?? null } catch { return null } })()
report.orderPathFromApi = facts ? facts.orderPath : null
report.orderIsolated = !!(report.orderPathFromApi && stateDir && report.orderPathFromApi.startsWith(stateDir))
if (!report.orderIsolated) {
  console.log('拒绝运行：orderPath = ' + report.orderPathFromApi + ' 不在 DRAG_STATE_DIR=' + stateDir + ' 之下 —— 这一轮会真写顺序表，不能写进使用者的状态目录。')
  chrome.kill(); process.exit(2)
}
const orderFile = join(stateDir, 'dsh-console', 'order.json')
const readOrderFile = () => existsSync(orderFile) ? readFileSync(orderFile, 'utf8').trim() : null
const clearOrderFile = () => { if (existsSync(orderFile)) { try { chmodSync(dirname(orderFile), 0o755); chmodSync(orderFile, 0o644); writeFileSync(orderFile, '') } catch (e) {} } }

// 造的数据只活在浏览器那一侧：拦 /api/local/profiles，把真读数复制几份改个名字。
// 为什么需要：本机只有 3 条已停止的条目，810 两列下折成两行（2 + 1）——
// 「最后一格是最后一行的最后一格」要一个**填满的末行**才证得干净（3 + 5 = 8 条 → 4 行 × 2）。
const FIXTURE_JS = (() => {
  const names = ['fx-end-1', 'fx-end-2', 'fx-end-3', 'fx-end-4', 'fx-end-5']
  return `(() => {
  const NAMES = ${JSON.stringify(names)};
  const orig = window.fetch.bind(window);
  window.fetch = async (input, init) => {
    const url = typeof input === 'string' ? input : (input && input.url) || '';
    const res = await orig(input, init);
    if (!url.includes('/api/local/profiles')) return res;
    let j; try { j = await res.clone().json() } catch (e) { return res }
    if (!j || !j.data || !Array.isArray(j.data.profiles)) return res;
    const base = j.data.profiles.find((p) => p.note) || j.data.profiles[0];
    const extra = NAMES.map((n) => Object.assign({}, base, { name: n, dir: '/tmp/fx-end/' + n, isCurrent: false,
      note: '桩 fixture：这一条是造的（多行落点那一趟要一个填满的末行），不指向磁盘上的任何目录' }));
    j.data.profiles = j.data.profiles.concat(extra);
    return new Response(JSON.stringify(j), { status: res.status, statusText: res.statusText, headers: { 'content-type': 'application/json' } });
  };
})()`
})()

// 一趟拖动：按下 → 分步移动（逐帧采一格）→ 松手。
async function pull(name, src, release, opts = {}) {
  const group = opts.group || 'stopped'
  const steps = opts.steps || 8
  const before = await readOrder()
  const t = { name, group, from: src.row, release: { x: Math.round(release.x), y: Math.round(release.y) },
    orderBefore: groupRows(before, group), frames: [] }
  await down(src.cx, src.cy); await wait(160)
  for (let i = 1; i <= steps; i++) {
    const px = src.cx + (release.x - src.cx) * (i / steps)
    const py = src.cy + (release.y - src.cy) * (i / steps)
    await move(px, py); await wait(55)
    const f = await snap()
    const g = slotOf(f, group)
    t.frames.push({ i, pointer: { x: Math.round(px), y: Math.round(py) }, slotVisual: g.slotVisual,
      slotDeclared: g.slotDeclared, slotIsLastOfLastRow: !!g.slotIsLastOfLastRow, slots: f.slots, ghost: f.ghost })
  }
  await wait(250)
  const last = await snap()
  const g = slotOf(last, group)
  t.preview = { slotVisual: g.slotVisual, slotDeclared: g.slotDeclared, slotIsLastCell: !!g.slotIsLastCell,
    slotInLastRow: !!g.slotInLastRow, slotIsLastOfLastRow: !!g.slotIsLastOfLastRow,
    rowCounts: g.rowCounts || null, count: g.count, cells: g.cells }
  if (shotPrefix && opts.shot) await shot(shotPrefix + '-' + opts.shot + '-preview.png')
  await up(release.x, release.y); await wait(1300)
  const after = await readOrder()
  t.orderAfter = groupRows(after, group)
  t.orderFileAfter = readOrderFile()
  t.landedAt = t.orderAfter.indexOf(src.row)
  t.consistent = t.preview.slotVisual >= 0 && t.landedAt === t.preview.slotVisual
  t.declaredMatchesVisual = t.frames.every((f) => f.slotVisual < 0 || f.slotDeclared === f.slotVisual)
  t.slotEveryFrame = t.frames.every((f) => f.slots === 1)
  if (shotPrefix && opts.shot) await shot(shotPrefix + '-' + opts.shot + '-after.png')
  report.trials.push(t)
  return t
}

const reload = async () => { clearOrderFile(); await send('Page.navigate', { url: baseUrl }); await wait(5200) }

// ── 单行那几趟：1280 ──
await viewport(VW, VH); await wait(600)
await reload()
{
  let s = await snap()
  report.layoutSingle = { stopped: { grid: gridOf(s, 'stopped'), rows: slotOf(s, 'stopped').rowCounts,
      cards: slotOf(s, 'stopped').cells.map((c) => ({ row: c.row, cell: c.cell, x: c.x, y: c.y })) },
    running: gridOf(s, 'running'), viewport: VW }

  // ① 拖到最末：指针越过最后一块的下沿再往下
  let cards = cardsOf(s, 'stopped')
  const lastC = cards[cards.length - 1]
  await reload()
  s = await snap()
  cards = cardsOf(s, 'stopped')
  const last = cards[cards.length - 1]
  await pull('拖到最末（越过最后一块下沿）', cards[0], { x: last.cx, y: last.bottom + 60 }, { shot: 'last' })

  // ② 拖到最前：指针越过第一块的上沿（仍在标题带里，没进另一组）
  s = await snap()
  cards = cardsOf(s, 'stopped')
  const first = cards[0]
  const run1 = gridOf(s, 'running')
  const yTop = Math.max((run1 ? run1.bottom : 0) + 4, first.top - 40)
  report.topBandSingle = { firstTop: first.top, runningBottom: run1 ? run1.bottom : null, releaseY: yTop,
    aboveFirst: yTop < first.top, belowRunning: !run1 || yTop > run1.bottom }
  await pull('拖到最前（越过第一块上沿）', cards[cards.length - 1], { x: first.cx, y: yTop }, { shot: 'first' })

  // ④-a 作废：拖进另一组
  s = await snap()
  const stoppedCards = cardsOf(s, 'stopped')
  const runCards = cardsOf(s, 'running')
  const runGrid = gridOf(s, 'running')
  {
    const before = await readOrder()
    const t = { name: '拖进另一组', from: stoppedCards[0].row, to: runCards.length ? runCards[0].row : null, orderBefore: before }
    if (runCards.length && runGrid) {
      const src = stoppedCards[0], dst = runCards[0]
      await down(src.cx, src.cy); await wait(160)
      for (let i = 1; i <= 8; i++) { await move(src.cx + (dst.cx - src.cx) * i / 8, src.cy + (dst.cy - src.cy) * i / 8); await wait(55) }
      await wait(250)
      const f = await snap()
      t.duringDrag = { slots: f.slots, ghosts: f.ghosts, dragActive: f.dragActive }
      if (shotPrefix) await shot(shotPrefix + '-void-group-preview.png')
      await up(dst.cx, dst.cy); await wait(1200)
      t.orderAfter = await readOrder()
      t.orderSame = JSON.stringify(groupRows(before, 'stopped')) === JSON.stringify(groupRows(t.orderAfter, 'stopped'))
      t.notice = await notice()
      if (shotPrefix) await shot(shotPrefix + '-void-group-after.png')
    } else t.skipped = '没有运行中的实例可比'
    report.voids.push(t)
  }

  // ④-b 作废：横向拖出栅格很远（1600 宽，右侧留出余量）
  await viewport(XVW, VH); await wait(1200)
  {
    s = await snap()
    const st = gridOf(s, 'stopped')
    const c0 = cardsOf(s, 'stopped')[0]
    const before = await readOrder()
    // 栅格右缘之外不一定有余量（内容列会跟着视口变宽），左缘之外一定有（左侧是导航那一栏）
    const xVoid = (st.left - 120 >= 10) ? st.left - 120 : Math.min(XVW - 10, st.right + 120)
    const t = { name: '横向拖出栅格很远', from: c0.row, gridLeft: st.left, gridRight: st.right, releaseX: xVoid,
      clearsPad: xVoid <= st.left - 24 || xVoid >= st.right + 24, orderBefore: before }
    if (t.clearsPad) {
      await down(c0.cx, c0.cy); await wait(160)
      for (let i = 1; i <= 8; i++) { await move(c0.cx + (xVoid - c0.cx) * i / 8, c0.cy); await wait(55) }
      await wait(250)
      const f = await snap()
      t.duringDrag = { slots: f.slots, ghosts: f.ghosts, dragActive: f.dragActive }
      if (shotPrefix) await shot(shotPrefix + '-void-x-preview.png')
      await up(xVoid, c0.cy); await wait(1200)
      t.orderAfter = await readOrder()
      t.orderSame = JSON.stringify(groupRows(before, 'stopped')) === JSON.stringify(groupRows(t.orderAfter, 'stopped'))
      t.notice = await notice()
      if (shotPrefix) await shot(shotPrefix + '-void-x-after.png')
    } else t.skipped = '这一档宽度下栅格右缘之外没有余量'
    report.voids.push(t)
  }
  await viewport(VW, VH); await wait(1000)

  // ⑥-a 6px 位移阈值：位移 3px 的按下-松开仍是点击（开抽屉、顺序不动、没有占位块）
  await reload()
  {
    s = await snap()
    const cards = cardsOf(s, 'stopped')
    const c = cards[1] || cards[0]
    const before = await readOrder()
    await down(c.cx, c.cy); await wait(120)
    await move(c.cx + 3, c.cy); await wait(120)
    const f = await snap()
    const during = { slots: f.slots, ghosts: f.ghosts }
    await up(c.cx + 3, c.cy); await wait(900)
    const n = await notice()
    report.regressions.click = { row: c.row, moved: 3, during, drawerOpen: n.drawer,
      orderSame: JSON.stringify(groupRows(before, 'stopped')) === JSON.stringify(groupRows(await readOrder(), 'stopped')) }
    await escKey()
  }

  // ⑥-b 窄屏 726 不响应：720 宽下拖一趟
  await viewport(720, 900); await wait(1400)
  {
    s = await snap()
    const cards = cardsOf(s, 'stopped')
    const before = await readOrder()
    const src = cards[0], dst = cards[Math.min(2, cards.length - 1)]
    await down(src.cx, src.cy); await wait(140)
    for (let i = 1; i <= 6; i++) { await move(src.cx, src.cy + (dst.cy - src.cy) * i / 6); await wait(60) }
    await wait(200)
    const f = await snap()
    const during = { slots: f.slots, ghosts: f.ghosts, dragActive: f.dragActive }
    await up(src.cx, dst.cy); await wait(900)
    report.regressions.narrow = { viewport: await ev('window.innerWidth'), during,
      orderSame: JSON.stringify(groupRows(before, 'stopped')) === JSON.stringify(groupRows(await readOrder(), 'stopped')) }
    if (shotPrefix) await shot(shotPrefix + '-narrow-720.png')
  }
  await viewport(VW, VH); await wait(1000)
}

// ── 多行那一趟：810 两列 + 造 5 条（共 8 条 → 4 行 × 2）──
await send('Page.addScriptToEvaluateOnNewDocument', { source: FIXTURE_JS })
await viewport(MVW, MVH); await wait(800)
await reload()
{
  let s = await snap()
  report.layoutMulti = { grid: gridOf(s, 'stopped'), rows: slotOf(s, 'stopped').rowCounts, count: slotOf(s, 'stopped').count,
    cards: slotOf(s, 'stopped').cells.map((c) => ({ row: c.row, cell: c.cell, x: c.x, y: c.y })), viewport: MVW }
  let cards = cardsOf(s, 'stopped')
  const last = cards[cards.length - 1]
  await pull('多行：拖到最末', cards[0], { x: last.cx, y: last.bottom + 60 }, { shot: 'multi-last' })

  s = await snap()
  cards = cardsOf(s, 'stopped')
  const first = cards[0]
  const run1 = gridOf(s, 'running')
  const yTop = Math.max((run1 ? run1.bottom : 0) + 4, first.top - 40)
  report.topBandMulti = { firstTop: first.top, runningBottom: run1 ? run1.bottom : null, releaseY: yTop,
    aboveFirst: yTop < first.top, belowRunning: !run1 || yTop > run1.bottom }
  await pull('多行：拖到最前', cards[cards.length - 1], { x: first.cx, y: yTop }, { shot: 'multi-first' })
}

// ── 判定表 ──
const checks = []
const push = (name, pass, detail) => checks.push({ name, pass: !!pass, detail })
const tOf = (n) => report.trials.find((t) => t.name === n)
{
  const t = tOf('拖到最末（越过最后一块下沿）')
  push('拖到最末：拖动中有占位块', t && t.slotEveryFrame, t && (t.frames.length + ' 帧，占位块每帧 1 个'))
  push('拖到最末：占位块在最后一格', t && t.preview.slotVisual === t.preview.count - 1, t && ('第 ' + t.preview.slotVisual + ' 格 / 共 ' + t.preview.count + ' 格'))
  push('拖到最末：预览与结果逐格一致', t && t.consistent, t && ('占位块第 ' + t.preview.slotVisual + ' 格 → 落在第 ' + t.landedAt + ' 格'))
  push('拖到最末：落在最后一格', t && t.landedAt === t.orderAfter.length - 1, t && (JSON.stringify(t.orderBefore) + ' → ' + JSON.stringify(t.orderAfter)))
  push('拖到最末：占位块声明与摆位同格', t && t.declaredMatchesVisual, '')

  const f = tOf('拖到最前（越过第一块上沿）')
  push('拖到最前：拖动中有占位块', f && f.slotEveryFrame, f && (f.frames.length + ' 帧，占位块每帧 1 个'))
  push('拖到最前：占位块在第 0 格', f && f.preview.slotVisual === 0, f && ('第 ' + f.preview.slotVisual + ' 格'))
  push('拖到最前：预览与结果逐格一致', f && f.consistent, f && ('占位块第 ' + f.preview.slotVisual + ' 格 → 落在第 ' + f.landedAt + ' 格'))
  push('拖到最前：落在第一格', f && f.landedAt === 0, f && (JSON.stringify(f.orderBefore) + ' → ' + JSON.stringify(f.orderAfter)))

  const m = tOf('多行：拖到最末')
  push('多行：占位块在最后一格', m && m.preview.slotVisual === m.preview.count - 1, m && ('第 ' + m.preview.slotVisual + ' 格 / 共 ' + m.preview.count + ' 格，各行条数 ' + JSON.stringify(m.preview.rowCounts)))
  push('多行：最后一格在最后一行的最后一列', m && m.preview.slotInLastRow && m.preview.slotIsLastOfLastRow, m && ('各行条数 ' + JSON.stringify(m.preview.rowCounts) + '，共 ' + (m.preview.rowCounts || []).length + ' 行'))
  push('多行：预览与结果逐格一致', m && m.consistent, m && ('占位块第 ' + m.preview.slotVisual + ' 格 → 落在第 ' + m.landedAt + ' 格'))
  push('多行：落在最后一行的最后一格', m && m.landedAt === m.orderAfter.length - 1, m && (JSON.stringify(m.orderBefore) + ' → ' + JSON.stringify(m.orderAfter)))

  const mf = tOf('多行：拖到最前')
  push('多行：拖到最前落在第 0 格', mf && mf.preview.slotVisual === 0 && mf.landedAt === 0, mf && ('占位块第 ' + mf.preview.slotVisual + ' 格 → 落在第 ' + mf.landedAt + ' 格'))
}
for (const v of report.voids) {
  push('作废（' + v.name + '）：拖动中没有占位块', v.skipped ? false : (v.duringDrag && v.duringDrag.slots === 0), v.skipped || JSON.stringify(v.duringDrag))
  push('作废（' + v.name + '）：顺序不变', v.skipped ? false : v.orderSame === true, v.skipped || JSON.stringify({ before: v.orderBefore && groupRows(v.orderBefore, 'stopped'), after: v.orderAfter && groupRows(v.orderAfter, 'stopped') }))
}
{
  const c = report.regressions.click
  push('点击不误触发（位移 3px 未过阈值）', c && c.drawerOpen && c.orderSame && c.during.slots === 0, JSON.stringify(c))
  const n = report.regressions.narrow
  push('窄屏 720（<726）不响应拖动', n && n.during.slots === 0 && n.during.ghosts === 0 && n.orderSame, JSON.stringify(n))
}
report.checks = checks
writeFileSync(OUT, JSON.stringify(report, null, 1))
const failed = checks.filter((x) => !x.pass)
console.log(checks.map((x) => (x.pass ? '通过  ' : '✗失败 ') + x.name + (x.detail ? '  —— ' + x.detail : '')).join('\n'))
console.log('\n判定 ' + checks.length + ' 项：通过 ' + (checks.length - failed.length) + '，失败 ' + failed.length)
if (failed.length) console.log('失败项: ' + failed.map((f) => f.name).join(' / '))
chrome.kill()
process.exit(failed.length ? 1 : 0)

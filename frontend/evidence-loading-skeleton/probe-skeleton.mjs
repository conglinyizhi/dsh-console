// 加载骨架屏（卡片栅格里的占位块）的验收探针。
//   node probe-skeleton.mjs <baseUrl> [输出前缀]
//
// 量四件事，全部是 DOM 实测（getBoundingClientRect / getComputedStyle /
// elementFromPoint），不从截图里认数：
//   1. 用 Fetch 拦截把 /api/local/* 压后 2 秒：那 2 秒里的加载态长什么样
//      —— 占位块的个数、几何、列起点，与真条目对得上对不上
//   2. 放行之后：主区宽度 / 列轨数 / 第一项的 x,y 与加载时逐项比（布局没跳）
//   3. 窄屏 360 / 768：占位块跟着列数走
//   4. 占位块不可交互：使用者给的那条查询 + 真点一下 + Tab 走一圈 + 可 Tab 元素扫描
// 只读：不点任何写动作按钮。唯一的「点」是点占位块本身（点了应当没反应）。
import { spawn } from 'node:child_process'
import { writeFileSync, readFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const here = dirname(fileURLToPath(import.meta.url))
const baseUrl = (process.argv[2] || 'http://127.0.0.1:5390/').replace(/\/$/, '')
const prefix = process.argv[3] || 'skeleton'
const CDP_PORT = 9540

const pageSrc = readFileSync(join(here, 'page-probe.js'), 'utf8')

const chrome = spawn('chromium', ['--headless', '--no-sandbox', '--disable-gpu', '--disable-extensions',
  '--hide-scrollbars', '--remote-debugging-port=' + CDP_PORT, '--user-data-dir=/tmp/chrome-skel-' + process.pid,
  '--window-size=1280,900', 'about:blank'], { stdio: 'ignore' })

let page = null
for (let i = 0; i < 60 && !page; i++) {
  try { const l = await (await fetch('http://127.0.0.1:' + CDP_PORT + '/json')).json(); page = l.find((t) => t.type === 'page') } catch {}
  if (!page) await new Promise((r) => setTimeout(r, 250))
}
if (!page) { console.log('chrome 没起来'); process.exit(1) }

const ws = new WebSocket(page.webSocketDebuggerUrl)
let id = 0
const pending = new Map()
const consoleIssues = []
let delayMs = 0
let interceptOn = false

const send = (method, params = {}) => new Promise((res) => {
  const i = ++id; pending.set(i, res); ws.send(JSON.stringify({ id: i, method, params }))
})
const continuePaused = async (p) => {
  if (!interceptOn) { await send('Fetch.continueRequest', { requestId: p.requestId }); return }
  if (delayMs > 0) await new Promise((r) => setTimeout(r, delayMs))
  await send('Fetch.continueRequest', { requestId: p.requestId })
}
ws.onmessage = (e) => {
  const m = JSON.parse(e.data)
  if (m.method === 'Runtime.consoleAPICalled' && ['error', 'warning'].includes(m.params && m.params.type)) {
    consoleIssues.push(m.params.type + ': ' + (m.params.args || []).map((a) => a.value || a.description || '').join(' ').slice(0, 160))
  }
  if (m.method === 'Fetch.requestPaused') { continuePaused(m.params); return }
  if (m.id && pending.has(m.id)) { pending.get(m.id)(m); pending.delete(m.id) }
}
await new Promise((r) => { ws.onopen = r })

const ev = async (expression) => {
  const r = await send('Runtime.evaluate', { expression, returnByValue: true, awaitPromise: true })
  if (r.result && r.result.exceptionDetails) throw new Error('eval 出错: ' + JSON.stringify(r.result.exceptionDetails).slice(0, 400))
  return r.result && r.result.result ? r.result.result.value : undefined
}
const evJson = async (expression) => JSON.parse(await ev(expression))
const sleep = (ms) => new Promise((r) => setTimeout(r, ms))
const setViewport = (w, h) => send('Emulation.setDeviceMetricsOverride', { width: w, height: h, deviceScaleFactor: 1, mobile: false })
const shot = async (name) => {
  const s = await send('Page.captureScreenshot', { format: 'png' })
  writeFileSync(join(here, name), Buffer.from(s.result.data, 'base64'))
  return name
}
const measure = () => evJson(pageSrc + ';JSON.stringify(__dshProbe.measure())')
const snapshot = () => evJson(pageSrc + ';JSON.stringify(__dshProbe.snapshot())')

await send('Page.enable')
await send('Runtime.enable')
await send('Fetch.enable', { patterns: [{ urlPattern: '*/api/local/*', requestStage: 'Request' }] })
interceptOn = true

// 一张表：视口 → 加载态与放行后各量一次
const VIEWS = [
  { w: 1280, h: 900, tag: '1280' },
  { w: 1920, h: 1080, tag: '1920' },
  { w: 768, h: 900, tag: '768' },
  { w: 360, h: 900, tag: '360' },
]
const out = { baseUrl, views: [], interaction: null, columns: null, consoleIssues: null }
const byTag = {}

for (const v of VIEWS) {
  await setViewport(v.w, v.h)
  delayMs = 2000
  await send('Page.navigate', { url: baseUrl + '/' })
  await sleep(1100)                       // 2 秒的延迟还没到 → 还在加载
  const loading = await measure()
  await shot(prefix + '-loading-' + v.tag + '.png')
  // 单列那一档：6 块一列比一屏还高，把视口拉高（只动高度，列数由宽度决定，不影响量到的数）
  // 单独拍一张，好一眼看出「一列 6 块」。
  if (v.tag === '360') {
    await setViewport(360, 1500)
    await sleep(300)
    await shot(prefix + '-loading-360-tall.png')
    await setViewport(360, 900)
    await sleep(300)
  }

  // 交互性：第一档（1280）上真点一下、再 Tab 走一圈
  if (v.tag === '1280') {
    const hit = await evJson(pageSrc + ';JSON.stringify(__dshProbe.clickFirstPlaceholder())')
    const before = await snapshot()
    await send('Input.dispatchMouseEvent', { type: 'mousePressed', x: hit.point.x, y: hit.point.y, button: 'left', clickCount: 1 })
    await send('Input.dispatchMouseEvent', { type: 'mouseReleased', x: hit.point.x, y: hit.point.y, button: 'left', clickCount: 1 })
    await sleep(400)
    const after = await snapshot()
    const tabWalk = []
    // 先把焦点放回页首（点空白处），再按 Tab
    await ev('document.activeElement && document.activeElement.blur && document.activeElement.blur(); true')
    for (let i = 0; i < 12; i++) {
      await send('Input.dispatchKeyEvent', { type: 'rawKeyDown', key: 'Tab', code: 'Tab', windowsVirtualKeyCode: 9, nativeVirtualKeyCode: 9 })
      await send('Input.dispatchKeyEvent', { type: 'keyUp', key: 'Tab', code: 'Tab', windowsVirtualKeyCode: 9, nativeVirtualKeyCode: 9 })
      await sleep(80)
      tabWalk.push(await ev(pageSrc + ';__dshProbe.activeNow()'))
    }
    out.interaction = {
      hit,
      before,
      after,
      clickChanged: JSON.stringify(before) !== JSON.stringify(after),
      tabWalk,
      tabLandedOnPlaceholder: tabWalk.some((s) => String(s).indexOf('dsh-skeleton') >= 0),
      tabMoved: new Set(tabWalk).size > 1,
    }
    // Tab 之后焦点可能落在别处：重载回干净状态再放行
    await send('Page.navigate', { url: baseUrl + '/' })
    await sleep(200)
  }

  await sleep(4500)                       // 延迟放行 + 渲染
  const loaded = await measure()
  await shot(prefix + '-loaded-' + v.tag + '.png')
  byTag[v.tag] = { loading, loaded }
  out.views.push({
    tag: v.tag, viewport: v.viewport || { w: v.w, h: v.h },
    loading, loaded,
    // 逐项比对：加载时（占位块）vs 放行后（真卡片）
    compare: {
      mainWidth: [loading.main ? loading.main.width : null, loaded.main ? loaded.main.width : null],
      gridTracks: loading.grids.map((g, i) => [g.tracks, loaded.grids[i] ? loaded.grids[i].tracks : null]),
      gridTrackSizes: loading.grids.map((g, i) => [g.trackSizes, loaded.grids[i] ? loaded.grids[i].trackSizes : null]),
      firstItemXY: loading.grids.map((g, i) => [g.firstPlaceholder ? [g.firstPlaceholder.x, g.firstPlaceholder.y] : null, loaded.grids[i] && loaded.grids[i].firstCard ? [loaded.grids[i].firstCard.x, loaded.grids[i].firstCard.y] : null]),
      placeholderColsVsCards: loading.grids.map((g, i) => [g.placeholderColXs, loaded.grids[i] ? loaded.grids[i].cardColXs : null]),
      widthPerCol: loading.grids.map((g, i) => [g.placeholderColXs.length ? +g.trackSizes[0].replace('px', '') : null, loaded.grids[i] && loaded.grids[i].cardCount ? loaded.grids[i].firstCard.w : null]),
      pageOverflowX: [loading.pageOverflowX, loaded.pageOverflowX],
      emptyStates: [loading.emptyStates, loaded.emptyStates],
      headHeight: [loading.head ? loading.head.rect.h : null, loaded.head ? loaded.head.rect.h : null],
      headBadges: [loading.head ? loading.head.badges.map((b) => b.text) : null, loaded.head ? loaded.head.badges.map((b) => b.text) : null],
    },
  })
}

// 最后一步：把真卡片克隆到 6 张，量它们的列起点 —— 与加载时的占位块列起点逐列比
delayMs = 0
await setViewport(1920, 1080)
await send('Page.navigate', { url: baseUrl + '/' })
await sleep(4200)
const cloned = await evJson(pageSrc + ';JSON.stringify(__dshProbe.cloneCardsTo(6))')
const phXs = byTag['1920'] ? byTag['1920'].loading.grids[0].placeholderColXs : null
out.columns = {
  note: '克隆只为量列轨（data-clone=1），量完整页重载，不进任何提交',
  placeholderColXs: phXs,
  placeholderTracks: byTag['1920'] ? byTag['1920'].loading.grids[0].tracks : null,
  clonedCardColXs: cloned ? cloned.colXs : null,
  clonedTracks: cloned ? cloned.tracks : null,
  clonedWidths: cloned ? cloned.widths : null,
  clonedHeights: cloned ? cloned.heights : null,
  placeholderWidths: byTag['1920'] ? byTag['1920'].loading.grids[0].trackSizes : null,
  sameXs: JSON.stringify(phXs) === JSON.stringify(cloned ? cloned.colXs : null),
}
await send('Page.navigate', { url: baseUrl + '/' })
await sleep(1500)

out.consoleIssues = consoleIssues
writeFileSync(join(here, prefix + '.json'), JSON.stringify(out, null, 1))

// 一行一行的摘要，方便贴进报告
for (const v of out.views) {
  const L = v.loading
  const D = v.loaded
  console.log('--- 视口 ' + v.tag + ' ---')
  console.log('  加载态: 占位块 ' + (L.loading ? L.loading.placeholderCount : 0) + ' 个，高度 ' + JSON.stringify(L.loading ? L.loading.placeholderHeights : null) + '，宽度 ' + JSON.stringify(L.loading ? L.loading.placeholderWidths : null))
  console.log('  加载态: 每格占位块 ' + JSON.stringify(L.grids.map((g) => g.placeholderCount)) + '，列轨 ' + JSON.stringify(L.grids.map((g) => g.tracks)) + '，占位块列起点 ' + JSON.stringify(L.grids.map((g) => g.placeholderColXs)) + '，主区宽 ' + (L.main ? L.main.width : null))
  console.log('  放行后: 卡片 ' + D.cards.count + ' 张，高度 ' + JSON.stringify(D.cards.heights) + '（带备注 ' + D.cards.withNote + '），宽度 ' + JSON.stringify(D.cards.widths))
  console.log('  放行后: 列轨 ' + JSON.stringify(D.grids.map((g) => g.tracks)) + '，卡片列起点 ' + JSON.stringify(D.grids.map((g) => g.cardColXs)) + '，主区宽 ' + (D.main ? D.main.width : null))
  console.log('  比对  : 主区宽 ' + JSON.stringify(v.compare.mainWidth) + ' 列轨 ' + JSON.stringify(v.compare.gridTracks) + ' 第一项 xy ' + JSON.stringify(v.compare.firstItemXY) + ' 空态 ' + JSON.stringify(v.compare.emptyStates))
  console.log('  动效  : ' + JSON.stringify(L.animations))
  console.log('  页头  : 高 ' + JSON.stringify(v.compare.headHeight) + ' 徽标 ' + JSON.stringify(v.compare.headBadges))
}
console.log('--- 不可交互 ---')
console.log('  ' + JSON.stringify(out.interaction ? { hit: out.interaction.hit, clickChanged: out.interaction.clickChanged, tabLandedOnPlaceholder: out.interaction.tabLandedOnPlaceholder, tabWalk: out.interaction.tabWalk } : null))
const L0 = byTag['1280'].loading
console.log('  加载区里 button/' + L0.loading.buttonsInside + ' [tabindex]/' + L0.loading.tabbablesInside + ' a/' + L0.loading.linksInside + ' [role=button]/' + L0.loading.roleButtonsInside)
console.log('  使用者那条查询 .dsh-loading button, .dsh-loading [tabindex] = ' + L0.loading.acceptanceQuery)
console.log('  aria-hidden 的占位块 ' + L0.loading.placeholdersAriaHidden + '/' + L0.loading.placeholderCount + '，带 role ' + L0.loading.placeholdersWithRole + '，带 tabindex ' + L0.loading.placeholdersWithTabindex)
console.log('  说明行: ' + JSON.stringify(L0.loading.note))
console.log('--- 列轨对照（1920，克隆到 6 张）---')
console.log('  ' + JSON.stringify(out.columns))
console.log('--- 控制台问题 ---')
console.log('  ' + (consoleIssues.length ? consoleIssues.join(' | ') : '无'))

ws.close()
try { chrome.kill() } catch (e) {}
process.exit(0)

// 骨架屏「每个分组最多一行」的验收探针（第十一轮）。
//   node probe-skeleton-rows.mjs <baseUrl> [输出前缀]
//
// 口径照上一轮 evidence-loading-skeleton/probe-skeleton.mjs：用 Fetch 拦截把 /api/local/*
// 压后 2 秒 —— 那 2 秒里量一次加载态，放行之后再量一次，逐项比。
// 这一轮新量的是**每个分组的骨架区高度**（.dsh-skeleton-row）：它必须恰好等于真条目那一行。
//
// 每档视口量：
//   1. 分组里 .dsh-skeleton-row 的高度 / max-height / overflow / scrollHeight
//   2. 真正露在外面的占位块有几个（整块落在裁剪框内的才算）—— 应当等于这一档的列数
//   3. 露出来的占位块的 x / 宽 / 高（与放行后的真卡片逐项比）
//   4. 栅格列轨（grid-template-columns）与主区宽（加载时 vs 放行后）
// 全部是 DOM 实测（getBoundingClientRect / getComputedStyle），不从截图里认数。
import { spawn } from 'node:child_process'
import { writeFileSync } from 'node:fs'

const here = new URL('.', import.meta.url).pathname
const baseUrl = (process.argv[2] || 'http://127.0.0.1:5390/').replace(/\/$/, '')
const prefix = process.argv[3] || 'skeleton-rows'
const CDP_PORT = 9540 + (process.pid % 400)

const chrome = spawn('chromium', ['--headless', '--no-sandbox', '--disable-gpu', '--disable-extensions',
  '--hide-scrollbars', '--remote-debugging-port=' + CDP_PORT, '--user-data-dir=/tmp/chrome-rows-' + process.pid,
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

const send = (method, params = {}) => new Promise((res) => {
  const i = ++id; pending.set(i, res); ws.send(JSON.stringify({ id: i, method, params }))
})
ws.onmessage = (e) => {
  const m = JSON.parse(e.data)
  if (m.method === 'Runtime.consoleAPICalled' && ['error', 'warning'].includes(m.params && m.params.type)) {
    consoleIssues.push(m.params.type + ': ' + (m.params.args || []).map((a) => a.value || a.description || '').join(' ').slice(0, 160))
  }
  if (m.method === 'Fetch.requestPaused') {
    const p = m.params
    setTimeout(() => { send('Fetch.continueRequest', { requestId: p.requestId }) }, delayMs)
    return
  }
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
  writeFileSync(here + name, Buffer.from(s.result.data, 'base64'))
  return name
}

// 页面里那段测量：一次把加载态与放行后都用得上的东西量全
const MEASURE = `(() => {
  const R = (el) => { const r = el.getBoundingClientRect(); return { x: +r.x.toFixed(1), y: +r.y.toFixed(1), w: +r.width.toFixed(1), h: +r.height.toFixed(1), right: +r.right.toFixed(1), bottom: +r.bottom.toFixed(1) } }
  const groups = [...document.querySelectorAll('[data-name="row-group"]')].map((g) => {
    const cs = getComputedStyle(g)
    const row = g.querySelector('.dsh-skeleton-row')
    const rowRect = row ? R(row) : null
    const rcs = row ? getComputedStyle(row) : null
    const tiles = [...g.querySelectorAll('.dsh-skeleton')]
    // 「露在外面」= 整块落在裁剪框里。被 overflow: hidden 裁掉的那些，layout rect 仍在
    // （getBoundingClientRect 不裁剪），所以用「底边有没有超出这一行的底」来分。
    // 注意 R() 给的是 y 不是 top（踩过一次：拿 rowRect.top 比出 NaN，6 块全被判成"裁掉了"）
    const visible = rowRect ? tiles.filter((t) => { const r = t.getBoundingClientRect(); return r.height > 0 && r.bottom <= rowRect.bottom + 0.5 && r.top >= rowRect.y - 0.5 }) : tiles
    const cards = [...g.querySelectorAll('.dsh-case')]
    return {
      group: g.getAttribute('data-group'),
      gridWidth: +g.getBoundingClientRect().width.toFixed(1),
      tracks: cs.gridTemplateColumns,
      trackCount: cs.gridTemplateColumns.split(' ').filter((s) => s).length,
      row: rowRect,
      rowMaxHeight: rcs ? rcs.maxHeight : null,
      rowOverflow: rcs ? rcs.overflow : null,
      rowScrollHeight: row ? row.scrollHeight : null,
      skeletonCount: tiles.length,
      visibleCount: visible.length,
      visibleRects: visible.map(R),
      hiddenRects: rowRect ? tiles.filter((t) => !visible.includes(t)).map(R) : [],
      note: g.querySelector('.dsh-loading-note') ? R(g.querySelector('.dsh-loading-note')) : null,
      cards: cards.map((c) => ({ row: c.getAttribute('data-row'), rect: R(c) })),
    }
  })
  const main = document.querySelector('.dsh-main')
  const anim = [...document.querySelectorAll('*')].filter((e) => { const c = getComputedStyle(e); return c.animationName && c.animationName !== 'none' })
  return JSON.stringify({
    viewport: { w: innerWidth, h: innerHeight },
    main: main ? R(main) : null,
    groups,
    pageOverflowX: document.documentElement.scrollWidth > document.documentElement.clientWidth,
    animations: { count: anim.length, names: anim.map((e) => getComputedStyle(e).animationName) },
  })
})()`

await send('Page.enable')
await send('Runtime.enable')
await send('Fetch.enable', { patterns: [{ urlPattern: '*/api/local/*', requestStage: 'Request' }] })

const VIEWS = [
  { w: 1920, h: 1080, tag: '1920', cols: 6 },
  { w: 1280, h: 900, tag: '1280', cols: 4 },
  { w: 768, h: 900, tag: '768', cols: 2 },
  { w: 360, h: 900, tag: '360', cols: 1 },
]
const out = { baseUrl, views: [], consoleIssues: null }

for (const v of VIEWS) {
  await setViewport(v.w, v.h)
  delayMs = 2000
  await send('Page.navigate', { url: baseUrl + '/' })
  await sleep(1200)                       // 2 秒的延迟还没到 → 还在加载
  const loading = await evJson(MEASURE)
  await shot(prefix + '-loading-' + v.tag + '.png')
  await sleep(4200)                       // 放行 + 渲染
  const loaded = await evJson(MEASURE)
  await shot(prefix + '-loaded-' + v.tag + '.png')
  out.views.push({
    tag: v.tag, viewport: { w: v.w, h: v.h }, expectedCols: v.cols,
    loading, loaded,
    compare: loading.groups.map((g, i) => {
      const d = loaded.groups[i] || { cards: [] }
      const firstCard = d.cards[0] ? d.cards[0].rect : null
      return {
        group: g.group,
        tracks: [g.trackCount, d.trackCount],
        trackSizes: [g.tracks, d.tracks],
        gridWidth: [g.gridWidth, d.gridWidth],
        skeletonRowHeight: g.row ? g.row.h : null,
        cardHeight: firstCard ? firstCard.h : null,
        cardHeights: d.cards.map((c) => c.rect.h),
        firstItemXY: [g.visibleRects[0] ? [g.visibleRects[0].x, g.visibleRects[0].y] : null, firstCard ? [firstCard.x, firstCard.y] : null],
        placeholderX: g.visibleRects.map((r) => r.x),
        cardX: d.cards.map((c) => c.rect.x),
        placeholderW: g.visibleRects.map((r) => r.w),
        cardW: d.cards.map((c) => c.rect.w),
      }
    }),
    mainWidth: [loading.main ? loading.main.w : null, loaded.main ? loaded.main.w : null],
  })
}

out.consoleIssues = consoleIssues
writeFileSync(here + prefix + '.json', JSON.stringify(out, null, 1))

for (const v of out.views) {
  const L = v.loading, D = v.loaded
  console.log('--- 视口 ' + v.tag + '（这一档 ' + v.expectedCols + ' 列）---')
  for (let i = 0; i < L.groups.length; i++) {
    const g = L.groups[i], c = v.compare[i], d = D.groups[i] || { cards: [] }
    console.log('  分组 ' + g.group + ' 加载态: 骨架区 h=' + (g.row ? g.row.h : null) +
      '（max-height ' + g.rowMaxHeight + ' / overflow ' + g.rowOverflow + ' / 内容高 ' + g.rowScrollHeight + '）' +
      ' 占位块 ' + g.skeletonCount + ' 块，露在外面 ' + g.visibleCount + ' 块' +
      ' 列轨 ' + g.trackCount + ' 列 宽 ' + JSON.stringify(g.visibleRects.map((r) => r.w)))
    console.log('  分组 ' + g.group + ' 放行后: 卡片 ' + d.cards.length + ' 张，高度 ' + JSON.stringify(c.cardHeights) +
      ' 列轨 ' + d.trackCount + ' 列 [' + d.tracks + ']')
    console.log('  分组 ' + g.group + ' 比对  : 骨架区高/卡片高 [' + c.skeletonRowHeight + ',' + c.cardHeight + ']' +
      ' 列轨 [' + c.tracks + ']' +
      ' 第一项 xy [' + JSON.stringify(c.firstItemXY) + ']' +
      ' 占位块 vs 卡片 x ' + JSON.stringify(c.placeholderX) + ' / ' + JSON.stringify(c.cardX))
  }
  console.log('  主区宽（加载/放行）: ' + JSON.stringify(v.mainWidth) + ' 横向溢出: ' + L.pageOverflowX + ' 动效: ' + JSON.stringify(L.animations))
}
console.log('--- 控制台问题 ---')
console.log('  ' + (consoleIssues.length ? consoleIssues.join(' | ') : '无'))

ws.close()
try { chrome.kill() } catch (e) {}
process.exit(0)

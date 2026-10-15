// 路由与加载态的验收探针（CDP）。跑法：
//   node verify-routing.mjs http://127.0.0.1:5390/
//
// 覆盖三件事：
//   A 路由   —— 逐页 / 逐设置分组切过去 → 贴 URL；Page.reload 之后还在原处；
//               前进 / 后退各一次；直接敲错误 path 的表现（回落 + 为什么）。
//   B 加载态 —— 用 Fetch 拦截把 /api/local/* 压后 2 秒：这 2 秒里必须是「加载中」，
//               不是「空态」；接口回来之后再截一张。
//   C 空态   —— 把 instances / profiles / logs 的响应换成空数组：
//               这时候才该出现空态（与 B 那两张必须能一眼分开）。
//
// 只读：不点任何写动作按钮。截图落在脚本同目录。
import { spawn } from 'node:child_process'
import { writeFileSync, mkdirSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const here = dirname(fileURLToPath(import.meta.url))
const baseUrl = (process.argv[2] || 'http://127.0.0.1:5390/').replace(/\/$/, '')
const out = {}
const CDP_PORT = 9411

mkdirSync(here, { recursive: true })
const chrome = spawn('chromium', ['--headless', '--no-sandbox', '--disable-gpu', '--disable-extensions',
  '--hide-scrollbars', '--remote-debugging-port=' + CDP_PORT, '--user-data-dir=/tmp/chrome-routing-' + process.pid,
  '--window-size=1440,960', 'about:blank'], { stdio: 'ignore' })

let page = null
for (let i = 0; i < 60 && !page; i++) {
  try { const l = await (await fetch('http://127.0.0.1:' + CDP_PORT + '/json')).json(); page = l.find((t) => t.type === 'page') } catch {}
  if (!page) await new Promise((r) => setTimeout(r, 250))
}
if (!page) { console.log(JSON.stringify({ ok: false, error: 'chrome 没起来' })); process.exit(1) }

const ws = new WebSocket(page.webSocketDebuggerUrl)
let id = 0
const pending = new Map()
const busy = new Set()
ws.onmessage = (e) => {
  const m = JSON.parse(e.data)
  if (m.id && pending.has(m.id)) { pending.get(m.id)(m); pending.delete(m.id); return }
  if (m.method === 'Fetch.requestPaused') { handlePaused(m.params) }
}
await new Promise((r) => { ws.onopen = r })
const send = (method, params = {}) => new Promise((res) => { const i = ++id; pending.set(i, res); ws.send(JSON.stringify({ id: i, method, params })) })
const ev = async (expression) => {
  const r = await send('Runtime.evaluate', { expression, returnByValue: true, awaitPromise: true })
  if (r.result?.exceptionDetails) return 'EXCEPTION: ' + JSON.stringify(r.result.exceptionDetails).slice(0, 200)
  return r.result?.result?.value
}
const sleep = (ms) => new Promise((r) => setTimeout(r, ms))
const shot = async (name) => {
  const s = await send('Page.captureScreenshot', { format: 'png' })
  writeFileSync(join(here, name), Buffer.from(s.result.data, 'base64'))
  return name
}

// ── 拦截规则 ────────────────────────────────────────────────
// delayMs：命中的接口压后多少毫秒再放行
// fulfill：命中之后直接回这份 JSON（空数组那一档用它）
let intercept = { enabled: false, delayMs: 0, fulfill: null }
const handlePaused = async (params) => {
  const url = params.request.url
  if (!intercept.enabled) { await send('Fetch.continueRequest', { requestId: params.requestId }); return }
  if (intercept.fulfill && intercept.fulfill.match.some((m) => url.includes(m))) {
    const body = intercept.fulfill.bodyFor(url)
    await send('Fetch.fulfillRequest', {
      requestId: params.requestId,
      responseCode: 200,
      responseHeaders: [{ name: 'content-type', value: 'application/json' }],
      body: Buffer.from(JSON.stringify(body)).toString('base64'),
    })
    return
  }
  if (intercept.delayMs > 0) await sleep(intercept.delayMs)
  await send('Fetch.continueRequest', { requestId: params.requestId })
}
const setIntercept = async (next) => {
  intercept = { ...intercept, ...next }
  await send('Fetch.enable', { patterns: [{ urlPattern: '*/api/local/*', requestStage: 'Request' }] })
}
const clearIntercept = async () => {
  intercept = { enabled: false, delayMs: 0, fulfill: null }
  await send('Fetch.disable')
}

// ── 页面标识 ────────────────────────────────────────────────
const IDENT = `(() => {
  const q = (s) => !!document.querySelector(s)
  return JSON.stringify({
    url: location.pathname + location.search,
    h1: document.querySelector('h1') ? document.querySelector('h1').textContent.trim() : null,
    settingsGroup: document.querySelector('.dsh-settings-tab.active') ? document.querySelector('.dsh-settings-tab.active').textContent.trim() : null,
    routeNotice: document.querySelector('[data-name="route-notice"]') ? document.querySelector('[data-name="route-notice"]').textContent.trim() : null,
    overview: q('[data-name="overview-page"]'), logs: q('[data-name="logs-page"]'),
    settings: q('[data-name="settings-page"]'), about: q('[data-name="about-page"]'),
  })
})()`
const ident = async () => JSON.parse(await ev(IDENT) || '{}')
const clickNav = async (label) => {
  await ev(`[...document.querySelectorAll('.dsh-nav-item')].find((e) => e.textContent.trim() === ${JSON.stringify(label)})?.click()`)
  await sleep(700)
}
const clickGroup = async (id) => {
  await ev(`document.querySelector('[data-name="settings-tab"][data-group="' + ${JSON.stringify(id)} + '"]')?.click()`)
  await sleep(600)
}
const goto = async (url, wait = 2500) => { await send('Page.navigate', { url }); await sleep(wait) }
const reload = async (wait = 2500) => { await send('Page.reload', { ignoreCache: true }); await sleep(wait) }

await send('Page.enable')
await send('Runtime.enable')
await send('Emulation.setDeviceMetricsOverride', { width: 1440, height: 960, deviceScaleFactor: 1, mobile: false })

// ── A 路由 ─────────────────────────────────────────────────
await goto(baseUrl + '/', 3000)
const routing = { pages: [], reloads: [] }
routing.pages.push({ step: '初始 /', ...(await ident()) })
for (const [label, tag] of [['日志', '日志'], ['设置', '设置'], ['关于', '关于'], ['实例总览', '实例总览']]) {
  await clickNav(label)
  routing.pages.push({ step: '点侧栏 ' + tag, ...(await ident()) })
}
// 设置页的五个分组，逐个切
await clickNav('设置')
routing.pages.push({ step: '点侧栏 设置（回到设置）', ...(await ident()) })
const groups = []
for (const g of ['instance', 'process', 'logs', 'ui', 'safety']) {
  await clickGroup(g)
  groups.push(await ident())
}
routing.groups = groups
// 刷新落回同一页：日志页
await clickNav('日志')
await reload(3000)
routing.reloads.push({ step: '日志页刷新', ...(await ident()) })
// 刷新落回同一分组：设置 / safety（先切到最靠后的那一组）
await clickNav('设置')
await clickGroup('safety')
const beforeReload = await ident()
await reload(3000)
const afterReload = await ident()
routing.reloads.push({ step: '设置/safety 刷新', before: beforeReload, after: afterReload })
await shot('settings-safety-after-reload.png')
// 前进 / 后退
await clickNav('实例总览')
const backFrom = await ident()
await ev('history.back()')
await sleep(1200)
const backTo = await ident()
await ev('history.forward()')
await sleep(1200)
const fwdTo = await ident()
routing.history = { from: backFrom, back: backTo, forward: fwdTo }
// 错误 path：设置里一个不存在的分组
await goto(baseUrl + '/settings/not-a-group', 3000)
routing.badGroup = await ident()
await shot('route-fallback-settings.png')
// 错误 path：整条不认识的路径
await goto(baseUrl + '/nope/deep', 3000)
routing.badPath = await ident()
await shot('route-fallback-overview.png')
out.routing = routing

// ── B 加载态（接口压后 2 秒） ──────────────────────────────
await setIntercept({ enabled: true, delayMs: 2000, fulfill: null })
await send('Page.navigate', { url: baseUrl + '/' })
await sleep(1000) // 2 秒延迟还没到
const duringLoad = JSON.parse(await ev(`(() => {
  const de = document.body.innerText
  return JSON.stringify({
    url: location.pathname + location.search,
    runningLoading: !!document.querySelector('[data-name="running-loading"]'),
    stoppedLoading: !!document.querySelector('[data-name="stopped-loading"]'),
    runningEmptyEl: !!document.querySelector('[data-name="running-empty"]'),
    stoppedEmptyEl: !!document.querySelector('[data-name="stopped-empty"]'),
    emptyRunning: de.includes('当前没有检测到正在运行的 dsh 实例'),
    emptyStopped: de.includes('还没有已停止的实例'),
    loadingText: (document.querySelector('[data-name="running-loading"]') || {}).textContent || null,
    badge: [...document.querySelectorAll('[data-name="source-badge"]')].map((e) => e.textContent.trim()).slice(0, 3),
    sectionTitles: [...document.querySelectorAll('.dsh-section-title')].map((e) => e.textContent.trim()),
  })
})()`) || {})
await shot('overview-loading.png')
await sleep(4000) // 延迟放行 + 渲染
const afterLoad = JSON.parse(await ev(`(() => {
  const de = document.body.innerText
  return JSON.stringify({
    runningLoading: !!document.querySelector('[data-name="running-loading"]'),
    cards: document.querySelectorAll('[data-name="instance-card"]').length,
    realBadge: de.includes('真实数据'),
    sectionTitles: [...document.querySelectorAll('.dsh-section-title')].map((e) => e.textContent.trim()),
  })
})()`) || {})
await shot('overview-loaded.png')
// 日志页：同样压后 2 秒
await send('Page.navigate', { url: baseUrl + '/logs' })
await sleep(1000)
const logDuringLoad = JSON.parse(await ev(`(() => {
  const de = document.body.innerText
  return JSON.stringify({
    url: location.pathname + location.search,
    logLoading: !!document.querySelector('[data-name="log-loading"]'),
    emptyLogEl: !!document.querySelector('.dsh-log-empty'),
    emptyLog: de.includes('没有可显示的行'),
  })
})()`) || {})
await shot('logs-loading.png')
// 读数落地之后来源会自动定下来（host → instance:<id>），那是一次补读，也要等它回来
await sleep(9000)
const logLoaded = JSON.parse(await ev(`(() => {
  const de = document.body.innerText
  return JSON.stringify({
    logLoading: !!document.querySelector('[data-name="log-loading"]'),
    box: !!document.querySelector('[data-name="log-box"]'),
    lines: document.querySelectorAll('.dsh-log-line').length,
    emptyLogEl: !!document.querySelector('.dsh-log-empty'),
    emptyLog: de.includes('没有可显示的行'),
  })
})()`) || {})
await shot('logs-loaded.png')
out.loading = { duringLoad, afterLoad, logDuringLoad, logLoaded }
await clearIntercept()

// ── C 空态（响应换成空数组） ────────────────────────────────
const emptyEnvelope = (data) => ({ ok: true, data })
await setIntercept({
  enabled: true, delayMs: 0,
  fulfill: {
    match: ['/api/local/instances', '/api/local/profiles', '/api/local/logs'],
    bodyFor: (url) => {
      if (url.includes('/api/local/instances')) {
        return emptyEnvelope({
          sources: ['/proc/net/tcp'], candidateCount: 0, probe: { hits: 0 },
          signatures: [], processSupplement: { note: '空数组（验收用）' }, instances: [],
        })
      }
      if (url.includes('/api/local/profiles')) {
        return emptyEnvelope({
          dshHome: '/tmp/empty', dshHomeSource: '空数组（验收用）',
          profilesRoot: '/tmp/empty/profiles', currentProfile: null, profiles: [],
        })
      }
      return emptyEnvelope({ source: 'host', kind: 'host', readOk: true, lines: [], effectiveTail: 200, maxTail: 2000, windowBytes: 0, detectedInstances: 0, truncated: false })
    },
  },
})
await send('Page.navigate', { url: baseUrl + '/' })
await sleep(3500)
const emptyState = JSON.parse(await ev(`(() => {
  const de = document.body.innerText
  return JSON.stringify({
    url: location.pathname + location.search,
    runningLoading: !!document.querySelector('[data-name="running-loading"]'),
    runningEmpty: !!document.querySelector('[data-name="running-empty"]'),
    stoppedEmpty: !!document.querySelector('[data-name="stopped-empty"]'),
    emptyRunningText: de.includes('当前没有检测到正在运行的 dsh 实例'),
    emptyStoppedText: de.includes('还没有已停止的实例'),
    sectionTitles: [...document.querySelectorAll('.dsh-section-title')].map((e) => e.textContent.trim()),
  })
})()`) || {})
await shot('overview-empty.png')
await send('Page.navigate', { url: baseUrl + '/logs' })
await sleep(3500)
const emptyLog = JSON.parse(await ev(`(() => {
  const de = document.body.innerText
  return JSON.stringify({
    logLoading: !!document.querySelector('[data-name="log-loading"]'),
    emptyLogEl: !!document.querySelector('.dsh-log-empty'),
    emptyLog: de.includes('没有可显示的行'),
    lines: document.querySelectorAll('.dsh-log-line').length,
  })
})()`) || {})
await shot('logs-empty.png')
out.empty = { overview: emptyState, logs: emptyLog }
await clearIntercept()

writeFileSync(join(here, 'verify-routing.json'), JSON.stringify(out, null, 1))
console.log(JSON.stringify(out, null, 1))
chrome.kill()
process.exit(0)

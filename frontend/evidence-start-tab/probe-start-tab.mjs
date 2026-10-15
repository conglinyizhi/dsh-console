// 启动成功后自动开标页的取证探针（backlog 第 5 条）。
//
// 用法：
//   node probe-start-tab.mjs --mode auto|blocked|fail|external [--profile review-dev]
//                            [--url http://127.0.0.1:5390/] [--out .] [--tag auto]
//
// 三条规矩：
//
// 1. **真手势**。点按钮走 Input.dispatchMouseEvent，不用 element.click() ——
//    后者是脚本事件，没有 user activation，浏览器一定拦 window.open，
//    那样测出来的「被拦」是我们自己造的假象。
// 2. **让标页自己说话**。新标页的地址从它自己的 CDP 会话里读（location.href），
//    并且单独收它的 Page.frameNavigated —— /json 与 Target.targetInfo 里的 url
//    可能省略查询串，令牌在不在，只有页面自己说了算。
// 3. **每一枪都有上限**。CDP 调用 8 秒不应答就记超时继续走，最后一定落盘 ——
//    挂在半路的探针留下的是一堆猜。
//
// 连接方式：走浏览器级 endpoint（/json/version）再 Target.attachToTarget（flatten），
// 控制台页与每一个新标页各是一个会话，事件靠 sessionId 分。
//
// 四个模式：
//   auto      启动一只真实例：占位标页应当被填成带令牌的地址
//   blocked   模拟弹窗拦截（见 simulateBlock 的说明）：不开标页，
//             提示条里出现「打开 Web UI」按钮，点它（新手势）能开
//   fail      启动一只起不来的 profile：占位标页应当被关掉（不留白页）
//   external  外部实例（webUrl 为 null）点「打开 Web UI」：一个标页都不开，只给原因
import { spawn } from 'node:child_process'
import { mkdirSync, writeFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const here = dirname(fileURLToPath(import.meta.url))
const argv = process.argv.slice(2)
const opt = (name, def) => {
  const i = argv.indexOf('--' + name)
  return i >= 0 && argv[i + 1] !== undefined ? argv[i + 1] : def
}
const mode = opt('mode', 'auto')
const baseUrl = opt('url', 'http://127.0.0.1:5390/')
const profileName = opt('profile', 'review-dev')
const outDir = opt('out', here)
const tag = opt('tag', mode)

mkdirSync(outDir, { recursive: true })

const CDP_PORT = 9300 + (process.pid % 600)
const httpBase = 'http://127.0.0.1:' + CDP_PORT
const chrome = spawn('chromium', ['--headless', '--no-sandbox', '--disable-gpu',
  '--disable-extensions', '--hide-scrollbars', '--remote-debugging-port=' + CDP_PORT,
  '--user-data-dir=/tmp/chrome-probe-' + process.pid, '--window-size=1280,900',
  'about:blank'], { stdio: 'ignore' })

const T0 = Date.now()
const ms = () => Date.now() - T0
const wait = (n) => new Promise((r) => setTimeout(r, n))
const listTargets = async () => {
  try { return await (await fetch(httpBase + '/json')).json() } catch (e) { return [] }
}
const pagesViaHttp = async () => (await listTargets()).filter((t) => t.type === 'page').map((t) => ({ id: t.id, url: t.url, title: t.title }))

// 浏览器级 endpoint
let browserWsUrl = null
for (let i = 0; i < 40 && !browserWsUrl; i++) {
  try {
    const v = await (await fetch(httpBase + '/json/version')).json()
    browserWsUrl = v.webSocketDebuggerUrl
  } catch (e) {}
  if (!browserWsUrl) await wait(250)
}
if (!browserWsUrl) { console.log(JSON.stringify({ ok: false, error: 'chrome 没起来' })); process.exit(1) }

const bw = new WebSocket(browserWsUrl)
const pending = new Map()
const sessions = {}          // sessionId -> targetId
const attached = {}          // targetId -> sessionId
let mainSid = null           // 控制台页那个会话（附上之后才知道），事件分流要用它
const mainIssues = []
const childIssues = []
const events = { targetCreated: [], targetDestroyed: [], targetInfoChanged: [], attachedToTarget: [] }
const childNav = []
// 标页发出的请求（只记文档级）：**「这个标页请求的是哪条地址」是这一轮最硬的一条证据**。
// 地址栏会变 —— dsh web 握完手会把 ?token= 清掉（history.replaceState 或 302），
// 所以「后来地址栏里没有 token」不等于「开的时候没带 token」。
const childRequests = []
const sendRaw = (method, params, sessionId) => new Promise((res) => {
  const i = ++id
  pending.set(i, res)
  bw.send(JSON.stringify(sessionId ? { id: i, method, params, sessionId } : { id: i, method, params }))
})
let id = 0
// 不应答就认超时：一次挂住的 CDP 调用不该把整趟取证拖成零产出
const send = async (method, params = {}, sessionId, timeoutMs = 8000) => {
  const out = await Promise.race([
    sendRaw(method, params, sessionId).then((r) => ({ r })),
    wait(timeoutMs).then(() => ({ timeout: true })),
  ])
  if (out.timeout) return { result: { __timeout: method + ' ' + timeoutMs + 'ms 没应答' } }
  return out.r
}
bw.onmessage = (e) => {
  const m = JSON.parse(e.data)
  const p = m.params || {}
  if (m.method === 'Target.targetCreated') {
    events.targetCreated.push({ t: ms(), targetId: p.targetInfo && p.targetInfo.targetId, type: p.targetInfo && p.targetInfo.type, url: p.targetInfo && p.targetInfo.url, title: p.targetInfo && p.targetInfo.title, openerId: p.targetInfo && p.targetInfo.openerId })
    if (p.targetInfo && p.targetInfo.type === 'page') attachNewTarget(p.targetInfo.targetId)
  } else if (m.method === 'Target.targetDestroyed') {
    events.targetDestroyed.push({ t: ms(), targetId: p.targetId })
  } else if (m.method === 'Target.targetInfoChanged') {
    events.targetInfoChanged.push({ t: ms(), targetId: p.targetInfo && p.targetInfo.targetId, type: p.targetInfo && p.targetInfo.type, url: p.targetInfo && p.targetInfo.url, title: p.targetInfo && p.targetInfo.title })
  } else if (m.method === 'Target.attachedToTarget') {
    events.attachedToTarget.push({ t: ms(), sessionId: p.sessionId, targetId: p.targetInfo && p.targetInfo.targetId, url: p.targetInfo && p.targetInfo.url })
  } else if (m.method === 'Network.requestWillBeSent' && m.sessionId && p.type === 'Document') {
    childRequests.push({ t: ms(), sessionId: m.sessionId, targetId: sessions[m.sessionId] || null, event: 'requestWillBeSent', url: p.request && p.request.url })
  } else if (m.method === 'Network.responseReceived' && m.sessionId && p.type === 'Document') {
    childRequests.push({ t: ms(), sessionId: m.sessionId, targetId: sessions[m.sessionId] || null, event: 'responseReceived', status: p.response && p.response.status, url: p.response && p.response.url })
  } else if (m.method === 'Page.frameNavigated' && m.sessionId) {
    childNav.push({ t: ms(), sessionId: m.sessionId, targetId: sessions[m.sessionId] || null, event: 'frameNavigated', url: p.frame && p.frame.url })
  } else if (m.method === 'Page.loadEventFired' && m.sessionId) {
    childNav.push({ t: ms(), sessionId: m.sessionId, targetId: sessions[m.sessionId] || null, event: 'loadEventFired' })
  } else if (m.method === 'Runtime.consoleAPICalled' && ['error', 'warning'].indexOf(p.type) >= 0) {
    // 分清是谁的控制台：控制台页自己的问题才是「控制台零问题」那一条要看的，
    // 标页（实例的 Web UI）那边的 401/404 是那个应用自己的事
    const line = 'consoleAPICalled(' + p.type + '): ' + (p.args || []).map((a) => a.value || a.description || '').join(' ').slice(0, 200)
    if (m.sessionId === mainSid) mainIssues.push(line)
    else childIssues.push(line)
  } else if (m.method === 'Log.entryAdded' && p.entry && p.entry.level === 'error') {
    const line = 'log: ' + String(p.entry.text).slice(0, 200)
    if (m.sessionId === mainSid) mainIssues.push(line)
    else childIssues.push(line)
  }
  if (m.id && pending.has(m.id)) { pending.get(m.id)(m); pending.delete(m.id) }
}
await new Promise((r) => { bw.onopen = r })

const attachNewTarget = async (targetId) => {
  if (attached[targetId]) return attached[targetId]
  const r = await send('Target.attachToTarget', { targetId, flatten: true })
  const sid = r.result && r.result.sessionId
  if (!sid) return null
  sessions[sid] = targetId
  attached[targetId] = sid
  await send('Page.enable', {}, sid)
  await send('Runtime.enable', {}, sid)
  await send('Log.enable', {}, sid)
  await send('Network.enable', {}, sid)
  return sid
}

const evIn = async (sessionId, expression) => {
  const r = await send('Runtime.evaluate', { expression, returnByValue: true, awaitPromise: true }, sessionId)
  if (r.result && r.result.exceptionDetails) return { __error: String(r.result.exceptionDetails.text) }
  return r.result && r.result.result ? r.result.result.value : undefined
}
const shotIn = async (sessionId, name, beyond) => {
  // 整页截图（captureBeyondViewport）在实例那一页上很慢：拍一张要十几秒，
  // 8 秒的超时会把图悄悄变没了。标页就拍视口，时间放宽到 30 秒。
  const r = await send('Page.captureScreenshot', { format: 'png', captureBeyondViewport: !!beyond }, sessionId, beyond ? 8000 : 30000)
  if (!r.result || !r.result.data) return { error: (r.result && r.result.__timeout) || '没有图' }
  const path = join(outDir, tag + '-' + name + '.png')
  writeFileSync(path, Buffer.from(r.result.data, 'base64'))
  return path
}

await send('Target.setDiscoverTargets', { discover: true })
const pageTarget = (await listTargets()).find((t) => t.type === 'page')
mainSid = await attachNewTarget(pageTarget.id)
if (!mainSid) { console.log(JSON.stringify({ ok: false, error: '附不上控制台页' })); process.exit(1) }
const ev = (expression) => evIn(mainSid, expression)
const shot = (name) => shotIn(mainSid, name)
const clickAt = async (x, y) => {
  await send('Input.dispatchMouseEvent', { type: 'mousePressed', x, y, button: 'left', clickCount: 1 }, mainSid)
  await send('Input.dispatchMouseEvent', { type: 'mouseReleased', x, y, button: 'left', clickCount: 1 }, mainSid)
}
// 无头浏览器里新标页一抢焦点，控制台那一页就成了「看不见的页」，requestAnimationFrame
// 停摆、DOM 不再被 patch —— 界面看着像没反应，其实 model 早改了。
// 读界面前把它拎到前面来，才是它该有的样子。
const bringToFront = () => send('Page.bringToFront', {}, mainSid)
await send('Emulation.setDeviceMetricsOverride', { width: 1280, height: 900, deviceScaleFactor: 1, mobile: false }, mainSid)

const result = { mode, baseUrl, profile: profileName, steps: {} }
const noticeExpr = "(() => { const n = document.querySelector('[data-name=\"action-notice\"]'); if (!n) return JSON.stringify({ present: false }); const b = n.querySelector('[data-name=\"notice-open-web-ui\"]'); return JSON.stringify({ present: true, ok: n.getAttribute('data-ok'), text: n.innerText, hasButton: !!b }) })()"
const notice = async () => { const v = await ev(noticeExpr); try { return JSON.parse(v) } catch (e) { return { parseError: String(v).slice(0, 120) } } }
const instances = async () => {
  const raw = await ev("fetch('/api/local/instances').then((r) => r.json()).then((j) => JSON.stringify((j.data.instances || []).map((i) => ({ port: i.port, profile: i.profile, webUrl: i.webUrl }))))")
  try { return JSON.parse(raw) } catch (e) { return null }
}

await send('Page.navigate', { url: baseUrl }, mainSid)
await wait(4500)
const before = (await instances()) || []
result.portsBefore = before.map((i) => i.port)

if (mode === 'blocked') {
  // 模拟弹窗拦截。**模拟的是「占位页那一枪被拦」**：把 window.open 对空 URL 的调用
  // 换成返回 null，其余调用照旧转给真的 window.open —— 不这么分，方案 B 那颗按钮
  // 也会一起被换掉，「点了能开」就成了无从验证的事。
  const patched = "(() => { const real = window.open.bind(window); window.open = (...args) => (args[0] === '' ? null : real(...args)); return 'patched' })()"
  await send('Page.addScriptToEvaluateOnNewDocument', { source: patched }, mainSid)
  await send('Page.reload', { ignoreCache: true }, mainSid)
  await wait(4500)
  await ev(patched)
  result.simulation = {
    what: 'window.open 被换成：空 URL（占位页那一枪）返回 null，其余调用照旧转给真的 window.open',
    how: 'Page.addScriptToEvaluateOnNewDocument 装上 + 当场 Runtime.evaluate 再写一次，然后 Page.reload',
    patched: await ev("String(window.open).indexOf('args[0]') >= 0"),
    probe: await ev("(() => { const w = window.open('', '_blank'); return w === null ? 'window.open(空 URL) 现在返回 null' : '还是开了：' + String(w) })()"),
  }
}

const findJs = mode === 'external'
  ? "(() => { const norm = (s) => s.replace(/[ \\t\\n]+/g, '').trim(); const cards = [...document.querySelectorAll('[data-name=\"instance-card\"]')]; const card = cards.find((c) => /:3080/.test(c.getAttribute('data-instance') || '')); if (!card) return JSON.stringify({ found: false, cards: cards.map((c) => c.getAttribute('data-instance')) }); const b = [...card.querySelectorAll('button')].find((e) => norm(e.textContent) === '打开WebUI'); if (!b) return JSON.stringify({ found: false }); b.scrollIntoView({ block: 'center' }); const r = b.getBoundingClientRect(); return JSON.stringify({ found: true, x: r.x + r.width / 2, y: r.y + r.height / 2, label: b.textContent.trim(), card: card.getAttribute('data-instance') }) })()"
  : "(() => { const norm = (s) => s.replace(/[ \\t\\n]+/g, '').trim(); const cards = [...document.querySelectorAll('[data-name=\"instance-card\"]')]; const want = " + JSON.stringify(profileName) + "; const card = cards.find((c) => { const sub = c.querySelector('[data-name=\"sub-line\"]'); const stopped = sub && sub.getAttribute('data-status') === 'stopped'; const name = (c.getAttribute('data-instance') || '').replace(/:[0-9]+$/, ''); return stopped && name === want }); if (!card) return JSON.stringify({ found: false, cards: cards.map((c) => c.getAttribute('data-instance')) }); const b = [...card.querySelectorAll('button')].find((e) => norm(e.textContent) === '启动'); if (!b) return JSON.stringify({ found: false, reason: '卡上找不到「启动」' }); b.scrollIntoView({ block: 'center' }); const r = b.getBoundingClientRect(); return JSON.stringify({ found: true, x: r.x + r.width / 2, y: r.y + r.height / 2, label: b.textContent.trim(), card: card.getAttribute('data-instance') }) })()"

const findAndClick = async (js) => {
  const raw = await ev(js)
  let info = null
  try { info = typeof raw === 'string' ? JSON.parse(raw) : raw } catch (e) { info = { parseError: String(raw).slice(0, 120) } }
  if (!info || !info.found) return { clicked: false, info }
  await clickAt(info.x, info.y)
  return { clicked: true, info }
}

result.steps.click = await findAndClick(findJs)

// 每 400ms 采一次：标页的地址什么时候变、提示条什么时候出现。
// 只看最后一帧分不出「早就开了」和「兜底才开的」。
const timeline = []
const polls = mode === 'fail' ? 24 : 40
for (let i = 0; i < polls; i++) {
  await bringToFront()
  const n = await notice()
  const pages = await pagesViaHttp()
  timeline.push({ t: ms(), noticePresent: n.present, noticeHead: n.present ? String(n.text).slice(0, 100) : null, hasButton: !!n.hasButton, pages: pages.map((x) => ({ url: x.url, title: x.title })) })
  if (i === 2) result.shotAfter1s = await shot('after1s')
  await wait(400)
}
result.timeline = timeline
await bringToFront()
result.steps.final = { notice: await notice(), instances: await instances() }
result.shotConsole = await shot('console')

// 自动开的那个标页 / 兜底开出来的标页：读它自己的地址、收它自己的 frameNavigated
const newPageTargets = events.targetCreated.filter((t) => t.type === 'page' && t.targetId !== pageTarget.id)
const childOf = async (targetId) => {
  for (let i = 0; i < 20; i++) {
    if (attached[targetId]) return attached[targetId]
    await wait(400)
  }
  return null
}
const lastChildTarget = () => (newPageTargets.length ? newPageTargets[newPageTargets.length - 1].targetId : null)

if (mode === 'auto') {
  result.steps.pagesAfterAuto = await pagesViaHttp()
  const tid = lastChildTarget()
  result.steps.childTarget = tid
  const sid = tid ? await childOf(tid) : null
  result.steps.childSession = sid
  if (sid) {
    result.steps.childLocation = await evIn(sid, 'location.href')
    result.steps.childTitle = await evIn(sid, 'document.title')
    // 地址栏会被握手清掉（见 README），但**这一页最初是被哪条地址导航进来的**记在
    // Navigation Timing 里，replaceState 也改不掉它
    result.steps.childNavigationEntry = await evIn(sid, "(() => { const n = performance.getEntriesByType('navigation')[0]; return n ? JSON.stringify({ name: n.name, redirectCount: n.redirectCount, type: n.type }) : 'none' })()")
    for (let i = 0; i < 12; i++) {
      const ready = await evIn(sid, 'document.readyState')
      if (ready === 'complete' || ready === 'interactive') break
      await wait(700)
    }
    // 拍标页之前先把它拎到前面：后台的标页不产帧，截图会一直等下去
    await send('Page.bringToFront', {}, sid)
    await wait(500)
    result.shotAutoTab = await shotIn(sid, 'auto-tab')
  }
}

if (mode === 'blocked') {
  // 兜底入口：点提示条里那颗「打开 Web UI」（新手势），这一次一定开得成
  const beforeCount = events.targetCreated.length
  const b = await ev("(() => { const n = document.querySelector('[data-name=\"notice-open-web-ui\"]'); if (!n) return JSON.stringify({ found: false }); n.scrollIntoView({ block: 'center' }); const r = n.getBoundingClientRect(); return JSON.stringify({ found: true, x: r.x + r.width / 2, y: r.y + r.height / 2, label: n.textContent.trim() }) })()")
  let bi = null
  try { bi = typeof b === 'string' ? JSON.parse(b) : b } catch (e) { bi = { parseError: String(b).slice(0, 120) } }
  result.steps.fallbackClick = bi
  if (bi && bi.found) await clickAt(bi.x, bi.y)
  await wait(4000)
  result.steps.fallbackOpened = events.targetCreated.slice(beforeCount).filter((t) => t.type === 'page')
  result.steps.pagesAfterFallback = await pagesViaHttp()
  const tid = (result.steps.fallbackOpened[0] || {}).targetId
  const sid = tid ? await childOf(tid) : null
  if (sid) {
    result.steps.fallbackLocation = await evIn(sid, 'location.href')
    result.steps.fallbackNavigationEntry = await evIn(sid, "(() => { const n = performance.getEntriesByType('navigation')[0]; return n ? JSON.stringify({ name: n.name, redirectCount: n.redirectCount, type: n.type }) : 'none' })()")
    await send('Page.bringToFront', {}, sid)
    await wait(500)
    result.shotFallbackTab = await shotIn(sid, 'fallback-tab')
  }
  await bringToFront()
  result.steps.noticeAfterFallback = await notice()
  result.shotAfterFallback = await shot('console-after-fallback')
}

result.events = {
  targetCreated: events.targetCreated,
  targetDestroyed: events.targetDestroyed,
  targetInfoChanged: events.targetInfoChanged.slice(0, 60),
  attachedToTarget: events.attachedToTarget,
  childNavigation: childNav.slice(0, 40),
  childDocumentRequests: childRequests.slice(0, 40),
}
result.consoleIssues = mainIssues.slice(0, 10)          // 控制台页自己的
result.childConsoleIssues = childIssues.slice(0, 10)    // 标页（实例 Web UI）那边的

// 收尾：停掉本次新起的实例（只停新出现的端口，既有的一律不碰）
const cleanup = { stopped: [] }
if (mode === 'auto' || mode === 'blocked') {
  const now = (await instances()) || []
  for (const inst of now) {
    if (result.portsBefore.indexOf(inst.port) >= 0) continue
    const r = await ev("fetch('/api/local/action', { method: 'POST', headers: { 'content-type': 'application/json', 'X-DSH-Console': '1' }, body: JSON.stringify({ action: 'stop-instance', params: { port: " + inst.port + " } }) }).then((r) => r.text().then((t) => r.status + ' ' + t.slice(0, 160)))")
    cleanup.stopped.push({ port: inst.port, result: r })
  }
}
result.cleanup = cleanup

console.log(JSON.stringify(result, null, 1))
writeFileSync(join(outDir, tag + '-result.json'), JSON.stringify(result, null, 1))
chrome.kill()
process.exit(0)

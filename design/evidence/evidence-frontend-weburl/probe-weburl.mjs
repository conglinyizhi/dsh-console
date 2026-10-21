// 带令牌访问地址的端到端探针（第四轮）
//
//   node probe-weburl.mjs <baseUrl> <outPrefix> [injectPort injectUrl injectSource]
//
// 有 webUrl 的那张卡：菜单里该多出「复制带令牌的地址」；点卡上的「打开 Web UI」要开一个
//   新标签页，target URL 就是那条带令牌的地址；两条复制菜单都用 navigator.clipboard.readText()
//   把剪贴板读回来核对（不是看提示条自证）。
// 没有 webUrl 的那张卡（外部实例）：同一个按钮点下去**不该开任何标签页**，
//   提示条要说清为什么读不到令牌，并把裸地址给人。
//
// 给了 injectPort / injectUrl / injectSource 时，用 CDP 把 instances 响应里的 webUrl 字段
// 补上（后端这一轮的字段还没落到跑着的那个进程上时，用它来验前端这条通路）。
import { spawn } from 'node:child_process'
import { writeFileSync } from 'node:fs'

const CDP_PORT = 9300 + (process.pid % 600)
const [baseUrl, outPrefix = '/tmp/weburl', injectPort, injectUrl, injectSource] = process.argv.slice(2)
const inject = injectPort ? { port: Number(injectPort), url: injectUrl, source: injectSource } : null

const chrome = spawn('chromium', ['--headless', '--no-sandbox', '--disable-gpu', '--disable-extensions',
  '--hide-scrollbars', '--remote-debugging-port=' + CDP_PORT, '--user-data-dir=/tmp/chrome-weburl-' + process.pid,
  '--window-size=1280,900', 'about:blank'], { stdio: 'ignore' })

let page = null
for (let i = 0; i < 60 && !page; i++) {
  try { const l = await (await fetch('http://127.0.0.1:' + CDP_PORT + '/json')).json(); page = l.find((t) => t.type === 'page') } catch {}
  if (!page) await new Promise((r) => setTimeout(r, 250))
}
if (!page) { console.log('CDP 起不来'); process.exit(1) }

const ws = new WebSocket(page.webSocketDebuggerUrl)
let id = 0
const pending = new Map()
const targets = []
const tabNet = []
const netLog = []
let injected = 0
ws.onmessage = async (e) => {
  const m = JSON.parse(e.data)
  if (m.id && pending.has(m.id)) { pending.get(m.id)(m); pending.delete(m.id); return }
  if (m.method === 'Target.targetCreated' || m.method === 'Target.targetInfoChanged') {
    const t = m.params.targetInfo || m.params.target
    if (t && t.type === 'page' && t.url && t.url !== 'about:blank') targets.push({ url: t.url, how: m.method })
  }
  if (m.method === 'Network.responseReceived') {
    const r = m.params.response
    if (m.sessionId) {
      // 新标签页自己的文档响应：这条是「打开的那条地址不是 401」的直接证据
      if (m.params.type === 'Document') tabNet.push({ status: r.status, url: r.url, session: m.sessionId })
    } else if (r.url.includes('/api/local/')) netLog.push({ status: r.status, url: r.url.slice(0, 120) })
  }
  if (m.method === 'Target.attachedToTarget') {
    send('Network.enable', {}, m.params.sessionId).catch(() => {})
  }
  if (m.method === 'Fetch.requestPaused') {
    const p = m.params
    try {
      const bodyRes = await send('Fetch.getResponseBody', { requestId: p.requestId })
      let text = bodyRes.result.base64Encoded
        ? Buffer.from(bodyRes.result.body, 'base64').toString('utf8')
        : bodyRes.result.body
      if (p.request.url.includes('/api/local/instances')) {
        const doc = JSON.parse(text)
        for (const inst of (doc.data && doc.data.instances) || []) {
          if (inst.port === inject.port) { inst.webUrl = inject.url; inst.webUrlSource = inject.source }
          else { inst.webUrl = null; inst.webUrlSource = '外部实例：令牌在启动它的终端里，控制台可读的文件里没有' }
        }
        text = JSON.stringify(doc)
        injected++
      }
      await send('Fetch.fulfillRequest', {
        requestId: p.requestId, responseCode: p.responseStatusCode || 200,
        responseHeaders: (p.responseHeaders || []).filter((h) => !/^content-length$/i.test(h.name)),
        body: Buffer.from(text, 'utf8').toString('base64'),
      })
    } catch (err) {
      try { await send('Fetch.continueRequest', { requestId: p.requestId }) } catch (e) {}
    }
  }
}
await new Promise((r) => { ws.onopen = r })
const send = (method, params = {}, sessionId) => new Promise((res) => {
  const i = ++id
  pending.set(i, res)
  ws.send(JSON.stringify(sessionId ? { id: i, method, params, sessionId } : { id: i, method, params }))
})
const evalJs = async (expression) => {
  const out = await send('Runtime.evaluate', { expression, returnByValue: true, awaitPromise: true })
  if (out.result && out.result.exceptionDetails) return { EVAL_ERROR: JSON.stringify(out.result.exceptionDetails).slice(0, 300) }
  return out.result && out.result.result ? out.result.result.value : null
}
const wait = (ms) => new Promise((r) => setTimeout(r, ms))
const shot = async (file) => {
  const out = await send('Page.captureScreenshot', { format: 'png' })
  if (out.result && out.result.data) { writeFileSync(file, Buffer.from(out.result.data, 'base64')); return true }
  return false
}

await send('Page.enable'); await send('Network.enable'); await send('Runtime.enable')
// headless 里页面默认没被聚焦，剪贴板 API 会直接拒（Document is not focused）：打开焦点模拟。
// 另外点击一律走 Input.dispatchMouseEvent —— 那是真手势；element.click() 不算手势，
// window.open 会被弹窗拦截挡住，量出来的结论就不对了。
await send('Emulation.setFocusEmulationEnabled', { enabled: true }).catch(() => {})
await send('Target.setDiscoverTargets', { discover: true })
// 新标签页是另一个 target：挂上去，把它的文档响应抓下来（是不是 401 由它说了算）
await send('Target.setAutoAttach', { autoAttach: true, waitForDebuggerOnStart: false, flatten: true })
await send('Browser.grantPermissions', { origin: baseUrl, permissions: ['clipboardReadWrite', 'clipboardSanitizedWrite'] })
if (inject) await send('Fetch.enable', { patterns: [{ urlPattern: '*api/local/instances*', requestStage: 'Response' }] })
await send('Emulation.setDeviceMetricsOverride', { width: 1280, height: 900, deviceScaleFactor: 1, mobile: false })
await send('Page.navigate', { url: baseUrl })
await wait(5000)
if (inject) { try { await send('Fetch.disable') } catch (e) {} }

const report = { baseUrl, inject, injectedResponses: injected, steps: [] }

const inventory = () => evalJs(`(() => [...document.querySelectorAll('[data-name=instance-card]')].map((c) => {
  const sub = c.querySelector('[data-name=sub-line]')
  const btn = c.querySelector('[data-name=open-web-ui]')
  const fields = [...c.querySelectorAll('.dsh-field')].map((f) => ({
    label: f.querySelector('.dsh-field-label').textContent.trim(),
    value: f.querySelector('.dsh-field-value').textContent.trim(),
    title: f.querySelector('.dsh-field-value').getAttribute('title'),
  }))
  return { card: c.getAttribute('data-instance'), status: sub && sub.getAttribute('data-status'),
    openBtn: btn ? { text: btn.textContent.trim(), title: btn.getAttribute('title'), disabled: btn.disabled } : null,
    urlField: fields.find((f) => f.label === '访问地址') || null }
}))()`)

const menuItems = () => evalJs(`(() => { const menu = document.querySelector('[data-name=row-menu]');
  if (!menu) return { open: false }
  return { open: true, items: [...menu.querySelectorAll('.dsh-menu-item')].map((e) => ({
    text: e.textContent.trim(), action: e.getAttribute('data-action'), disabled: e.disabled,
    icon: e.querySelector('svg') ? e.querySelector('svg').getAttribute('width') : null })) } })()`)

// 按 data-instance 取那张卡：名字里带冒号，不用拼选择器
const inCard = (name, inner) =>
  '(() => { const c = [...document.querySelectorAll("[data-name=instance-card]")].find((x) => x.getAttribute("data-instance") === ' +
  JSON.stringify(name) + '); if (!c) return { found: false }; ' + inner + ' })()'

const closeMenu = () => evalJs('(() => { const o = document.querySelector("[data-name=menu-overlay]"); if (o) o.click(); return 1 })()')

// 真手势点击：算出元素中心，再用 Input 层按下抬起（element.click() 不产生 user activation）
const clickAtSelector = async (expr) => {
  const box = await evalJs('(() => { const el = ' + expr + '; if (!el) return null; const r = el.getBoundingClientRect(); if (r.width === 0) return null; return { x: r.x + r.width / 2, y: r.y + r.height / 2 } })()')
  if (!box || !box.x) return { clicked: false, why: '找不到元素或尺寸为 0' }
  await send('Input.dispatchMouseEvent', { type: 'mouseMoved', x: box.x, y: box.y, button: 'none', clickCount: 0 })
  await send('Input.dispatchMouseEvent', { type: 'mousePressed', x: box.x, y: box.y, button: 'left', clickCount: 1 })
  await send('Input.dispatchMouseEvent', { type: 'mouseReleased', x: box.x, y: box.y, button: 'left', clickCount: 1 })
  return { clicked: true, at: box }
}

const openMenu = async (card) => {
  await closeMenu()
  await wait(300)
  await evalJs(inCard(card, 'const t = c.querySelector(".dsh-actions button[id^=dsh-trigger-]"); if (t) t.click(); return { clicked: !!t }'))
  await wait(500)
  return await menuItems()
}
const clickItem = async (action) => {
  const sel = "document.querySelector(\"[data-name=row-menu] .dsh-menu-item[data-action='" + action + "']\")"
  const has = await evalJs('(() => { const menu = document.querySelector("[data-name=row-menu]"); if (!menu) return "菜单没开"; return ' + sel + ' ? "ok" : "没有这一项" })()')
  if (has !== 'ok') return { clicked: false, why: has }
  return await clickAtSelector(sel)
}
const clickOpenBtn = (card) => clickAtSelector(inCard(card, 'return c.querySelector("[data-name=open-web-ui]")'))
const notice = () => evalJs("(() => { const n = document.querySelector('[data-name=action-notice]'); return n ? { text: n.textContent.trim(), ok: n.getAttribute('data-ok') } : null })()")
const clipboard = () => evalJs("navigator.clipboard.readText().then((t) => t, (e) => 'READ_FAILED: ' + String((e && e.message) || e))")

report.cards = await inventory()
for (const c of report.cards) c.menu = await openMenu(c.card)
await closeMenu()
report.shotMenus = await shot(outPrefix + '-after-menus.png')

// ── 有 webUrl 的那张卡（inject 端口）还是外部卡，按有没有 webUrl 分 ──
const tokenCard = report.cards.find((c) => c.menu.open && c.menu.items.some((i) => i.action === 'copy-token-url'))
// 没有 webUrl 的那张卡：优先挑外部实例 3080（它的令牌在启动它的终端里，控制台读不到）
const noToken = report.cards.filter((c) => c.menu.open && !c.menu.items.some((i) => i.action === 'copy-token-url'))
const bareCard = noToken.find((c) => c.card === 'port:3080') || noToken.find((c) => c.status === 'running') || noToken[0]

if (tokenCard) {
  await openMenu(tokenCard.card)
  report.shotTokenMenu = await shot(outPrefix + '-menu-with-token.png')
  report.steps.push({ step: '有 webUrl 的卡：菜单项', card: tokenCard.card, menu: await menuItems() })
  await evalJs("navigator.clipboard.writeText('CLIPBOARD-SENTINEL')")
  report.steps.push({ step: '点「复制访问地址」', clicked: await clickItem('copy-url') })
  await wait(1200)
  report.steps.push({ step: '复制访问地址的回执', notice: await notice(), clipboard: await clipboard() })
  await openMenu(tokenCard.card)
  report.steps.push({ step: '点「复制带令牌的地址」', clicked: await clickItem('copy-token-url') })
  await wait(1200)
  report.steps.push({ step: '复制带令牌地址的回执', notice: await notice(), clipboard: await clipboard() })
  // 点按钮之前先把菜单收掉：菜单那层遮罩铺满视口，鼠标点下去会被它接走
  await closeMenu()
  await wait(400)
  // 挂钩 window.open：记下前端交给浏览器的那条地址原值（新标签的 target URL 会被重定向洗掉）
  await evalJs('(() => { window.__opened = []; if (!window.__openHooked) { const o = window.open; window.open = function (u, n, f) { window.__opened.push(String(u)); return o.call(window, u, n, f) }; window.__openHooked = true } return 1 })()')
  const before = targets.length
  report.steps.push({ step: '点卡上「打开 Web UI」', clicked: await clickOpenBtn(tokenCard.card) })
  await wait(3500)
  const fresh = targets.slice(before)
  // 前端交给浏览器的到底是哪条地址：页面里 window.open 收到的原值（点击前挂的钩子）
  const opened = await evalJs('window.__opened || []')
  let probe = null
  const first = (opened || [])[0]
  if (first) {
    try { const r = await fetch(first, { redirect: 'manual' }); probe = { url: first, status: r.status, location: r.headers.get('location') } } catch (e) { probe = { url: first, error: String(e.message) } }
  }
  // 新标签本身：挂上去问它一句「你那条文档响应的状态码是多少」（responseStatus 是浏览器自己记的）
  let tabState = null
  try {
    const list = await (await fetch('http://127.0.0.1:' + CDP_PORT + '/json')).json()
    const tab = list.find((t) => t.type === 'page' && t.url.includes(':8400'))
    if (tab) {
      const att = await send('Target.attachToTarget', { targetId: tab.id, flatten: true })
      const sid = att.result && att.result.sessionId
      if (sid) {
        const out = await send('Runtime.evaluate', {
          expression: '(() => { const n = performance.getEntriesByType("navigation")[0]; return JSON.stringify({ url: location.href, title: document.title, readyState: document.readyState, responseStatus: n ? n.responseStatus : null, type: n ? n.type : null }) })()',
          returnByValue: true, awaitPromise: true,
        }, sid)
        tabState = out.result && out.result.result ? out.result.result.value : JSON.stringify(out).slice(0, 200)
      }
    }
  } catch (e) { tabState = 'attach 失败：' + String(e.message) }
  report.steps.push({
    step: '打开后：新标签与提示', newTargets: fresh, windowOpenArgs: opened, notice: await notice(),
    openUrlProbe: probe, newTabDocumentResponses: tabNet.slice(), newTabState: tabState,
  })
  report.shotOpenToken = await shot(outPrefix + '-open-with-token.png')
}

if (bareCard) {
  await openMenu(bareCard.card)
  report.shotBareMenu = await shot(outPrefix + '-menu-without-token.png')
  report.steps.push({ step: '没有 webUrl 的卡：菜单项', card: bareCard.card, menu: await menuItems() })
  await closeMenu()
  await wait(300)
  const before2 = targets.length
  report.steps.push({ step: '点同一个「打开 Web UI」', clicked: await clickOpenBtn(bareCard.card) })
  await wait(2500)
  report.steps.push({ step: '打开后：新标签与提示', newTargets: targets.slice(before2), notice: await notice() })
  report.shotOpenBare = await shot(outPrefix + '-open-without-token.png')
  // 访问地址那一行的悬停：把鼠标移到那一行上再截图，title 也从 DOM 里读出来
  const box = await evalJs(inCard(bareCard.card, 'const f = [...c.querySelectorAll(".dsh-field")].find((x) => x.querySelector(".dsh-field-label").textContent.trim() === "访问地址"); const v = f.querySelector(".dsh-field-value"); const r = v.getBoundingClientRect(); return { x: r.x + r.width / 2, y: r.y + r.height / 2, title: v.getAttribute("title") }'))
  if (box && box.x) {
    await send('Input.dispatchMouseEvent', { type: 'mouseMoved', x: box.x, y: box.y })
    await wait(600)
  }
  report.steps.push({ step: '访问地址那一行的悬停', hover: box })
  report.shotFieldHover = await shot(outPrefix + '-field-hover.png')
}

report.allTargets = targets
writeFileSync(outPrefix + '.json', JSON.stringify(report, null, 1))
console.log(JSON.stringify(report, null, 1))
chrome.kill()
process.exit(0)

// 可见文案扫描：把「渲染后使用者真能读到的字」全部抓下来，在其中找内部术语。
//
//   node scan-visible-text.mjs <baseUrl> [outJson]
//
// 抓两样：
//   * 正文的文本节点（逐节点抓，来源能指到具体元素）
//   * 悬停与无障碍属性：title / aria-label / placeholder / alt
//     （hover 里的字使用者把鼠标放上去就能读到，同样算「可见文本」）
//
// 覆盖面：各路由各扫一趟；总览页额外点开一张卡的详情抽屉再扫一遍
//（抽屉不在 DOM 里的时候扫不到它）。
//
// 判据一条：这句话是给「用这个工具的人」看的，还是给「改这个工具的人」看的？
// 后者不该出现在使用者读得到的地方 —— 收进悬停或删掉。
import { spawn } from 'node:child_process'
import { writeFileSync } from 'node:fs'

const CDP_PORT = 9300 + (process.pid % 600)
const VW = Number(process.env.PROBE_VIEWPORT_W || 1440)
const VH = Number(process.env.PROBE_VIEWPORT_H || 950)
const base = (process.argv[2] || 'http://127.0.0.1:5390/').replace(/\/$/, '')
const outJson = process.argv[3] || ''

// 内部术语表：这些都是「给改工具的人看的」，一条都不该出现在使用者读得到的地方
const PATTERNS = [
  ['state= 这类取值写法', /state\s*=/i],
  ['stateReason', /stateReason/i],
  ['profileHealth', /profileHealth/i],
  ['成因 b / 成因 c（契约编号）', /成因/],
  // 只认**签名 id 与组件名**这类内部标识：包名（@deepseek-ai/dsh-experimental-*）
  // 是使用者真要读到的东西（缺的就是这些包），不算内部术语。
  ['签名 id / 组件名（内部标识）', /dsh-auth-401|dsh-boot-global|dsh-client-connection|dsh-console-(api|runner)/i],
  ['后端', /后端/],
  ['接口', /接口/],
  ['字段', /字段/],
  ['API 路径（POST/GET + 路径）', /(POST|GET|PUT|DELETE)\s*\/api\//i],
  ['裸 API 路径', /\/api\//],
  ['实现细节（登记文件 / 请求头）', /X-DSH-Console|runtime\.json|readOnly|read-only/i],
]

const chrome = spawn('chromium', ['--headless', '--no-sandbox', '--disable-gpu', '--disable-extensions', '--hide-scrollbars', '--remote-debugging-port=' + CDP_PORT, '--user-data-dir=/tmp/chrome-copy-scan-' + process.pid, '--window-size=' + VW + ',' + VH, 'about:blank'], { stdio: 'ignore' })
let page = null
for (let i = 0; i < 60 && !page; i++) { try { const l = await (await fetch('http://127.0.0.1:' + CDP_PORT + '/json')).json(); page = l.find((t) => t.type === 'page') } catch (e) {} if (!page) await new Promise((r) => setTimeout(r, 250)) }
if (!page) { console.error('拿不到 chromium 的调试目标'); process.exit(2) }
const ws = new WebSocket(page.webSocketDebuggerUrl); let id = 0; const pend = new Map()
ws.onmessage = (e) => { const m = JSON.parse(e.data); if (m.id && pend.has(m.id)) { pend.get(m.id)(m); pend.delete(m.id) } }
await new Promise((r) => { ws.onopen = r })
const send = (m, p) => new Promise((res) => { const i = ++id; pend.set(i, res); ws.send(JSON.stringify({ id: i, method: m, params: p || {} })) })
const ev = async (expression) => { const r = await send('Runtime.evaluate', { expression, returnByValue: true, awaitPromise: true }); return r.result && r.result.result ? r.result.result.value : undefined }
const wait = (ms) => new Promise((r) => setTimeout(r, ms))

const collectFn = function () {
  var items = []
  var clean = function (s) { return String(s).replace(/\s+/g, ' ').trim() }
  var desc = function (el) {
    if (!el) return { tag: '', name: '', cls: '' }
    return { tag: el.tagName.toLowerCase(), name: el.getAttribute('data-name') || '', cls: (el.getAttribute('class') || '').slice(0, 48) }
  }
  var walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT)
  var n
  while ((n = walker.nextNode())) {
    var t = clean(n.nodeValue)
    if (t) {
      var d = desc(n.parentElement)
      items.push({ kind: 'text', tag: d.tag, name: d.name, cls: d.cls, text: t })
    }
  }
  var all = document.querySelectorAll('*')
  var attrs = ['title', 'aria-label', 'placeholder', 'alt']
  for (var i = 0; i < all.length; i++) {
    for (var j = 0; j < attrs.length; j++) {
      var v = clean(all[i].getAttribute(attrs[j]) || '')
      if (v) {
        var d2 = desc(all[i])
        items.push({ kind: attrs[j], tag: d2.tag, name: d2.name, cls: d2.cls, text: v })
      }
    }
  }
  return items
}
const COLLECT = '(' + collectFn.toString() + ')()'
const OPEN_DRAWER = "(() => { const c = document.querySelector('[data-name^=\"instance-card\"]'); if (c) c.click(); return !!c })()"

const results = []
const scanRoute = async (label, path, extra) => {
  await send('Page.navigate', { url: base + path }); await wait(2800)
  if (extra) { await ev(extra); await wait(1000) }
  const raw = await ev(COLLECT)
  const items = typeof raw === 'string' ? JSON.parse(raw || '[]') : (raw || [])
  const hits = []
  for (const it of items) {
    for (const p of PATTERNS) {
      if (p[1].test(it.text)) hits.push({ why: p[0], kind: it.kind, name: it.name, tag: it.tag, text: it.text.slice(0, 240) })
    }
  }
  results.push({ label: label, path: path, itemCount: items.length, hits: hits })
}

await send('Page.enable'); await send('Runtime.enable')
await send('Emulation.setDeviceMetricsOverride', { width: VW, height: VH, deviceScaleFactor: 1, mobile: false })

await scanRoute('总览', '/', null)
await scanRoute('总览 + 详情抽屉', '/', OPEN_DRAWER)
await scanRoute('日志', '/logs', null)
await scanRoute('设置 · 实例', '/settings/instance', null)
await scanRoute('设置 · 进程', '/settings/process', null)
await scanRoute('设置 · 日志', '/settings/logs', null)
await scanRoute('设置 · 界面', '/settings/ui', null)
await scanRoute('设置 · 安全', '/settings/safety', null)
await scanRoute('回收站', '/trash', null)
await scanRoute('关于', '/about', null)

var total = 0
var uniq = new Set()
for (const r of results) {
  total += r.hits.length
  console.log('── ' + r.label + '  (' + r.path + '，抓到 ' + r.itemCount + ' 条可读文本，命中 ' + r.hits.length + ')')
  const seen = new Set()
  for (const h of r.hits) {
    const key = h.why + '|' + h.text
    uniq.add(key)
    if (seen.has(key)) continue
    seen.add(key)
    console.log('   [' + h.why + '] <' + h.tag + (h.name ? ' data-name=' + h.name : '') + '> ' + h.kind + ': ' + h.text)
  }
}
console.log()
console.log('命中合计：' + total + ' 条（去重后 ' + uniq.size + '）')
if (outJson) writeFileSync(outJson, JSON.stringify({ base: base, viewport: { VW: VW, VH: VH }, patterns: PATTERNS.map((p) => p[0]), results: results, total: total }, null, 1))
ws.close(); chrome.kill(); process.exit(0)

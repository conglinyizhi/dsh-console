// 「访问地址」那一行的悬停文案取证：title 是浏览器原生提示，headless 截图抓不到，
// 所以从 DOM 的 title 属性与无障碍树（Accessibility.getPartialAXTree）两头把它读出来 ——
// 无障碍树里那个节点的 description 就是浏览器准备给用户看的提示文案。
// node probe-title-ax.mjs <baseUrl> <outJson>
import { spawn } from 'node:child_process'
import { writeFileSync } from 'node:fs'

const CDP_PORT = 9300 + (process.pid % 600)
const [baseUrl, outJson = '/tmp/title-ax.json'] = process.argv.slice(2)
const chrome = spawn('chromium', ['--headless', '--no-sandbox', '--disable-gpu', '--disable-extensions',
  '--hide-scrollbars', '--remote-debugging-port=' + CDP_PORT, '--user-data-dir=/tmp/chrome-title-' + process.pid,
  '--window-size=1280,900', 'about:blank'], { stdio: 'ignore' })
let page = null
for (let i = 0; i < 60 && !page; i++) {
  try { const l = await (await fetch('http://127.0.0.1:' + CDP_PORT + '/json')).json(); page = l.find((t) => t.type === 'page') } catch {}
  if (!page) await new Promise((r) => setTimeout(r, 250))
}
const ws = new WebSocket(page.webSocketDebuggerUrl)
let id = 0
const pending = new Map()
ws.onmessage = (e) => { const m = JSON.parse(e.data); if (m.id && pending.has(m.id)) { pending.get(m.id)(m); pending.delete(m.id) } }
await new Promise((r) => { ws.onopen = r })
const send = (method, params = {}, sessionId) => new Promise((res) => { const i = ++id; pending.set(i, res); ws.send(JSON.stringify(sessionId ? { id: i, method, params, sessionId } : { id: i, method, params })) })
const ev = async (expression) => {
  const r = await send('Runtime.evaluate', { expression, returnByValue: true, awaitPromise: true })
  return r.result && r.result.result ? r.result.result.value : null
}
const wait = (ms) => new Promise((r) => setTimeout(r, ms))
await send('Page.enable'); await send('Runtime.enable'); await send('DOM.enable'); await send('Accessibility.enable')
await send('Emulation.setDeviceMetricsOverride', { width: 1280, height: 900, deviceScaleFactor: 1, mobile: false })
await send('Page.navigate', { url: baseUrl })
// 等到卡片真的画出来再取：首屏要等几个只读接口回来
for (let i = 0; i < 40; i++) {
  const n = await ev('document.querySelectorAll("[data-name=instance-card]").length')
  if (n > 0) break
  await wait(500)
}
await wait(800)

const out = { baseUrl, fields: [] }
const cards = await ev('[...document.querySelectorAll("[data-name=instance-card]")].map((c) => c.getAttribute("data-instance"))')
const doc = await send('DOM.getDocument', { depth: -1 })
for (const card of cards || []) {
  // 「访问地址」是字段区第 3 行（DSH 版本 / Profile / 访问地址 / DSH_HOME / 插件数量）
  const sel = '[data-instance="' + card + '"] .dsh-field:nth-child(3) .dsh-field-value'
  const q = await send('DOM.querySelector', { nodeId: doc.result.root.nodeId, selector: sel })
  const labels = await ev('(() => { const c = [...document.querySelectorAll("[data-name=instance-card]")].find((x) => x.getAttribute("data-instance") === ' + JSON.stringify(card) + '); if (!c) return null; return [...c.querySelectorAll(".dsh-field")].map((f) => ({ label: f.querySelector(".dsh-field-label").textContent.trim(), value: f.querySelector(".dsh-field-value").textContent.trim(), title: f.querySelector(".dsh-field-value").getAttribute("title") })) })()')
  const entry = { card, fields: labels }
  // 访问地址那一行单独取一次无障碍树（第 3 个字段是「访问地址」）
  const urlNodeId = q.result ? q.result.nodeId : 0
  if (urlNodeId) {
    const ax = await send('Accessibility.getPartialAXTree', { nodeId: urlNodeId, fetchRelatives: false })
    const node = ax.result && ax.result.nodes && ax.result.nodes[0]
    entry.axNode = node ? { role: node.role && node.role.value, name: node.name && node.name.value, description: node.description && node.description.value } : null
  }
  out.fields.push(entry)
}
writeFileSync(outJson, JSON.stringify(out, null, 1))
console.log(JSON.stringify(out, null, 1))
chrome.kill()
process.exit(0)

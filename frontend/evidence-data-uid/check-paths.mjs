// 算法对照：拿「语义路径」直接算出 uid，再去真实页面上读那个元素的 data-uid，两边必须一致。
//
//   node check-paths.mjs <baseUrl> [outFile]
//
// 页面上那串值来自 MoonBit 侧的 uid()（FNV-1a 64 位 → base36 取 8 位）；
// 这里用 JS **重写**同一套算法，路径照 uid.mbt 的口径手写。三列一致（路径算出来的 /
// 页面上真的 / 语义上该是这一个），才说明 uid 是由语义路径算出来的，不是贴上去的常量。
import { spawn } from 'node:child_process'
import { writeFileSync } from 'node:fs'

const CDP_PORT = 9300 + (process.pid % 600)
const [baseUrl, outFile = 'uid-crosscheck.md'] = process.argv.slice(2)
if (!baseUrl) { console.log('用法: node check-paths.mjs <baseUrl> [outFile]'); process.exit(1) }

// ── 与 uid.mbt 同一套算法 ───────────────────────────────────
const uid = (parts) => {
  const M = (1n << 64n) - 1n
  const P = 0x100000001b3n
  let h = 0xcbf29ce484222325n
  for (const part of parts) {
    const bytes = Buffer.from(part, 'utf8')
    h = (h ^ BigInt(bytes.length)) & M
    h = (h * P) & M
    for (const b of bytes) { h = (h ^ BigInt(b)) & M; h = (h * P) & M }
  }
  let rest = h % 2821109907456n
  const digits = '0123456789abcdefghijklmnopqrstuvwxyz'
  let out = ''
  for (let i = 0; i < 8; i++) { out = digits[Number(rest % 36n)] + out; rest /= 36n }
  return out
}

const chrome = spawn('chromium', ['--headless', '--no-sandbox', '--disable-gpu', '--disable-extensions',
  '--hide-scrollbars', '--remote-debugging-port=' + CDP_PORT, '--user-data-dir=/tmp/chrome-path-' + process.pid,
  '--window-size=1400,1000', 'about:blank'], { stdio: 'ignore' })
let page = null
for (let i = 0; i < 60 && !page; i++) {
  try { page = (await (await fetch('http://127.0.0.1:' + CDP_PORT + '/json')).json()).find((t) => t.type === 'page') } catch {}
  if (!page) await new Promise((r) => setTimeout(r, 250))
}
const ws = new WebSocket(page.webSocketDebuggerUrl)
let id = 0
const pending = new Map()
ws.onmessage = (e) => { const m = JSON.parse(e.data); if (m.id && pending.has(m.id)) { pending.get(m.id)(m); pending.delete(m.id) } }
await new Promise((r) => { ws.onopen = r })
const send = (method, params = {}) => new Promise((res) => { const i = ++id; pending.set(i, res); ws.send(JSON.stringify({ id: i, method, params })) })
const sleep = (ms) => new Promise((r) => setTimeout(r, ms))
const ev = async (expression) => (await send('Runtime.evaluate', { expression, returnByValue: true, awaitPromise: true })).result?.result?.value
const clickAndWait = async (clickExpr, waitSel) => {
  await ev(clickExpr)
  for (let i = 0; i < 80; i++) { if (await ev('!!document.querySelector(' + JSON.stringify(waitSel) + ')')) break; await sleep(250) }
  await sleep(900)
}
const oneUid = (sel) => ev('(() => { const el = document.querySelector(' + JSON.stringify(sel) + '); return el ? el.getAttribute("data-uid") : null })()')

await send('Runtime.enable'); await send('Page.enable')
await send('Emulation.setDeviceMetricsOverride', { width: 1400, height: 1000, deviceScaleFactor: 1, mobile: false })
await send('Page.navigate', { url: baseUrl })
for (let i = 0; i < 80; i++) { if (await ev('!!document.querySelector(' + JSON.stringify('[data-name="overview-page"]') + ')')) break; await sleep(250) }
await sleep(800)

// 行 id 的口径见 state.mbt：运行中的卡是 port:<端口>，已停止 / 归档卡是 profile:<名> / archived:<名>。
// 卡片名从 DOM 里读（挑第一张已停止的卡）—— 哪只 profile 在跑会变，路径规则不变。
const cardName = await ev('(() => { const c = [...document.querySelectorAll(' + JSON.stringify('[data-name="instance-card"]') + ')].find((x) => x.querySelector(' + JSON.stringify('[data-name="sub-line"][data-status="stopped"]') + ')); return c ? c.getAttribute("data-instance") : "" })()')
if (!cardName) { console.log('没有已停止的卡，复核跑不下去'); chrome.kill(); process.exit(1) }
const CARD = '[data-instance="' + cardName + '"]'
const CARD_PARTS = ['overview', 'card', 'profile:' + cardName]
const resolve = (parts) => typeof parts === 'string' ? CARD_PARTS.concat(parts.split('|').slice(1)) : parts

const CASES = [
  ['实例总览', '页面', '[data-name="overview-page"]', ['overview', 'page']],
  ['实例总览', '侧栏导航项「设置」', '[data-name="nav-settings"]', ['shell', 'nav', 'settings']],
  ['实例总览', '「新建实例」按钮', '[data-name="new-instance"]', ['overview', 'new-instance']],
  ['实例总览', '运行中分组标题', '[data-name="section-title"]', ['overview', 'section', 'running', 'title']],
  ['实例总览', '页眉来源徽标', '[data-name="source-badge"]', ['overview', 'head', 'source-badge']],
  ['实例总览', '运行中分组来源徽标', 'HEAD:当前运行的实例', ['overview', 'section', 'running', 'source-badge']],
  ['实例总览', '已停止分组来源徽标', 'HEAD:已停止的实例', ['overview', 'section', 'stopped', 'source-badge']],
  ['实例总览', '已停止的那张卡（' + cardName + '）', CARD, CARD_PARTS],
  ['实例总览', '该卡的「重启」按钮', CARD + ' [data-name="restart"]', '@|restart'],
  ['实例总览', '该卡的「⋯」触发按钮', CARD + ' [data-name="menu-trigger"]', '@|menu-trigger'],
  ['实例总览', '该卡的字段「最近改动」', CARD + ' [data-field="mtime"]', '@|field|mtime'],
  ['实例总览', '该卡字段「最近改动」的值', CARD + ' [data-field="mtime"] [data-name="field-value"]', '@|field|mtime|value'],
  ['日志页', '页面', '[data-name="logs-page"]', ['logs', 'page']],
  ['日志页', '来源下拉', '[data-name="log-source"]', ['logs', 'source-select']],
  ['日志页', '来源项「宿主日志」', '[data-name="log-source-option"][value="host"]', ['logs', 'source-option', 'host']],
  ['设置页', '页面', '[data-name="settings-page"]', ['settings', 'page']],
  ['设置页', '左索引项「界面」', '[data-name="settings-tab"][data-group="ui"]', ['settings', 'tab', 'ui']],
  ['设置页', '条目「签名探测超时」', '[data-name="setting-row"][data-setting="probe.timeoutMs"]', ['settings', 'row', 'probe.timeoutMs']],
  ['设置页', '该条目的数字输入框', '[data-name="setting-input"][id="dsh-setting-probe.timeoutMs"]', ['settings', 'row', 'probe.timeoutMs', 'input']],
]

const readCase = (sel) => {
  if (sel.startsWith('HEAD:')) {
    const title = sel.slice(5)
    return ev('(() => { const h = [...document.querySelectorAll(".dsh-section-head")].find((x) => x.textContent.includes(' + JSON.stringify(title) + ')); const b = h && h.querySelector(' + JSON.stringify('[data-name="source-badge"]') + '); return b ? b.getAttribute("data-uid") : null })()')
  }
  return oneUid(sel)
}

const rows = []
let stage = 'overview'
for (const [pageName, label, sel, rawParts] of CASES) {
  if (pageName === '日志页' && stage === 'overview') {
    await clickAndWait('document.querySelector(' + JSON.stringify('[data-name="nav-logs"]') + ').click()', '[data-name="logs-page"]')
    stage = 'logs'
  }
  if (pageName === '设置页' && stage !== 'settings') {
    await clickAndWait('document.querySelector(' + JSON.stringify('[data-name="nav-settings"]') + ').click()', '[data-name="settings-page"]')
    stage = 'settings'
  }
  const parts = resolve(rawParts)
  const domUid = await readCase(sel)
  const computed = uid(parts)
  rows.push({ page: pageName, label, path: parts.join(' | '), computed, domUid, ok: domUid === computed })
}

console.log('两张分组来源徽标（过去是同一路径、同一个 data-name 分不开的那一对）：')
for (const r of rows.filter((x) => x.label.includes('分组来源徽标'))) {
  console.log('  ' + r.label + '  ' + r.path + '  →  ' + r.domUid)
}

const lines = []
lines.push('# 语义路径 → uid 对照（活页面复核）')
lines.push('')
lines.push('路径按 uid.mbt 的口径手写；「算出来的 uid」由 JS 侧独立重写的同一套算法算出；')
lines.push('「页面上的 data-uid」是页面上那个元素实际带的值。三列一致才算过。')
lines.push('')
lines.push('| 页面 | 元素 | 语义路径 | 算出来的 uid | 页面上的 data-uid | 一致 |')
lines.push('| --- | --- | --- | --- | --- | --- |')
for (const r of rows) {
  lines.push('| ' + r.page + ' | ' + r.label + ' | ' + r.path + ' | ' + r.computed + ' | ' + (r.domUid || '(没找到)') + ' | ' + (r.ok ? '✓' : '✗') + ' |')
}
const bad = rows.filter((r) => !r.ok)
lines.push('')
lines.push('共 ' + rows.length + ' 条，不一致 ' + bad.length + ' 条。')
writeFileSync(outFile, lines.join(String.fromCharCode(10)) + String.fromCharCode(10))
console.log('共 ' + rows.length + ' 条，不一致 ' + bad.length + ' 条 → ' + outFile)
for (const b of bad) console.log('  ✗ ' + b.label + ' ' + b.path + ' 算 ' + b.computed + ' / 页面 ' + b.domUid)
chrome.kill()
process.exit(0)

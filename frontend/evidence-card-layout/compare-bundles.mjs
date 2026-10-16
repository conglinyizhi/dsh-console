// 「没有备注的条目与改动前逐像素一致」的实测：同一份数据、同一条 URL、同一个视口，
// 只把 /assets/app.js 与 /assets/app.css 换掉（CDP Fetch 在请求阶段顶替响应），量两遍再逐项相减。
//   node compare-bundles.mjs <baseUrl> <改前 dist 目录> <改后 dist 目录> [输出前缀]
// 改前那一份从 git 里导出并现编：git archive <上个提交> frontend | tar -x -C /tmp/dsh-before
// 顶替响应的是**编译产物**，不是源码 —— 两边跑的是真页面、真读数（不注入 fixture）。
import { spawn } from 'node:child_process'
import { writeFileSync, readFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const here = dirname(fileURLToPath(import.meta.url))
const base = (process.argv[2] || 'http://127.0.0.1:5390').replace(/\/$/, '')
const beforeDir = process.argv[3]
const afterDir = process.argv[4]
const prefix = process.argv[5] || 'bundle'
const MEASURE = readFileSync(join(here, 'measure.js'), 'utf8')
const CDP_PORT = 9610 + (process.pid % 80)

const bundles = {
  before: { js: readFileSync(join(beforeDir, 'app.js')).toString('base64'), css: readFileSync(join(beforeDir, 'app.css')).toString('base64') },
  after: { js: readFileSync(join(afterDir, 'app.js')).toString('base64'), css: readFileSync(join(afterDir, 'app.css')).toString('base64') },
}
let which = 'after'

const sleep = (ms) => new Promise((r) => setTimeout(r, ms))
const chrome = spawn('chromium', ['--headless', '--no-sandbox', '--disable-gpu', '--disable-extensions',
  '--hide-scrollbars', '--remote-debugging-port=' + CDP_PORT, '--user-data-dir=/tmp/chrome-bundle-' + process.pid,
  '--window-size=1280,900', '--noerrdialogs', '--no-first-run', '--ozone-platform=headless', 'about:blank'], { stdio: 'ignore' })

let page = null
for (let i = 0; i < 60 && !page; i++) {
  try { const l = await (await fetch('http://127.0.0.1:' + CDP_PORT + '/json')).json(); page = l.find((t) => t.type === 'page') } catch {}
  if (!page) await sleep(250)
}
if (!page) { console.log('chrome 没起来'); process.exit(1) }

const ws = new WebSocket(page.webSocketDebuggerUrl)
let id = 0
const pending = new Map()
const consoleIssues = []
const send = (method, params = {}) => new Promise((res) => { const i = ++id; pending.set(i, res); ws.send(JSON.stringify({ id: i, method, params })) })
ws.onmessage = (e) => {
  const m = JSON.parse(e.data)
  if (m.method === 'Runtime.consoleAPICalled' && ['error', 'warning'].includes(m.params && m.params.type)) {
    consoleIssues.push(m.params.type + ': ' + (m.params.args || []).map((a) => a.value || a.description || '').join(' ').slice(0, 160))
  }
  if (m.method === 'Fetch.requestPaused') {
    const p = m.params
    const url = p.request.url
    const kind = url.includes('app.css') ? 'css' : (url.includes('app.js') ? 'js' : null)
    if (!kind) { send('Fetch.continueRequest', { requestId: p.requestId }); return }
    send('Fetch.fulfillRequest', {
      requestId: p.requestId,
      responseCode: 200,
      responseHeaders: [{ name: 'content-type', value: kind === 'css' ? 'text/css; charset=utf-8' : 'application/javascript; charset=utf-8' }],
      body: bundles[which][kind],
    })
    return
  }
  if (m.id && pending.has(m.id)) { pending.get(m.id)(m); pending.delete(m.id) }
}
await new Promise((r) => { ws.onopen = r })
await send('Page.enable')
await send('Runtime.enable')
await send('Fetch.enable', { patterns: [
  { urlPattern: '*/assets/app.js*', requestStage: 'Request' },
  { urlPattern: '*/assets/app.css*', requestStage: 'Request' },
] })

const ev = async (expr) => {
  const r = await send('Runtime.evaluate', { expression: expr, returnByValue: true, awaitPromise: true })
  if (r.result && r.result.exceptionDetails) throw new Error('eval 出错: ' + JSON.stringify(r.result.exceptionDetails).slice(0, 300))
  return r.result && r.result.result ? r.result.result.value : undefined
}
const evJson = async (expr) => JSON.parse(await ev(expr))
const setViewport = (w, h) => send('Emulation.setDeviceMetricsOverride', { width: w, height: h, deviceScaleFactor: 1, mobile: false })
const shot = async (name) => {
  const s = await send('Page.captureScreenshot', { format: 'png' })
  writeFileSync(name, Buffer.from(s.result.data, 'base64'))
}

const out = { base, bundles: { before: beforeDir, after: afterDir }, runs: {}, consoleIssues }
const passes = ['before', 'after']
for (const pass of passes) {
  which = pass
  out.runs[pass] = {}
  for (const v of [{ w: 1280, h: 900, tag: '1280' }, { w: 360, h: 900, tag: '360' }]) {
    await setViewport(v.w, v.h)
    await send('Page.navigate', { url: base + '/' })
    await sleep(5200)
    // 打一个只有这一遍才有的记号：确认页面跑的确实是这一份产物（不是缓存里的另一份）
    out.runs[pass][v.tag] = await evJson(MEASURE)
    await shot(prefix + '-' + pass + '-' + v.tag + '.png')
  }
}

writeFileSync(prefix + '.json', JSON.stringify(out, null, 1))

// ── 逐项相减 ──
const PARTS = ['card', 'content', 'head', 'tile', 'dot', 'name', 'port', 'note']
const diffs = []
for (const tag of ['1280', '360']) {
  const B = out.runs.before[tag], A = out.runs.after[tag]
  console.log('=== 视口 ' + tag + '  改前卡片 ' + B.cards.length + ' 张 / 改后 ' + A.cards.length + ' 张 ===')
  for (const a of A.cards) {
    const b = B.cards.find((x) => x.id === a.id)
    if (!b) { console.log('  ' + a.id + '：改前没有这一张，跳过'); continue }
    const row = { id: a.id, case: a.case, status: a.status, deltas: {}, nodes: {} }
    for (const p of PARTS) {
      const pa = a[p], pb = b[p]
      if (!pa && !pb) continue
      if (!pa || !pb) { row.deltas[p] = pa ? '改前没有' : '改后没有'; continue }
      const d = {}
      for (const k of ['x', 'y', 'w', 'h', 'right', 'bottom']) {
        if (typeof pa[k] === 'number' && typeof pb[k] === 'number') {
          const dv = +(pa[k] - pb[k]).toFixed(1)
          if (dv !== 0) d[k] = dv
        }
      }
      row.deltas[p] = Object.keys(d).length ? d : '同'
    }
    row.deltas.dotFromTile = JSON.stringify(a.deltas.dotFromTile) === JSON.stringify(b.deltas.dotFromTile) ? '同' : [b.deltas.dotFromTile, a.deltas.dotFromTile]
    row.nodes = { before: b.nodes, after: a.nodes }
    row.textBefore = b.text
    row.textAfter = a.text
    diffs.push(row)
    const changed = JSON.stringify(row.deltas).replace(/"同",?/g, '')
    const only = Object.entries(row.deltas).filter(([, v]) => v !== '同')
    console.log('  ' + a.id + ' [' + a.case + '] ' + (only.length ? '有差异 → ' + JSON.stringify(only) : '逐项相同'))
    if (b.text !== a.text) console.log('      文本 改前=' + JSON.stringify(b.text) + ' 改后=' + JSON.stringify(a.text))
    const nb = b.nodes, na = a.nodes
    if (nb.port !== na.port || nb.noteTag !== na.noteTag) console.log('      节点 改前=' + JSON.stringify(nb) + ' 改后=' + JSON.stringify(na))
  }
}
writeFileSync(prefix + '-diff.json', JSON.stringify(diffs, null, 1))
console.log('')
console.log('控制台问题: ' + (consoleIssues.length ? consoleIssues.join(' | ') : '无'))
ws.close()
try { chrome.kill() } catch (e) {}
process.exit(0)
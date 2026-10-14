// 日志页不变量探针：node probe-logs.mjs <baseUrl> <outJson> [侧栏文字]
import { spawn } from 'node:child_process'
import { writeFileSync, readFileSync } from 'node:fs'
const [baseUrl, outJson, navLabel = '日志', profileArg = 'vue'] = process.argv.slice(2)

// 选择器映射：内置 vue，或一份 JSON 文件（换栈后的新前端用这个）
const BUILTIN = {
  vue: { box: '.log-box', line: '.log-line', lvError: '.lv-error', lvWarn: '.lv-warn', meta: '.meta', select: 'select' },
}
let SEL = BUILTIN[profileArg]
if (!SEL) {
  try { SEL = JSON.parse(readFileSync(profileArg, 'utf8')); console.log('用外部选择器映射: ' + profileArg) } catch (e) { console.log('读不到选择器映射: ' + profileArg); process.exit(1) }
}

const chrome = spawn('chromium', ['--headless', '--no-sandbox', '--disable-gpu', '--disable-extensions',
  '--hide-scrollbars', '--remote-debugging-port=9336', '--user-data-dir=/tmp/chrome-logs',
  '--window-size=1280,900', 'about:blank'], { stdio: 'ignore' })
let page = null
for (let i = 0; i < 40 && !page; i++) {
  try { const l = await (await fetch('http://127.0.0.1:9336/json')).json(); page = l.find((t) => t.type === 'page') } catch {}
  if (!page) await new Promise((r) => setTimeout(r, 250))
}
const ws = new WebSocket(page.webSocketDebuggerUrl)
let id = 0
const pending = new Map()
ws.onmessage = (e) => { const m = JSON.parse(e.data); if (m.id && pending.has(m.id)) { pending.get(m.id)(m); pending.delete(m.id) } }
await new Promise((r) => { ws.onopen = r })
const send = (method, params = {}) => new Promise((res) => { const i = ++id; pending.set(i, res); ws.send(JSON.stringify({ id: i, method, params })) })
await send('Page.enable')
await send('Emulation.setDeviceMetricsOverride', { width: 1280, height: 900, deviceScaleFactor: 1, mobile: false })
await send('Page.navigate', { url: baseUrl })
await new Promise((r) => setTimeout(r, 4000))

// 切到日志页（状态切页，点侧栏）
await send('Runtime.evaluate', { expression: `(() => {
  const el = [...document.querySelectorAll('.nav-item, nav *, aside *')].find((e) => e.children.length === 0 && e.textContent.trim() === ${JSON.stringify(navLabel)})
  if (el) { el.click(); return 'clicked' }
  return 'not-found'
})()`, returnByValue: true })
await new Promise((r) => setTimeout(r, 3000))

const expr = `(() => {
  const S = ${JSON.stringify(SEL)}
  const R = (el) => { const r = el.getBoundingClientRect(); return { x: +r.x.toFixed(1), y: +r.y.toFixed(1), w: +r.width.toFixed(1), h: +r.height.toFixed(1), right: +r.right.toFixed(1), bottom: +r.bottom.toFixed(1) } }
  const box = document.querySelector(S.box)
  const lines = [...document.querySelectorAll(S.line)]
  const lv = (sel) => { const el = document.querySelector(sel); return el ? getComputedStyle(el).color : null }
  const sel = document.querySelector(S.select)
  const de = document.documentElement
  return JSON.stringify({
    overflow: { scrollW: de.scrollWidth, clientW: de.clientWidth, overflowX: de.scrollWidth > de.clientWidth },
    title: document.querySelector('h1')?.textContent.trim(),
    box: box ? {
      rect: R(box),
      scrollHeight: box.scrollHeight, clientHeight: box.clientHeight,
      scrollTop: box.scrollTop, maxScrollTop: box.scrollHeight - box.clientHeight,
      atBottom: Math.abs(box.scrollTop - (box.scrollHeight - box.clientHeight)) <= 2,
      scrollWidth: box.scrollWidth, clientWidth: box.clientWidth,
      horizontalScroll: box.scrollWidth > box.clientWidth,
      whiteSpace: getComputedStyle(box).whiteSpace,
      fontFamily: getComputedStyle(box).fontFamily.slice(0, 30),
      fontSize: getComputedStyle(box).fontSize,
    } : null,
    lineCount: lines.length,
    firstLine: lines[0]?.textContent.trim().slice(0, 70) ?? null,
    lastLine: lines.slice(-1)[0]?.textContent.trim().slice(0, 70) ?? null,
    levels: {
      error: document.querySelectorAll(S.lvError).length,
      warn: document.querySelectorAll(S.lvWarn).length,
      errorColor: lv(S.lvError), warnColor: lv(S.lvWarn),
    },
    select: sel ? {
      value: sel.value,
      options: [...sel.options].map((o) => ({ text: o.textContent.trim(), value: o.value, disabled: o.disabled })),
    } : null,
    meta: document.querySelector(S.meta)?.textContent.trim() ?? null,
  })
})()`
const out = await send('Runtime.evaluate', { expression: expr, returnByValue: true })
const data = JSON.parse(out.result?.result?.value ?? '{}')
writeFileSync(outJson, JSON.stringify(data, null, 1))
console.log(JSON.stringify({ overflow: data.overflow, box: data.box && { scrollHeight: data.box.scrollHeight, clientHeight: data.box.clientHeight, atBottom: data.box.atBottom, horizontalScroll: data.box.horizontalScroll, whiteSpace: data.box.whiteSpace }, lineCount: data.lineCount, levels: data.levels, options: data.select?.options?.length, meta: data.meta?.slice(0, 90) }, null, 1))
chrome.kill()
process.exit(0)
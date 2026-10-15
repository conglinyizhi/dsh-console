// 出一张卡片的 DOM 片段：能看到 data-name 与 data-uid。
//
//   node dump-card-dom.mjs <baseUrl> <outDir>
//
// 产物：
//   card-dom.txt   片段原文（缩进过的）
//   card-dom.html  把片段渲染成一张可读的「图页」
//   card-dom.png   上面那张图页的截图（这就是「出图」）
//   card.png       卡片本体的截图（对照用）
//
// 片段里 svg 内部折成 <svg …/>：图标那几十个 path 跟 data-name / data-uid 没关系，
// 留着会把要看的东西淹掉。
import { spawn } from 'node:child_process'
import { writeFileSync, mkdirSync } from 'node:fs'

const CDP_PORT = 9300 + (process.pid % 600)
const [baseUrl, outDir = '.'] = process.argv.slice(2)
if (!baseUrl) { console.log('用法: node dump-card-dom.mjs <baseUrl> [outDir]'); process.exit(1) }
mkdirSync(outDir, { recursive: true })

const chrome = spawn('chromium', ['--headless', '--no-sandbox', '--disable-gpu', '--disable-extensions',
  '--hide-scrollbars', '--remote-debugging-port=' + CDP_PORT, '--user-data-dir=/tmp/chrome-dom-' + process.pid,
  '--window-size=1400,1000', 'about:blank'], { stdio: 'ignore' })

let page = null
for (let i = 0; i < 60 && !page; i++) {
  try {
    const list = await (await fetch('http://127.0.0.1:' + CDP_PORT + '/json')).json()
    page = list.find((t) => t.type === 'page')
  } catch {}
  if (!page) await new Promise((r) => setTimeout(r, 250))
}
const ws = new WebSocket(page.webSocketDebuggerUrl)
let id = 0
const pending = new Map()
ws.onmessage = (e) => {
  const m = JSON.parse(e.data)
  if (m.id && pending.has(m.id)) { pending.get(m.id)(m); pending.delete(m.id) }
}
await new Promise((r) => { ws.onopen = r })
const send = (method, params = {}) => new Promise((res) => { const i = ++id; pending.set(i, res); ws.send(JSON.stringify({ id: i, method, params })) })
const sleep = (ms) => new Promise((r) => setTimeout(r, ms))
const ev = async (expression) => {
  const r = await send('Runtime.evaluate', { expression, returnByValue: true, awaitPromise: true })
  return r.result?.result?.value
}

await send('Runtime.enable'); await send('Page.enable')
await send('Emulation.setDeviceMetricsOverride', { width: 1400, height: 1000, deviceScaleFactor: 1, mobile: false })
await send('Page.navigate', { url: baseUrl })
for (let i = 0; i < 60; i++) {
  if (await ev("!!document.querySelector('[data-name=\"instance-card\"]')")) break
  await sleep(300)
}
await sleep(800)

const html = await ev(`(() => {
  const card = [...document.querySelectorAll('[data-name="instance-card"]')]
    .find((c) => c.querySelector('[data-name="sub-line"][data-status="stopped"]'))
    || document.querySelector('[data-name="instance-card"]')
  return card ? card.outerHTML : ''
})()`)
if (!html) { console.log('没找到卡片'); chrome.kill(); process.exit(1) }

// ── 缩进 ────────────────────────────────────────────────────
const VOID = new Set(['input', 'br', 'img', 'hr', 'meta', 'link', 'path', 'circle', 'rect', 'line', 'polyline', 'polygon', 'use', 'stop'])
const pretty = (src) => {
  const flat = src.replace(/<svg\b[\s\S]*?<\/svg>/g, '<svg …/>').replace(/>\s+</g, '><')
  const tokens = flat.match(/<[^>]+>|[^<]+/g) || []
  const out = []
  let depth = 0
  for (const raw of tokens) {
    const t = raw.trim()
    if (!t) continue
    if (t.startsWith('</')) { depth = Math.max(0, depth - 1); out.push('  '.repeat(depth) + t) }
    else if (t.startsWith('<')) {
      const name = (t.match(/^<([a-zA-Z0-9-]+)/) || [])[1] || ''
      // 注释（<!--[--> 是 rabbita 的占位）不是元素：不占层级，否则缩进会一路漂
      const selfClose = t.endsWith('/>') || VOID.has(name) || t.startsWith('<!')
      out.push('  '.repeat(depth) + t)
      if (!selfClose) depth++
    } else out.push('  '.repeat(depth) + t)
  }
  return out.join('\n')
}
const prettyHtml = pretty(html)
writeFileSync(outDir + '/card-dom.txt', prettyHtml + '\n')
console.log('片段行数: ' + prettyHtml.split('\n').length)
console.log('data-name 处数: ' + (prettyHtml.match(/data-name=/g) || []).length)
console.log('data-uid  处数: ' + (prettyHtml.match(/data-uid=/g) || []).length)

// 卡片本体截图
const box = JSON.parse(await ev(`(() => {
  const card = [...document.querySelectorAll('[data-name="instance-card"]')]
    .find((c) => c.querySelector('[data-name="sub-line"][data-status="stopped"]'))
    || document.querySelector('[data-name="instance-card"]')
  card.scrollIntoView({ block: 'center' })
  const r = card.getBoundingClientRect()
  return JSON.stringify({ x: Math.max(0, r.x - 8), y: Math.max(0, r.y - 8), width: r.width + 16, height: r.height + 16 })
})()`))
const shot = await send('Page.captureScreenshot', { format: 'png', clip: { ...box, scale: 2 } })
writeFileSync(outDir + '/card.png', Buffer.from(shot.result.data, 'base64'))

// ── 图页 ────────────────────────────────────────────────────
const esc = (s) => s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
const page2 = `<!doctype html><meta charset="utf-8">
<style>
  body { margin: 0; padding: 28px 32px; background: #10151c; color: #d7e0ea;
         font: 13px/1.65 "JetBrains Mono", "DejaVu Sans Mono", monospace; }
  h1 { font-size: 15px; margin: 0 0 4px; color: #eaf2fa; font-weight: 600; }
  p.note { margin: 0 0 18px; color: #8fa3b8; font-size: 12px; }
  pre { margin: 0; white-space: pre; }
  .n { color: #7fd1a6; }   /* data-name */
  .u { color: #f0b46a; }   /* data-uid  */
</style>
<h1>实例卡片的 DOM 片段 —— data-name（角色）与 data-uid（这一个）</h1>
<p class="note">每一处标注同时带两个属性：<span class="n">data-name</span> 说角色（同类共用，可重复），<span class="u">data-uid</span> 说具体是哪一个（8 位 base36，全页唯一、跨刷新稳定）。svg 内部已折叠。</p>
<pre>${esc(prettyHtml)
  .replace(/data-name="([^"]*)"/g, '<span class="n">data-name="$1"</span>')
  .replace(/data-uid="([^"]*)"/g, '<span class="u">data-uid="$1"</span>')}</pre>
`
writeFileSync(outDir + '/card-dom.html', page2)
await send('Page.navigate', { url: 'file://' + outDir.replace(/^\./, process.cwd()) + '/card-dom.html' })
await sleep(600)
await send('Emulation.setDeviceMetricsOverride', { width: 1400, height: 2200, deviceScaleFactor: 1, mobile: false })
await sleep(300)
const shot2 = await send('Page.captureScreenshot', { format: 'png', captureBeyondViewport: true })
writeFileSync(outDir + '/card-dom.png', Buffer.from(shot2.result.data, 'base64'))
console.log('产物写到 ' + outDir)
chrome.kill()
process.exit(0)

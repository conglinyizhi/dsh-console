// 行菜单探针：node probe-menus.mjs <baseUrl> [outJson]
// 逐张卡点开 ⋯ 菜单，把菜单项的文本、分隔线的位置、以及每项的中心点能不能点到记下来。
// 「运行中的卡不许有归档」「分隔线别留孤立的」两条判定直接看这份输出。
import { spawn } from 'node:child_process'
import { writeFileSync } from 'node:fs'

const CDP_PORT = 9300 + (process.pid % 600)
const [baseUrl, outJson] = process.argv.slice(2)
const chrome = spawn('chromium', ['--headless', '--no-sandbox', '--disable-gpu', '--disable-extensions',
  '--hide-scrollbars', '--remote-debugging-port=' + CDP_PORT, '--user-data-dir=/tmp/chrome-menus-' + process.pid,
  '--window-size=1280,900', '--noerrdialogs', '--no-first-run', '--ozone-platform=headless',
  '--ozone-override-screen-size=800,600', '--use-angle=swiftshader-webgl', 'about:blank'], { stdio: 'ignore' })

let page = null
for (let i = 0; i < 40 && !page; i++) {
  try { const list = await (await fetch('http://127.0.0.1:' + CDP_PORT + '/json')).json(); page = list.find((t) => t.type === 'page') } catch {}
  if (!page) await new Promise((r) => setTimeout(r, 250))
}
if (!page) { console.log(JSON.stringify({ ok: false, error: 'chrome 没起来' })); process.exit(1) }
const ws = new WebSocket(page.webSocketDebuggerUrl)
let id = 0
const pending = new Map()
ws.onmessage = (e) => { const m = JSON.parse(e.data); if (m.id && pending.has(m.id)) { pending.get(m.id)(m); pending.delete(m.id) } }
await new Promise((r) => { ws.onopen = r })
const send = (method, params = {}) => new Promise((res) => { const i = ++id; pending.set(i, res); ws.send(JSON.stringify({ id: i, method, params })) })
const ev = async (expression) => {
  const r = await send('Runtime.evaluate', { expression, returnByValue: true })
  // 页面里那一段抛了的话**要说出来**：静默返回 undefined 会把「没量到」伪装成「空菜单」
  if (r.result?.exceptionDetails) {
    console.log('EVAL ERROR: ' + JSON.stringify(r.result.exceptionDetails).slice(0, 400))
  }
  return r.result?.result?.value
}
await send('Page.enable')
await send('Emulation.setDeviceMetricsOverride', { width: 1280, height: 900, deviceScaleFactor: 1, mobile: false })
await send('Page.navigate', { url: baseUrl })
await new Promise((r) => setTimeout(r, 4500))

const cardNames = JSON.parse(await ev(`JSON.stringify([...document.querySelectorAll('.dsh-case')].map((c,i)=>({i, name: c.querySelector('.dsh-name').textContent.trim(), status: c.querySelector('.dsh-sub').dataset.status})))`) || '[]')
const out = []
for (const c of cardNames) {
  const opened = await ev(`(() => {
    const card = document.querySelectorAll('.dsh-case')[${c.i}]
    const t = card.querySelector('[data-name=menu-trigger]')
    if (!t) return 'no-trigger'
    t.click(); return 'clicked'
  })()`)
  await new Promise((r) => setTimeout(r, 700))
  // String.raw：这一段里带反斜杠（正则），普通模板串会把 \s 吃成 s、把 \/ 吃成 /，
  // 结果页面收到一个语法坏掉的表达式 —— 静默变成「空菜单」（真踩过）
  const dump = await ev(String.raw`(() => {
    const card = document.querySelectorAll('.dsh-case')[${c.i}]
    const menu = card.querySelector('[data-name=row-menu]')
    if (!menu) return JSON.stringify({ opened: false })
    const kids = [...menu.children]
    const rows = kids.map((e) => {
      const r = e.getBoundingClientRect()
      const hit = document.elementFromPoint(r.x + r.width/2, r.y + r.height/2)
      return {
        kind: e.classList.contains('dsh-menu-sep') ? 'sep' : 'item',
        text: e.textContent.trim(),
        reachable: !!(hit && (hit === e || e.contains(hit))),
      }
    })
    const labels = rows.filter((r) => r.kind === 'item').map((r) => r.text)
    const sepIdx = rows.map((r, i) => r.kind === 'sep' ? i : -1).filter((i) => i >= 0)
    return JSON.stringify({
      opened: true,
      rows,
      labels,
      sepCount: sepIdx.length,
      sepOrphans: sepIdx.filter((i) => i === 0 || i === rows.length - 1 || rows[i-1].kind === 'sep' || rows[i+1].kind === 'sep'),
      menuHTML: menu.outerHTML.replace(/\s+/g, ' ').slice(0, 200),
      // 逐项的 DOM（内联 SVG 折起来，只留结构：标签 / role / class / data-action / 文本）
      dom: kids.map((e) => e.outerHTML
        .replace(/<svg[\s\S]*?<\/svg>/g, '<svg/>')
        .replace(/\s+/g, ' ')
        .trim()),
    })
  })()`)
  out.push({ name: c.name, status: c.status, openResult: opened, menu: JSON.parse(dump || '{}') })
  await ev("document.body.click()")
  await new Promise((r) => setTimeout(r, 300))
}
if (outJson) writeFileSync(outJson, JSON.stringify(out, null, 1))
console.log(JSON.stringify(out, null, 1))
chrome.kill()
process.exit(0)

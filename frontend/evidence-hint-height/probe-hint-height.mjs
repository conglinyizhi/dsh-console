// 两件事的证据：加载态那条 sr-only、抽屉问题提示的高度上限。
// 用法：node probe-hint-height.mjs <输出目录（绝对路径）> <baseUrl>
import { spawn } from 'node:child_process'
import { writeFileSync, mkdirSync } from 'node:fs'

const OUT = process.argv[2]
const BASE = process.argv[3]
mkdirSync(OUT, { recursive: true })

const CDP_PORT = 9400 + (process.pid % 400)
const VW = 1280, VH = 900
const chrome = spawn('chromium', ['--headless', '--no-sandbox', '--disable-gpu', '--disable-extensions', '--hide-scrollbars', '--remote-debugging-port=' + CDP_PORT, '--user-data-dir=/tmp/chrome-hint-' + process.pid, '--window-size=' + VW + ',' + VH, 'about:blank'], { stdio: 'ignore' })
let page = null
for (let i = 0; i < 60 && !page; i++) { try { const l = await (await fetch('http://127.0.0.1:' + CDP_PORT + '/json')).json(); page = l.find((t) => t.type === 'page') } catch {} if (!page) await new Promise((r) => setTimeout(r, 250)) }
const ws = new WebSocket(page.webSocketDebuggerUrl); let id = 0; const pend = new Map()
ws.onmessage = (e) => { const m = JSON.parse(e.data); if (m.id && pend.has(m.id)) { pend.get(m.id)(m); pend.delete(m.id) } }
await new Promise((r) => { ws.onopen = r })
const send = (m, p = {}) => new Promise((res) => { const i = ++id; pend.set(i, res); ws.send(JSON.stringify({ id: i, method: m, params: p })) })
const wait = (ms) => new Promise((r) => setTimeout(r, ms))
const ev = async (expr) => {
  const r = await send('Runtime.evaluate', { expression: expr, returnByValue: true, awaitPromise: true })
  if (r.result && r.result.exceptionDetails) throw new Error('页面里抛错: ' + JSON.stringify(r.result.exceptionDetails).slice(0, 400))
  return r.result && r.result.result ? r.result.result.value : undefined
}
const shot = async (name) => { const r = await send('Page.captureScreenshot', { format: 'png' }); writeFileSync(OUT + '/' + name, Buffer.from(r.result.data, 'base64')) }

await send('Page.enable'); await send('Runtime.enable')
await send('Emulation.setDeviceMetricsOverride', { width: VW, height: VH, deviceScaleFactor: 1, mobile: false })

// 页面里那几个小工具。可见性的判据写在前面：
// 元素自己或任一祖先被裁成 ≤2px、或挂了 clip / clip-path、或 display:none / visibility:hidden，都算不可见。
const HELP = [
  'const FOUR = ["正在读取实例读数…", "实例与 profile 的读数还在路上。这里先摆加载态 —— 「确实一个都没有」要等读数回来才敢说。", "正在读取 profile 读数…", "profile 的读数还在路上，这里先摆加载态。"];',
  'const hiddenBy = (el) => { let cur = el; while (cur && cur !== document.documentElement) { const cs = getComputedStyle(cur); if (cs.display === "none" || cs.visibility === "hidden" || Number(cs.opacity) === 0) return "style"; const r = cur.getBoundingClientRect(); if (r.width <= 2 || r.height <= 2) return "tiny-box"; if (cs.clipPath && cs.clipPath !== "none") return "clip-path"; if (cs.clip && cs.clip !== "auto") return "clip"; cur = cur.parentElement } return "" };',
  'const visibleText = () => { const out = []; const w = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT); while (w.nextNode()) { const n = w.currentNode; const t = (n.textContent || "").trim(); if (!t) continue; const el = n.parentElement; if (!el || hiddenBy(el)) continue; out.push(t) } return out.join(" ") };',
  'const measure = (sel) => { const p = document.querySelector(sel); if (!p) return { found: false }; const inner = p.querySelector(".dsh-problem-text") || p; const cs = getComputedStyle(inner); const pr = p.getBoundingClientRect(); const ir = inner.getBoundingClientRect(); const lh = parseFloat(cs.lineHeight); const txt = inner.textContent.trim(); const title = p.getAttribute("title") || ""; return { found: true, cardH: Math.round(pr.height * 100) / 100, innerH: Math.round(ir.height * 100) / 100, lineHeight: cs.lineHeight, lines: Math.round(ir.height / lh), text: txt, textLen: txt.length, titleLen: title.length, titleHead: title.slice(0, 24), fullInTitle: title === txt, className: p.getAttribute("class"), innerDisplay: cs.display, clamp: cs.webkitLineClamp || "", whiteSpace: cs.whiteSpace, ellipsizedX: inner.scrollWidth > inner.clientWidth + 1, clippedY: inner.scrollHeight > inner.clientHeight + 1 }; };',
].join('\n')

// ── 一、加载态：把 /api/local 的请求拦在半路（Fetch 拦下不继续），读数永远不回 ──
await send('Fetch.enable', { patterns: [{ urlPattern: '*api/local*', requestStage: 'Request' }] })
await send('Page.navigate', { url: BASE }); await wait(3000)

const loading = JSON.parse(await ev('(() => {' + HELP + ' const note = document.querySelector(".dsh-loading-note"); const cs = note ? getComputedStyle(note) : null; const r = note ? note.getBoundingClientRect() : null; const vt = visibleText(); return JSON.stringify({ noteInDom: !!note, noteRole: note ? note.getAttribute("role") : null, noteAriaLive: note ? note.getAttribute("aria-live") : null, noteClass: note ? note.getAttribute("class") : null, noteHtml: note ? note.outerHTML : "", noteText: note ? note.textContent.trim() : "", noteRect: r ? { w: r.width, h: r.height } : null, noteStyle: cs ? { position: cs.position, width: cs.width, height: cs.height, clip: cs.clip, clipPath: cs.clipPath, overflow: cs.overflow, whiteSpace: cs.whiteSpace } : null, skeletonTiles: document.querySelectorAll(".dsh-skeleton").length, skeletonRowH: (() => { const s = document.querySelector(".dsh-skeleton-row"); return s ? Math.round(s.getBoundingClientRect().height) : null })(), visibleHasFour: FOUR.map((s) => vt.includes(s)), visibleLen: vt.length, visibleHead: vt.slice(0, 120), visibleHasRunningHead: vt.includes("当前运行的实例"), visibleHasStoppedHead: vt.includes("已停止的实例") }) })()'))
await shot('loading.png')

await send('Accessibility.enable')
const ax = await send('Accessibility.getFullAXTree')
const axStatus = (ax.result.nodes || []).filter((n) => n.role && n.role.value === 'status').map((n) => ({ role: n.role.value, name: (n.name && n.name.value) || '', ignored: !!n.ignored }))
const axText = (ax.result.nodes || []).filter((n) => { const v = (n.name && n.name.value) || ''; return v.includes('正在读取') || v.includes('读数还在路上') }).map((n) => ({ role: n.role && n.role.value, name: n.name && n.name.value, ignored: !!n.ignored }))
writeFileSync(OUT + '/loading.json', JSON.stringify({ loading, axStatus, axText }, null, 1))

// ── 二、抽屉：放行网络，等读数回来，点开 fixture-11 那张卡 ──
await send('Fetch.disable')
await send('Page.navigate', { url: BASE }); await wait(6000)
const clicked = await ev('(() => { const card = [...document.querySelectorAll(".dsh-case")].find((c) => c.textContent.includes("fixture-11")); if (!card) return "没找到卡"; card.click(); return card.textContent.trim().slice(0, 40) })()')
await wait(1200)
const drawer = JSON.parse(await ev('(() => {' + HELP + ' const d = measure(".dsh-drawer-health"); const sec = document.querySelector(".dsh-drawer-health"); const body = document.querySelector(".dsh-drawer-body"); return JSON.stringify(Object.assign({}, d, { outerHtml: (sec ? sec.outerHTML : ""), sectionH: sec ? Math.round(sec.closest(".dsh-drawer-section").getBoundingClientRect().height) : null, drawerBody: body ? { scrollH: body.scrollHeight, clientH: body.clientHeight } : null })) })()'))
await shot('drawer.png')

// ── 三、两副形状各来一份：都拿真抽屉里那条的**同一段标记**，只换正文与 class ──
const longError = '读取这只 profile 的 package.json 时失败了：EACCES: permission denied, open /home/someone/.dsh/profiles/fixture-11/package.json —— 上一次同步在 pnpm install 中途被打断，node_modules 里留下一个半装的目录，声明的包一个没装上、装上的一半又对不上 lock，后端只把原始错误串报回来，前端认不出它属于哪一条已知问题。'
const longKnown = '缺 11 个包：@acme/alpha-long-name、@acme/beta-long-name、@acme/gamma-long-name、@acme/delta-long-name、@acme/epsilon-long-name（这一条仍走「已知」那一副形状，用来看它会不会被顶成两行）'
const knownHtml = drawer.outerHtml
const swapText = (html, t) => html.replace(/(<span class="dsh-problem-text">)[\s\S]*?(<\/span>)/, '$1' + t + '$2')
const swapTitle = (html, t) => html.replace(/title="[^"]*"/, 'title="' + t + '"')
const knownLongHtml = swapTitle(swapText(knownHtml, longKnown), longKnown)
const freeHtml = swapTitle(swapText(knownHtml, longError), longError).replace('class="dsh-drawer-health dsh-problem"', 'class="dsh-drawer-health dsh-problem is-free"')
const fixture = '<!doctype html>\n<html lang="zh"><head><meta charset="utf-8"><title>问题提示两副形状（fixture，用同一份 app.css）</title>\n<link rel="stylesheet" href="../dist/assets/app.css"></head>\n<body>\n<main class="dsh-drawer-body" style="width:520px">\n  <div class="dsh-drawer-section">\n    <h3 class="dsh-drawer-section-title">profile 健康</h3>\n    ' + knownHtml.replace('<p ', '<p id="fixture-known" ') + '\n    ' + knownLongHtml.replace('<p ', '<p id="fixture-known-long" ') + '\n    ' + freeHtml.replace('<p ', '<p id="fixture-free" ') + '\n  </div>\n</main>\n</body></html>\n'
writeFileSync(OUT + '/fixture-problem-hint.html', fixture)

await send('Page.navigate', { url: 'file://' + OUT + '/fixture-problem-hint.html' }); await wait(1200)
const free = JSON.parse(await ev('(() => {' + HELP + ' return JSON.stringify({ known: measure("#fixture-known"), knownLong: measure("#fixture-known-long"), freeCase: measure("#fixture-free") }) })()'))
await shot('fixture-problem-hint.png')

writeFileSync(OUT + '/drawer.json', JSON.stringify({ clicked, drawer }, null, 1))
writeFileSync(OUT + '/free.json', JSON.stringify({ longError, longKnown, free }, null, 1))

const brief = (m) => ({ text: m.text, textLen: m.textLen, lines: m.lines, cardH: m.cardH, innerH: m.innerH, clamp: m.clamp, whiteSpace: m.whiteSpace, ellipsizedX: m.ellipsizedX, clippedY: m.clippedY, titleLen: m.titleLen, fullInTitle: m.fullInTitle })
console.log(JSON.stringify({
  loading: { noteInDom: loading.noteInDom, role: loading.noteRole, ariaLive: loading.noteAriaLive, noteClass: loading.noteClass, rect: loading.noteRect, position: loading.noteStyle && loading.noteStyle.position, clip: loading.noteStyle && loading.noteStyle.clip, clipPath: loading.noteStyle && loading.noteStyle.clipPath, skeletonTiles: loading.skeletonTiles, skeletonRowH: loading.skeletonRowH, visibleHasFour: loading.visibleHasFour, headingsVisible: [loading.visibleHasRunningHead, loading.visibleHasStoppedHead] },
  axStatus,
  axText,
  click: clicked,
  drawer: Object.assign(brief(drawer), { sectionH: drawer.sectionH, drawerBody: drawer.drawerBody }),
  fixture: { known: brief(free.known), knownLong: brief(free.knownLong), freeCase: brief(free.freeCase) },
}, null, 1))
chrome.kill(); process.exit(0)

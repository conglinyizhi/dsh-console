// 三处改动的验收探针（2026-10-16）：
//   node accept.mjs <baseUrl> [outPrefix]
//
// 一次跑完四组，把结果写进 outPrefix-*.json / *.png：
//   A 首页     右栏确实没了、页面变单栏、状态点跨卡对齐、按钮组右缘贴内容右缘
//   B 行菜单   「复制开发指令」在哪一张卡的菜单里、第几项，以及**真正写进剪贴板的那段全文**
//              （用 navigator.clipboard.readText 读回来，不是拿页面里的字符串充数）
//   C 失败路径 把剪贴板两条路（navigator.clipboard 与 execCommand）都打断，
//              看提示条如实说了什么 —— 不许静默、也不许假装复制成功
//   D 设置页   默认时「恢复默认」一个节点都没有（DOM 计数）→ 改成非默认 → 入口出现
//              → 点它 → 值回默认且入口消失；另做一遍可见文本扫描（来源 / 缺省 / 当前）
//
// 剪贴板权限：headless Chrome 默认不给页面读写剪贴板，这里用 CDP 的
// Browser.grantPermissions 显式授权（clipboardReadWrite + clipboardSanitizedWrite），
// 否则 readText 会以权限错误拒绝，量到的是「读不回来」而不是「没写进去」。
//
// 页面里求值的表达式一律用单引号字符串拼（**不在页面代码里用模板串**）：
// 这个文件本身是模板串，里面再出现反引号会把它提前截断。
import { spawn } from 'node:child_process'
import { writeFileSync } from 'node:fs'

const CDP_PORT = 9300 + (process.pid % 600)
const [baseUrl, outPrefix = '/tmp/accept-three'] = process.argv.slice(2)
if (!baseUrl) { console.log('用法: node accept.mjs <baseUrl> [outPrefix]'); process.exit(1) }
const origin = new URL(baseUrl).origin
const sleep = (ms) => new Promise((r) => setTimeout(r, ms))

const chrome = spawn('chromium', ['--headless', '--no-sandbox', '--disable-gpu', '--disable-extensions',
  '--hide-scrollbars', '--remote-debugging-port=' + CDP_PORT, '--user-data-dir=/tmp/chrome-accept3-' + process.pid,
  '--window-size=1280,900', '--noerrdialogs', '--no-first-run', '--ozone-platform=headless',
  '--ozone-override-screen-size=1280,900', '--use-angle=swiftshader-webgl', 'about:blank'], { stdio: 'ignore' })

let page = null
for (let i = 0; i < 60 && !page; i++) {
  try { const list = await (await fetch('http://127.0.0.1:' + CDP_PORT + '/json')).json(); page = list.find((t) => t.type === 'page') } catch {}
  if (!page) await sleep(250)
}
if (!page) { console.log(JSON.stringify({ ok: false, error: 'chrome 没起来' })); process.exit(1) }
const ws = new WebSocket(page.webSocketDebuggerUrl)
let id = 0
const pending = new Map()
ws.onmessage = (e) => { const m = JSON.parse(e.data); if (m.id && pending.has(m.id)) { pending.get(m.id)(m); pending.delete(m.id) } }
await new Promise((r) => { ws.onopen = r })
const send = (method, params = {}) => new Promise((res) => { const i = ++id; pending.set(i, res); ws.send(JSON.stringify({ id: i, method, params })) })
const ev = async (expression) => {
  const r = await send('Runtime.evaluate', { expression, returnByValue: true, awaitPromise: true })
  if (r.result?.exceptionDetails) console.log('EVAL ERROR: ' + JSON.stringify(r.result.exceptionDetails).slice(0, 400))
  return r.result?.result?.value
}
const shot = async (path) => {
  const r = await send('Page.captureScreenshot', { format: 'png' })
  if (r.result?.data) writeFileSync(path, Buffer.from(r.result.data, 'base64'))
}
const menuTriggerOf = (n) => '(() => { document.querySelectorAll(".dsh-case")[' + n + '].querySelector("[data-name=menu-trigger]").click(); return 1 })()'
const clickCopyDevAt = (n) => '(() => { const c = document.querySelectorAll(".dsh-case")[' + n + ']; c.querySelector("[data-action=copy-dev]").click(); return 1 })()'

await send('Page.enable')
await send('Runtime.enable')
// 剪贴板读写在 headless 下还要求**文档是聚焦的**（否则 writeText / readText 都直接以
// "Document is not focused" 拒绝 —— 那量到的是「没聚焦」，不是「没写进去」）。
// 焦点仿真 + 把标签页提到最前，这两条一起才够。
await send('Emulation.setFocusEmulationEnabled', { enabled: true })
await send('Page.bringToFront')
const granted = await send('Browser.grantPermissions', { origin, permissions: ['clipboardReadWrite', 'clipboardSanitizedWrite'] })
await send('Emulation.setDeviceMetricsOverride', { width: 1280, height: 900, deviceScaleFactor: 1, mobile: false })
await send('Page.navigate', { url: baseUrl })
await send('Page.bringToFront')
await sleep(5000)
await shot(outPrefix + '-A-overview.png')

const report = { baseUrl, clipboardGrant: granted.result ?? granted, A: null, B: null, C: null, D: null }

// ── A. 首页：右栏没了 / 单栏 / 几何不变量 ─────────────────────────
const exprA = [
  '(() => {',
  '  const R = (el) => { const r = el.getBoundingClientRect(); return { x:+r.x.toFixed(1), y:+r.y.toFixed(1), w:+r.width.toFixed(1), h:+r.height.toFixed(1), right:+r.right.toFixed(1), bottom:+r.bottom.toFixed(1) } };',
  '  const contentRight = (el) => { const cs = getComputedStyle(el); const r = el.getBoundingClientRect(); return +(r.right - parseFloat(cs.paddingRight) - parseFloat(cs.borderRightWidth)).toFixed(1) };',
  '  const ov = document.querySelector(".dsh-overview");',
  '  const page = document.querySelector(".dsh-overview-page");',
  '  const main = document.querySelector(".dsh-main");',
  '  const cards = [...document.querySelectorAll(".dsh-case")];',
  '  const dots = cards.map((c) => c.querySelector(".dsh-dot")).filter(Boolean).map((d) => +d.getBoundingClientRect().x.toFixed(1));',
  '  const deltas = cards.map((c) => { const a = c.querySelector(".dsh-actions"); return a ? +(a.getBoundingClientRect().right - contentRight(c)).toFixed(1) : null });',
  '  const mainCs = getComputedStyle(main), mainR = main.getBoundingClientRect();',
  '  const mainContent = { left: +(mainR.left + parseFloat(mainCs.paddingLeft)).toFixed(1), right: +(mainR.right - parseFloat(mainCs.paddingRight)).toFixed(1) };',
  '  return JSON.stringify({',
  '    sidePanelNodes: document.querySelectorAll(".dsh-side-info,.dsh-info-card,.dsh-flows,.dsh-flow,.dsh-notes,.dsh-note,.dsh-note-text").length,',
  '    sidePanelMarks: document.querySelectorAll("[data-name=side-info],[data-name=workflow-entry]").length,',
  '    textHasWorkflowTitle: document.body.textContent.includes("\u5de5\u4f5c\u6d41\u5165\u53e3"),',
  '    textHasAboutTitle: document.body.textContent.includes("\u5173\u4e8e\u5b9e\u4f8b"),',
  '    textHasHandback: document.body.textContent.includes("\u5c06\u63d2\u4ef6\u4ea4\u56de\u4e3b\u7ebf\u5b9e\u4f8b"),',
  '    overviewChildren: [...ov.children].map((e) => e.className),',
  '    singleColumn: ov.children.length === 1,',
  '    ovRect: R(ov), pageRect: R(page), mainContent,',
  '    pageRightVsMainContent: +(R(page).right - mainContent.right).toFixed(1),',
  '    cardCount: cards.length,',
  '    dotXs: dots, dotXsAllEqual: dots.length > 1 ? new Set(dots).size === 1 : null,',
  '    actionsDeltas: deltas, actionsAllZero: deltas.every((d) => d === 0),',
  '    overflowX: document.documentElement.scrollWidth > document.documentElement.clientWidth,',
  '  })',
  '})()',
].join('\n')
report.A = JSON.parse(await ev(exprA))

// ── B. 行菜单：位置、顺序、真写进剪贴板的那段全文 ──────────────────
const cardCount = await ev('document.querySelectorAll(".dsh-case").length')
report.B = { cardCount, menus: [], clipboard: null, toast: null, copiedFrom: null }
for (let i = 0; i < cardCount; i++) {
  await ev(menuTriggerOf(i))
  await sleep(500)
  const exprB = [
    '(() => {',
    '  const c = document.querySelectorAll(".dsh-case")[' + i + '];',
    '  const m = c.querySelector("[data-name=row-menu]");',
    '  if (!m) return JSON.stringify({ opened: false });',
    '  const kids = [...m.children];',
    '  const dev = kids.find((e) => e.dataset && e.dataset.action === "copy-dev");',
    '  const R = (el) => { const r = el.getBoundingClientRect(); return { x:+r.x.toFixed(1), y:+r.y.toFixed(1), w:+r.width.toFixed(1), h:+r.height.toFixed(1) } };',
    '  return JSON.stringify({',
    '    opened: true,',
    '    name: c.querySelector(".dsh-name").textContent.trim(),',
    '    status: c.querySelector(".dsh-sub").dataset.status,',
    '    menuRect: R(m),',
    '    labels: kids.map((e) => e.classList.contains("dsh-menu-sep") ? "\u2014\u5206\u9694\u7ebf\u2014" : e.textContent.trim()),',
    '    actions: kids.map((e) => (e.dataset && e.dataset.action) || "sep"),',
    '    copyDevIndex: kids.indexOf(dev),',
    '    copyDevText: dev ? dev.textContent.trim() : null,',
    '    copyDevRect: dev ? R(dev) : null,',
    '    copyDevUid: dev ? dev.getAttribute("data-uid") : null,',
    '  })',
    '})()',
  ].join('\n')
  report.B.menus.push(JSON.parse(await ev(exprB)))
  await ev('document.body.click()')
  await sleep(250)
}
const targetIdx = report.B.menus.findIndex((m) => m.opened && m.copyDevIndex >= 0)
if (targetIdx >= 0) {
  report.B.copiedFrom = { cardIndex: targetIdx, name: report.B.menus[targetIdx].name, status: report.B.menus[targetIdx].status }
  await ev(menuTriggerOf(targetIdx))
  await sleep(500)
  await shot(outPrefix + '-B-menu.png')
  await ev(clickCopyDevAt(targetIdx))
  await sleep(800)
  const readBack = await send('Runtime.evaluate', {
    expression: 'navigator.clipboard.readText().then((t) => t, (e) => "READ-ERR: " + String((e && e.message) || e))',
    returnByValue: true, awaitPromise: true, userGesture: true,
  })
  report.B.clipboard = readBack.result?.result?.value ?? ('READ-CALL-FAILED: ' + JSON.stringify(readBack).slice(0, 200))
  report.B.toast = JSON.parse(await ev('(() => { const t = document.querySelector(".dsh-toast"); return JSON.stringify({ text: t ? t.textContent.trim() : null, ok: t ? t.dataset.ok : null }) })()'))
  report.B.noticeBar = await ev('(() => { const n = document.querySelector(".dsh-notice-text"); return n ? n.textContent.trim() : "" })()')
  if (typeof report.B.clipboard === 'string' && !report.B.clipboard.startsWith('READ-ERR'))
    writeFileSync(outPrefix + '-clipboard.txt', report.B.clipboard)
}

// ── B2. 再从一只已停止的 profile 卡上复制一次 ─────────────────────
// 这一项本来就是给 profile 用的，运行中的卡与已停止的卡都要量到：
// 复制出来的 profile 名与目录会跟着这一行走，不能只测一张。
const profileIdx = report.B.menus.findIndex((m) => m.opened && m.copyDevIndex >= 0 && m.status === 'stopped')
report.B.profileCopy = null
if (profileIdx >= 0) {
  await ev(menuTriggerOf(profileIdx))
  await sleep(500)
  await ev(clickCopyDevAt(profileIdx))
  await sleep(800)
  const back = await send('Runtime.evaluate', {
    expression: 'navigator.clipboard.readText().then((t) => t, (e) => "READ-ERR: " + String((e && e.message) || e))',
    returnByValue: true, awaitPromise: true, userGesture: true,
  })
  report.B.profileCopy = {
    cardIndex: profileIdx,
    name: report.B.menus[profileIdx].name,
    status: report.B.menus[profileIdx].status,
    clipboard: back.result?.result?.value ?? null,
    toast: JSON.parse(await ev('(() => { const t = document.querySelector(".dsh-toast"); return JSON.stringify({ text: t ? t.textContent.trim() : null, ok: t ? t.dataset.ok : null }) })()')),
  }
  if (typeof report.B.profileCopy.clipboard === 'string' && !report.B.profileCopy.clipboard.startsWith('READ-ERR'))
    writeFileSync(outPrefix + '-clipboard-profile.txt', report.B.profileCopy.clipboard)
  await sleep(4200) // 等这条 toast 自己走掉，免得下一段读到它
}

// ── C. 失败路径：剪贴板两条路都打断 ───────────────────────────────
if (targetIdx >= 0) {
  await ev('(() => { window.__probeExec = document.execCommand; window.__probeWrite = navigator.clipboard && navigator.clipboard.writeText; if (navigator.clipboard && navigator.clipboard.writeText) { navigator.clipboard.writeText = () => Promise.reject(new Error("\u63a2\u9488\uff1a\u6a21\u62df\u526a\u8d34\u677f\u4e0d\u53ef\u7528")); } document.execCommand = () => false; return "patched" })()')
  await ev(menuTriggerOf(targetIdx))
  await sleep(500)
  await ev(clickCopyDevAt(targetIdx))
  await sleep(800)
  report.C = JSON.parse(await ev([
    '(() => {',
    '  const n = document.querySelector("[data-name=action-notice]");',
    '  const t = document.querySelector(".dsh-toast");',
    '  return JSON.stringify({',
    '    noticeBarPresent: !!n,',
    '    noticeOk: n ? n.dataset.ok : null,',
    '    noticeText: n ? n.querySelector(".dsh-notice-text").textContent.trim() : null,',
    '    toastPresent: !!t,',
    '    toastText: t ? t.textContent.trim() : null,',
    '  })',
    '})()',
  ].join('\n')))
  await shot(outPrefix + '-C-copy-failed.png')
  await ev('(() => { if (window.__probeWrite) navigator.clipboard.writeText = window.__probeWrite; document.execCommand = window.__probeExec; return "restored" })()')
}

// ── D. 设置页 ────────────────────────────────────────────────────
await ev('(() => { document.querySelector("[data-name=nav-settings]").click(); return 1 })()')
for (let i = 0; i < 25; i++) {
  const ready = await ev('!!document.querySelector("[data-name=settings-panel]")')
  if (ready) break
  await sleep(400)
}
await sleep(600)
report.D = {}
report.D.initial = JSON.parse(await ev([
  '(() => {',
  '  const rows = [...document.querySelectorAll("[data-name=setting-row]")];',
  '  const t = document.querySelector(".dsh-settings-tab.active");',
  '  return JSON.stringify({',
  '    group: t ? t.textContent.trim() : null,',
  '    rowCount: rows.length,',
  '    metaNodes: document.querySelectorAll(".dsh-setting-meta,[data-name=setting-meta]").length,',
  '    resetNodes: document.querySelectorAll("[data-name=setting-reset]").length,',
  '    rows: rows.map((r) => ({ key: r.dataset.setting, value: r.dataset.value, hasReset: !!r.querySelector("[data-name=setting-reset]") })),',
  '  })',
  '})()',
].join('\n')))
const scanExpr = [
  '(() => {',
  '  const root = document.querySelector(".dsh-settings-page");',
  '  const text = root ? root.innerText : "";',
  '  const hits = ["\u6765\u6e90", "\u7f3a\u7701", "\u5f53\u524d"].map((w) => {',
  '    const i = text.indexOf(w);',
  '    return { word: w, count: (text.split(w).length - 1), context: i < 0 ? "" : text.slice(Math.max(0, i - 30), i + 30).replace(/\\n/g, " ") };',
  '  });',
  '  return JSON.stringify({ chars: text.length, hits });',
  '})()',
].join('\n')
report.D.textScan = JSON.parse(await ev(scanExpr))
await ev('(() => { document.querySelector("[data-name=settings-tab][data-group=ui]").click(); return 1 })()')
await sleep(800)
const rowExpr = [
  '(() => {',
  '  const r = document.querySelector("[data-setting=\u0027ui.archiveOpenByDefault\u0027]");',
  '  if (!r) return JSON.stringify({ found: false });',
  '  const reset = r.querySelector("[data-name=setting-reset]");',
  '  const sw = r.querySelector("[data-name=setting-switch]");',
  '  return JSON.stringify({',
  '    found: true,',
  '    value: r.dataset.value,',
  '    resetCount: r.querySelectorAll("[data-name=setting-reset]").length,',
  '    resetText: reset ? reset.textContent.trim() : null,',
  '    resetTitle: reset ? reset.getAttribute("title") : null,',
  '    switchText: sw ? sw.textContent.trim() : null,',
  '    rowInnerText: r.innerText.replace(/\\n/g, " | ").trim(),',
  '    pageResetNodes: document.querySelectorAll("[data-name=setting-reset]").length,',
  '  });',
  '})()',
].join('\n')
const switchSel = 'document.querySelector("[data-setting=\u0027ui.archiveOpenByDefault\u0027] [data-name=setting-switch]")'
const resetSel = 'document.querySelector("[data-setting=\u0027ui.archiveOpenByDefault\u0027] [data-name=setting-reset]")'
report.D.step1Default = JSON.parse(await ev(rowExpr))
await shot(outPrefix + '-D1-settings-default.png')
await ev('(() => { ' + switchSel + '.click(); return 1 })()')
await sleep(1600)
report.D.step2Changed = JSON.parse(await ev(rowExpr))
report.D.step2Toast = await ev('(() => { const t = document.querySelector(".dsh-toast"); return t ? t.textContent.trim() : null })()')
// 非默认这一档也要扫一遍：这一趟页面上多了一颗「恢复默认」，它自己不许把那三个词带回来
report.D.textScanNonDefault = JSON.parse(await ev(scanExpr))
await shot(outPrefix + '-D2-settings-nondefault.png')
await ev('(() => { ' + resetSel + '.click(); return 1 })()')
await sleep(1600)
report.D.step3Reset = JSON.parse(await ev(rowExpr))
report.D.step3Toast = await ev('(() => { const t = document.querySelector(".dsh-toast"); return t ? t.textContent.trim() : null })()')
report.D.textScanAfterReset = JSON.parse(await ev(scanExpr))
await shot(outPrefix + '-D3-settings-after-reset.png')

writeFileSync(outPrefix + '-report.json', JSON.stringify(report, null, 1))
console.log(JSON.stringify(report, null, 1))
chrome.kill()
process.exit(0)

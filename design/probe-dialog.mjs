const CDP_PORT = 9300 + (process.pid % 600) // 按进程取，并行跑不抢端口
import { spawn } from 'node:child_process'
const baseUrl = process.argv[2]
const chrome = spawn('chromium', ['--headless','--no-sandbox','--disable-gpu','--disable-extensions','--hide-scrollbars','--remote-debugging-port=' + CDP_PORT,'--user-data-dir=/tmp/chrome-probe-' + process.pid,'--window-size=1440,900','about:blank'], { stdio: 'ignore' })
let page = null
for (let i = 0; i < 40 && !page; i++) { try { const l = await (await fetch('http://127.0.0.1:' + CDP_PORT + '/json')).json(); page = l.find((t) => t.type === 'page') } catch {} if (!page) await new Promise((r) => setTimeout(r, 250)) }
const ws = new WebSocket(page.webSocketDebuggerUrl); let id = 0; const pend = new Map()
ws.onmessage = (e) => { const m = JSON.parse(e.data); if (m.id && pend.has(m.id)) { pend.get(m.id)(m); pend.delete(m.id) } }
await new Promise((r) => { ws.onopen = r })
const send = (method, params = {}) => new Promise((res) => { const i = ++id; pend.set(i, res); ws.send(JSON.stringify({ id: i, method, params })) })
const ev = async (e) => { const r = await send('Runtime.evaluate', { expression: e, returnByValue: true }); return r.result?.result?.value }
const evAsync = async (e) => { const r = await send('Runtime.evaluate', { expression: e, returnByValue: true, awaitPromise: true }); return r.result?.result?.value }
const wait = (ms) => new Promise((r) => setTimeout(r, ms))
await send('Page.enable'); await send('Runtime.enable')
await send('Emulation.setDeviceMetricsOverride', { width: 1440, height: 900, deviceScaleFactor: 1, mobile: false })
await send('Page.navigate', { url: baseUrl }); await wait(4500)
// 打开停止卡的 ▾ 菜单 → 重命名
// 入口用 [aria-haspopup="menu"]（选择器映射里的 menuTrigger）—— 曾经用 `.split-caret || buttons[1]` 兜底，
  // 分段按钮撤掉之后那个兜底会点到「重启」，菜单开不了、框也开不了，于是四条判定变成「没框所以关着」的假通过 ✗
await ev(`(() => { const c = [...document.querySelectorAll('[data-name="instance-card"]')].find((e) => e.querySelector('[data-name="sub-line"][data-status="stopped"]')); const t = c && c.querySelector('[aria-haspopup="menu"]'); if (!t) return 'no-trigger'; t.click(); return 'clicked' })()`)
await wait(800)
await ev(`(() => { const it = [...document.querySelectorAll('[data-name="row-menu"] button, [data-name="row-menu"] [role=menuitem]')].find((e) => e.textContent.trim() === '重命名'); if (it) it.click() })()`)
await wait(900)
const out = await ev(`(() => {
  const R = (e) => { const r = e.getBoundingClientRect(); return { x: +r.x.toFixed(1), y: +r.y.toFixed(1), w: +r.width.toFixed(1), h: +r.height.toFixed(1), right: +r.right.toFixed(1), bottom: +r.bottom.toFixed(1) } }
  const info = (sel) => { const e = document.querySelector(sel); if (!e) return null; const cs = getComputedStyle(e); return { sel, rect: R(e), position: cs.position, zIndex: cs.zIndex, parent: String(e.parentElement.className).slice(0, 40), parentPos: e.parentElement ? getComputedStyle(e.parentElement).position : null } }
  const dlg = document.querySelector('.dsh-dialog-card')
  const scrim = document.querySelector('.dsh-scrim')
  const vw = innerWidth, vh = innerHeight
  // 对话框中心点被谁接收
  let hit = null
  if (dlg) { const r = dlg.getBoundingClientRect(); const t = document.elementFromPoint(r.x + r.width / 2, r.y + r.height / 2); hit = t ? { tag: t.tagName.toLowerCase(), cls: String(t.className).slice(0, 40), inDialog: dlg.contains(t) } : null }
  return JSON.stringify({
    viewport: { vw, vh },
    dialog: info('.dsh-dialog-card'),
    scrim: info('.dsh-scrim'),
    centeredInViewport: dlg ? (() => { const r = dlg.getBoundingClientRect(); return Math.abs((r.x + r.width / 2) - vw / 2) < 8 && Math.abs((r.y + r.height / 2) - vh / 2) < 8 })() : null,
    hitAtDialogCenter: hit,
    scrimAttrs: scrim ? [...scrim.attributes].map((a) => a.name + '=' + a.value).slice(0, 4) : null,
  }, null, 1)
})()`)
console.log(out)
// 真点击：取消键能关 / 点遮罩能关（兄弟结构的意义所在）
const clickTest = await evAsync(`(async () => {
  const wait = (ms) => new Promise((r) => setTimeout(r, ms))
  const openRename = async () => {
    const c = [...document.querySelectorAll('[data-name="instance-card"]')].find((e) => e.textContent.includes('启动'))
    if (!c) return false
    const t = c.querySelector('[aria-haspopup="menu"]')
    if (!t) return false
    t.click()
    await wait(700)
    const it = [...document.querySelectorAll('[data-name="row-menu"] button, [data-name="row-menu"] [role=menuitem]')].find((e) => e.textContent.trim() === '重命名')
    if (!it) return false
    it.click(); await wait(700)
    return !!document.querySelector('.dsh-dialog-card')
  }
  const out = {}
  out.opened1 = await openRename()
  const cancel = [...document.querySelectorAll('.dsh-dialog-btn')].find((b) => b.textContent.trim() === '取消')
  if (cancel) cancel.click()
  await wait(700)
  out.closedByCancel = !document.querySelector('.dsh-dialog-card')
  out.opened2 = await openRename()
  const scrim = document.querySelector('.dsh-scrim')
  if (scrim) scrim.click()
  await wait(700)
  out.closedByScrim = !document.querySelector('.dsh-dialog-card')
  return JSON.stringify(out)
})()`)
const t = JSON.parse(clickTest || '{}')
const d = JSON.parse(out || '{}')
console.log('SUMMARY ' + JSON.stringify({
  centered: d.centeredInViewport === true,
  onTop: d.hitAtDialogCenter && d.hitAtDialogCenter.inDialog === true,
  closedByCancel: t.closedByCancel === true,
  closedByScrim: t.closedByScrim === true,
  // 前置条件：入口真的把框开出来过。没有这一条，入口坏掉时四条会全绿（假通过）
  opened: t.opened1 === true && t.opened2 === true,
  ok: t.opened1 === true && t.opened2 === true &&
    d.centeredInViewport === true && !!(d.hitAtDialogCenter && d.hitAtDialogCenter.inDialog) &&
    t.closedByCancel === true && t.closedByScrim === true,
}))
chrome.kill(); process.exit(0)
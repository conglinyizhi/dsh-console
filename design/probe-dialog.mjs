import { spawn } from 'node:child_process'
const baseUrl = process.argv[2]
const chrome = spawn('chromium', ['--headless','--no-sandbox','--disable-gpu','--disable-extensions','--hide-scrollbars','--remote-debugging-port=9348','--user-data-dir=/tmp/chrome-dlg','--window-size=1440,900','about:blank'], { stdio: 'ignore' })
let page = null
for (let i = 0; i < 40 && !page; i++) { try { const l = await (await fetch('http://127.0.0.1:9348/json')).json(); page = l.find((t) => t.type === 'page') } catch {} if (!page) await new Promise((r) => setTimeout(r, 250)) }
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
await ev(`(() => { const c = [...document.querySelectorAll('[data-name="instance-card"]')].find((e) => e.querySelector('[data-name="sub-line"][data-status="stopped"]')); (c.querySelector('.split-caret') || c.querySelectorAll('button')[1]).click() })()`)
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
    ;(c.querySelector('.split-caret') || c.querySelectorAll('button')[1]).click()
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
}))
chrome.kill(); process.exit(0)
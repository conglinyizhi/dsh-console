// 交互探针：菜单 Esc/点外关闭与焦点回传、重命名对话框、关于页断言
import { spawn } from 'node:child_process'
const baseUrl = process.argv[2]
const chrome = spawn('chromium', ['--headless','--no-sandbox','--disable-gpu','--disable-extensions','--hide-scrollbars','--remote-debugging-port=9340','--user-data-dir=/tmp/chrome-int','--window-size=1280,900','about:blank'], { stdio: 'ignore' })
let page = null
for (let i = 0; i < 40 && !page; i++) { try { const l = await (await fetch('http://127.0.0.1:9340/json')).json(); page = l.find(t => t.type === 'page') } catch {} if (!page) await new Promise(r => setTimeout(r, 250)) }
const ws = new WebSocket(page.webSocketDebuggerUrl); let id = 0; const pend = new Map()
ws.onmessage = e => { const m = JSON.parse(e.data); if (m.id && pend.has(m.id)) { pend.get(m.id)(m); pend.delete(m.id) } }
await new Promise(r => { ws.onopen = r })
const send = (method, params = {}) => new Promise(res => { const i = ++id; pend.set(i, res); ws.send(JSON.stringify({ id: i, method, params })) })
const ev = async (expr) => { const r = await send('Runtime.evaluate', { expression: expr, returnByValue: true }); return r.result?.result?.value }
const key = async (k) => { await send('Input.dispatchKeyEvent', { type: 'keyDown', key: k, code: k === 'Escape' ? 'Escape' : k, windowsVirtualKeyCode: k === 'Escape' ? 27 : 13 }); await send('Input.dispatchKeyEvent', { type: 'keyUp', key: k, code: k === 'Escape' ? 'Escape' : k, windowsVirtualKeyCode: k === 'Escape' ? 27 : 13 }) }
const wait = (ms) => new Promise(r => setTimeout(r, ms))
await send('Page.enable'); await send('Runtime.enable')
await send('Emulation.setDeviceMetricsOverride', { width: 1280, height: 900, deviceScaleFactor: 1, mobile: false })
await send('Page.navigate', { url: baseUrl }); await wait(4500)

const out = {}
// 1) 菜单：Esc 关闭 + 焦点回触发元素
await ev(`document.querySelector('[aria-haspopup="menu"]').click()`)
await wait(600)
out.menuOpened = await ev(`!!document.querySelector('[data-name="row-menu"]')`)
await key('Escape'); await wait(600)
out.menuClosedByEsc = await ev(`!document.querySelector('[data-name="row-menu"]')`)
out.focusBackToTrigger = await ev(`document.activeElement === document.querySelector('[aria-haspopup="menu"]')`)

// 2) 菜单：点外关闭
await ev(`document.querySelector('[aria-haspopup="menu"]').click()`); await wait(600)
const before = await ev(`!!document.querySelector('[data-name="row-menu"]')`)
await ev(`document.querySelector('[data-name="menu-overlay"]') ? document.querySelector('[data-name="menu-overlay"]').click() : document.body.click()`)
await wait(600)
out.menuOpened2 = before
out.menuClosedByOutside = await ev(`!document.querySelector('[data-name="row-menu"]')`)

// 3) 重命名对话框
await ev(`document.querySelector('[aria-haspopup="menu"]').click()`); await wait(600)
const clicked = await ev(`(() => { const it = [...document.querySelectorAll('[data-name="row-menu"] button, [data-name="row-menu"] [role=menuitem]')].find(e => e.textContent.trim() === '重命名'); if (!it) return 'no-item'; it.click(); return 'clicked' })()`)
out.renameItemClicked = clicked
await wait(800)
out.dialogOpen = await ev(`!!document.querySelector('.dsh-dialog-card, [class*=dialog]')`)
out.dialogInputValue = await ev(`(() => { const i = document.querySelector('.dsh-dialog-input, [class*=dialog] input'); return i ? { value: i.value, selectedAll: i.selectionStart === 0 && i.selectionEnd === i.value.length } : null })()`)
await key('Escape'); await wait(700)
out.dialogClosedByEsc = await ev(`!document.querySelector('.dsh-dialog-card')`)
out.focusAfterDialog = await ev(`(() => { const a = document.activeElement; return { tag: a && a.tagName.toLowerCase(), hasPopup: a ? a.getAttribute('aria-haspopup') : null, text: a ? a.textContent.trim().slice(0,10) : null } })()`)

// 4) 关于页断言：没有「node 版本」那行
await ev(`[...document.querySelectorAll('.dsh-nav-item')].find(e => e.textContent.trim() === '关于')?.click()`)
await wait(2000)
out.aboutText = await ev(`document.body.innerText.slice(0, 400)`)
out.aboutHasNodeRow = await ev(`document.body.innerText.includes('node 版本')`)
out.aboutHasConsoleVersion = await ev(`document.body.innerText.includes('控制台版本')`)
console.log(JSON.stringify(out, null, 1))
chrome.kill(); process.exit(0)

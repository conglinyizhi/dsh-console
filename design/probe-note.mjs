
import { writeFileSync } from 'node:fs'
const PORT = 9346
const sleep = (ms) => new Promise((r) => setTimeout(r, ms))
const list = await (await fetch('http://127.0.0.1:' + PORT + '/json/list')).json()
const page = list.find((t) => t.type === 'page')
const ws = new WebSocket(page.webSocketDebuggerUrl)
let id = 0
const pending = new Map()
ws.addEventListener('message', (e) => { const m = JSON.parse(e.data); if (m.id && pending.has(m.id)) { pending.get(m.id)(m); pending.delete(m.id) } })
await new Promise((r) => ws.addEventListener('open', r))
const send = (method, params = {}) => new Promise((res) => { const i = ++id; pending.set(i, res); ws.send(JSON.stringify({ id: i, method, params })) })
await send('Page.enable'); await send('Runtime.enable')
await send('Page.navigate', { url: "file://~/Public/deepseek-harness-project/dsh-console/design/button-variants.html" })
const evalJs = async (e) => { const r = await send('Runtime.evaluate', { expression: e, returnByValue: true }); if (r.result && r.result.exceptionDetails) throw new Error(JSON.stringify(r.result.exceptionDetails)); return r.result.result.value }
for (let i = 0; i < 30; i++) { await sleep(300); if (await evalJs("document.querySelectorAll('.row').length") >= 8) break }
const out = await evalJs(`(() => {
  const notes = [...document.querySelectorAll('.anchor-note')].map((n, i) => {
    const r = n.getBoundingClientRect()
    const cs = getComputedStyle(n)
    return { i, text: n.innerText.slice(0, 30), x: r.x, y: r.y, w: r.width, h: r.height, fs: cs.fontSize, color: cs.color, opacity: cs.opacity, visibility: cs.visibility, display: cs.display }
  })
  const sec = [...document.querySelectorAll('.variant')].map((s) => { const r = s.getBoundingClientRect(); const cs = getComputedStyle(s); return { v: s.getAttribute('data-variant'), x: r.x, y: r.y, w: r.width, h: r.height, opacity: cs.opacity, overflow: cs.overflow } })
  return { notes, sec }
})()`)
console.log(JSON.stringify(out, null, 1))
ws.close(); process.exit(0)

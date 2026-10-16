// 通用 CDP 助手：起一个无头 chromium、连上去、发命令。
import { spawn } from 'node:child_process'

export async function launch({ width = 1280, height = 900, port } = {}) {
  const p = port ?? (9300 + (process.pid % 600))
  const proc = spawn('chromium', [
    '--headless', '--no-sandbox', '--disable-gpu', '--disable-extensions',
    '--hide-scrollbars', '--remote-debugging-port=' + p,
    '--user-data-dir=/tmp/chrome-resp-' + process.pid,
    '--window-size=' + width + ',' + height,
    '--noerrdialogs', '--no-first-run', '--ozone-platform=headless',
    '--use-angle=swiftshader-webgl',
    'about:blank',
  ], { stdio: 'ignore' })

  let page = null
  for (let i = 0; i < 60 && !page; i++) {
    try {
      const list = await (await fetch('http://127.0.0.1:' + p + '/json')).json()
      page = list.find((t) => t.type === 'page')
    } catch {}
    if (!page) await new Promise((r) => setTimeout(r, 250))
  }
  if (!page) { proc.kill(); throw new Error('chromium 没起来') }

  const ws = new WebSocket(page.webSocketDebuggerUrl)
  let id = 0
  const pending = new Map()
  ws.onmessage = (e) => {
    const m = JSON.parse(e.data)
    if (m.id && pending.has(m.id)) { pending.get(m.id)(m); pending.delete(m.id) }
  }
  await new Promise((r) => { ws.onopen = r })
  const send = (method, params = {}) => new Promise((res) => {
    const i = ++id; pending.set(i, res); ws.send(JSON.stringify({ id: i, method, params }))
  })
  await send('Page.enable')
  await send('Runtime.enable')
  const close = () => { try { ws.close() } catch {} try { proc.kill() } catch {} }
  return { send, close, proc, port: p }
}

export async function evalJson(send, expression) {
  const out = await send('Runtime.evaluate', { expression, returnByValue: true, awaitPromise: true })
  if (out.result && out.result.exceptionDetails) {
    throw new Error('eval exception: ' + JSON.stringify(out.result.exceptionDetails).slice(0, 1200))
  }
  const v = out.result?.result?.value
  if (typeof v !== 'string') return v
  try { return JSON.parse(v) } catch { return v }
}

export const sleep = (ms) => new Promise((r) => setTimeout(r, ms))

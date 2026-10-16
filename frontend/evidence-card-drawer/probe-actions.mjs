// 抽屉里的按钮不是摆设：抽两个只读的抽一枪，看它真的按契约发出去 / 真的切页。
// node probe-actions.mjs <baseUrl> [outPrefix]
import { launch, evalJson, setViewport, shot, sleep } from './cdp.mjs'
import { writeFileSync } from 'node:fs'

const [baseUrl = 'http://127.0.0.1:5390/', prefix = 'actions'] = process.argv.slice(2)
const { send, close } = await launch({ width: 1440, height: 900, profile: 'act' })
await setViewport(send, 1440, 900)
await send('Page.navigate', { url: baseUrl })
await sleep(5000)

const out = { baseUrl, steps: {} }

// 「查看日志」：切到日志页，来源设成这一只实例（第三轮接上的那一项）
await evalJson(send, "(() => { const c = [...document.querySelectorAll('[data-name=\"instance-card\"]')].find((x) => x.getAttribute('data-status') === 'running'); if (c) c.click(); return !!c })()")
await sleep(500)
out.steps.beforeLogs = await evalJson(send, "JSON.stringify({ url: location.pathname + location.search, drawer: !!document.querySelector('[data-name=\"detail-drawer\"]') })")
await evalJson(send, "(() => { const b = document.querySelector('[data-action=\"logs\"]'); if (b) b.click(); return !!b })()")
await sleep(2500)
out.steps.afterLogs = await evalJson(send, "JSON.stringify({ url: location.pathname + location.search, drawer: !!document.querySelector('[data-name=\"detail-drawer\"]'), h1: document.querySelector('h1')?.textContent.trim(), select: document.querySelector('select')?.value })")
await shot(send, prefix + '-after-logs.png')

// 「复制访问地址」：走 navigator.clipboard 那条路，回执进 toast
await evalJson(send, "(() => { location.href = '/'; return true })()")
await sleep(4500)
await evalJson(send, "(() => { const c = [...document.querySelectorAll('[data-name=\"instance-card\"]')].find((x) => x.getAttribute('data-status') === 'running'); if (c) c.click(); return !!c })()")
await sleep(500)
await send('Browser.grantPermissions', { permissions: ['clipboardReadWrite', 'clipboardSanitizedWrite'] }).catch(() => {})
await evalJson(send, "(() => { const b = document.querySelector('[data-action=\"copy-url\"]'); if (b) b.click(); return !!b })()")
await sleep(1200)
out.steps.copy = await evalJson(send, "(async () => JSON.stringify({ toast: document.querySelector('.dsh-toast')?.textContent.trim() ?? null, notice: document.querySelector('.dsh-notice')?.textContent.trim() ?? null, clip: await navigator.clipboard.readText().catch((e) => 'read-failed: ' + e.message) }))()")
await shot(send, prefix + '-copy.png')

writeFileSync(prefix + '.json', JSON.stringify(out, null, 1))
console.log(JSON.stringify(out, null, 1))
close()
process.exit(0)

// 一键验收：node run-acceptance.mjs <baseUrl> [输出前缀]
// 依次跑四个探针，把结果与 Vue 基线逐条对数，打印判定表。
import { spawnSync } from 'node:child_process'
import { readFileSync, existsSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const here = dirname(fileURLToPath(import.meta.url))
const [baseUrl, prefix = '/tmp/acc', profile = join(here, 'new-selectors.draft.json')] = process.argv.slice(2)
if (!baseUrl) { console.log('用法: node run-acceptance.mjs <baseUrl> [输出前缀]'); process.exit(1) }

const run = (script, args) => {
  const r = spawnSync('node', [join(here, script), ...args], { encoding: 'utf8', timeout: 180000 })
  return r.status === 0 ? null : (r.stderr || r.stdout || '').slice(-200)
}
const j = (p) => existsSync(p) ? JSON.parse(readFileSync(p, 'utf8')) : null

const errs = []
if (run('verify-frontend.mjs', [baseUrl, prefix + '-verify.png', prefix + '-verify.json'])) errs.push('verify-frontend 失败')
if (run('probe-invariants.mjs', [baseUrl, prefix + '-inv.json', profile])) errs.push('probe-invariants 失败')
if (run('probe-logs.mjs', [baseUrl, prefix + '-logs.json', '日志', profile])) errs.push('probe-logs 失败')
if (run('probe-animation.mjs', [baseUrl, prefix + '-anim.json', '启动'])) errs.push('probe-animation 失败')
if (errs.length) console.log('探针执行问题: ' + errs.join(' / '))

const v = j(prefix + '-verify.json')
const inv = j(prefix + '-inv.json')
const logs = j(prefix + '-logs.json')
const anim = j(prefix + '-anim.json')

const vueInv = j(join(here, 'vue-baseline-rects.json'))
const vueLogs = j(join(here, 'vue-baseline-logs.json'))
const vueAnim = j(join(here, 'vue-baseline-animation.json'))

const rows = []
const add = (name, want, got, ok) => rows.push({ name, want, got, ok })

if (v) {
  add('无横向溢出', 'false', String(v.overflowX), v.overflowX === false)
  add('控制台零问题', '0', String(v.consoleIssueCount), v.consoleIssueCount === 0)
  add('真数据标记', 'true', String(v.markers?.['真实数据']), v.markers?.['真实数据'] === true)
  add('无读取失败标记', 'false', String(v.markers?.['读取失败']), v.markers?.['读取失败'] === false)
}

if (inv) {
  add('无横向溢出', String(vueInv?.overflow?.overflowX ?? false), String(inv.overflow?.overflowX), inv.overflow?.overflowX === false)
  add('状态点跨卡对齐', String(vueInv?.invariants?.dotXsAllEqual), String(inv.invariants?.dotXsAllEqual), inv.invariants?.dotXsAllEqual === true)
  add('按钮组右缘贴内容右缘', '全 0', JSON.stringify(inv.invariants?.actionsDeltas), (inv.invariants?.actionsDeltas ?? [1]).every((d) => d === 0))
  add('两段式无缝', String(vueInv?.split?.gap ?? 0), String(inv.split?.gap), inv.split ? inv.split.gap === 0 : false)
  add('菜单锚点 top+6', String(vueInv?.menu?.deltaTop ?? 6), String(inv.menu?.deltaTop), inv.menu?.deltaTop === 6)
  add('菜单锚点 right 对齐', String(vueInv?.menu?.deltaRight ?? 0), String(inv.menu?.deltaRight), inv.menu?.deltaRight === 0)
  add('菜单落焦第一项', String(vueInv?.menu?.activeIsFirstItem), String(inv.menu?.activeIsFirstItem), inv.menu?.activeIsFirstItem === true)
}
if (logs) {
  add('日志可滚动', 'true', String(logs.box && logs.box.scrollHeight > logs.box.clientHeight), !!(logs.box && logs.box.scrollHeight > logs.box.clientHeight))
  add('打开即滚到底', String(vueLogs?.box?.atBottom), String(logs.box?.atBottom), logs.box?.atBottom === true)
  add('长行横向滚动', String(vueLogs?.box?.horizontalScroll), String(logs.box?.horizontalScroll), logs.box?.horizontalScroll === true)
  add('级别配色', vueLogs?.levels?.errorColor ?? null, logs.levels?.errorColor ?? null, logs.levels?.errorColor === (vueLogs?.levels?.errorColor ?? null))
  add('来源下拉项数', String(vueLogs?.select?.options?.length ?? 4), String(logs.select?.options?.length), logs.select?.options?.length === (vueLogs?.select?.options?.length ?? 4))
  add('元信息含目录依据', 'true', String(!!(logs.meta && logs.meta.includes('目录依据'))), !!(logs.meta && logs.meta.includes('目录依据')))
}
if (anim) {
  add('点击前无可见动效', String(vueAnim?.before?.visibleCount ?? 0), String(anim.before?.visibleCount), anim.before?.visibleCount === 0)
  add('等待态恰好一个动效', String(vueAnim?.after?.count ?? 1), String(anim.after?.count), anim.after?.count === 1)
  add('等待态禁用按钮数', String(vueAnim?.after?.disabledButtons ?? 3), String(anim.after?.disabledButtons), anim.after?.disabledButtons === (vueAnim?.after?.disabledButtons ?? 3))
}

const w = Math.max(...rows.map((r) => r.name.length), 12)
console.log('判定   ' + '检查项'.padEnd(w) + '  期望(基线)                     实测')
for (const r of rows) {
  console.log((r.ok ? ' 通过  ' : ' ✗失败 ') + r.name.padEnd(w) + '  ' + String(r.want).slice(0, 30).padEnd(30) + '  ' + String(r.got))
}
const failed = rows.filter((r) => !r.ok)
console.log()
console.log('共 ' + rows.length + ' 项，通过 ' + (rows.length - failed.length) + '，失败 ' + failed.length)
if (failed.length) console.log('失败项: ' + failed.map((f) => f.name).join(' / '))
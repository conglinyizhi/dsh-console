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
// 动效探针会点「启动」真拉起一只实例。收尾放在 Node 侧：
// 无头浏览器页面里的 fetch 实测不可靠（两次都拿不到数据），Node 这边稳。
// 先记下起跑时就在跑的端口，收尾时只停这一轮新起来的。
const apiBase = baseUrl.replace(/\/$/, '')
const listPorts = async () => {
  try {
    const j = await (await fetch(apiBase + '/api/local/instances')).json()
    return (j?.data?.instances ?? []).map((i) => i.port)
  } catch (e) { return [] }
}
const portsBefore = await listPorts()
if (run('probe-logs.mjs', [baseUrl, prefix + '-logs.json', '日志', profile])) errs.push('probe-logs 失败')
if (run('probe-animation.mjs', [baseUrl, prefix + '-anim.json', '启动'])) errs.push('probe-animation 失败')
const dlgOut = spawnSync('node', [join(here, 'probe-dialog.mjs'), baseUrl], { encoding: 'utf8', timeout: 180000 })
let dlg = null
for (const line of (dlgOut.stdout || '').split('\n')) {
  if (line.startsWith('SUMMARY ')) { try { dlg = JSON.parse(line.slice(8)) } catch (e) {} }
}
if (!dlg) errs.push('对话框探针没给出 SUMMARY')

const ccOut = spawnSync('node', [join(here, 'probe-class-contract.mjs'), baseUrl], { encoding: 'utf8', timeout: 180000 })
let cc = null
try { cc = JSON.parse((ccOut.stdout || '').trim().split('\n').pop()) } catch (e) { errs.push('类名契约探针输出无法解析') }
// 收尾：等这一轮新起来的实例真的出现（有界 8 秒）再停掉，起跑时就在跑的一只不碰。
// 不这么做会两个后果：别人的机器上留一只实例 ✗；日志页默认来源被它带偏 ✗
const cleanup = { waitedMs: 0, appeared: [], stopped: [] }
try {
  const t0 = Date.now()
  let now = await listPorts()
  while (Date.now() - t0 < 8000 && !now.some((p) => !portsBefore.includes(p))) {
    await new Promise((r) => setTimeout(r, 500))
    now = await listPorts()
  }
  cleanup.waitedMs = Date.now() - t0
  cleanup.appeared = now.filter((p) => !portsBefore.includes(p))
  for (const p of cleanup.appeared) {
    try {
      const r = await fetch(apiBase + '/api/local/action', {
        method: 'POST',
        headers: { 'content-type': 'application/json', 'X-DSH-Console': '1' },
        body: JSON.stringify({ action: 'stop-instance', params: { port: p } }),
      })
      cleanup.stopped.push({ port: p, status: r.status })
    } catch (e) { cleanup.stopped.push({ port: p, error: String(e).slice(0, 60) }) }
  }
} catch (e) { cleanup.error = String(e).slice(0, 80) }
if (cleanup.appeared.length) console.log('收尾：本轮新起的实例 ' + cleanup.appeared.join(',') + ' 已停（等了 ' + cleanup.waitedMs + 'ms）')

if (errs.length) console.log('探针执行问题: ' + errs.join(' / '))

const v = j(prefix + '-verify.json')
const inv = j(prefix + '-inv.json')
const logs = j(prefix + '-logs.json')
const anim = j(prefix + '-anim.json')

const vueInv = j(join(here, 'vue-baseline-rects.json'))
const vueLogs = j(join(here, 'vue-baseline-logs.json'))
const vueAnim = j(join(here, 'vue-baseline-animation.json'))

const rows = []
const add = (name, want, got, ok) => rows.push({ name, want, got, ok, info: false })
const addInfo = (name, got) => rows.push({ name, want: '（信息，非判定）', got, ok: true, info: true })

if (v) {
  add('无横向溢出', 'false', String(v.overflowX), v.overflowX === false)
  add('控制台零问题', '0', String(v.consoleIssueCount), v.consoleIssueCount === 0)
  // 「真实数据」是迁移期的历史标签（旧前端 vs 新前端并存时标真假的），现在全页都是真读数，它就是噪声 ✗
  // 这条判定反过来：**页面不该再出现它** —— 这样它再也回不来。
  // 但「读数失败」的标记必须还在（见下一条「无读取失败标记」的相反面）：删了它，失败就会伪装成正常 ✗
  add('页面不出现「真实数据」标记', 'false', String(v.markers?.['真实数据']), v.markers?.['真实数据'] !== true)
  add('无读取失败标记', 'false', String(v.markers?.['读取失败']), v.markers?.['读取失败'] === false)
}

if (inv) {
  add('无横向溢出', String(vueInv?.overflow?.overflowX ?? false), String(inv.overflow?.overflowX), inv.overflow?.overflowX === false)
  add('状态点跨卡对齐', String(vueInv?.invariants?.dotXsAllEqual), String(inv.invariants?.dotXsAllEqual), inv.invariants?.dotXsAllEqual === true)
  add('按钮组右缘贴内容右缘', '全 0', JSON.stringify(inv.invariants?.actionsDeltas), (inv.invariants?.actionsDeltas ?? [1]).every((d) => d === 0))
  // 「两段式无缝」退役（2026-10-15，使用者决定）：
  // 那条是照 Vue 版的「启动 ▾」分段按钮录的（gap 0 / 左右半圆角 6 0 0 6 与 0 6 6 0）。
  // 分段按钮的形状暗示"有多种启动方式可选"，而我们只有一种 —— 已改成「启动」+ 独立的「⋯」，
  // 与运行中卡一致。**这是有意识放弃的基线，不是回归**；探针若拿不到分段元素，这里不再当成失败。
  if (inv.split) {
    add('两段式无缝（该形态已弃用，仍存在则顺带一量）', String(vueInv?.split?.gap ?? 0), String(inv.split.gap), inv.split.gap === 0)
  }
  add('菜单锚点 top+6', String(vueInv?.menu?.deltaTop ?? 6), String(inv.menu?.deltaTop), inv.menu?.deltaTop === 6)
  add('菜单锚点 right 对齐', String(vueInv?.menu?.deltaRight ?? 0), String(inv.menu?.deltaRight), inv.menu?.deltaRight === 0)
  add('菜单落焦第一项', String(vueInv?.menu?.activeIsFirstItem), String(inv.menu?.activeIsFirstItem), inv.menu?.activeIsFirstItem === true)
  const unreachable = (inv.menu?.itemsReachable ?? []).filter((x) => !x.reachable).map((x) => x.text)
  add('菜单每项都可点到', '0 项不可达', unreachable.length ? unreachable.join(',') : '0 项不可达', (inv.menu?.itemsReachable ?? []).length > 0 && unreachable.length === 0)
  // 靠底部那张卡的菜单：往下展开会越出视口被截（使用者报过一次）。
  // 只测第一张卡是这个盲区的来源 —— 同一模式要测到边界那一格。
  const lm = inv.menuLast
  if (lm && lm.opened) {
    add('底部卡的菜单不出屏', 'true', String(lm.insideViewport), lm.insideViewport === true)
    const un2 = (lm.itemsReachable ?? []).filter((x) => !x.reachable).map((x) => x.text)
    add('底部卡的菜单每项可点到', '0 项不可达', un2.length ? un2.join(',') : '0 项不可达', (lm.itemsReachable ?? []).length > 0 && un2.length === 0)
  } else {
    addInfo('底部卡的菜单（没量到：可能只有一张卡）', String(lm?.opened))
  }
}
if (logs) {
  // 这两条取决于当前默认来源那个日志文件有多长：实例日志可能只有 1 行，行数不够自然滚不动。
  const box = logs.box
  if (box && box.scrollHeight > box.clientHeight) {
    add('日志可滚动', 'true', 'true', true)
    add('长行横向滚动', String(vueLogs?.box?.horizontalScroll), String(box.horizontalScroll), box.horizontalScroll === true)
  } else {
    addInfo('日志可滚动 / 长行横向滚动（当前来源只有 ' + (logs.lineCount ?? 0) + ' 行，无从验证）', '行数不够')
  }
  add('打开即滚到底', String(vueLogs?.box?.atBottom), String(box?.atBottom), box?.atBottom === true)
  // 这条判定的前提是「窗口里真有错误行」。实时日志窗口的级别分布会变，
  // 没有 error 行时 errorColor 必然是 null——那不是回归，是无从验证。
  const errRows = logs.levels?.error ?? 0
  if (errRows > 0) {
    add('级别配色', vueLogs?.levels?.errorColor ?? null, logs.levels?.errorColor ?? null, logs.levels?.errorColor === (vueLogs?.levels?.errorColor ?? null))
  } else {
    addInfo('级别配色（窗口里 0 条 error 行，无从验证）', 'error 行 ' + errRows)
  }
  // 下拉项数取决于当时有几只实例在跑 —— 基线里那个 4 是「1 只实例 + 分隔 + 宿主 + 审计」，
  // 拿它当固定期望是错的（并行起一只实例就会挂）。改成从实时数据推期望。
  // 用探针抓取那一刻记下的实例数（同一时刻），不再另起一次 fetch —— 那会拿到"另一个时刻"的数据 ✗
  const live = logs.instancesAtRead ?? null
  const opts = logs.select?.options ?? []
  const vals = opts.map((o) => o.value)
  const instOpts = vals.filter((v) => typeof v === 'string' && v.startsWith('instance:'))
  if (live === null) {
    addInfo('来源下拉（读不到实例列表，无从推算期望）', String(opts.length) + ' 项')
  } else {
    add('来源下拉含全部在跑实例', live.length + ' 只', instOpts.length + ' 项', instOpts.length >= live.length)
    add('来源下拉含固定来源', 'host + audit', vals.filter((v) => v === 'host' || v === 'audit').join(' + ') || '无',
      vals.includes('host') && vals.includes('audit'))
  }
  // 「目录依据」只在来源是实例时才渲染（来源是 host 时后端给 kind=fixed，没有 homeSource）。
  // 验收把来源钉死成 host（为了让判据不随在跑实例增删而变），所以这里判一条与来源无关的，
  // 目录依据如实记为信息 —— 验不了就说验不了，不留假红灯 ✗
  add('元信息含来源与路径', 'true', String(!!(logs.meta && logs.meta.includes('行') && logs.meta.includes('/'))),
    !!(logs.meta && logs.meta.includes('行') && logs.meta.includes('/')))
  addInfo('目录依据（只在实例来源渲染；本轮验收量的是 host 来源）',
    logs.meta && logs.meta.includes('目录依据') ? '出现了' : '未出现（预期）')
}
if (anim) {
  add('点击前无可见动效', String(vueAnim?.before?.visibleCount ?? 0), String(anim.before?.visibleCount), anim.before?.visibleCount === 0)
  add('等待态恰好一个动效', String(vueAnim?.after?.count ?? 1), String(anim.after?.count), anim.after?.count === 1)
  add('等待态禁用按钮数', String(vueAnim?.after?.disabledButtons ?? 3), String(anim.after?.disabledButtons), anim.after?.disabledButtons === (vueAnim?.after?.disabledButtons ?? 3))
}

if (dlg) {
  // 这一组是「看得见但用不了」的克星：位置不对/被遮罩盖住，键盘能过但鼠标点不到。
  // **但先说前置条件**：入口必须真的把框开出来过。
  // 否则「没框所以框关着」会让后面四条全绿 —— 那是假通过，比红灯危险 ✗
  const opened = dlg.opened === true
  add('对话框入口能开框（后面四条的判据）', 'true', String(opened), opened)
  add('对话框居中', 'true', String(dlg.centered), opened && dlg.centered === true)
  add('对话框在最上层可点', 'true', String(dlg.onTop), opened && dlg.onTop === true)
  add('取消键能关', 'true', String(dlg.closedByCancel), opened && dlg.closedByCancel === true)
  add('点遮罩能关', 'true', String(dlg.closedByScrim), opened && dlg.closedByScrim === true)
}
if (cc) {
  // 这是**候选发现器**，不是判决器：无规则的类未必是缺陷（容器、继承样式的 span 都属正常）。
  // 已知合理：notranslate（翻译排除）、v-card--density-default（默认密度不加规则）。
  // 曾经的两个例外（notranslate / v-card--density-default）随 md2 一起消失了，
  // 现在这里不该再放任何白名单：有例外就得说清为什么。
  const known = []
  const candidates = (cc.missing || []).filter((c) => !known.includes(c))
  addInfo('类名契约候选（无规则的类）', candidates.length ? candidates.join(',') : '无')
  addInfo('DOM 类总数', String(cc.totalClasses))
}

const w = Math.max(...rows.map((r) => r.name.length), 12)
console.log('判定   ' + '检查项'.padEnd(w) + '  期望(基线)                     实测')
for (const r of rows) {
  const mark = r.info ? ' 信息  ' : (r.ok ? ' 通过  ' : ' ✗失败 ')
  console.log(mark + r.name.padEnd(w) + '  ' + String(r.want).slice(0, 30).padEnd(30) + '  ' + String(r.got))
}
const failed = rows.filter((r) => !r.ok && !r.info)
console.log()
const judged = rows.filter((r) => !r.info).length
console.log('判定 ' + judged + ' 项：通过 ' + (judged - failed.length) + '，失败 ' + failed.length + '；另有信息 ' + (rows.length - judged) + ' 条')
if (failed.length) console.log('失败项: ' + failed.map((f) => f.name).join(' / '))
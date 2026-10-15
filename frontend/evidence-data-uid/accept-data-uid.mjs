// data-name / data-uid 验收：唯一性、稳定性、顺序无关、对照表。
//
//   node accept-data-uid.mjs <baseUrl> <outJson> [翻转 mtime 的 profile 名]
//
// 量的是**跑起来的页面**，不是代码：CDP 起一个无头 chromium，逐个状态枚举
// 所有 [data-uid]，把结论落成 JSON。
//
// 五个判定：
//   1. 唯一性    每个状态下 data-uid 零重复
//   2. 稳定性    每个状态刷新两次，同一个语义元素两次的 uid 相同
//   3. 顺序无关  把一个 profile 目录的 mtime 推新（已停止组按 mtime 降序），
//                卡片顺序真变了之后，各元素 uid 一个都不许变；改完还原
//   4. 对照表    「语义路径 → uid」，路径是从 DOM 上读出来的角色 + 该项自己的键
//   5. 元素总数  每个状态贴出来
//
// 语义身份的取法（比对两次抓取时用，与 uid 无关）：
//   元素自己的 data-name，加上它所在卡片（最近的 [data-instance]）、
//   所在对话框（最近的 [data-name$="-dialog"]）、以及它自己的键属性
//   （data-action / data-field / data-group / data-setting / option 的 value）。
//   **不含位置**：不拿第几个孩子、不拿列表下标 —— 顺序变了身份不该变。
//   也不含文本：卡片上「最近改动」的值会随 mtime 翻转而变，那是内容不是身份。
import { spawn, execFileSync } from 'node:child_process'
import { writeFileSync, readFileSync, existsSync } from 'node:fs'

const CDP_PORT = 9300 + (process.pid % 600)
const [baseUrl, outJson, flipProfile = 'web'] = process.argv.slice(2)
if (!baseUrl) {
  console.log('用法: node accept-data-uid.mjs <baseUrl> <outJson> [profile]')
  process.exit(1)
}

const chrome = spawn('chromium', ['--headless', '--no-sandbox', '--disable-gpu', '--disable-extensions',
  '--hide-scrollbars', '--remote-debugging-port=' + CDP_PORT, '--user-data-dir=/tmp/chrome-uid-' + process.pid,
  '--window-size=1400,1000', 'about:blank'], { stdio: 'ignore' })

let page = null
for (let i = 0; i < 60 && !page; i++) {
  try {
    const list = await (await fetch('http://127.0.0.1:' + CDP_PORT + '/json')).json()
    page = list.find((t) => t.type === 'page')
  } catch {}
  if (!page) await new Promise((r) => setTimeout(r, 250))
}
if (!page) { console.log(JSON.stringify({ ok: false, error: 'chrome 没起来' })); process.exit(1) }

const ws = new WebSocket(page.webSocketDebuggerUrl)
let id = 0
const pending = new Map()
ws.onmessage = (e) => {
  const m = JSON.parse(e.data)
  if (m.id && pending.has(m.id)) { pending.get(m.id)(m); pending.delete(m.id) }
}
await new Promise((r) => { ws.onopen = r })
const send = (method, params = {}) => new Promise((res) => { const i = ++id; pending.set(i, res); ws.send(JSON.stringify({ id: i, method, params })) })

await send('Runtime.enable')
await send('Page.enable')
await send('Emulation.setDeviceMetricsOverride', { width: 1400, height: 1000, deviceScaleFactor: 1, mobile: false })

const sleep = (ms) => new Promise((r) => setTimeout(r, ms))
const ev = async (expression) => {
  const r = await send('Runtime.evaluate', { expression, returnByValue: true, awaitPromise: true })
  if (r.result?.exceptionDetails) throw new Error(JSON.stringify(r.result.exceptionDetails).slice(0, 300))
  return r.result?.result?.value
}
const waitFor = async (expr, timeoutMs = 15000) => {
  const t0 = Date.now()
  while (Date.now() - t0 < timeoutMs) {
    if (await ev('!!(' + expr + ')')) return true
    await sleep(200)
  }
  return false
}
const reload = async () => {
  await send('Page.navigate', { url: baseUrl })
  await waitFor("document.querySelector('[data-name=\"overview-page\"]')", 20000)
  await sleep(700)
}

// ── 抓取 ────────────────────────────────────────────────────
const CAPTURE = `(() => {
  const keyOf = (el) => {
    const card = el.closest('[data-instance]')
    const dlg = el.closest('[data-name$="-dialog"]')
    const own = ['action','field','group','setting','instance','mark','status','ok','state']
      .map((a) => el.getAttribute('data-' + a)).filter((v) => v !== null && v !== '').join('/')
    const val = el.tagName === 'OPTION' ? (el.getAttribute('value') || '') : ''
    return [card ? 'card=' + card.getAttribute('data-instance') : '',
            dlg ? 'dlg=' + dlg.getAttribute('data-name') : '',
            own ? 'own=' + own : '', val ? 'val=' + val : ''].filter(Boolean).join(' ')
  }
  const nodes = [...document.querySelectorAll('[data-uid]')]
  return JSON.stringify({
    count: nodes.length,
    items: nodes.map((el) => ({
      uid: el.getAttribute('data-uid'),
      name: el.getAttribute('data-name') || '(无名)',
      identity: (el.getAttribute('data-name') || '(无名)') + ' :: ' + keyOf(el),
      tag: el.tagName.toLowerCase(),
      text: (el.textContent || '').replace(/\\s+/g, ' ').trim().slice(0, 24),
    })),
  })
})()`

const capture = async () => JSON.parse(await ev(CAPTURE))

// ── 状态 ────────────────────────────────────────────────────
// 每个状态：先回到干净的一页，再把它摆成那个样子，然后抓一遍。
const STATES = [
  {
    name: '初始页（实例总览）',
    setup: async () => { await reload() },
  },
  {
    name: '展开行菜单',
    setup: async () => {
      await reload()
      const ok = await ev(`(() => {
        const card = [...document.querySelectorAll('[data-name="instance-card"]')]
          .find((c) => c.querySelector('[data-name="sub-line"][data-status="stopped"]'))
        if (!card) return false
        const b = card.querySelector('[data-name="menu-trigger"]')
        if (!b) return false
        b.click()
        return true
      })()`)
      if (!ok) throw new Error('找不到已停止卡上的 ⋯ 触发按钮')
      if (!await waitFor("document.querySelector('[data-name=\"row-menu\"]')")) throw new Error('菜单没打开')
      await sleep(300)
    },
  },
  {
    name: '打开对话框（重命名）',
    setup: async () => {
      await reload()
      const ok = await ev(`(() => {
        const card = [...document.querySelectorAll('[data-name="instance-card"]')]
          .find((c) => c.querySelector('[data-name="sub-line"][data-status="stopped"]'))
        if (!card) return false
        card.querySelector('[data-name="menu-trigger"]').click()
        return true
      })()`)
      if (!ok) throw new Error('找不到已停止卡')
      if (!await waitFor("document.querySelector('[data-name=\"row-menu\"]')")) throw new Error('菜单没打开')
      const clicked = await ev(`(() => {
        const it = [...document.querySelectorAll('[data-name="row-menu"] [data-name="menu-item"]')]
          .find((e) => e.textContent.trim() === '重命名')
        if (!it) return false
        it.click()
        return true
      })()`)
      if (!clicked) throw new Error('菜单里没有「重命名」')
      if (!await waitFor("document.querySelector('[data-name=\"rename-dialog\"]')")) throw new Error('重命名框没打开')
      await sleep(300)
    },
  },
  {
    name: '设置页',
    setup: async () => {
      await reload()
      await ev("document.querySelector('[data-name=\"nav-settings\"]').click()")
      if (!await waitFor("document.querySelector('[data-name=\"settings-page\"]')")) throw new Error('设置页没出来')
      await sleep(900)
    },
  },
  {
    name: '日志页',
    setup: async () => {
      await reload()
      await ev("document.querySelector('[data-name=\"nav-logs\"]').click()")
      if (!await waitFor("document.querySelector('[data-name=\"logs-page\"]')")) throw new Error('日志页没出来')
      await sleep(900)
    },
  },
  {
    name: '关于页',
    setup: async () => {
      await reload()
      await ev("document.querySelector('[data-name=\"nav-about\"]').click()")
      if (!await waitFor("document.querySelector('[data-name=\"about-page\"]')")) throw new Error('关于页没出来')
      await sleep(700)
    },
  },
  {
    name: '展开归档区',
    optional: true,
    setup: async () => {
      await reload()
      if (!await ev("!!document.querySelector('[data-name=\"archived-toggle\"]')")) return 'skip'
      await ev("document.querySelector('[data-name=\"archived-toggle\"]').click()")
      if (!await waitFor("document.querySelector('[data-name=\"archived-row\"]')")) return 'skip'
      await sleep(300)
      return 'ok'
    },
  },
]

const runPass = async (label) => {
  const out = {}
  for (const st of STATES) {
    try {
      const res = await st.setup()
      if (res === 'skip') { out[st.name] = { skipped: true }; continue }
      out[st.name] = await capture()
    } catch (e) {
      out[st.name] = { error: String(e.message || e) }
    }
  }
  return out
}

console.log('== 第一遍 ==')
const passA = await runPass('A')
console.log('== 第二遍（每个状态重新加载后再抓）==')
const passB = await runPass('B')

// ── 判定 1：唯一性 ──────────────────────────────────────────
const uniqueness = {}
for (const [state, cap] of Object.entries(passA)) {
  if (cap.skipped) { uniqueness[state] = { skipped: true }; continue }
  if (cap.error) { uniqueness[state] = { error: cap.error }; continue }
  const seen = new Map()
  const dup = []
  for (const it of cap.items) {
    if (seen.has(it.uid)) dup.push({ uid: it.uid, a: seen.get(it.uid), b: it.name + ' / ' + it.text })
    else seen.set(it.uid, it.name + ' / ' + it.text)
  }
  uniqueness[state] = { total: cap.count, distinct: seen.size, duplicates: dup }
  console.log(`  [唯一性] ${state}: 元素 ${cap.count} 个，去重后 ${seen.size} 个，重复 ${dup.length}`)
}

// ── 判定 2：稳定性 ──────────────────────────────────────────
// identity → 该身份下所有 uid（升序）。两次抓取逐身份比。
const byIdentity = (cap) => {
  const m = new Map()
  for (const it of cap.items) {
    if (!m.has(it.identity)) m.set(it.identity, [])
    m.get(it.identity).push(it.uid)
  }
  for (const v of m.values()) v.sort()
  return m
}
const stability = {}
let stableCount = 0
for (const state of Object.keys(passA)) {
  const a = passA[state], b = passB[state]
  if (a.skipped || b.skipped) { stability[state] = { skipped: true }; continue }
  if (a.error || b.error) { stability[state] = { error: a.error || b.error }; continue }
  const ma = byIdentity(a), mb = byIdentity(b)
  const mismatched = []
  for (const [ident, uids] of ma) {
    const other = mb.get(ident)
    if (!other) { mismatched.push({ identity: ident, a: uids, b: null }); continue }
    if (JSON.stringify(uids) !== JSON.stringify(other)) mismatched.push({ identity: ident, a: uids, b: other })
  }
  for (const ident of mb.keys()) if (!ma.has(ident)) mismatched.push({ identity: ident, a: null, b: mb.get(ident) })
  const compared = [...ma.values()].reduce((n, v) => n + v.length, 0)
  stableCount += compared
  stability[state] = { compared, mismatched }
  console.log(`  [稳定性] ${state}: 比对 ${compared} 个元素，不一致 ${mismatched.length}`)
}

// 同名不同卡：两张卡上的同名按钮，uid 必须不同
const sameNameDiffCard = []
{
  const cap = passA['初始页（实例总览）']
  if (cap && !cap.error && !cap.skipped) {
    const groups = new Map()
    for (const it of cap.items) {
      const k = it.name + ' :: ' + (it.identity.split(' ').find((p) => p.startsWith('card=')) || '')
      if (!groups.has(it.name)) groups.set(it.name, new Map())
      groups.get(it.name).set(k, it.uid)
    }
    for (const [name, m] of groups) {
      const uids = [...m.values()]
      if (uids.length >= 2) {
        sameNameDiffCard.push({ name, perCard: Object.fromEntries(m), allDistinct: new Set(uids).size === uids.length })
      }
    }
  }
}

// ── 判定 3：顺序无关 ────────────────────────────────────────
const order = { profile: flipProfile }
{
  const dir = `${process.env.HOME}/.dsh/profiles/${flipProfile}`
  const orderOf = async () => ev(`JSON.stringify([...document.querySelectorAll('[data-name="instance-card"]')].map((c) => c.getAttribute('data-instance')))`).then(JSON.parse)
  await reload()
  const before = { uids: await capture(), cards: await orderOf() }
  order.beforeCards = before.cards
  let touched = false
  try {
    const stat = execFileSync('stat', ['-c', '%y', dir], { encoding: 'utf8' }).trim()
    order.originalMtime = stat
    execFileSync('touch', ['-d', '2030-01-01 00:00:00', dir])
    touched = true
    order.touched = `touch -d 2030-01-01 00:00:00 ${dir}`
    await reload()
    const after = { uids: await capture(), cards: await orderOf() }
    order.afterCards = after.cards
    order.orderChanged = JSON.stringify(before.cards) !== JSON.stringify(after.cards)
    const ma = byIdentity(before.uids), mb = byIdentity(after.uids)
    const changed = []
    for (const [ident, uids] of ma) {
      const other = mb.get(ident)
      if (!other) { changed.push({ identity: ident, a: uids, b: null }); continue }
      if (JSON.stringify(uids) !== JSON.stringify(other)) changed.push({ identity: ident, a: uids, b: other })
    }
    order.changedUids = changed
    order.compared = [...ma.values()].reduce((n, v) => n + v.length, 0)
    console.log(`  [顺序无关] 卡片顺序变了: ${order.orderChanged}；比对 ${order.compared} 个元素，uid 变了 ${changed.length}`)
  } catch (e) {
    order.error = String(e.message || e)
  } finally {
    if (touched) {
      try {
        execFileSync('touch', ['-d', order.originalMtime, dir])
        order.restored = execFileSync('stat', ['-c', '%y', dir], { encoding: 'utf8' }).trim() === order.originalMtime
      } catch (e) { order.restoreError = String(e.message || e) }
    }
    order.restoreNote = `touch -d "${order.originalMtime}" ${dir}`
  }
}

// ── 判定 4：对照表 ──────────────────────────────────────────
const table = []
for (const [state, cap] of Object.entries(passA)) {
  if (cap.skipped || cap.error) continue
  for (const it of cap.items) {
    table.push({ state, identity: it.identity, name: it.name, uid: it.uid, tag: it.tag, sample: it.text })
  }
}

const result = {
  baseUrl,
  states: Object.fromEntries(Object.entries(passA).map(([k, v]) => [k, v.skipped ? { skipped: true } : v.error ? { error: v.error } : { total: v.count }])),
  uniqueness,
  stability,
  sameNameDiffCard,
  order,
  tableSize: table.length,
  table,
}
if (outJson) writeFileSync(outJson, JSON.stringify(result, null, 1))
console.log(JSON.stringify({
  uniqueness: Object.fromEntries(Object.entries(uniqueness).map(([k, v]) => [k, v.skipped ? 'skipped' : v.error ? 'error' : `${v.total}/${v.duplicates.length}`])),
  stability: Object.fromEntries(Object.entries(stability).map(([k, v]) => [k, v.skipped ? 'skipped' : v.error ? 'error' : `${v.compared}/${v.mismatched.length}`])),
  order: { changed: order.orderChanged, uidChanged: order.changedUids?.length, restored: order.restored },
  tableSize: table.length,
}, null, 1))
chrome.kill()
process.exit(0)

// 三色状态灯的实测：node probe-states.mjs <baseUrl> [outPrefix]
//
// 量的是**计算样式**（getComputedStyle 的 backgroundColor），不是看截图认颜色。
// 每一档同时抓两样东西：卡片上那颗灯的样式/档位，与抽屉里那句「为什么是这个颜色」。
//
// 数据从哪来：
//   * 绿 —— 3080 那只真实例（签名探测真的通过）。state 字段由 fixture 按契约补上。
//   * 黄 b —— 本进程真起一个「端口在听、cmdline 像 dsh、签名探测不通过」的假进程，
//             fixture 按契约把它列成一条 state=fault 的实例。
//   * 黄 c —— 真实的 profile 读数：缺包的 profile（review-dev）。
//   * 红 —— 真实的 profile 读数：不缺包、patch 也在的 profile（headless）。
// 后两档用的是真数据，前端照契约的判据自己算 —— 它们不需要后端那三个新字段。
import { launch, evalJson, setViewport, shot, sleep } from './cdp.mjs'
import { startFakeDsh, instancesPatchSource } from './fixture.mjs'
import { writeFileSync, readFileSync } from 'node:fs'
import { createServer } from 'node:net'

const [baseUrl = 'http://127.0.0.1:5390/', prefix = 'states'] = process.argv.slice(2)

const freePort = () => new Promise((res) => {
  const s = createServer()
  s.listen(0, '127.0.0.1', () => { const p = s.address().port; s.close(() => res(p)) })
})

const fakePort = await freePort()
const fake = startFakeDsh(fakePort, prefix + '-fake.pid')
await sleep(500)

// 假 dsh 真的在听、而且真的过不了 dsh 的签名探测 —— 这两条是「成因 b」的前提，先证下来。
const fakeProbe = await (async () => {
  try {
    const r = await fetch('http://127.0.0.1:' + fakePort + '/', { signal: AbortSignal.timeout(3000) })
    return { status: r.status, contentType: r.headers.get('content-type'), body: (await r.text()).slice(0, 60) }
  } catch (e) { return { error: String(e).slice(0, 120) } }
})()
let fakeCmdline = ''
try { fakeCmdline = readFileSync('/proc/' + fake.pid + '/cmdline', 'utf8').split('\0').join(' ').trim() } catch {}

// 绿的 3080 **不注入**：后端这一版已经把 state / stateReason / profileHealth 发出来了，
// 那一档用的是真读数（探针只往响应里**追加**下面那条造出来的故障实例）。
// 黄 c 与红用的也是真读数（profile 缺包 / 不缺包），一个字段都没造。
const spec = {
  byPort: {},
  extra: [{
    id: 'proc-' + fakePort,
    port: fakePort,
    url: 'http://127.0.0.1:' + fakePort + '/',
    title: null,
    httpStatus: fakeProbe.status ?? null,
    contentType: fakeProbe.contentType ?? null,
    signature: { id: '', describe: '没有命中任何 DSH 签名', evidence: String(fakeProbe.body || '').slice(0, 60) },
    profile: 'web',
    pid: fake.pid,
    dshHome: '~/.dsh',
    exePath: fakeCmdline.split(' ')[1] || '',
    startedAt: null,
    uptimeSeconds: null,
    probeMs: 1,
    inode: null,
    version: null,
    versionSource: '这一条是探针造的：假 dsh 没有入口包',
    profileSource: 'PID ' + fake.pid + ' 的 cmdline：--profile web（探针按契约补的口径）',
    dshHomeSource: '探针按契约补的口径',
    processReason: { code: 'port-join', message: '端口对应的 socket inode 在 /proc/<pid>/fd 里对到了持有进程' },
    webUrl: null,
    webUrlSource: '外部实例：令牌在启动它的终端里',
    state: 'fault',
    stateReason: '端口在听、持有它的进程 cmdline 看着是 dsh，但签名探测不通过（HTTP ' + (fakeProbe.status ?? '?') + ' ' + (fakeProbe.contentType ?? '') + '，没有命中任何签名）',
    // 与这只实例解析出的 profile（web，真读数：缺 3 个包）保持一致：
    // 造一份「说它不缺包」的健康读数，就与同一张抽屉里的插件读数自相矛盾了。
    // 握手这一条照样落在句子的前半句（「端口在听，但不应答 dsh 的握手」）。
    profileHealth: { missingBundles: 3, hasPatch: true },
  }],
}

const { send, close } = await launch({ width: 1440, height: 900, profile: 'states' })
await send('Page.addScriptToEvaluateOnNewDocument', { source: instancesPatchSource(spec) })
await setViewport(send, 1440, 900)
await send('Page.navigate', { url: baseUrl })
await sleep(5000)

const readCards = `(() => {
  const cards = [...document.querySelectorAll('[data-name="instance-card"]')]
  return JSON.stringify(cards.map((c) => {
    const dot = c.querySelector('.dsh-dot')
    const cs = dot ? getComputedStyle(dot) : null
    return {
      id: c.id,
      name: c.querySelector('.dsh-name')?.textContent.trim() ?? null,
      dataLight: c.getAttribute('data-light'),
      dataStatus: c.getAttribute('data-status'),
      dotState: dot ? dot.getAttribute('data-state') : null,
      dotClass: dot ? dot.className : null,
      dotBg: cs ? cs.backgroundColor : null,
      dotSize: cs ? cs.width + 'x' + cs.height : null,
      dotAria: dot ? dot.getAttribute('aria-label') : null,
      note: c.querySelector('[data-name="card-note"]')?.textContent.trim() ?? null,
      text: c.textContent.trim(),
    }
  }))
})()`

const openDrawer = (i) => `(() => {
  const cards = [...document.querySelectorAll('[data-name="instance-card"]')]
  const c = cards[${i}]
  if (!c) return 'no-card'
  c.click()
  return 'clicked'
})()`

const readDrawer = `(() => {
  const d = document.querySelector('[data-name="detail-drawer"]')
  if (!d) return JSON.stringify({ open: false })
  const cs = getComputedStyle(d)
  const r = d.getBoundingClientRect()
  const light = d.querySelector('.dsh-dot')
  const lcs = light ? getComputedStyle(light) : null
  return JSON.stringify({
    open: true,
    id: d.id, role: d.getAttribute('role'), ariaModal: d.getAttribute('aria-modal'),
    width: +r.width.toFixed(1), right: +r.right.toFixed(1), viewportW: innerWidth,
    position: cs.position,
    lightState: d.getAttribute('data-light'),
    lightBg: lcs ? lcs.backgroundColor : null,
    lightLabel: d.querySelector('.dsh-drawer-light-label')?.textContent.trim() ?? null,
    why: d.querySelector('[data-name="drawer-why"]')?.textContent.trim() ?? null,
    // 技术依据在悬停里：正文一个字不占（哪一条握手应答命中、探测回来的是什么）
    whyHover: d.querySelector('[data-name="drawer-why"]')?.getAttribute('title') ?? null,
    dotHover: d.querySelector('.dsh-dot')?.getAttribute('title') ?? null,
    dotAria: d.querySelector('.dsh-dot')?.getAttribute('aria-label') ?? null,
    health: d.querySelector('[data-name="drawer-health"]')?.textContent.trim() ?? null,
    // 抽屉全文：可见文字 + 每一处悬停（这就是使用者真能读到的全部）
    // 逐行收：空行去掉。这一段是模板字符串，反斜杠转义会被吃掉，所以这里一个都不用
    text: d.innerText.split(String.fromCharCode(10)).filter((s) => s.trim().length > 0).join(String.fromCharCode(10)),
    hovers: [...d.querySelectorAll('[title], [aria-label]')].map((e) => ({
      name: e.getAttribute('data-name') || '', title: e.getAttribute('title') || '', aria: e.getAttribute('aria-label') || '',
    })),
    fieldCount: d.querySelectorAll('[data-name="drawer-field"]').length,
    fieldLabels: [...d.querySelectorAll('[data-name="drawer-field"]')].map((f) => f.querySelector('.dsh-field-label').textContent.trim()),
    buttons: [...d.querySelectorAll('.dsh-drawer-body button, .dsh-drawer-head button')].map((b) => ({
      action: b.getAttribute('data-action') || 'close',
      text: b.textContent.trim(),
      disabled: b.disabled,
      reachable: (() => {
        const r = b.getBoundingClientRect()
        const hit = document.elementFromPoint(r.x + r.width / 2, r.y + r.height / 2)
        return !!(hit && (hit === b || b.contains(hit)))
      })(),
    })),
    activeElement: (() => { const a = document.activeElement; return a ? (a.id || a.className || a.tagName) : null })(),
  })
})()`

const cardsRaw = await evalJson(send, readCards)
const cards = Array.isArray(cardsRaw) ? cardsRaw : []
const out = { baseUrl, fakePort, fakeProbe, fakeCmdline, fakePid: fake.pid, cards, drawers: {} }

// 每一张卡都开一次抽屉：档位、那句为什么、六格读数、按钮可达性
const shots = { running: 'drawer-green', fault: 'drawer-fault-b', 'fault-c': 'drawer-fault-c', stopped: 'drawer-stopped' }
for (let i = 0; i < cards.length; i++) {
  const c = cards[i]
  await evalJson(send, openDrawer(i))
  await sleep(500)
  const dRaw = await evalJson(send, readDrawer)
  const d = dRaw && typeof dRaw === 'object' ? dRaw : {}
  const key = c.dotClass?.includes('light-unknown') ? 'unknown'
    : c.dotClass?.includes('light-fault') ? (c.name.includes(':' + fakePort) ? 'fault' : 'fault-c')
    : c.dotClass?.includes('light-run') ? 'running' : 'stopped'
  out.drawers[key] = { card: c, drawer: d }
  if (shots[key]) await shot(send, prefix + '-' + shots[key] + '.png')
  // 收起来（点关闭键）
  await evalJson(send, "(() => { const b = document.getElementById('dsh-drawer-close'); if (b) b.click(); return true })()")
  await sleep(400)
}

await shot(send, prefix + '-cards.png')
out.consoleIssues = (await Promise.resolve([]))
writeFileSync(prefix + '.json', JSON.stringify(out, null, 1))
console.log(JSON.stringify({
  fakeProbe, fakeCmdline,
  cards: cards.map((c) => ({ name: c.name, light: c.dotClass, bg: c.dotBg, state: c.dotState, aria: c.dotAria })),
  drawers: Object.fromEntries(Object.entries(out.drawers).map(([k, v]) => [k, {
    label: v.drawer.lightLabel, bg: v.drawer.lightBg, why: v.drawer.why,
    whyHover: v.drawer.whyHover, health: v.drawer.health,
    fields: v.drawer.fieldCount, buttons: v.drawer.buttons?.length,
    unreachable: (v.drawer.buttons || []).filter((b) => !b.reachable).map((b) => b.text),
    active: v.drawer.activeElement, width: v.drawer.width, vw: v.drawer.viewportW,
  }])),
}, null, 1))

close()
try { process.kill(fake.pid, 'SIGTERM') } catch {}
process.exit(0)

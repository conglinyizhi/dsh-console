// 量「一行自己的 home」：抽屉里 DSH_HOME 那一格 + 「复制开发指令」的剪贴板回读。
//
// 用法：
//   node probe-home-own.mjs <baseUrl> <mode> [target] [outPrefix]
//     mode = real                 不注入，量当前后端的真实读数
//          = profiles-home:<路径>  把 /api/local/profiles 的 dshHome 换成 <路径>
//                                  **桩**：模拟跨 home 聚合之后的读数（这批 profile 属于另一个 home）
//          = strip-profiles-home  把 profiles 响应里的 dshHome / dshHomeSource 删掉
//                                  **桩**：读数没给 home（复现「home 认不出」那一支，缺键不编值）
//     target = 要看的那一行：行 id 或卡上名字的子串（默认取第一张卡）
//     outPrefix 默认 /tmp/home-own
//     actionName = 复制之后可选再点一颗抽屉按钮（如 drawer-start），看它发出去的 params
//
// 三件事都从**页面里**取，不从我们这边的参数推：
//   1. 卡片的行 id / 名字 / 状态灯档位（确认量的是哪一张）；
//   2. 抽屉里六格读数的标签与值（DSH_HOME 那一格的实际文本 + 悬停原文）；
//   3. 「复制开发指令」点下去之后的**剪贴板回读**（不是页面里那个字符串）。
//      点之前先往剪贴板写一个哨兵串：回读还是哨兵 = 这一枪什么都没写进去 ✓
//      （拼不出说明时前端就该这样，而不是塞一段错的进去）。
import { spawn } from 'node:child_process'
import { readFileSync, writeFileSync } from 'node:fs'

const CDP_PORT = 9500 + (process.pid % 400)
const [baseUrl, mode = 'real', target = '', outPrefix = '/tmp/home-own', actionName = ''] = process.argv.slice(2)
if (!baseUrl) { console.log('用法: node probe-home-own.mjs <baseUrl> [mode] [target] [outPrefix]'); process.exit(1) }

const chrome = spawn('chromium', ['--headless', '--no-sandbox', '--disable-gpu', '--disable-extensions',
  '--hide-scrollbars', '--remote-debugging-port=' + CDP_PORT, '--user-data-dir=/tmp/chrome-homeown-' + process.pid,
  '--window-size=1280,1000', 'about:blank'], { stdio: 'ignore' })

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
const consoleIssues = []
ws.onmessage = (e) => {
  const m = JSON.parse(e.data)
  if (m.method === 'Runtime.consoleAPICalled' && ['error', 'warning'].includes(m.params?.type)) {
    consoleIssues.push(m.params.type + ': ' + (m.params.args || []).map((a) => a.value ?? a.description ?? '').join(' ').slice(0, 200))
  }
  if (m.method === 'Log.entryAdded' && m.params?.entry?.level === 'error') {
    consoleIssues.push('log: ' + String(m.params.entry.text).slice(0, 200))
  }
  if (m.id && pending.has(m.id)) { pending.get(m.id)(m); pending.delete(m.id) }
}
await new Promise((r) => { ws.onopen = r })
const send = (method, params = {}) => new Promise((res) => { const i = ++id; pending.set(i, res); ws.send(JSON.stringify({ id: i, method, params })) })
const ev = async (expr) => {
  const r = await send('Runtime.evaluate', { expression: expr, returnByValue: true, awaitPromise: true })
  return r.result?.result?.value
}

await send('Runtime.enable')
await send('Log.enable')
await send('Page.enable')
await send('Emulation.setDeviceMetricsOverride', { width: 1280, height: 1000, deviceScaleFactor: 1, mobile: false })
const origin = new URL(baseUrl).origin
const grant = await send('Browser.grantPermissions', { origin, permissions: ['clipboardReadWrite', 'clipboardSanitizedWrite'] })

// 记录器：所有模式都装。它只**看**前端发出去的请求体（不改、不拦），
// 用来证「params 里到底带没带 home」—— 从网络这一侧看，不从页面里的字符串看。
const recorder = `(() => {
  window.__PROBE_REQS__ = [];
  const orig = window.fetch;
  window.fetch = async function (input, init) {
    const url = typeof input === 'string' ? input : (input && input.url) || '';
    const method = String((init && init.method) || (input && input.method) || 'GET').toUpperCase();
    if (url.indexOf('/api/local/action') >= 0 && method === 'POST') {
      window.__PROBE_REQS__.push({ url, method, body: (init && init.body) || null });
    }
    return orig.call(this, input, init);
  };
})()`
await send('Page.addScriptToEvaluateOnNewDocument', { source: recorder })

// 注入：只改 /api/local/profiles 这一份读数，别的一律照后端原样
let stub = { mode, note: '未注入' }
if (mode.startsWith('profiles-home:')) {
  const home = mode.slice('profiles-home:'.length)
  stub = { mode, injected: { dshHome: home }, note: '桩：把 profiles 读数的 dshHome 换成这个值（模拟跨 home 聚合后的读数）' }
  const inject = `(() => {
    const home = ${JSON.stringify(home)};
    const orig = window.fetch;
    window.fetch = async function (input, init) {
      const res = await orig.call(this, input, init);
      const url = typeof input === 'string' ? input : (input && input.url) || '';
      if (url.indexOf('/api/local/profiles') < 0) return res;
      const body = await res.clone().json();
      body.data.dshHome = home;
      body.data.dshHomeSource = '桩：探针把 profiles 读数的 dshHome 换成了 ' + home;
      body.data.profilesRoot = home + '/profiles';
      return new Response(JSON.stringify(body), { status: res.status, headers: { 'content-type': 'application/json' } });
    };
  })()`
  await send('Page.addScriptToEvaluateOnNewDocument', { source: inject })
} else if (mode.startsWith('synth-profiles:')) {
  // 完全合成的 profile 读数（形状照后端）：用来造「这一只属于另一个 home」这一支。
  // **这是桩**：真实后端现在只列一个 home，跨 home 聚合还没落地（见设计文档第四节）。
  const raw = JSON.parse(readFileSync(mode.slice('synth-profiles:'.length), 'utf8'))
  stub = { mode, injected: raw, note: '桩：整份 profiles 读数（dshHome + 列表）按文件合成' }
  const inject = `(() => {
    const syn = ${JSON.stringify(raw)};
    const orig = window.fetch;
    window.fetch = async function (input, init) {
      const res = await orig.call(this, input, init);
      const url = typeof input === 'string' ? input : (input && input.url) || '';
      if (url.indexOf('/api/local/profiles') < 0) return res;
      const body = await res.clone().json();
      body.data.dshHome = syn.dshHome;
      body.data.dshHomeSource = syn.dshHomeSource || '桩：合成读数的 dshHome';
      body.data.profilesRoot = (syn.dshHome || '') + '/profiles';
      body.data.profiles = syn.profiles;
      return new Response(JSON.stringify(body), { status: res.status, headers: { 'content-type': 'application/json' } });
    };
  })()`
  await send('Page.addScriptToEvaluateOnNewDocument', { source: inject })
} else if (mode === 'strip-profiles-home') {
  stub = { mode, note: '桩：把 profiles 响应里的 dshHome / dshHomeSource 删掉（缺键，不编值）' }
  const inject = `(() => {
    const orig = window.fetch;
    window.fetch = async function (input, init) {
      const res = await orig.call(this, input, init);
      const url = typeof input === 'string' ? input : (input && input.url) || '';
      if (url.indexOf('/api/local/profiles') < 0) return res;
      const body = await res.clone().json();
      delete body.data.dshHome;
      delete body.data.dshHomeSource;
      return new Response(JSON.stringify(body), { status: res.status, headers: { 'content-type': 'application/json' } });
    };
  })()`
  await send('Page.addScriptToEvaluateOnNewDocument', { source: inject })
}

await send('Page.navigate', { url: baseUrl })
for (let i = 0; i < 60; i++) {
  await new Promise((r) => setTimeout(r, 300))
  const n = await ev("document.querySelectorAll('[data-name=instance-card]').length")
  if (n > 0) break
}
await new Promise((r) => setTimeout(r, 900))
await send('Page.bringToFront')

const pageExpr = `(async () => {
  const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
  const txt = (e) => (e ? e.textContent.trim() : null);
  const allCards = () => [...document.querySelectorAll('[data-name=instance-card]')];
  const cards = allCards().map((c) => ({
    id: c.dataset.instance,
    name: txt(c.querySelector('.dsh-name')),
    light: c.querySelector('.dsh-dot')?.dataset.state ?? null,
  }));
  const target = ${JSON.stringify(target)};
  const list = allCards();
  // 归档区那一趟（target = __archive__）：归档行不是卡片、没有抽屉，
  // 要量的是它「取消归档」这一枪发出去的 params（那一行自己的 home 有没有跟着走）。
  if (target === '__archive__') {
    // 归档区默认折叠（构件在 set-archived-open 那一枪里）：先展开再量。
    const toggle = document.querySelector('[data-name=archived-toggle]');
    if (toggle && !document.querySelector('[data-name=archived-row]')) { toggle.click(); await sleep(500); }
    const btn = document.querySelector('[data-name=unarchive]');
    const state = btn ? (btn.disabled ? 'disabled' : 'enabled') : 'absent';
    if (btn && !btn.disabled) { btn.click(); await sleep(2500); }
    const rows = [...document.querySelectorAll('[data-name=archived-row]')].map((r) => ({
      id: r.dataset.instance ?? null,
      text: txt(r.querySelector('.dsh-archive-name')) + ' | ' + txt(r.querySelector('.dsh-archive-kind')),
    }));
    return JSON.stringify({ cards, archiveRows: rows, archiveAction: { button: 'unarchive', state,
      toast: txt(document.querySelector('[data-name=flash-toast-text]')),
      notice: txt(document.querySelector('[data-name=action-notice-text]')) },
      actionRequests: (window.__PROBE_REQS__ || []).map((r) => ({ url: r.url, body: r.body })) });
  }
  const card = target
    ? list.find((c) => (c.dataset.instance || '').indexOf(target) >= 0 || (txt(c.querySelector('.dsh-name')) || '').indexOf(target) >= 0)
    : list[0];
  if (!card) return JSON.stringify({ cards, error: '找不到要量的那一张卡' });
  const picked = { id: card.dataset.instance, name: txt(card.querySelector('.dsh-name')) };
  card.click();
  await sleep(600);
  const drawer = document.querySelector('.dsh-drawer');
  const fields = drawer ? [...drawer.querySelectorAll('.dsh-field')].map((f) => ({
    label: txt(f.querySelector('.dsh-field-label')),
    value: txt(f.querySelector('.dsh-field-value')),
    title: f.querySelector('.dsh-field-value')?.getAttribute('title') ?? null,
  })) : [];
  const homeField = fields.find((f) => f.label === 'DSH_HOME') || null;
  const btn = drawer ? drawer.querySelector('[data-name=drawer-copy-dev]') : null;
  const copyEntry = btn ? (btn.disabled ? 'disabled' : 'enabled') : 'absent';
  let clipboard = null, notice = null, toast = null, sentinel = null;
  if (btn && !btn.disabled) {
    sentinel = '__PROBE_SENTINEL_' + Date.now() + '__';
    await navigator.clipboard.writeText(sentinel).catch(() => {});
    btn.click();
    await sleep(1000);
    clipboard = await navigator.clipboard.readText().then((t) => t, (e) => 'READ-ERR: ' + String((e && e.message) || e));
    notice = txt(document.querySelector('[data-name=action-notice-text]'));
    toast = txt(document.querySelector('[data-name=flash-toast-text]'));
  }
  // 可选：再点一颗抽屉里的动作按钮（默认不点）。请求体由页面里的记录器抓下来 ——
  // 「params 里带没带 home」看的就是它。
  const action = ${JSON.stringify(actionName)};
  let afterAction = null;
  if (action && drawer) {
    const ab = drawer.querySelector('[data-name=' + action + ']');
    const has = ab ? (ab.disabled ? 'disabled' : 'enabled') : 'absent';
    if (ab && !ab.disabled) {
      ab.click();
      await sleep(3000);
    }
    afterAction = {
      button: action,
      state: has,
      toast: txt(document.querySelector('[data-name=flash-toast-text]')),
      notice: txt(document.querySelector('[data-name=action-notice-text]')),
    };
  }
  const reqs = (window.__PROBE_REQS__ || []).map((r) => ({ url: r.url, body: r.body }));
  return JSON.stringify({ cards, picked, drawerOpen: !!drawer, fields, homeField, copyEntry, sentinel, clipboard, notice, toast, afterAction, actionRequests: reqs });
})()`
const data = JSON.parse((await ev(pageExpr)) ?? '{}')
data.baseUrl = baseUrl
data.stub = stub
data.clipboardGrant = grant.result ?? grant
data.consoleIssues = consoleIssues.slice(0, 8)
data.consoleIssueCount = consoleIssues.length

// 截图：整页 + 抽屉 + 那一张卡的近景（先滚到视口中间再按视口坐标拍）
const shot = async (clip, name) => {
  const r = await send('Page.captureScreenshot', { format: 'png', clip: { ...clip, scale: 1 } })
  writeFileSync(name + '.png', Buffer.from(r.result.data, 'base64'))
}
const boxRaw = await ev(`(() => {
  const c = [...document.querySelectorAll('[data-name=instance-card]')].find((e) => e.dataset.instance === ${JSON.stringify(data.picked?.id ?? '')});
  if (!c) return 'null';
  c.scrollIntoView({ block: 'center' });
  const b = c.getBoundingClientRect();
  return JSON.stringify({ x: b.x, y: b.y, w: b.width, h: b.height });
})()`)
const box = JSON.parse(boxRaw ?? 'null')
await new Promise((r) => setTimeout(r, 400))
await shot({ x: 0, y: 0, width: 1280, height: 1000 }, outPrefix + '-page')
if (box) {
  await shot({
    x: Math.max(0, Math.min(1280 - 8, box.x - 12)),
    y: Math.max(0, Math.min(1000 - 8, box.y - 12)),
    width: Math.min(1280, box.w + 24),
    height: Math.min(1000, box.h + 24),
  }, outPrefix + '-card')
}
await shot({ x: 800, y: 0, width: 480, height: 1000 }, outPrefix + '-drawer')
data.shots = [outPrefix + '-page.png', outPrefix + '-card.png', outPrefix + '-drawer.png']
console.log(JSON.stringify(data, null, 1))
writeFileSync(outPrefix + '.json', JSON.stringify(data, null, 1))
chrome.kill()
process.exit(0)

// 量「第六格：最近改动」与「已停止组按最近改动降序」。
//
// 用法：
//   node probe-mtime.mjs <baseUrl> <mode> <outPrefix>
//     mode = real          不注入，量当前后端的真实响应
//     mode = stub:<json>   把 <json> 里的 { profile: ms|null } 并进 /api/local/profiles 的响应，
//                          用来验「有值时怎么显示」与「null 排最后」——**这是桩，不是真读数**。
//     mode = strip         把 dirMtimeMs / dirMtimeSource 从响应里删掉，复现「后端还没有这个字段」
//                          那一支（桩造的是**缺字段**，不是编的值）
//     mode = synth:<json>  用 <json> 里的 profile 列表替掉响应里的 profiles，**并把 instances 清空**。
//                          为什么要清 instances：已停止组会排除「正被某个实例用着」的 profile，
//                          机器上谁在跑是活的（并行那一路随时起实例），不清就没法稳定复现排序。
//                          这是**完全合成的 fixture**：不碰磁盘上的任何 profile。
//
// 注入点在 window.fetch 上（app 走的是全局 fetch），在页面脚本之前装上，
// 所以读数一落地就带着桩值，不存在「先真后假」的中间态。
import { spawn } from 'node:child_process'
import { writeFileSync, readFileSync } from 'node:fs'

const CDP_PORT = 9700 + (process.pid % 200)
const [baseUrl, mode = 'real', outPrefix = '/tmp/mtime'] = process.argv.slice(2)

const chrome = spawn('chromium', ['--headless', '--no-sandbox', '--disable-gpu', '--disable-extensions',
  '--hide-scrollbars', '--remote-debugging-port=' + CDP_PORT, '--user-data-dir=/tmp/chrome-mtime-' + process.pid,
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

let stub = null
if (mode.startsWith('stub:')) {
  stub = JSON.parse(readFileSync(mode.slice(5), 'utf8'))
  const inject = `(() => {
    const t = ${JSON.stringify(stub)};
    window.__MTIME_STUB__ = t;
    const orig = window.fetch;
    window.fetch = async function (input, init) {
      const res = await orig.call(this, input, init);
      const url = typeof input === 'string' ? input : (input && input.url) || '';
      if (url.indexOf('/api/local/profiles') < 0) return res;
      const body = await res.clone().json();
      for (const p of ((body && body.data && body.data.profiles) || [])) {
        if (Object.prototype.hasOwnProperty.call(t, p.name)) {
          p.dirMtimeMs = t[p.name];
          p.dirMtimeSource = t[p.name] === null
            ? '桩响应：这只 profile 的目录 stat 读不到 mtime'
            : '桩响应：stat(profile 目录).mtimeMs（真实目录 mtime，由探针按值注入）';
        }
      }
      return new Response(JSON.stringify(body), { status: res.status, headers: { 'content-type': 'application/json' } });
    };
  })()`
  await send('Page.addScriptToEvaluateOnNewDocument', { source: inject })
} else if (mode.startsWith('synth:')) {
  const raw = JSON.parse(readFileSync(mode.slice(6), 'utf8'))
  // 两种形状：数组 = 只换 profiles（instances 清空）；
  // { profiles, instances } = 两边都换（用来造「运行卡解析不出 profile」那一支）
  const list = Array.isArray(raw) ? raw : raw.profiles
  const instOverride = Array.isArray(raw) ? [] : raw.instances
  // 记下来的表就是排序判定的依据（与页面同源）
  stub = Object.fromEntries(list.map((p) => [p.name, p.dirMtimeMs ?? null]))
  const inject = `(() => {
    const profiles = ${JSON.stringify(list)};
    const instances = ${JSON.stringify(instOverride)};
    const orig = window.fetch;
    window.fetch = async function (input, init) {
      const res = await orig.call(this, input, init);
      const url = typeof input === 'string' ? input : (input && input.url) || '';
      if (url.indexOf('/api/local/profiles') >= 0) {
        const body = await res.clone().json();
        body.data.profiles = profiles;
        return new Response(JSON.stringify(body), { status: res.status, headers: { 'content-type': 'application/json' } });
      }
      if (url.indexOf('/api/local/instances') >= 0) {
        const body = await res.clone().json();
        body.data.instances = instances;
        body.data.probeResults = [];
        return new Response(JSON.stringify(body), { status: res.status, headers: { 'content-type': 'application/json' } });
      }
      return res;
    };
  })()`
  await send('Page.addScriptToEvaluateOnNewDocument', { source: inject })
} else if (mode === 'strip') {
  // 复现「响应里根本没有这个字段」：删键，不编值。
  const inject = `(() => {
    const orig = window.fetch;
    window.fetch = async function (input, init) {
      const res = await orig.call(this, input, init);
      const url = typeof input === 'string' ? input : (input && input.url) || '';
      if (url.indexOf('/api/local/profiles') < 0) return res;
      const body = await res.clone().json();
      for (const p of ((body && body.data && body.data.profiles) || [])) {
        delete p.dirMtimeMs;
        delete p.dirMtimeSource;
      }
      return new Response(JSON.stringify(body), { status: res.status, headers: { 'content-type': 'application/json' } });
    };
  })()`
  await send('Page.addScriptToEvaluateOnNewDocument', { source: inject })
}

await send('Page.navigate', { url: baseUrl })
// 读数落地 + 卡片渲染
for (let i = 0; i < 60; i++) {
  await new Promise((r) => setTimeout(r, 300))
  const n = await ev("document.querySelectorAll('[data-name=instance-card]').length")
  if (n > 0) break
}
await new Promise((r) => setTimeout(r, 800))

const probe = await ev(`(() => {
  const txt = (e) => (e ? e.textContent.trim() : null)
  const cards = [...document.querySelectorAll('[data-name=instance-card]')].map((c) => ({
    instance: c.dataset.instance,
    status: c.querySelector('.dsh-sub')?.dataset.status ?? null,
    fields: [...c.querySelectorAll('.dsh-field')].map((f) => ({
      label: txt(f.querySelector('.dsh-field-label')),
      value: txt(f.querySelector('.dsh-field-value')),
      title: f.querySelector('.dsh-field-value')?.getAttribute('title') ?? null,
    })),
  }));
  const mtimeOf = (c) => c.fields.find((f) => f.label === '最近改动') || null;
  return JSON.stringify({
    cards,
    runningOrder: cards.filter((c) => c.status !== 'stopped').map((c) => c.instance),
    stoppedOrder: cards.filter((c) => c.status === 'stopped').map((c) => c.instance),
    sixth: cards.map((c) => ({ instance: c.instance, status: c.status, fieldCount: c.fields.length, mtime: mtimeOf(c) })),
    grid: {
      cardsWithSixFilled: cards.filter((c) => c.fields.length === 6 && c.fields.every((f) => f.value && f.value.length > 0)).map((c) => c.instance),
      cardsWithEmptyCell: cards.filter((c) => c.fields.length !== 6 || c.fields.some((f) => !f.value || f.value.length === 0)).map((c) => c.instance),
    },
    labels: [...new Set(cards.flatMap((c) => c.fields.map((f) => f.label)))],
  });
})()`)
const data = JSON.parse(probe ?? '{}')
data.mode = mode
data.stub = stub
data.consoleIssues = consoleIssues.slice(0, 8)
data.consoleIssueCount = consoleIssues.length

// 卡片的几何：给截图取窗口用
const rects = JSON.parse(await ev(`(() => {
  const out = {};
  for (const c of document.querySelectorAll('[data-name=instance-card]')) {
    const r = c.getBoundingClientRect();
    out[c.dataset.instance] = { x: r.x + scrollX, y: r.y + scrollY, w: r.width, h: r.height };
  }
  out.__stoppedHead = (() => { const h = [...document.querySelectorAll('.dsh-section-head, .dsh-sec-head, h2')].find(e => e.textContent.includes('已停止')); if (!h) return null; const r = h.getBoundingClientRect(); return { x: r.x + scrollX, y: r.y + scrollY, w: r.width, h: r.height }; })();
  out.__docH = document.documentElement.scrollHeight;
  return JSON.stringify(out);
})()`))
data.rects = rects

const shot = async (clip, name) => {
  const r = await send('Page.captureScreenshot', { format: 'png', clip: { ...clip, scale: 1 } })
  writeFileSync(name + '.png', Buffer.from(r.result.data, 'base64'))
}

// 列表顶部：整页顶端。页面自己是滚不动的（内容在内部滚动容器里），
// 所以这一步不用把 captureBeyondViewport 打开 —— 打开拍到的也是同一屏。
await shot({ x: 0, y: 0, width: 1280, height: 1000 }, outPrefix + '-top')

// 某一张卡的近景：**先把卡滚到视口中间再按视口坐标拍**。
// 踩过的坑：内容在内部滚动容器里，document.scrollHeight 恒等于视口高，
// 拿「加上 scrollY 的页面坐标 + captureBeyondViewport」去拍屏外的卡，拍出来是一张空图。
const cardShot = async (instance, name) => {
  const ok = await ev(`(() => {
    const c = [...document.querySelectorAll('[data-name=instance-card]')]
      .find((e) => e.dataset.instance === ${JSON.stringify(instance)});
    if (!c) return null;
    c.scrollIntoView({ block: 'center' });
    const b = c.getBoundingClientRect();
    return JSON.stringify({ x: b.x, y: b.y, w: b.width, h: b.height });
  })()`)
  if (!ok) return null
  await new Promise((r) => setTimeout(r, 350))
  // 滚动之后再量一次：scrollIntoView 之后视口坐标才作数
  const box = JSON.parse(await ev(`(() => {
    const c = [...document.querySelectorAll('[data-name=instance-card]')]
      .find((e) => e.dataset.instance === ${JSON.stringify(instance)});
    const b = c.getBoundingClientRect();
    return JSON.stringify({ x: b.x, y: b.y, w: b.width, h: b.height });
  })()`))
  const clip = {
    x: Math.max(0, Math.min(1280 - 8, box.x - 12)),
    y: Math.max(0, Math.min(1000 - 8, box.y - 12)),
    width: Math.min(1280, box.w + 24),
    height: Math.min(1000, box.h + 24),
  }
  await shot(clip, name)
  return name + '.png'
}

// 第一张已停止卡（它的第六格）
const stoppedNames = data.stoppedOrder ?? []
data.shots = [outPrefix + '-top.png']
if (stoppedNames.length > 0) {
  data.shots.push(await cardShot(stoppedNames[0], outPrefix + '-stopped-first'))
  if (stoppedNames.length > 1) {
    data.shots.push(await cardShot(stoppedNames[stoppedNames.length - 1], outPrefix + '-stopped-last'))
  }
}
data.shots = data.shots.filter(Boolean)
console.log(JSON.stringify(data, null, 1))
writeFileSync(outPrefix + '.json', JSON.stringify(data, null, 1))
chrome.kill()
process.exit(0)

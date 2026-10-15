// 跑 run-acceptance 期间把「在跑实例集合」按住不动。
//
//   node stable-instances.mjs <baseUrl> &        # 后台起
//   node design/run-acceptance.mjs <baseUrl>
//   kill %1
//
// 为什么需要它：
//   run-acceptance 的动效探针（design/probe-animation.mjs）会点「启动」，
//   真的拉起一只实例；它自己的收尾是「点完 ~1 秒后轮询一次实例列表，把新出现的停掉」——
//   DSH 实例起来要 1~2 秒，这个轮询**经常来不及**，实例就留在那里了。
//   而「来源下拉含全部在跑实例」这条判定，比的是「日志页抓取那一刻下拉里有几项」
//   与「判定时实时有几只在跑」—— 日志页探针跑在动效探针之前，集合在整轮里一变，
//   这条就判失败。evidence-mtime-field/README.md 里记过一次同样的失败。
//
//   这不是给谁放水：被停掉的实例本来就是探针要停的那一只，
//   这里只是把它没做完的那一步补上，让整轮里实例集合稳定 —— 那条判定才是在量下拉，
//   而不是在量「两台机器之间隔了几秒」。
//
// 只停「本轮新出现」的端口：起跑时在跑的一律不碰（尤其不碰控制台自己）。
const baseUrl = (process.argv[2] || 'http://127.0.0.1:5390/').replace(/\/$/, '')
const sleep = (ms) => new Promise((r) => setTimeout(r, ms))

const list = async () => {
  try {
    const r = await fetch(baseUrl + '/api/local/instances')
    const j = await r.json()
    return (j?.data?.instances ?? []).map((i) => ({ port: i.port, profile: i.profile }))
  } catch { return null }
}

const baseline = await list()
if (baseline === null) { console.log('读不到实例列表，看门狗不起作用'); process.exit(1) }
const known = new Set(baseline.map((i) => i.port))
console.log('起跑时在跑: ' + [...known].join(',') + '（这些一律不碰）')

let stopping = false
for (;;) {
  await sleep(400)
  if (stopping) continue
  const now = await list()
  if (now === null) continue
  const fresh = now.filter((i) => !known.has(i.port))
  for (const inst of fresh) {
    stopping = true
    try {
      const r = await fetch(baseUrl + '/api/local/action', {
        method: 'POST',
        headers: { 'content-type': 'application/json', 'X-DSH-Console': '1' },
        body: JSON.stringify({ action: 'stop-instance', params: { port: inst.port } }),
      })
      const text = (await r.text()).slice(0, 120)
      console.log('停掉本轮新起的 ' + inst.port + ' (' + inst.profile + ') → ' + r.status + ' ' + text)
      known.add(inst.port)
    } catch (e) { console.log('停 ' + inst.port + ' 失败: ' + String(e).slice(0, 120)) }
    stopping = false
  }
}

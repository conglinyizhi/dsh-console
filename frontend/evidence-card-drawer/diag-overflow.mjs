import { launch, evalJson, setViewport, sleep } from './cdp.mjs'
const [baseUrl = 'http://127.0.0.1:5390/'] = process.argv.slice(2)
const { send, close } = await launch({ width: 360, height: 900, profile: 'diag' })
await send('Page.navigate', { url: baseUrl })
await sleep(5000)
for (const w of [360, 480]) {
  await setViewport(send, w, 900)
  await sleep(400)
  const out = await evalJson(send, `(() => {
    const main = document.querySelector('.dsh-main')
    const mr = main.getBoundingClientRect()
    const limit = mr.left + main.clientWidth
    const over = []
    for (const el of document.querySelectorAll('.dsh-main *')) {
      const r = el.getBoundingClientRect()
      if (r.width === 0) continue
      if (r.right > limit + 0.5) {
        over.push({ tag: el.tagName.toLowerCase(), cls: String(el.className).slice(0, 46), right: +r.right.toFixed(1), w: +r.width.toFixed(1), sw: el.scrollWidth, cw: el.clientWidth })
      }
    }
    return JSON.stringify({ w: innerWidth, mainRight: +limit.toFixed(1), mainClientW: main.clientWidth, mainScrollW: main.scrollWidth, count: over.length, top: over.slice(0, 12) })
  })()`)
  console.log(JSON.stringify(out, null, 1))
}
close(); process.exit(0)

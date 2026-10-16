// 响应式重算的实测：node probe-widths.mjs <baseUrl> [outPrefix]
//
// 卡片瘦成一行之后，最小可用宽度从 553px 变成 240px，列数断点整套重推。
// 这里在十几档宽度上量三件事：
//   1. 卡片栅格实际排了几列（读 computed 的 grid-template-columns 轨道数 ——
//      比数卡片可靠：本机只有三只 profile，数卡片永远看不到第 4 列）
//   2. 页面有没有横向溢出（documentElement.scrollWidth > clientWidth）
//   3. 每张卡、卡片栅格、主区自己有没有横向溢出（scrollWidth > clientWidth）
import { launch, evalJson, setViewport, shot, sleep } from './cdp.mjs'
import { writeFileSync } from 'node:fs'

const [baseUrl = 'http://127.0.0.1:5390/', prefix = 'widths'] = process.argv.slice(2)

const WIDTHS = [360, 480, 620, 725, 726, 900, 977, 978, 1100, 1229, 1230, 1280, 1440, 1481, 1482, 1600, 1733, 1734, 1920, 2560]
const SHOTS = new Set([360, 768, 1280, 1920])

const measure = `(() => {
  const de = document.documentElement
  const grid = document.querySelector('.dsh-card-grid')
  const main = document.querySelector('.dsh-main')
  const cards = [...document.querySelectorAll('[data-name="instance-card"]')]
  const tracks = grid ? getComputedStyle(grid).gridTemplateColumns.split(' ').filter((s) => s.length) : []
  const xs = [...new Set(cards.map((c) => Math.round(c.getBoundingClientRect().x / 2) * 2))]
  return JSON.stringify({
    viewportW: innerWidth,
    tracks: tracks.length,
    trackSizes: tracks.slice(0, 8),
    observedColumns: xs.length,
    cardWidths: cards.map((c) => +c.getBoundingClientRect().width.toFixed(1)),
    pageOverflowX: de.scrollWidth > de.clientWidth,
    pageScrollW: de.scrollWidth, pageClientW: de.clientWidth,
    gridOverflowX: grid ? grid.scrollWidth > grid.clientWidth : null,
    mainOverflowX: main ? main.scrollWidth > main.clientWidth : null,
    cardOverflowX: cards.map((c) => c.scrollWidth > c.clientWidth),
    headOverflowX: cards.map((c) => { const h = c.querySelector('.dsh-case-head'); return h ? h.scrollWidth > h.clientWidth : null }),
  })
})()`

const { send, close } = await launch({ width: 1280, height: 900, profile: 'widths' })
await send('Page.navigate', { url: baseUrl })
await sleep(5000)

const rows = []
for (const w of WIDTHS) {
  await setViewport(send, w, 900)
  await sleep(450)
  const m = await evalJson(send, measure)
  rows.push(m)
  if (SHOTS.has(w)) await shot(send, prefix + '-' + w + '.png')
}

const out = { baseUrl, widths: rows }
writeFileSync(prefix + '.json', JSON.stringify(out, null, 1))
console.log(JSON.stringify(rows.map((r) => ({
  w: r.viewportW, cols: r.tracks, observed: r.observedColumns,
  cardW: r.cardWidths[0], pageOverflow: r.pageOverflowX, gridOverflow: r.gridOverflowX,
  mainOverflow: r.mainOverflowX, cardOverflow: r.cardOverflowX.some(Boolean), headOverflow: r.headOverflowX.some(Boolean),
})), null, 0))
console.log('任何宽度横向溢出: ' + rows.filter((r) => r.pageOverflowX || r.gridOverflowX || r.mainOverflowX || r.cardOverflowX.some(Boolean) || r.headOverflowX.some(Boolean)).map((r) => r.viewportW).join(',') || '无')
close()
process.exit(0)

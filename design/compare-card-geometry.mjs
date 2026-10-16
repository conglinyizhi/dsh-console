// 条目几何的改动前后对照：读同目录上一级 evidence-card-layout/ab-old-*.json 与 ab-new-*.json。
//
//   node compare-card-geometry.mjs
//
// 两份 JSON 由 design/probe-card-rows.mjs 量出来，跑在同一份 fixture、同一台机器上：
// ab-old-* 是改动前的构建（git archive HEAD 解出来单独编的产物），ab-new-* 是当前构建。
//
// 对照的是**与数据无关的那几项**（条目宽高、图标偏移与尺寸、名字偏移与尺寸、
// 端口相对条目右缘与顶的偏移）—— 名字的宽度会随 profile 名变，不在这几项里。
// 「无备注、无时间」的那一条每一项都应当相等；有备注/有时刻的那些**刻意不等**，
// 那正是这一轮的改动（第二行从另起一行改成并在右半边）。
import { readFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const dir = join(dirname(fileURLToPath(import.meta.url)), '..', 'frontend', 'evidence-card-layout')
const load = (f) => JSON.parse(readFileSync(join(dir, f), 'utf8'))
const off = (a, b) => +(a - b).toFixed(1)
const shape = (c) => ({
  cardW: c.card.w,
  cardH: c.card.h,
  tile: [off(c.tile.x, c.card.x), off(c.tile.y, c.card.y), c.tile.w, c.tile.h],
  nameFromCard: [off(c.name.x, c.card.x), off(c.name.y, c.card.y), c.name.w, c.name.h],
  portFromCardRight: c.portRect ? off(c.card.right, c.portRect.right) : null,
  portFromCardTop: c.portRect ? off(c.portRect.y, c.card.y) : null,
  portH: c.portRect ? c.portRect.h : null,
})
const keys = ['cardW', 'cardH', 'tile', 'nameFromCard', 'portFromCardRight', 'portFromCardTop', 'portH']

for (const vw of ['1280', '360']) {
  const nw = load('ab-new-' + vw + '.json').cards
  const od = load('ab-old-' + vw + '.json').cards
  console.log('=== 视口 ' + vw + ' ===')
  for (const c of nw) {
    const o = od.find((x) => x.nameText === c.nameText)
    if (!o) {
      console.log('  ' + c.nameText + '（改动前没有这一条）')
      continue
    }
    const a = shape(o), b = shape(c)
    const diffs = keys.filter((k) => JSON.stringify(a[k]) !== JSON.stringify(b[k]))
    console.log('  ' + c.nameText.padEnd(10) + ' 第二行=' + c.secondKind.padEnd(6) +
      ' 不一致=' + (diffs.length ? diffs.join(',') : '无'))
    console.log('     改前 ' + JSON.stringify(a))
    console.log('     改后 ' + JSON.stringify(b))
  }
}

// 条目标签的改动前后对照：node compare-port-geometry.mjs <改前.json> <改后.json> [<改前.json> <改后.json> ...]
//
//   node compare-port-geometry.mjs before-1280.json after-1280.json before-360.json after-360.json
//
// 两份 JSON 都由同目录的 probe-port-label.mjs 量出来，跑在同一个后端、同一份数据上。
// 对照的是**与数据无关的那几项**：条目宽高、第一行的位置与高度、名字那一格的位置、
// 那一串端口相对内容盒右缘的偏移与高度 —— 名字的宽度会随这一格够不够放而变，不在这几项里。
//
// 三种结论分开说，不混成一句「通过」：
//   · 无端口那一行：形状每一项都应当**逐像素相等**（标签只挂在有端口的那一格上）
//   · 有端口那一行：条目/第一行的位置与高度相等，只有那一串变长（名字那一格相应变窄）
//   · 硬要求：那一串的右缘与内容盒右缘对齐（偏移 0）、名字仍是一行省略号、
//     标签不换行、第一行不溢出、整页不横向滚动
import { readFileSync } from 'node:fs'

const files = process.argv.slice(2)
if (files.length < 2 || files.length % 2) {
  console.log('用法: node compare-port-geometry.mjs <改前.json> <改后.json> [<改前.json> <改后.json> ...]')
  process.exit(1)
}
const load = (f) => JSON.parse(readFileSync(f, 'utf8'))
const off = (a, b) => +(a - b).toFixed(1)
const shape = (c) => ({
  cardW: c.card.w, cardH: c.card.h,
  headFromCard: [off(c.head.x, c.card.x), off(c.head.y, c.card.y), c.head.w, c.head.h],
  nameFromCard: [off(c.name.x, c.card.x), off(c.name.y, c.card.y), c.name.h],
  portNode: c.nodes.port,
  portFromContentRight: c.port ? off(c.port.right, c.content.right) : null,
  portFromCardTop: c.port ? off(c.port.y, c.card.y) : null,
  portH: c.port ? c.port.h : null,
})
const KEYS = ['cardW', 'cardH', 'headFromCard', 'nameFromCard', 'portNode', 'portFromContentRight', 'portFromCardTop', 'portH']
// 名字那一格的**宽度**单列：有端口那一行它本就该变窄（标签占了地方），不算形状不一致
const WIDTH_KEY = 'nameW'

let bad = 0
for (let i = 0; i < files.length; i += 2) {
  const a = load(files[i]), b = load(files[i + 1])
  console.log('=== ' + files[i] + ' → ' + files[i + 1] + '（视口 ' + b.viewport.w + '×' + b.viewport.h + '）===')
  console.log('  整页横向滚动：改前 ' + a.overflowX + '(' + a.scrollW + '/' + a.clientW + ') → 改后 ' + b.overflowX + '(' + b.scrollW + '/' + b.clientW + ')' + (b.overflowX ? '  ✗' : '  ✓'))
  if (b.overflowX) bad++
  for (const c of b.cards) {
    const o = a.cards.find((x) => x.rowId === c.rowId)
    if (!o) { console.log('  ' + c.rowId + '：改前没有这一条（数据变了，跳过逐像素对照）'); continue }
    const sa = shape(o), sb = shape(c)
    const diffs = KEYS.filter((k) => JSON.stringify(sa[k]) !== JSON.stringify(sb[k]))
    const widthDiff = off(o.name.w, c.name.w)
    const hasPort = c.nodes.port
    const labelShown = !!(c.label && c.label.w > 0)
    const expectWidthChange = !!hasPort
    const widthOk = expectWidthChange ? true : Math.abs(widthDiff) < 0.05
    const tag = diffs.length === 0 ? '逐像素一致' : ('不一致=' + diffs.join(','))
    console.log('  ' + String(c.rowId).padEnd(34) + (hasPort ? '[有端口]' : '[无端口]') + ' ' + tag +
      ' | 名字宽 ' + o.name.w + ' → ' + c.name.w + (widthOk ? '' : '  ✗ 无端口那一行的名字宽也变了') +
      (hasPort ? ' | 那一格 ' + JSON.stringify(c.portTextTrimmed) + ' 标签' + (labelShown ? '显示' : '让位') : ''))
    if (diffs.length) {
      for (const k of diffs) console.log('       ' + k + ': ' + JSON.stringify(sa[k]) + ' → ' + JSON.stringify(sb[k]))
      // 有端口那一行只允许「那一串变长」——形状里允许变的只有 port* 与端口节点本身
      const unexpected = diffs.filter((k) => !k.startsWith('port'))
      if (unexpected.length) { console.log('       ✗ 上面这些不该动'); bad++ }
    }
    if (!widthOk) bad++
    // 硬要求逐条
    const problems = []
    if (hasPort) {
      if (Math.abs(c.deltas.portRight) > 0.05) problems.push('那一串的右缘没对齐内容盒右缘（偏移 ' + c.deltas.portRight + '）')
      // 标签在 ≤420 那一档**刻意让位**（display: none）：那是让位，不是折行。
      // 只在它真显示时要求「一行不折」。
      if (labelShown && c.label.lineBoxes !== 1) problems.push('标签折成了 ' + c.label.lineBoxes + ' 行')
      if (labelShown && !/^端口：\d+$/.test(c.portTextTrimmed)) problems.push('那一格的 DOM 文本不是「端口：<数字>」：' + JSON.stringify(c.portTextTrimmed))
      if (c.headOverflow) problems.push('第一行溢出（scrollWidth ' + c.headScrollW + ' > clientWidth ' + c.headClientW + '）')
    } else {
      // 没有端口的那一行：节点一个都不许有，文本里也不许冒出「端口：」
      if (c.nodes.port) problems.push('没有端口却产出了那一格的节点')
      if (c.cardText.indexOf('端口：') >= 0) problems.push('没有端口却在文本里出现了「端口：」')
    }
    if (c.name.lineBoxes !== 1) problems.push('名字折成了 ' + c.name.lineBoxes + ' 行')
    if (c.headOverflow) problems.push('第一行溢出')
    if (c.cardOverflow) problems.push('条目自身溢出')
    if (problems.length) { console.log('       ✗ ' + problems.join(' / ')); bad++ }
  }
}
console.log(bad ? ('\n还有 ' + bad + ' 处不满足') : '\n全部满足')
process.exit(bad ? 1 : 0)

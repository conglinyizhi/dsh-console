// 改前 / 改后读数对照：node compare.mjs before.json after.json > compare.txt
import { readFileSync } from 'node:fs'
const [b, a] = process.argv.slice(2).map((p) => JSON.parse(readFileSync(p, 'utf8')))
const line = (s) => console.log(s)
const rect = (r) => r ? `x=${r.x} y=${r.y} w=${r.w} h=${r.h} right=${r.right} bottom=${r.bottom}` : '（无）'
const fmt = (c) => c ? `类名="${c.cls}" ${rect(c.rect)} radius=${c.radius} padding=${c.padding}` : '（无）'

line('一、按钮组构成（每张卡的直接子节点）')
const names = [...new Set([...(b.layout.cards ?? []), ...(a.layout.cards ?? [])].map((c) => c.name))]
for (const n of names) {
  const cb = b.layout.cards.find((c) => c.name === n), ca = a.layout.cards.find((c) => c.name === n)
  for (const [tag, c] of [['改前', cb], ['改后', ca]]) {
    if (!c) { line(`  ${tag} ${n}: 不在场`); continue }
    const kids = c.actionsChildren.map((ch) => ch.tag === 'button' ? `<button ${ch.cls}>「${ch.buttons[0] || '图标'}」` : `<${ch.tag} ${ch.cls}>[${ch.buttons.map((t) => t || '图标').join(' | ')}]`)
    line(`  ${tag} [${c.status}] ${n}: 子节点 ${c.actionsChildren.length} 个 → ${kids.join(' + ')}`)
    line(`       按钮组右缘 ${c.actionsRight} / 内容盒右缘 ${c.contentRight} → Δ${c.actionsDelta}`)
  }
}
line('')
line('二、两类卡的 ⋯ 按钮逐项对照（类名 / 矩形 / 圆角 / 内边距）')
for (const [tag, d] of [['改前', b], ['改后', a]]) {
  line(`  ${tag} 已停止卡入口: ${fmt(d.trigger)}`)
  line(`  ${tag} 运行中卡入口: ${fmt(d.runningTrigger)}`)
  const same = d.trigger && d.runningTrigger && d.trigger.cls === d.runningTrigger.cls && d.trigger.radius === d.runningTrigger.radius && d.trigger.rect.w === d.runningTrigger.rect.w && d.trigger.rect.h === d.runningTrigger.rect.h && d.trigger.padding === d.runningTrigger.padding
  line(`  ${tag} 两者一致: ${same}`)
}
line('')
line('三、已停止卡菜单（点开后的条目与顺序）')
const items = (d) => (d.menu?.items ?? []).map((t) => '  ' + t)
line('  改前:'); line(items(b).join('\n'))
line('  改后:'); line(items(a).join('\n'))
const ib = (b.menu?.items ?? []).join('|'), ia = (a.menu?.items ?? []).join('|')
line(`  逐条一致: ${ib === ia}（${(b.menu?.items ?? []).length} 行 vs ${(a.menu?.items ?? []).length} 行）`)
line(`  菜单锚点 改前 top+${b.menu?.deltaTop} right${b.menu?.deltaRight} / 改后 top+${a.menu?.deltaTop} right${a.menu?.deltaRight}`)
line(`  落焦第一项 改前 ${b.menu?.activeIsFirstItem} / 改后 ${a.menu?.activeIsFirstItem}；Esc 收起 改前 ${b.menu?.menuClosedByEscape} / 改后 ${a.menu?.menuClosedByEscape}`)

// 把 pass.json 里的实测结果整理成「语义路径 → uid」对照表。
//
//   node build-table.mjs pass.json uid-table.md
//
// 路径是从 DOM 上读出来的：data-name 是角色，后面括号里是限定它到具体哪一个的东西
// —— 所在卡片（data-instance 的值）、所在对话框、以及元素自己的键（data-action /
// data-field / data-setting / data-group / option 的 value）。**没有位置**。
import { readFileSync, writeFileSync } from 'node:fs'

const [inFile = 'pass.json', outFile = 'uid-table.md'] = process.argv.slice(2)
const r = JSON.parse(readFileSync(inFile, 'utf8'))

const qualifier = (identity) => {
  const tail = identity.split(' :: ')[1] || ''
  const m = {}
  for (const piece of tail.split(' ')) {
    const i = piece.indexOf('=')
    if (i > 0) m[piece.slice(0, i)] = piece.slice(i + 1)
  }
  if (m.card) return '卡片 ' + m.card
  if (m.dlg) return '对话框 ' + m.dlg + (m.own ? ' · ' + m.own : '')
  if (m.val) return m.val
  if (m.own) return m.own
  return '—'
}

let md = '# 语义路径 → uid 对照表（实测，\`accept-data-uid.mjs\`）\n\n'
md += '同一状态刷新两次各抓一遍，路径与 uid 逐一对应。取任意一个 uid，\n'
md += '在表里查到的那一行就是它：角色（data-name）+ 限定（哪张卡 / 哪个框 / 自己的键）。\n'

const states = [...new Set(r.table.map((t) => t.state))]
for (const st of states) {
  const rows = r.table.filter((t) => t.state === st)
  md += `\n## ${st}（${rows.length} 个元素）\n\n`
  md += '| data-name（角色） | 限定（是哪一个） | data-uid | 元素 | 文本样例 |\n'
  md += '| --- | --- | --- | --- | --- |\n'
  for (const t of rows) {
    const sample = (t.sample || '').replace(/\|/g, '\\|').slice(0, 18)
    md += `| \`${t.name}\` | ${qualifier(t.identity).replace(/\|/g, '\\|')} | \`${t.uid}\` | ${t.tag} | ${sample} |\n`
  }
}

md += '\n## 同名不同卡：uid 把两个「同一个角色」分开\n\n'
md += '| data-name | 所在卡片 | data-uid |\n| --- | --- | --- |\n'
for (const g of r.sameNameDiffCard || []) {
  for (const [k, uid] of Object.entries(g.perCard)) {
    const card = (k.split(' ').find((p) => p.startsWith('card=')) || '').replace('card=', '')
    md += `| \`${g.name}\` | ${card} | \`${uid}\` |\n`
  }
}
md += '\n（\`allDistinct\`：' + (r.sameNameDiffCard || []).map((g) => g.name + '=' + g.allDistinct).join('，') + '）\n'

writeFileSync(outFile, md)
console.log('表写到 ' + outFile + '，' + r.table.length + ' 行，状态 ' + states.length + ' 个')

// 把 DOM 那一侧的证据落成文本：node dump-dom-proof.mjs > dom-text.txt
//
// 读同目录 after-1280.json / after-360.json（probe-port-label.mjs 量的），打印：
//   · 有端口那一格的 DOM 文本、标签与数字的颜色
//   · 有端口那一行的头 HTML
//   · 没有端口那一行：节点表、卡片文本、头 HTML（证明没有「端口：」这个节点）
//   · 全页扫「端口：」落在哪几处
import { readFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const here = dirname(fileURLToPath(import.meta.url))
const load = (f) => JSON.parse(readFileSync(join(here, f), 'utf8'))
const cutHead = (html) => {
  const i = html.indexOf('dsh-case-head')
  const start = html.lastIndexOf('<', i)
  return i < 0 ? '(头没找到)' : html.slice(start, html.indexOf('</article>', i)).replace(/></g, '>\n<')
}

for (const vw of ['1280', '360']) {
  const j = load('after-' + vw + '.json')
  const p = j.cards.find((c) => c.nodes.port)
  const n = j.cards.find((c) => !c.nodes.port)
  console.log('================ 视口 ' + vw + '（' + j.viewport.w + '×' + j.viewport.h + '）================')
  console.log('')
  console.log('【有端口那一行】' + p.rowId)
  console.log('  那一格的 DOM 文本 : ' + JSON.stringify(p.portText) + '（原文，未 trim）')
  console.log('  标签文本           : ' + JSON.stringify(p.labelText))
  console.log('  标签颜色 / 字号    : ' + p.label.color + ' / ' + p.label.fontSize + '，行盒 ' + p.label.lineBoxes + ' 个，宽 ' + p.label.w)
  console.log('  数字颜色 / 字号    : ' + p.port.color + ' / ' + p.port.fontSize + '，行盒 ' + p.port.lineBoxes + ' 个，宽 ' + p.port.w + '，高 ' + p.port.h)
  console.log('  头那一行：')
  console.log(cutHead(p.html).split('\n').map((l) => '    ' + l).join('\n'))
  console.log('')
  console.log('【没有端口那一行】' + n.rowId)
  console.log('  节点表             : ' + JSON.stringify(n.nodes) + '（port=false 就是那一格一个节点都没产出）')
  console.log('  那一格的 DOM 文本  : ' + JSON.stringify(n.portText))
  console.log('  卡片整段文本       : ' + JSON.stringify(n.cardText))
  console.log('  文本里有「端口：」吗: ' + (n.cardText.indexOf('端口：') >= 0))
  console.log('  头那一行：')
  console.log(cutHead(n.html).split('\n').map((l) => '    ' + l).join('\n'))
  console.log('')
  console.log('  全页扫「端口：」    : ' + JSON.stringify(j.portHits))
  console.log('')
  const i = j.injected || {}
  console.log('【注入一个 46 字的名字之后】' + (i.ok ? i.injectedText : '(没量到)'))
  console.log('  名字那一格         : 宽 ' + (i.name ? i.name.w : '?') + '，行盒 ' + i.nameLineBoxes + ' 个，省略号生效 ' + i.nameEllipsis +
    '（scrollWidth ' + i.nameScrollW + ' > clientWidth ' + i.nameClientW + '）')
  console.log('  那一格             : ' + JSON.stringify(i.portText) + '，宽 ' + (i.port ? i.port.w : '?'))
  console.log('  右缘 − 内容盒右缘  : ' + i.portRightFromContentRight)
  console.log('  标签               : 显示 ' + i.labelShown + '，行盒 ' + i.labelLineBoxes + ' 个，横向越出那一格 ' + i.labelOutsidePortX +
    '，行内盒 ' + JSON.stringify(i.labelRect))
  console.log('  溢出               : 第一行 ' + i.headOverflow + '，条目 ' + i.cardOverflow + '，整页 ' + i.pageOverflowX)
  console.log('')
}

// 把「后端/桩给的 dirMtimeMs」与「页面上卡片的先后顺序」对照，证明是严格降序、null 沉底。
//
// 用法：node check-order.mjs <probe.json> [ref]
//   probe.json   probe-mtime.mjs 的产物（里面有 stoppedOrder 与 stub 表）
//   ref          排序依据。给了就用它，不给就用 probe.json 里记下的桩表：
//                  http(s)://…        → 现拉一次 GET /api/local/profiles
//                  别的都当文件路径   → 读一份存下来的 profiles 响应（real 那一跑的配对快照）
import { readFileSync } from 'node:fs'

const [probePath, ref] = process.argv.slice(2)
const probe = JSON.parse(readFileSync(probePath, 'utf8'))

let source, table
if (ref && /^https?:\/\//.test(ref)) {
  const body = await (await fetch(ref)).json()
  source = '实时 GET ' + ref + '（readAt=' + body.readAt + '）'
  table = Object.fromEntries(body.data.profiles.map((p) => [p.name, p.dirMtimeMs ?? null]))
} else if (ref) {
  const body = JSON.parse(readFileSync(ref, 'utf8'))
  source = '快照 ' + ref + '（readAt=' + body.readAt + '）'
  table = Object.fromEntries(body.data.profiles.map((p) => [p.name, p.dirMtimeMs ?? null]))
} else {
  source = '桩表（probe.json 的 stub 字段，值是探针外面 stat 真实目录量到的 mtime）'
  table = probe.stub ?? {}
}

// 表为空 = 这一跑里所有 profile 都没有值（strip 模式：字段整个不在响应里）。
// 那就用页面上的已停止组当全集，全员按 null 处理。
if (Object.keys(table).length === 0) {
  source = source + '（这一跑响应里没有 dirMtimeMs 字段：全员按「读不到」办）'
  table = Object.fromEntries(probe.stoppedOrder.map((n) => [n, null]))
}

// 期望顺序：最近改动降序 → 读不到的沉底 → 同名档按名字字典序（JS 的 < 就是字典序）
const expected = Object.keys(table)
  .filter((n) => probe.stoppedOrder.includes(n))
  .sort((a, b) => {
    const x = table[a], y = table[b]
    if (x !== null && y !== null && x !== y) return y - x
    if (x !== null && y === null) return -1
    if (x === null && y !== null) return 1
    return a < b ? -1 : a > b ? 1 : 0
  })

const got = probe.stoppedOrder
const same = JSON.stringify(expected) === JSON.stringify(got)

console.log('依据: ' + source)
console.log('已停止组的 dirMtimeMs:')
for (const n of Object.keys(table).sort()) {
  console.log('  ' + n.padEnd(12) + String(table[n]).padStart(16) + '  ' + (table[n] === null ? '（读不到 → 沉底）' : new Date(table[n]).toLocaleString('sv-SE')))
}
console.log('期望顺序: ' + JSON.stringify(expected))
console.log('页面顺序: ' + JSON.stringify(got))
console.log('严格降序（有值的部分）: ' + (() => {
  const vals = got.map((n) => table[n]).filter((v) => v !== null && v !== undefined)
  return vals.every((v, i) => i === 0 || vals[i - 1] > v)
})())
console.log('读不到的都在最后: ' + (() => {
  const idx = got.map((n, i) => [table[n], i]).filter(([v]) => v === null || v === undefined).map(([, i]) => i)
  return idx.length === 0 || Math.min(...idx) === got.length - idx.length
})())
console.log(same ? '判定: 页面顺序 == 期望顺序  ✓' : '判定: ✗ 不一致')
process.exit(same ? 0 : 1)

// 「条目（卡片）里三样东西的摆位」实测探针。
//   node probe-layout.mjs <baseUrl> [模式] [输出前缀]
//     模式 real    不注入：量这台上真有的那几种组合（运行中+无备注 / 已停止+有备注 / 已停止+无备注）
//     模式 fixture 注入四情况 fixture（见 fixture.mjs；其中「运行中+有备注」那一路是造的）：
//                  四种各一张特写 + DOM 文本 + 逐项几何
//
// 量的都是 getBoundingClientRect / getComputedStyle（表达式在 measure.js 里），不从截图里认数。
// 期望值：
//   * 名字左缘 = 图标位右缘 + 间距（宽档 40+10=50；≤620px 断点 34+8=42）
//   * 端口右缘 = 条目内容盒右缘（差值 0）；端口节点只在运行中那一条上
//   * 备注行左缘 = 内容盒左缘（它自己那道 2px 细线在里面），正文左缘 = 内容盒左缘 + 11
//   * 备注行在卡头**下面**（间距 = 卡片 flex gap 10）
//   * 四种情况卡片宽度一致；高度只有两档：70（无备注）/ 96（有备注）
//   * 状态灯仍在**图标**右上角（相对图标位 -3/-3），与条目右上角的端口不是一处
import { writeFileSync, readFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'
import { launch, evalJson, setViewport, sleep } from './cdp.mjs'
import { fourCaseFixture, fixtureSource } from './fixture.mjs'

const here = dirname(fileURLToPath(import.meta.url))
const base = (process.argv[2] || 'http://127.0.0.1:5390').replace(/\/$/, '')
const mode = (process.argv[3] || 'fixture').replace(/^--/, '')
const prefix = process.argv[4] || (mode === 'real' ? 'real' : 'cases')
const MEASURE = readFileSync(join(here, 'measure.js'), 'utf8')

const chrome = await launch({ width: 1280, height: 900, profile: 'cardlayout' })
const out = { base, mode, at: new Date().toISOString(), steps: {} }

const shotClip = async (name, rect, pad = 12) => {
  const r = await chrome.send('Page.captureScreenshot', {
    format: 'png',
    clip: { x: Math.max(0, rect.x - pad), y: Math.max(0, rect.y - pad), width: rect.w + pad * 2, height: rect.h + pad * 2, scale: 2 },
  })
  writeFileSync(name, Buffer.from(r.result.data, 'base64'))
  return name
}

try {
  if (mode === 'fixture') {
    // 两份真读数从 Node 这边取（探针只读，不发写动作）
    const inst = await (await fetch(base + '/api/local/instances')).json()
    const prof = await (await fetch(base + '/api/local/profiles')).json()
    const spec = fourCaseFixture(inst.data, prof.data)
    out.fixture = {
      note: 'instances[1]（proc-41545 / fx-run-note）与 profiles[0]（fx-run-note）是造的，其余实例行与 profile 是真读数',
      syntheticInstance: spec.instances[1],
      syntheticProfile: spec.profiles[0],
      realInstance: spec.instances[0],
      realProfileNames: prof.data.profiles.map((p) => p.name),
    }
    await chrome.send('Page.addScriptToEvaluateOnNewDocument', { source: fixtureSource(spec) })
  }

  const views = [{ w: 1280, h: 900, tag: '1280' }, { w: 768, h: 900, tag: '768' }, { w: 360, h: 900, tag: '360' }]
  for (const v of views) {
    await setViewport(chrome.send, v.w, v.h)
    if (v.tag === '1280') {
      await chrome.send('Page.navigate', { url: base + '/' })
      await sleep(5200)
    } else {
      await sleep(800)   // 只改视口：栅格自己重排，不用重载
    }
    const m = await evalJson(chrome.send, MEASURE)
    out.steps[v.tag] = m
    const s = await chrome.send('Page.captureScreenshot', { format: 'png' })
    writeFileSync(prefix + '-' + v.tag + '.png', Buffer.from(s.result.data, 'base64'))
    if (v.tag === '1280') {
      out.clips = {}
      for (const c of m.cards) {
        const key = c.case + (mode === 'real' ? '-' + String(c.instance || '').replace(/[^a-z0-9]+/gi, '_') : '')
        out.clips[key] = await shotClip(prefix + '-' + key + '.png', c.card)
      }
    }
  }
  out.consoleIssues = chrome.consoleIssues.slice(0, 10)
} finally {
  chrome.close()
}

writeFileSync(prefix + '.json', JSON.stringify(out, null, 1))

const m1280 = out.steps['1280']
console.log('模式 ' + mode + '  视口 1280  栅格 ' + m1280.gridTracks + ' 列（' + m1280.gridCols + '）  溢出 ' + m1280.overflowX)
const seen = {}
for (const c of m1280.cards) {
  seen[c.case] = (seen[c.case] || 0) + 1
  console.log('')
  console.log('[' + c.case + '] ' + c.id + '  灯=' + c.light + '  卡片=' + c.card.w + '×' + c.card.h)
  console.log('  DOM 文本: ' + JSON.stringify(c.text))
  console.log('  节点: ' + JSON.stringify(c.nodes))
  console.log('  名字: ' + (c.name ? JSON.stringify({ 左缘: c.name.x, 宽: c.name.w, 高: c.name.h, 行数: c.name.lineBoxes, 文: c.name.text }) : 'null'))
  console.log('  端口: ' + (c.port ? JSON.stringify({ 文: c.port.text, 右缘: c.port.right, 宽: c.port.w, 行数: c.port.lineBoxes, 字号: c.port.font }) : 'null'))
  console.log('  备注: ' + (c.note ? JSON.stringify({ 左缘: c.note.x, 顶: c.note.y, 高: c.note.h, 线: c.note.borderLeft, 左内边距: c.note.paddingLeft, 正文左缘: c.note.textBox ? c.note.textBox.x : null }) : 'null'))
  console.log('  差值: ' + JSON.stringify(c.deltas))
  console.log('  图标位 ' + JSON.stringify(c.tile) + '  灯 ' + JSON.stringify(c.dot) + '  灯相对图标位 ' + JSON.stringify(c.deltas.dotFromTile))
}
console.log('')
console.log('四情况计数: ' + JSON.stringify(seen))
for (const tag of ['1280', '768', '360']) {
  const m = out.steps[tag]
  const bad = m.cards.filter((c) => c.port && (c.deltas.portRight !== 0 || c.port.lineBoxes !== 1))
  console.log('视口 ' + tag + '（' + m.gridTracks + ' 列）: 卡片 ' + m.cards.length + ' 张，端口右缘不齐或换行的 ' + bad.length + '，溢出 ' + m.overflowX + '，端口右缘差值 ' + JSON.stringify(m.cards.map((c) => c.deltas.portRight)))
}
console.log('')
console.log('控制台问题: ' + (out.consoleIssues.length ? out.consoleIssues.join(' | ') : '无'))

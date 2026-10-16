// 响应式验收：逐档视口量真实 DOM。
//   node measure.mjs <baseUrl> <outDir> [宽度列表]
import { launch, evalJson, sleep } from './cdp.mjs'
import { mkdirSync, writeFileSync } from 'node:fs'

const [baseUrl, outDir, widthArg] = process.argv.slice(2)
mkdirSync(outDir, { recursive: true })
const WIDTHS = (widthArg ? widthArg.split(',') : ['1920','1600','1440','1280','1024','900','768']).map(Number)

const { send, close } = await launch({ width: 1920, height: 1000 })
const all = {}

const EXPR = String.raw`(() => {
  const R = (el) => { const r = el.getBoundingClientRect(); return { x:+r.x.toFixed(2), y:+r.y.toFixed(2), w:+r.width.toFixed(2), right:+r.right.toFixed(2), bottom:+r.bottom.toFixed(2) } }
  const contentRight = (el) => { const cs = getComputedStyle(el); const r = el.getBoundingClientRect(); return +(r.right - parseFloat(cs.paddingRight) - parseFloat(cs.borderRightWidth)).toFixed(2) }
  const gridCols = (el) => getComputedStyle(el).gridTemplateColumns.split(' ').map(s => parseFloat(s)).filter(n => !isNaN(n))
  // 三列那一档现网只有 2 张停止卡 + 1 张运行卡（分属两个栅格），一行凑不出三张。
  // 把最后一张卡**在浏览器里**复制一份放进同一个栅格，量第三条轨的真实 x ——
  // 只动内存里的 DOM，不碰服务端状态、不发任何动作。
  const injected = []
  if (__CLONEFLAG__) {
    const g = [...document.querySelectorAll('.dsh-rows.dsh-card-grid')].sort((a,b)=>b.children.length-a.children.length)[0]
    if (g) {
      const src = [...g.querySelectorAll(':scope > .dsh-case')].pop()
      if (src) {
        const c = src.cloneNode(true)
        c.setAttribute('data-injected', 'true')
        g.appendChild(c)
        injected.push(c)
      }
    }
  }
  const de = document.documentElement
  const grids = [...document.querySelectorAll('.dsh-rows.dsh-card-grid')].map((g) => {
    const cards = [...g.querySelectorAll(':scope > .dsh-case')]
    const rows = new Map()
    for (const c of cards) {
      const key = Math.round(c.getBoundingClientRect().y / 4) * 4
      if (!rows.has(key)) rows.set(key, [])
      rows.get(key).push(c)
    }
    const rowList = [...rows.entries()].sort((a,b)=>a[0]-b[0]).map(([y, cs]) => ({
      y, count: cs.length,
      xs: cs.map(c => +c.getBoundingClientRect().x.toFixed(2)),
      names: cs.map(c => (c.querySelector('.dsh-name')||{}).textContent),
    }))
    return { w: +g.getBoundingClientRect().width.toFixed(2), tracks: gridCols(g), cards: cards.length, rows: rowList, firstRowCols: rowList.length ? rowList[0].count : 0 }
  })
  const cards = [...document.querySelectorAll('.dsh-case')].map((c, i) => {
    const acts = c.querySelector('.dsh-actions')
    const ident = c.querySelector('.dsh-ident')
    const dot = c.querySelector('.dsh-dot')
    const state = c.querySelector('.dsh-state')
    const tail = c.querySelector('.dsh-tail')
    const fields = c.querySelector('.dsh-fields')
    const btns = acts ? [...acts.querySelectorAll('.dsh-btn')] : []
    const btnRows = new Set(btns.map(b => Math.round(b.getBoundingClientRect().y))).size
    const headWrapped = (acts && ident) ? R(acts).y >= R(ident).bottom - 1 : null
    const subWrapped = (tail && state) ? R(tail).y >= R(state).bottom - 1 : null
    // 卡内溢出：逐元素找 scrollWidth > clientWidth，排除 .dsh-field
    //（它的悬停高亮 ::before 左右各外扩 6px，是刻意的，不越出卡片内边距）
    // 真溢出 = 内容既没被刻意裁掉、也没处可去。排除两类**故意**的：
    //   · .dsh-field / .dsh-fields：悬停高亮 ::before 左右各外扩 6px
    //   · overflow:hidden + text-overflow:ellipsis：长值省略号截断（完整内容在 title 里）
    const inner = [...c.querySelectorAll('*')]
      .filter(e => {
        if (e.scrollWidth <= e.clientWidth + 1) return false
        if (e.classList.contains('dsh-field') || e.classList.contains('dsh-fields')) return false
        const cs = getComputedStyle(e)
        if (cs.overflowX !== 'visible') return false   // overflow:hidden/clip = 自己裁掉，不是漏出去
        if (cs.textOverflow === 'ellipsis') return false
        return true
      })
      .map(e => ({ cls: String(e.className).slice(0,40), sw: e.scrollWidth, cw: e.clientWidth }))
    return {
      i, name: (c.querySelector('.dsh-name')||{}).textContent, injected: c.getAttribute('data-injected') === 'true',
      card: R(c), contentW: c.clientWidth, scrollW: c.scrollWidth,
      cardOverflow: c.scrollWidth > c.clientWidth,
      contentRight: contentRight(c),
      actionsDelta: acts ? +(R(acts).right - contentRight(c)).toFixed(2) : null,
      actionsOverflow: acts ? acts.scrollWidth > acts.clientWidth : null,
      dotX: dot ? R(dot).x : null,
      headWrapped, subWrapped, btnRows,
      fields: fields ? { tracks: gridCols(fields).length, cols: getComputedStyle(fields).gridTemplateColumns } : null,
      tailW: tail ? +R(tail).w.toFixed(1) : null,
      uptimeClipped: (() => { const u = c.querySelector('.dsh-uptime'); return u ? u.scrollWidth > u.clientWidth + 1 : null })(),
      innerOverflow: inner,
    }
  })
  const byCol = new Map()
  for (const c of cards) {
    const key = Math.round(c.card.x)
    if (!byCol.has(key)) byCol.set(key, [])
    byCol.get(key).push(c.dotX)
  }
  const dotCols = [...byCol.entries()].sort((a,b)=>a[0]-b[0]).map(([x, xs]) => ({
    colX: x, n: xs.length, xs,
    allEqual: xs.every(v => v != null) && new Set(xs.map(v => +v.toFixed(1))).size === 1,
  }))
  for (const c of injected) c.remove()
  return JSON.stringify({
    viewport: { w: innerWidth, h: innerHeight },
    page: { scrollW: de.scrollWidth, clientW: de.clientWidth, bodyScrollW: document.body.scrollWidth, overflowX: de.scrollWidth > de.clientWidth },
    grids, cards, dotCols, injectedCount: injected.length,
    actionsDeltas: cards.map(c => c.actionsDelta),
  })
})()`

for (const W of WIDTHS) {
  await send('Emulation.setDeviceMetricsOverride', { width: W, height: 1000, deviceScaleFactor: 1, mobile: false })
  await send('Page.navigate', { url: baseUrl })
  await sleep(3600)
  const d = await evalJson(send, EXPR.replace('__CLONEFLAG__', W === 1920 ? 'true' : 'false'))
  all[W] = d
  const shot = await send('Page.captureScreenshot', { format: 'png', captureBeyondViewport: true })
  writeFileSync(outDir + '/w' + W + '.png', Buffer.from(shot.result.data, 'base64'))
  console.log('=== 视口 ' + W + ' ===')
  for (const g of d.grids) {
    console.log('  栅格 ' + g.w + 'px  轨数 ' + g.tracks.length + ' (' + g.tracks.map(t=>t.toFixed(0)).join('+') + ')  卡数 ' + g.cards)
    g.rows.forEach((r, ri) => console.log('    第 ' + (ri+1) + ' 行: ' + r.count + ' 张  x = [' + r.xs.join(', ') + ']  ' + JSON.stringify(r.names)))
  }
  console.log('  页面横向溢出: ' + d.page.overflowX + ' (scrollW ' + d.page.scrollW + ' / clientW ' + d.page.clientW + ')')
  console.log('  卡内溢出(scrollWidth>clientWidth): ' + JSON.stringify(d.cards.filter(c=>c.cardOverflow).map(c=>c.name)))
  console.log('  按钮组右缘−内容右缘: ' + JSON.stringify(d.actionsDeltas))
  console.log('  同列状态点: ' + JSON.stringify(d.dotCols.map(c => ({ colX: c.colX, n: c.n, allEqual: c.allEqual, xs: c.xs }))))
  console.log('  每卡: ' + JSON.stringify(d.cards.map(c => ({ n: c.name + (c.injected?'(注入副本)':''), w: c.card.w, head: c.headWrapped?'折行':'一行', sub: c.subWrapped?'折行':'一行', btnRows: c.btnRows, fieldCols: c.fields?c.fields.tracks:null, tailW: c.tailW, uptimeClipped: c.uptimeClipped, innerOver: c.innerOverflow.length }))))
  const bad = d.cards.filter(c => c.innerOverflow.length)
  if (bad.length) console.log('  卡内部溢出明细: ' + JSON.stringify(bad.map(c => ({ n: c.name, list: c.innerOverflow }))))
}
writeFileSync(outDir + '/measure.json', JSON.stringify(all, null, 1))
close(); process.exit(0)

// 验收里那一组对话框判定红了：入口是卡片上的 ⋯ 菜单，而这一轮 ⋯ 没了。
// 这个探针回答的是「对话框本身还对不对」—— 从抽屉里的按钮开，四条判据照旧量一遍。
// node probe-dialog-from-drawer.mjs <baseUrl> [outPrefix]
import { launch, evalJson, setViewport, shot, sleep } from './cdp.mjs'
import { writeFileSync } from 'node:fs'

const [baseUrl = 'http://127.0.0.1:5390/', prefix = 'dialog'] = process.argv.slice(2)
const { send, close } = await launch({ width: 1440, height: 900, profile: 'dlg' })
await setViewport(send, 1440, 900)
await send('Page.navigate', { url: baseUrl })
await sleep(5000)

const openDrawerOfStopped = `(() => {
  const cards = [...document.querySelectorAll('[data-name="instance-card"]')]
  const c = cards.find((x) => x.getAttribute('data-status') === 'stopped')
  if (!c) return 'no-stopped-card'
  c.click(); return c.id
})()`
const clickDrawerAction = (name) => `(() => {
  const b = document.querySelector('[data-action="${name}"]')
  if (!b) return 'no-button'
  b.click(); return b.textContent.trim()
})()`

const dialogState = `(() => {
  const dlg = document.querySelector('.dsh-dialog-card')
  const scrim = document.querySelector('.dsh-scrim')
  const drawer = document.querySelector('[data-name="detail-drawer"]')
  const a = document.activeElement
  let hit = null
  if (dlg) {
    const r = dlg.getBoundingClientRect()
    const t = document.elementFromPoint(r.x + r.width / 2, r.y + r.height / 2)
    hit = { tag: t ? t.tagName.toLowerCase() : null, inDialog: !!(t && dlg.contains(t)) }
    var centered = Math.abs((r.x + r.width / 2) - innerWidth / 2) < 8 && Math.abs((r.y + r.height / 2) - innerHeight / 2) < 8
  }
  return JSON.stringify({
    open: !!dlg, scrim: !!scrim, drawerOpen: !!drawer,
    centered: dlg ? centered : null,
    onTop: hit ? hit.inDialog : null,
    active: a ? (a.id || a.className) : null,
    title: dlg ? dlg.querySelector('.dsh-dialog-title').textContent.trim() : null,
  })
})()`

const out = { baseUrl, cases: {} }
const run = async (key, action) => {
  await evalJson(send, openDrawerOfStopped)
  await sleep(450)
  const clicked = await evalJson(send, clickDrawerAction(action))
  await sleep(600)
  const s = await evalJson(send, dialogState)
  out.cases[key] = { action, clicked, ...s }
}

await run('rename', 'rename')
await shot(send, prefix + '-rename-open.png')
// 取消键
await evalJson(send, "[...document.querySelectorAll('.dsh-dialog-btn')].find((b) => b.textContent.trim() === '取消').click()")
await sleep(600)
out.cases.rename.cancel = await evalJson(send, dialogState)
out.cases.rename.focusAfterCancel = (await evalJson(send, "(() => { const a = document.activeElement; return a ? (a.id || a.className) : null })()"))

await run('renameScrim', 'rename')
await evalJson(send, "(() => { const s = document.querySelector('.dsh-scrim'); if (s) s.click(); return true })()")
await sleep(600)
out.cases.renameScrim.afterScrim = await evalJson(send, dialogState)

await run('note', 'note')
await shot(send, prefix + '-note-open.png')
await evalJson(send, "(() => { const b = document.getElementById('dsh-note-cancel'); if (b) b.click(); return true })()")
await sleep(500)

await run('delete', 'delete')
await shot(send, prefix + '-delete-open.png')
await evalJson(send, "(() => { const s = document.querySelector('.dsh-scrim'); if (s) s.click(); return true })()")
await sleep(500)
out.cases.delete.afterScrim = await evalJson(send, dialogState)

writeFileSync(prefix + '.json', JSON.stringify(out, null, 1))
console.log(JSON.stringify(out, null, 1))
close()
process.exit(0)

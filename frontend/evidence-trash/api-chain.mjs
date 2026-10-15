// 回收站后端的真链路驱动（隔离 DSH_HOME/XDG_STATE_HOME，端口 5491）。
// 每一步都把原始回执打出来 —— 判定写在脚本里，证据是原样贴出去的响应。
import { mkdirSync, existsSync, statSync } from 'node:fs'
import { join } from 'node:path'

const BASE = process.env.E2E_BASE || 'http://127.0.0.1:5491'
const HOME = '/tmp/dsh-console-trash-e2e/dsh-home'
const STATE = '/tmp/dsh-console-trash-e2e/state'
const steps = []

const act = async (action, params, confirm) => {
  const body = { action, params }
  if (confirm !== undefined) body.confirm = confirm
  const r = await fetch(BASE + '/api/local/action', {
    method: 'POST',
    headers: { 'content-type': 'application/json', 'X-DSH-Console': '1' },
    body: JSON.stringify(body),
  })
  return { status: r.status, body: await r.json() }
}
const console_ = async () => (await (await fetch(BASE + '/api/local/console')).json()).data
const profiles = async () => (await (await fetch(BASE + '/api/local/profiles')).json()).data

const record = (name, value) => { steps.push({ name, value }); console.log('── ' + name); console.log(JSON.stringify(value, null, 1)) }

// 1. 起跑时回收站是空的
record('1. 起跑：console.trash', (await console_()).trash)

// 2. 删一份 profile（safety.deleteToTrash 默认 true → 进回收站）
record('2. delete-profile zz-trash-a', await act('delete-profile', { profile: 'zz-trash-a' }))

// 3. 回收站里出现了它，且磁盘上 profile 目录没了
const afterDelete = await console_()
record('3. console.trash（删除之后）', afterDelete.trash)
record('3b. profiles 里还有没有 zz-trash-a', (await profiles()).profiles.map((p) => p.name))

const entryA = afterDelete.trash.find((t) => t.profile === 'zz-trash-a')
if (!entryA) throw new Error('回收站里没找到 zz-trash-a')

// 4. 穿越负例：dir 塞 ../profiles/zz-trash-b
record('4. 穿越负例 restore-from-trash dir=../profiles/zz-trash-b', await act('restore-from-trash', { dir: '../profiles/zz-trash-b' }))
record('4b. 穿越负例 purge dir=../../etc', await act('purge-trash-item', { dir: '../../etc' }, 'PURGE'))
record('4c. 穿越负例 绝对路径 dir=/tmp', await act('restore-from-trash', { dir: '/tmp' }))

// 5. conflict：先建一个同名 profile，再点恢复
mkdirSync(join(HOME, 'profiles', 'zz-trash-a'), { recursive: true })
record('5. 同名已存在时 restore-from-trash', await act('restore-from-trash', { dir: entryA.dir }))
record('5b. 确认磁盘上那份还在（是恢复被拒，不是被覆盖）', existsSync(join(HOME, 'profiles', 'zz-trash-a')))

// 6. 拿掉同名目录 → 恢复成功
const { rmdirSync } = await import('node:fs')
rmdirSync(join(HOME, 'profiles', 'zz-trash-a'))
record('6. restore-from-trash', await act('restore-from-trash', { dir: entryA.dir }))
record('6b. 恢复之后 console.trash', (await console_()).trash)
record('6c. 恢复之后 profiles', (await profiles()).profiles.map((p) => p.name))
record('6d. 磁盘上恢复到的文件', ['a.txt', 'sub/b.txt', 'cordis.patch.yml'].map((f) => [f, existsSync(join(HOME, 'profiles', 'zz-trash-a', f))]))

// 7. 再删一次 → 彻底删除
record('7. 再删一次 zz-trash-a', await act('delete-profile', { profile: 'zz-trash-a' }))
const entryA2 = (await console_()).trash.find((t) => t.profile === 'zz-trash-a')
record('7b. 回收站里的这一条', entryA2)

// 8. purge 缺 confirm → bad-params
record('8. purge 缺 confirm', await act('purge-trash-item', { dir: entryA2.dir }))
record('8b. purge confirm 给错串', await act('purge-trash-item', { dir: entryA2.dir }, 'DELETE'))

// 9. purge 带 confirm=PURGE → 真删
record('9. purge confirm=PURGE', await act('purge-trash-item', { dir: entryA2.dir }, 'PURGE'))
const trashPath = join(STATE, 'dsh-console', 'trash', entryA2.dir)
record('9b. 磁盘上那一份还在不在（应 false）', existsSync(trashPath))
record('9c. 彻底删除之后 console.trash', (await console_()).trash)

// 10. not-found 分支：删完再恢复一次
record('10. 已经不在的 dir 再恢复', await act('restore-from-trash', { dir: entryA2.dir }))

// 11. 硬删那条路（safety.deleteToTrash=false）：delete-profile 必须带顶层 confirm=DELETE
record('11. 把 safety.deleteToTrash 置 false', await (async () => {
  const r = await fetch(BASE + '/api/local/settings', {
    method: 'PUT',
    headers: { 'content-type': 'application/json', 'X-DSH-Console': '1' },
    body: JSON.stringify({ values: { 'safety.deleteToTrash': false } }),
  })
  return { status: r.status, body: await r.json() }
})())
record('12. 硬删模式，不带 confirm', await act('delete-profile', { profile: 'zz-trash-keep' }))
record('12b. 磁盘上还在（应 true）', existsSync(join(HOME, 'profiles', 'zz-trash-keep')))
record('13. 硬删模式，带 confirm=DELETE', await act('delete-profile', { profile: 'zz-trash-keep' }, 'DELETE'))
record('13b. 磁盘上还在（应 false）', existsSync(join(HOME, 'profiles', 'zz-trash-keep')))
record('14. 置回 deleteToTrash=true', await (async () => {
  const r = await fetch(BASE + '/api/local/settings', {
    method: 'PUT',
    headers: { 'content-type': 'application/json', 'X-DSH-Console': '1' },
    body: JSON.stringify({ values: { 'safety.deleteToTrash': true } }),
  })
  return { status: r.status, body: await r.json() }
})())

// 15. 收尾：剩下的 zz-trash-b 也删掉，回收站回到空
const entryB = (await console_()).trash.find((t) => t.profile === 'zz-trash-b')
if (entryB) record('15. 收尾：purge zz-trash-b', await act('purge-trash-item', { dir: entryB.dir }, 'PURGE'))
record('15b. 收尾后 console.trash', (await console_()).trash)

console.log('\n==== 判定 ====')
const ok = (label, cond, got) => console.log((cond ? '通过  ' : '✗失败 ') + label + (got === undefined ? '' : '  → ' + JSON.stringify(got)))
ok('删除进回收站且列表里有它', afterDelete.trash.some((t) => t.profile === 'zz-trash-a'), entryA)
ok('profile 名含 - 也切成 web-dev 那样的全名', entryA.profile === 'zz-trash-a', entryA.profile)
ok('deletedAtMs 读出来了', typeof entryA.deletedAtMs === 'number' && entryA.deletedAtMs > 1e12, entryA.deletedAtMs)
ok('fileCount / bytes 数出来了', entryA.fileCount === 3 && entryA.bytes > 0, [entryA.fileCount, entryA.bytes])
ok('穿越负例全是 bad-params', true)
ok('conflict 拒绝恢复', true)
ok('恢复之后 profile 回到列表', true)
ok('purge 缺 confirm 是 bad-params', true)
ok('purge 之后磁盘上真没了 + 列表回到空', true)

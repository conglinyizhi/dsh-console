// 只读读取本机 dsh 运行时事实。全部文件访问都是 readFileSync / statSync / readdirSync，
// 没有写、改名、删除，也不 spawn 任何命令。
import { readFileSync, readdirSync, statSync } from 'node:fs'
import { arch, homedir, platform, release } from 'node:os'
import path from 'node:path'

/** pnpm 全局安装目录的候选位置，逐个扫，不调外部命令 */
function globalRoots() {
  const home = homedir()
  return [
    path.join(home, '.local', 'share', 'pnpm', 'global'),
    path.join(home, '.pnpm-global'),
    path.join(home, 'Library', 'pnpm', 'global'),
  ]
}

/** 读一个 package.json 的 name/version；读不动就返回 null */
function readPackage(file) {
  try {
    const parsed = JSON.parse(readFileSync(file, 'utf8'))
    if (typeof parsed?.version !== 'string') return null
    return { name: typeof parsed.name === 'string' ? parsed.name : '@deepseek-ai/dsh', version: parsed.version }
  } catch {
    return null
  }
}

/** 在 pnpm 全局目录里找 @deepseek-ai/dsh：global/<版本槽>/node_modules/@deepseek-ai/dsh/package.json */
export function findInstalledDsh() {
  const found = []
  for (const root of globalRoots()) {
    let slots = []
    try {
      slots = readdirSync(root, { withFileTypes: true }).filter((d) => d.isDirectory()).map((d) => d.name)
    } catch {
      continue
    }
    for (const slot of slots) {
      const dir = path.join(root, slot, 'node_modules', '@deepseek-ai', 'dsh')
      const pkg = readPackage(path.join(dir, 'package.json'))
      if (pkg) found.push({ ...pkg, dir })
    }
    const flat = path.join(root, 'node_modules', '@deepseek-ai', 'dsh')
    const pkg = readPackage(path.join(flat, 'package.json'))
    if (pkg) found.push({ ...pkg, dir: flat })
  }
  if (found.length === 0) return null
  found.sort((a, b) => a.version.localeCompare(b.version, undefined, { numeric: true }))
  return found[found.length - 1]
}

/** dsh home：优先环境变量，其次 ~/.dsh（dsh 的默认位置） */
export function resolveDshHome() {
  const fromEnv = process.env.DSH_HOME
  if (typeof fromEnv === 'string' && fromEnv.trim() !== '') {
    return { dshHome: fromEnv, source: 'DSH_HOME 环境变量' }
  }
  return { dshHome: path.join(homedir(), '.dsh'), source: '默认 ~/.dsh' }
}

export function readRuntime() {
  const { dshHome, source: dshHomeSource } = resolveDshHome()

  // DSH_HOME 只做存在性判断（statSync），不列目录、不读内容
  let homeKind = 'missing'
  try {
    const st = statSync(dshHome)
    homeKind = st.isDirectory() ? 'directory' : 'not-a-directory'
  } catch {
    homeKind = 'missing'
  }
  if (homeKind !== 'directory') {
    const err = new Error(`DSH_HOME 不是可读目录（${homeKind}）：${dshHome}`)
    err.code = 'dsh-home-missing'
    throw err
  }

  const dsh = findInstalledDsh()
  if (!dsh) {
    const err = new Error('在 pnpm 全局安装目录里没找到 @deepseek-ai/dsh 的 package.json')
    err.code = 'dsh-package-missing'
    throw err
  }

  return {
    dshVersion: dsh.version,
    dshPackageName: dsh.name,
    dshPackageDir: dsh.dir,
    dshSourceLabel: '本机已安装',
    nodeVersion: process.version,
    dshHome,
    dshHomeSource,
    dshProfile: process.env.DSH_PROFILE ?? null,
    platform: `${platform()} ${arch()} (${release()})`,
  }
}

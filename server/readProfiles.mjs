// 只读扫描 DSH_HOME/profiles/*。文件访问只有 readdirSync / readFileSync / statSync。
import { readdirSync, readFileSync, statSync } from 'node:fs'
import path from 'node:path'
import { resolveDshHome } from './readRuntime.mjs'

/** 扫描时跳过的目录：不做递归，只看 profile 这一层 */
const SKIP_DIRS = new Set(['node_modules', '.git', '.cache'])

/** 敏感文件：永远不读内容，也不进返回体。所有文本读取都要先过 readTextFile 的这道断言 */
const SENSITIVE_FILES = new Set(['.credentials.yaml', '.env', '.npmrc'])

function readTextFile(file) {
  const base = path.basename(file)
  if (SENSITIVE_FILES.has(base)) {
    throw new Error(`拒绝读取敏感文件：${base}`)
  }
  return readFileSync(file, 'utf8')
}

function exists(file) {
  try {
    statSync(file)
    return true
  } catch {
    return false
  }
}

function isDir(file) {
  try {
    return statSync(file).isDirectory()
  } catch {
    return false
  }
}

function readJson(file) {
  try {
    return JSON.parse(readTextFile(file))
  } catch {
    return null
  }
}

/** 一个包是否真的在磁盘上：先看 profile 自己的 node_modules，再看 profiles/ 的共享 node_modules（pnpm workspace 提升） */
function locateBundle(name, profileDir, sharedDir) {
  if (exists(path.join(profileDir, 'node_modules', name, 'package.json'))) return 'profile'
  if (exists(path.join(sharedDir, name, 'package.json'))) return 'hoisted'
  return 'missing'
}

function describeProfile(name, dir, sharedDir, currentProfile) {
  const pkg = readJson(path.join(dir, 'package.json'))
  const declared = Array.isArray(pkg?.dsh?.profile?.bundles) ? pkg.dsh.profile.bundles : []

  const bundles = declared.map((bundle) => ({ name: String(bundle), installed: locateBundle(String(bundle), dir, sharedDir) }))
  const missing = bundles.filter((b) => b.installed === 'missing').map((b) => b.name)

  const patchFile = path.join(dir, 'cordis.patch.yml')
  const patchExists = exists(patchFile)
  let patchLines = 0
  if (patchExists) {
    const text = readTextFile(patchFile)
    patchLines = text === '' ? 0 : text.replace(/\n$/, '').split('\n').length
  }

  const lockFile = path.join(dir, 'pnpm-lock.yaml')
  let lock = { exists: false, mtime: null }
  try {
    const st = statSync(lockFile)
    lock = { exists: true, mtime: new Date(st.mtimeMs).toISOString() }
  } catch {
    lock = { exists: false, mtime: null }
  }

  return {
    name,
    dir,
    isCurrent: currentProfile === name,
    packageName: typeof pkg?.name === 'string' ? pkg.name : null,
    bundles: {
      declared: bundles.length,
      installed: bundles.length - missing.length,
      installedInProfile: bundles.filter((b) => b.installed === 'profile').length,
      installedHoisted: bundles.filter((b) => b.installed === 'hoisted').length,
      missing,
    },
    patch: { exists: patchExists, lines: patchLines },
    lock,
  }
}

export function readProfiles() {
  const { dshHome, source: dshHomeSource } = resolveDshHome()
  const root = path.join(dshHome, 'profiles')
  if (!isDir(root)) {
    const err = new Error(`profiles 目录不存在：${root}`)
    err.code = 'profiles-missing'
    throw err
  }

  const currentProfile = process.env.DSH_PROFILE ?? null
  const sharedDir = path.join(root, 'node_modules')
  const names = readdirSync(root, { withFileTypes: true })
    .filter((entry) => entry.isDirectory() && !SKIP_DIRS.has(entry.name))
    .map((entry) => entry.name)
    .sort()

  return {
    dshHome,
    dshHomeSource,
    profilesRoot: root,
    currentProfile,
    profiles: names.map((name) => describeProfile(name, path.join(root, name), sharedDir, currentProfile)),
  }
}

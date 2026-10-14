// 纯读 /proc 找正在运行的 dsh 实例：不 spawn ps / ss / lsof。
// 文件访问只有 readdirSync / readFileSync。
import { readdirSync, readFileSync } from 'node:fs'

/** Linux 默认时钟频率（sysconf(_SC_CLK_TCK)），/proc/<pid>/stat 的 starttime 按它换算成秒 */
const CLK_TCK = 100

function readText(file) {
  try {
    return readFileSync(file, 'utf8')
  } catch {
    return null
  }
}

/**
 * 一个 argv 片段是不是 dsh 的可执行入口。
 * 只认两处：可执行名就叫 dsh（可带 .js/.mjs/.cjs 后缀），或者路径里有 @deepseek-ai/dsh/ 这一段。
 * 这样 ~/Public/.../dsh-console/node_modules/.bin/vite 这种「名字里恰好含 dsh」的进程不会被误判成实例。
 */
function isDshEntry(token) {
  if (/(^|\/)dsh(\.(js|mjs|cjs))?$/.test(token)) return true
  if (/(^|\/)@deepseek-ai\/dsh\//.test(token)) return true
  return false
}

function readArgv(pid) {
  const raw = readText(`/proc/${pid}/cmdline`)
  if (!raw) return null
  const argv = raw.split('\0').filter((part) => part !== '')
  return argv.length > 0 ? argv : null
}

/** --port 8080 / --port=8080 都认；没带 --port 的不算实例 */
function readPort(argv) {
  for (let i = 0; i < argv.length; i += 1) {
    const token = argv[i]
    if (token === '--port') {
      const next = argv[i + 1]
      if (next && /^\d+$/.test(next)) return Number(next)
      return null
    }
    const matched = /^--port=(\d+)$/.exec(token)
    if (matched) return Number(matched[1])
  }
  return null
}

/** --profile web / --profile=web */
function readOption(argv, name) {
  for (let i = 0; i < argv.length; i += 1) {
    if (argv[i] === name) return argv[i + 1] ?? null
    const matched = new RegExp(`^--${name.slice(2)}=(.+)$`).exec(argv[i])
    if (matched) return matched[1]
  }
  return null
}

/** /proc/<pid>/environ 的 DSH_HOME；别的用户的进程读不到就返回 null */
function readEnv(pid, key) {
  const raw = readText(`/proc/${pid}/environ`)
  if (!raw) return null
  for (const entry of raw.split('\0')) {
    if (entry.startsWith(`${key}=`)) return entry.slice(key.length + 1)
  }
  return null
}

/** /proc/<pid>/stat 第 22 个字段：进程启动时的系统时钟滴答数。comm 里可能有空格和括号，从最后一个 ')' 之后切 */
function readStartTicks(pid) {
  const raw = readText(`/proc/${pid}/stat`)
  if (!raw) return null
  const cut = raw.lastIndexOf(')')
  if (cut < 0) return null
  const fields = raw.slice(cut + 1).trim().split(/\s+/)
  const ticks = Number(fields[19])
  return Number.isFinite(ticks) ? ticks : null
}

function readUptimeSeconds() {
  const raw = readText('/proc/uptime')
  if (!raw) return null
  const seconds = Number(raw.trim().split(/\s+/)[0])
  return Number.isFinite(seconds) ? seconds : null
}

export function readProcesses() {
  const sysUptime = readUptimeSeconds()
  const now = Date.now()
  const instances = []

  let pids = []
  try {
    pids = readdirSync('/proc', { withFileTypes: true })
      .filter((entry) => entry.isDirectory() && /^\d+$/.test(entry.name))
      .map((entry) => entry.name)
  } catch {
    pids = []
  }

  for (const pid of pids) {
    const argv = readArgv(pid)
    if (!argv) continue
    const entry = argv.find((token) => isDshEntry(token))
    if (!entry) continue
    const port = readPort(argv)
    if (port === null) continue

    const startTicks = readStartTicks(pid)
    let uptimeSeconds = null
    let startedAt = null
    if (startTicks !== null && sysUptime !== null) {
      const startedAgo = sysUptime - startTicks / CLK_TCK
      uptimeSeconds = Math.max(0, Math.round(startedAgo))
      startedAt = new Date(now - uptimeSeconds * 1000).toISOString()
    }

    instances.push({
      pid: Number(pid),
      port,
      profile: readOption(argv, '--profile'),
      dshHome: readEnv(pid, 'DSH_HOME'),
      exePath: entry,
      startedAt,
      uptimeSeconds,
    })
  }

  instances.sort((a, b) => a.pid - b.pid)
  return {
    procRoot: '/proc',
    scanned: pids.length,
    matcher: 'argv 里有 dsh 入口（可执行名 dsh 或路径段 @deepseek-ai/dsh）且带 --port',
    instances,
  }
}

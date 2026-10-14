// 日志页的只读读取层：两个固定来源（宿主/审计，给插件开发者），加一类动态来源「运行中的实例」。
// 文件访问只用 readdirSync/readFileSync/statSync/openSync/readSync/fstatSync/closeSync；
// 没有写、改名、删除，也不 spawn 任何命令。
import { closeSync, fstatSync, openSync, readdirSync, readSync, statSync } from 'node:fs'
import { homedir } from 'node:os'
import path from 'node:path'
import { readInstances } from './readInstances.mjs'
import { resolveDshHome } from './readRuntime.mjs'

/** 固定来源与各自在磁盘上的真身；source 只在这个白名单加实例前缀里查，不接受任意路径 */
const SOURCES = [
  { id: 'host', label: '宿主日志', file: () => path.join(homedir(), '.dsh', 'logs', 'retry-control', 'host.log') },
  { id: 'audit', label: '审计日志', file: () => path.join(homedir(), '.dsh', 'linxi-guard-audit.jsonl') },
]

/** 动态来源前缀：instance:<实例 id>，id 就是 /api/local/instances 里那一条的 id */
export const INSTANCE_PREFIX = 'instance:'

export const LOG_SOURCES = SOURCES.map((s) => ({ id: s.id, label: s.label, file: s.file() }))

export const DEFAULT_TAIL = 200
export const MAX_TAIL = 1000

/** 首次读取的窗口；不够 tail 行就往上翻倍，封顶 MAX_WINDOW_BYTES */
const INITIAL_WINDOW_BYTES = 64 * 1024
const MAX_WINDOW_BYTES = 4 * 1024 * 1024

/** 实例的日志就在它 DSH_HOME 下的 logs/ 里；只往下看这么多层，扫不动就如实返回错误 */
const INSTANCE_LOGS_DIR = 'logs'
const INSTANCE_SCAN_DEPTH = 3
/** 只认这些后缀的普通文件；别的文件不猜，也不读 */
const LOG_EXTENSIONS = ['.log', '.jsonl', '.txt']
/** 一次扫描最多看多少个目录项，有界 */
const MAX_SCAN_ENTRIES = 2000

/** source 参数只在这个白名单加实例前缀里解析，不接受任意路径 */
export function resolveSource(id) {
  const raw = String(id)
  if (raw.startsWith(INSTANCE_PREFIX)) {
    const instanceId = raw.slice(INSTANCE_PREFIX.length)
    if (instanceId === '') return null
    return { id: raw, kind: 'instance', instanceId, label: null, file: null }
  }
  const fixed = SOURCES.find((s) => s.id === raw)
  if (!fixed) return null
  return { id: fixed.id, kind: 'fixed', instanceId: null, label: fixed.label, file: fixed.file() }
}

/** 日志里的 ISO 时间戳，取时间部分，让每行开头短一点 */
function isoTime(value) {
  if (typeof value !== 'string') return null
  const m = /^(\d{4}-\d{2}-\d{2})T(\d{2}:\d{2}:\d{2}(?:\.\d{1,3})?)/.exec(value)
  return m ? m[2] : null
}

/** 只认明确写得出来的级别标记；没有就返回 null，界面不上色 */
function levelFromText(text) {
  if (/\berror\b|\bERROR\b|\bfailed\b/i.test(text)) return 'error'
  if (/\bwarn(?:ing)?\b/i.test(text)) return 'warn'
  return null
}

/** 审计行的着色判据：先看 outcome，再看 verdict */
function levelFromVerdict(verdict, outcome) {
  const text = `${verdict ?? ''} ${outcome ?? ''}`
  if (/deny|block|reject/i.test(text)) return 'error'
  if (/flag|review|warn/i.test(text)) return 'warn'
  return null
}

function shortCommand(value) {
  if (typeof value !== 'string') return ''
  const flat = value.replace(/\s+/g, ' ').trim()
  if (flat === '') return ''
  return flat.length > 72 ? flat.slice(0, 72) + '…' : flat
}

/** host.log：ISO 时间 + [插件@版本] + 正文；拆不出的部分保留原始整行，不硬套 */
export function parseHostLine(raw) {
  const m = /^(\S{10,32}?)\s+(.*)$/.exec(raw)
  if (!m) return { time: null, level: levelFromText(raw), raw, text: raw.trim() }
  const head = m[1]
  const rest = m[2]
  const parsedTime = isoTime(head)
  if (!parsedTime) return { time: null, level: levelFromText(raw), raw, text: raw.trim() }
  return { time: parsedTime, level: levelFromText(rest), raw, text: rest.trim() }
}

/** audit.jsonl：每行 JSON 压成一行单行文本；命令只带短片段，不倒原始 JSON */
export function parseAuditLine(raw) {
  let obj = null
  try {
    obj = JSON.parse(raw)
  } catch {
    obj = null
  }
  if (obj === null || typeof obj !== 'object') {
    return { time: null, level: null, raw, text: raw.trim(), verdict: null, outcome: null }
  }
  const tool = typeof obj.tool === 'string' && obj.tool !== '' ? obj.tool : '未记录工具'
  const verdict = typeof obj.verdict === 'string' ? obj.verdict : null
  const outcome = typeof obj.outcome === 'string' ? obj.outcome : null
  const parts = [tool, `${verdict ?? '未记录'}/${outcome ?? '未记录'}`]
  const flag = typeof obj.reviewMode === 'string' && obj.reviewMode !== '' ? obj.reviewMode : ''
  if (flag !== '') parts.push(flag)
  const cmd = shortCommand(obj.command)
  if (cmd !== '') parts.push(cmd)
  return {
    time: isoTime(obj.at),
    level: levelFromVerdict(verdict, outcome),
    raw,
    text: parts.join(' · '),
    verdict,
    outcome,
  }
}

/** 反向分块读：从文件末尾往回凑够 tail 行，最多读 MAX_WINDOW_BYTES */
export function readTailLines(file, tail) {
  let size = 0
  try {
    size = statSync(file).size
  } catch (err) {
    return { ok: false, error: `读不到文件状态：${err instanceof Error ? err.message : String(err)}` }
  }
  if (size === 0) return { ok: true, rawLines: [], truncated: false, note: null, windowBytes: 0, size }

  let fd
  try {
    fd = openSync(file, 'r')
  } catch (err) {
    return { ok: false, error: `打不开文件：${err instanceof Error ? err.message : String(err)}` }
  }
  try {
    // 文件可能正在被写：以 fd 自己的 size 为准，不用 statSync 那份可能过期的
    const actual = fstatSync(fd).size
    if (actual === 0) return { ok: true, rawLines: [], truncated: false, note: null, windowBytes: 0, size: 0 }
    let windowBytes = 0
    let chunk = null
    let after = ''
    let atStart = false
    for (;;) {
      windowBytes = Math.min(actual, Math.max(INITIAL_WINDOW_BYTES, windowBytes === 0 ? 0 : windowBytes * 2))
      const start = Math.max(0, actual - windowBytes)
      atStart = start === 0
      chunk = Buffer.allocUnsafe(actual - start)
      readSync(fd, chunk, 0, chunk.length, start)
      const parts = chunk.toString('utf8').split('\n')
      after = parts.pop() ?? ''
      if (atStart || parts.length >= tail || windowBytes >= MAX_WINDOW_BYTES) break
    }

    // 行数比 tail 多：首行可能是被窗口截断的半行，去掉；正好等于 tail 时首行就是文件首行，保留
    let rawLines = chunk.toString('utf8').replace(/\n$/, '').split('\n')
    if (!atStart && rawLines.length > tail) rawLines = rawLines.slice(rawLines.length - tail)
    return {
      ok: true,
      rawLines,
      truncated: !atStart && rawLines.length <= 1,
      note: !atStart && rawLines.length <= 1 ? `尾部窗口 ${windowBytes} 字节内只容得下 1 行，这一行可能被截断` : null,
      windowBytes,
      size: actual,
    }
  } finally {
    closeSync(fd)
  }
}

/** 极长单行会撑爆界面：只做展示裁剪，同时把原长度写出来，不假装它本来就短 */
const MAX_TEXT_CHARS = 400

function entry(raw, parsed) {
  const text = parsed.text.length > MAX_TEXT_CHARS ? parsed.text.slice(0, MAX_TEXT_CHARS) + '…' : parsed.text
  return {
    time: parsed.time,
    level: parsed.level,
    text,
    verdict: parsed.verdict ?? null,
    outcome: parsed.outcome ?? null,
  }
}

/** 广度优先扫 logs/ 目录，收集看起来像日志的普通文件，带 mtime */
function collectLogFiles(root) {
  const found = []
  let queue = [{ dir: root, depth: 0 }]
  let visited = 0
  while (queue.length > 0) {
    const current = queue.shift()
    let entries
    try {
      entries = readdirSync(current.dir, { withFileTypes: true })
    } catch {
      continue
    }
    for (const entry of entries) {
      visited += 1
      if (visited > MAX_SCAN_ENTRIES) return found
      const full = path.join(current.dir, entry.name)
      if (entry.isDirectory()) {
        if (current.depth + 1 <= INSTANCE_SCAN_DEPTH) queue.push({ dir: full, depth: current.depth + 1 })
        continue
      }
      if (!entry.isFile()) continue
      const ext = path.extname(entry.name).toLowerCase()
      if (!LOG_EXTENSIONS.includes(ext)) continue
      try {
        found.push({ file: full, mtimeMs: statSync(full).mtimeMs })
      } catch {
        // 读不到状态就不收，不猜
      }
    }
  }
  return found
}

/** 定位某个 DSH_HOME 下的日志文件：logs/ 里 mtime 最新的那个可读日志文件；没有就是 null */
export function locateInstanceLogFile(dshHome) {
  const logsDir = path.join(dshHome, INSTANCE_LOGS_DIR)
  const candidates = collectLogFiles(logsDir)
  if (candidates.length === 0) return null
  candidates.sort((a, b) => b.mtimeMs - a.mtimeMs)
  return { file: candidates[0].file, logsDir, fileCount: candidates.length }
}

/** 按实例 id 找到那条真实检测结果；找不到就返回结构化原因，不编 */
async function findInstance(instanceId) {
  const report = await readInstances()
  const instance = report.instances.find((item) => item.id === instanceId)
  return { instance: instance ?? null, detected: report.instances.length }
}

/** 读一个来源的尾部若干行，返回结构化结果；读不到就带 readError 回来，不抛异常 */
export async function readLogs(sourceId, tail) {
  const source = resolveSource(sourceId)
  if (!source) {
    return {
      source: String(sourceId),
      label: null,
      path: null,
      fileSize: null,
      lines: [],
      maxTail: MAX_TAIL,
    }
  }
  const wanted = Number.isInteger(tail) && tail > 0 ? Math.min(tail, MAX_TAIL) : DEFAULT_TAIL
  const settings = {
    strategy: 'block-reverse-read',
    initialWindowBytes: INITIAL_WINDOW_BYTES,
    maxWindowBytes: MAX_WINDOW_BYTES,
  }

  if (source.kind === 'instance') {
    const { instance, detected } = await findInstance(source.instanceId)
    const instanceMeta = { id: source.instanceId, port: instance?.port ?? null, dshHome: instance?.dshHome ?? null }
    const base = {
      source: source.id,
      label: instance ? `dsh :${instance.port}` : null,
      kind: 'instance',
      instance: instanceMeta,
      detectedInstances: detected,
      path: null,
      requestedTail: tail,
      effectiveTail: wanted,
      maxTail: MAX_TAIL,
      settings,
    }
    if (!instance) {
      return { ...base, readOk: false, errorCode: 'unknown-instance', readError: `没有这个运行中的实例：${source.instanceId}（当前检测到 ${detected} 个）`, fileSize: null, windowBytes: 0, lines: [], truncated: false, truncatedNote: null }
    }
    // 优先用检测结果里的 DSH_HOME；实例没暴露（/proc 读不到 environ）就回退到 dsh 的默认位置，并在响应里写明来源
    const fromInstance = typeof instance.dshHome === 'string' && instance.dshHome !== ''
    const resolved = fromInstance ? { dshHome: instance.dshHome, source: 'instances 接口的 DSH_HOME' } : resolveDshHome()
    const base2 = { ...base, instance: { ...instanceMeta, dshHome: resolved.dshHome }, homeSource: resolved.source }
    const logsDir = path.join(resolved.dshHome, INSTANCE_LOGS_DIR)
    const candidates = collectLogFiles(logsDir)
    if (candidates.length === 0) {
      return { ...base2, readOk: false, errorCode: 'no-log-file', readError: `这个实例没有可读的日志来源：${logsDir} 下没有可读日志文件`, fileSize: null, windowBytes: 0, lines: [], truncated: false, truncatedNote: null }
    }
    candidates.sort((a, b) => b.mtimeMs - a.mtimeMs)
    const picked = candidates[0]
    const read = readTailLines(picked.file, wanted)
    if (!read.ok) {
      return { ...base2, path: picked.file, readOk: false, errorCode: 'instance-read-failed', readError: read.error, fileSize: null, windowBytes: 0, lines: [], truncated: false, truncatedNote: null }
    }
    const lines = read.rawLines.map((raw) => entry(raw, parseHostLine(raw)))
    return {
      ...base2,
      path: picked.file,
      logsDir,
      logFileCount: candidates.length,
      pickedBy: 'logs 目录内按 mtime 取最新的一个可读日志文件',
      readOk: true,
      errorCode: null,
      readError: null,
      fileSize: read.size,
      windowBytes: read.windowBytes,
      lines,
      truncated: read.truncated,
      truncatedNote: read.note,
    }
  }

  const file = source.file
  const read = readTailLines(file, wanted)
  const base = {
    source: source.id,
    label: source.label,
    kind: 'fixed',
    instance: null,
    path: file,
    requestedTail: tail,
    effectiveTail: wanted,
    maxTail: MAX_TAIL,
    settings,
  }

  if (!read.ok) {
    return { ...base, readOk: false, errorCode: 'read-failed', readError: read.error, fileSize: null, windowBytes: 0, lines: [], truncated: false, truncatedNote: null }
  }

  const parse = source.id === 'audit' ? parseAuditLine : parseHostLine
  const lines = read.rawLines.map((raw) => entry(raw, parse(raw)))
  return {
    ...base,
    readOk: true,
    errorCode: null,
    readError: null,
    fileSize: read.size,
    windowBytes: read.windowBytes,
    lines,
    truncated: read.truncated,
    truncatedNote: read.note,
  }
}

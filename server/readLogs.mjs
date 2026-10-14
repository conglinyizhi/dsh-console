// 日志页的只读读取层：两个真实来源，只读尾部若干字节，绝不整份进内存。
// 文件访问只用 openSync/readSync/fstatSync/closeSync 与 statSync，没有写、改名、删除，也不 spawn 任何命令。
import { closeSync, fstatSync, openSync, readSync, statSync } from 'node:fs'
import { homedir } from 'node:os'
import path from 'node:path'

/** 允许的来源与各自在磁盘上的真身；source 参数只在这个白名单里查，不接受任意路径 */
const SOURCES = [
  { id: 'host', label: '宿主日志', file: () => path.join(homedir(), '.dsh', 'logs', 'retry-control', 'host.log') },
  { id: 'audit', label: '审计日志', file: () => path.join(homedir(), '.dsh', 'linxi-guard-audit.jsonl') },
]

export const LOG_SOURCES = SOURCES.map((s) => ({ id: s.id, label: s.label, file: s.file() }))

export const DEFAULT_TAIL = 200
export const MAX_TAIL = 1000

/** 首次读取的窗口；不够 tail 行就往上翻倍，封顶 MAX_WINDOW_BYTES */
const INITIAL_WINDOW_BYTES = 64 * 1024
const MAX_WINDOW_BYTES = 4 * 1024 * 1024

export function resolveSource(id) {
  return SOURCES.find((s) => s.id === id) ?? null
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
function readTailLines(file, tail) {
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

/** 读一个来源的尾部若干行，返回结构化结果；读不到就带 readError 回来，不抛异常 */
export function readLogs(sourceId, tail) {
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
  const file = source.file()
  const wanted = Number.isInteger(tail) && tail > 0 ? Math.min(tail, MAX_TAIL) : DEFAULT_TAIL
  const read = readTailLines(file, wanted)
  const base = {
    source: source.id,
    label: source.label,
    path: file,
    requestedTail: tail,
    effectiveTail: wanted,
    maxTail: MAX_TAIL,
    settings: { strategy: 'block-reverse-read', initialWindowBytes: INITIAL_WINDOW_BYTES, maxWindowBytes: MAX_WINDOW_BYTES },
  }

  if (!read.ok) {
    return { ...base, readOk: false, readError: read.error, fileSize: null, windowBytes: 0, lines: [], truncated: false, truncatedNote: null }
  }

  const parse = source.id === 'audit' ? parseAuditLine : parseHostLine
  const lines = read.rawLines.map((raw) => entry(raw, parse(raw)))
  return {
    ...base,
    readOk: true,
    readError: null,
    fileSize: read.size,
    windowBytes: read.windowBytes,
    lines,
    truncated: read.truncated,
    truncatedNote: read.note,
  }
}

// dsh-console 的本地只读接口客户端：五个接口，只用 GET。
// /api/local/* 由 MoonBit 后端提供：dev 与 preview 走 vite.config.ts 里的代理，生产由后端自己接。
import type { SourceTag } from '../data/types'

/** 单个请求的超时：本地接口，超过这个时间就当读取失败，不无限等 */
const READ_TIMEOUT_MS = 4000

export interface LocalRuntime {
  /** 控制台自身版本：后端运行时读本项目 package.json，读不到给 null */
  consoleVersion: string | null
  /** 上面那个版本号怎么拿到的，或为什么没拿到 */
  consoleVersionSource: string
  consolePackageName: string
  dshVersion: string
  dshPackageName: string
  dshPackageDir: string
  dshSourceLabel: string
  /** 后端自己的运行时（moonbit/native）与版本，取代原来的 nodeVersion */
  backendRuntime: string
  backendVersion: string
  backendPackageName: string
  dshHome: string
  dshHomeSource: string
  dshProfile: string | null
  platform: string
}

export interface ProfileBundles {
  declared: number
  installed: number
  installedInProfile: number
  installedHoisted: number
  missing: string[]
}

export interface LocalProfileFact {
  name: string
  dir: string
  isCurrent: boolean
  packageName: string | null
  bundles: ProfileBundles
  patch: { exists: boolean; lines: number }
  lock: { exists: boolean; mtime: string | null }
}

export interface LocalProfiles {
  dshHome: string
  dshHomeSource: string
  profilesRoot: string
  currentProfile: string | null
  profiles: LocalProfileFact[]
}

export interface LocalProcessFact {
  pid: number
  port: number
  profile: string | null
  dshHome: string | null
  exePath: string
  startedAt: string | null
  uptimeSeconds: number | null
}

export interface LocalProcesses {
  procRoot: string
  scanned: number
  matcher: string
  instances: LocalProcessFact[]
}

/** 一条命中的运行中实例：端口探测到的事实 + 尽力而为的进程补充（补不到就是 null） */
export interface LocalInstanceFact {
  /** 稳定标识，日志页的 instance:<id> 用它 */
  id: string
  port: number
  url: string
  title: string | null
  httpStatus: number
  contentType: string | null
  /** 命中的判据，以及回显的证据片段 */
  signature: { id: string; describe: string; evidence: string }
  /** 进程扫描按端口对上号才有；对不上是 null，不编 */
  profile: string | null
  pid: number | null
  dshHome: string | null
  exePath: string | null
  startedAt: string | null
  uptimeSeconds: number | null
  probeMs: number
}

export interface LocalInstances {
  sources: string[]
  perFile: { file: string; family: string; readable: boolean; listenPorts: number }[]
  /** 逐个候选端口的探测结论（不含响应体），口径可核对 */
  probeResults: {
    port: number
    reached: boolean
    httpStatus: number | null
    contentType: string | null
    signatureId: string | null
    error: string | null
  }[]
  scope: string
  listenState: string
  candidateLimit: number
  truncated: boolean
  truncatedNote: string | null
  candidates: number[]
  candidateCount: number
  probe: {
    method: string
    redirect: string
    timeoutMs: number
    concurrency: number
    probed: number
    reached: number
    hits: number
  }
  signatures: { id: string; describe: string }[]
  processSupplement: { procRoot: string; scanned: number; dshProcesses: number; withPort: number; note: string }
  instances: LocalInstanceFact[]
}

export interface LocalLogLine {
  /** 从行里读出来的时间部分；读不出就是 null，不编 */
  time: string | null
  /** 只在真读得出级别时才有值：error / warn */
  level: 'error' | 'warn' | null
  text: string
  verdict: string | null
  outcome: string | null
}

export interface LocalLogInstance {
  id: string
  port: number | null
  dshHome: string | null
}

export interface LocalLogs {
  source: string
  label: string | null
  /** fixed = 宿主/审计文件；instance = 运行中实例 */
  kind: 'fixed' | 'instance'
  instance: LocalLogInstance | null
  detectedInstances?: number
  /** 实例来源：logs 目录下实际读到的那个文件；读不到就是 null */
  path: string | null
  logsDir?: string
  logFileCount?: number
  pickedBy?: string
  /** 实例来源下，日志目录依据什么定位（实例自带 / 环境变量 / 默认位置）；标注推断口径用 */
  homeSource?: string
  requestedTail: number | null
  effectiveTail: number
  maxTail: number
  readOk: boolean
  /** 结构化错误码：unknown-instance / instance-home-unknown / no-log-file / read-failed 等 */
  errorCode: string | null
  readError: string | null
  fileSize: number | null
  /** 实际读了多少字节的尾部窗口；大文件不整份进内存 */
  windowBytes: number
  lines: LocalLogLine[]
  /** 读到的行数本身就被窗口截断时为 true */
  truncated: boolean
  truncatedNote: string | null
  /** tail 超过上限时接口给的说明 */
  tailNote?: string | null
}

interface Envelope<T> {
  ok?: boolean
  readOnly?: boolean
  readAt?: string
  data?: T
  error?: { code?: string; message?: string }
}

/** 一次只读读取的结果：失败不抛异常，让调用方显式回退并改标记 */
export interface LocalRead<T> {
  ok: boolean
  data: T | null
  error: string | null
}

async function getLocal<T>(path: string): Promise<LocalRead<T>> {
  try {
    const res = await fetch(path, {
      method: 'GET',
      headers: { Accept: 'application/json' },
      signal: AbortSignal.timeout(READ_TIMEOUT_MS),
    })
    const body = (await res.json().catch(() => null)) as Envelope<T> | null
    if (!res.ok || !body?.ok || !body.data) {
      const reason = body?.error?.message ?? `HTTP ${res.status}`
      return { ok: false, data: null, error: reason }
    }
    return { ok: true, data: body.data, error: null }
  } catch (err) {
    const reason = err instanceof Error ? err.message : String(err)
    return { ok: false, data: null, error: `本地只读接口不可达（${reason}）` }
  }
}

export function fetchRuntime(): Promise<LocalRead<LocalRuntime>> {
  return getLocal<LocalRuntime>('/api/local/runtime')
}

export function fetchProfiles(): Promise<LocalRead<LocalProfiles>> {
  return getLocal<LocalProfiles>('/api/local/profiles')
}

export function fetchProcesses(): Promise<LocalRead<LocalProcesses>> {
  return getLocal<LocalProcesses>('/api/local/processes')
}

/** 运行中实例的主口径：监听端口 + HTTP 签名探测 */
export function fetchInstances(): Promise<LocalRead<LocalInstances>> {
  return getLocal<LocalInstances>('/api/local/instances')
}

/** 日志页：只读尾部若干行，source 认 host / audit 与 instance:<实例 id> */
export function fetchLogs(source: string, tail = 200): Promise<LocalRead<LocalLogs>> {
  return getLocal<LocalLogs>(`/api/local/logs?source=${encodeURIComponent(source)}&tail=${tail}`)
}

/** 数据源标记的构造口，三种标记只用这一处生成，避免各处手写不一致 */
export function realTag(detail: string): SourceTag {
  return { kind: 'real', label: '真实数据', detail }
}

export function demoTag(detail: string): SourceTag {
  return { kind: 'demo', label: '演示数据', detail }
}

export function fallbackTag(detail: string): SourceTag {
  return { kind: 'fallback', label: '演示数据 · 真实读取失败', detail }
}

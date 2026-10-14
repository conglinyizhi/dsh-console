// dsh-console 的本地只读接口客户端：三个接口，只用 GET。
// 对应 vite.config.ts 里 localApiPlugin 挂的 /api/local/*（dev 与 preview 都有）。
import type { SourceTag } from '../data/types'

/** 单个请求的超时：本地接口，超过这个时间就当读取失败，不无限等 */
const READ_TIMEOUT_MS = 4000

export interface LocalRuntime {
  dshVersion: string
  dshPackageName: string
  dshPackageDir: string
  dshSourceLabel: string
  nodeVersion: string
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

// 只读探测本机正在运行的 dsh 实例：口径是「loopback LISTEN 端口 + HTTP 签名」。
// 为什么不以 /proc 进程为主信号：PID 命名空间可能被隔离，宿主进程根本看不见；
// 而网络命名空间通常共享，/proc/net/tcp(6) 能读到宿主全部监听端口。
// 文件访问只有 readFileSync；网络只有对 127.0.0.1 的 GET 探测（同为读）；不 spawn、不写盘。
import { readFileSync } from 'node:fs'
import { readProcesses } from './readProcesses.mjs'

/** 监听套接字的来源文件；0A = LISTEN */
const SOCKET_FILES = [
  { file: '/proc/net/tcp', family: 'ipv4' },
  { file: '/proc/net/tcp6', family: 'ipv6' },
]
const LISTEN_STATE = '0A'

/** 只认 loopback：127.0.0.1 / ::1 / ::ffff:127.0.0.1（/proc/net 里按小端十六进制写） */
const LOOPBACK = {
  ipv4: new Set(['0100007F']),
  ipv6: new Set([
    '00000000000000000000000001000000',
    '0000000000000000FFFF00000100007F',
  ]),
}

/** 候选端口上限：超了就截断，并在响应里说明 */
const MAX_CANDIDATES = 40
/** 单个端口的探测超时 */
const PROBE_TIMEOUT_MS = 500
/** 探测并发上限：只打 loopback，8 路够快也不至于把本机端口打满 */
const PROBE_CONCURRENCY = 8
/** 每个响应只读前 8KB：探测不下载整页 */
const BODY_LIMIT_BYTES = 8192

/**
 * DSH 实例的判据，写死在这里，命中哪一条会在响应里回显。
 * 判据一 dsh-auth-401：dsh 浏览器认证的固定拒绝应答（dsh-client-connection 里写死的文案）。
 * 判据二 dsh-boot-global：dsh web 注入 index.html 的引导全局名（带 cookie 时才会走到这一步）。
 * 两条都要求是 DSH 独有的长字符串——本控制台自己的 index.html 两个都不含，
 * 所以「标题里带 DSH 字样」不会误判（实测 5320 返回的正是「DSH 控制台」页面）。
 */
const SIGNATURES = [
  {
    id: 'dsh-auth-401',
    describe: 'HTTP 401 且响应体含 "dsh web authentication required"（dsh-client-connection 的未授权应答）',
    hit: (probe) => probe.status === 401 && probe.body.includes('dsh web authentication required'),
  },
  {
    id: 'dsh-boot-global',
    describe: '响应体含 "__DSH_BOOT__"（dsh web 注入 index.html 的引导全局名）',
    hit: (probe) => probe.body.includes('__DSH_BOOT__'),
  },
]

function readText(file) {
  try {
    return readFileSync(file, 'utf8')
  } catch {
    return null
  }
}

/** 一行一个套接字，按列切：0 序号 1 本地地址 2 远端地址 3 状态 */
function parseListenPorts(text, family) {
  const ports = []
  if (text === null) return ports
  for (const line of text.split('\n')) {
    const cols = line.trim().split(/\s+/)
    if (cols.length < 4 || !/^\d+:$/.test(cols[0])) continue
    if (cols[3] !== LISTEN_STATE) continue
    const [address, portHex] = cols[1].split(':')
    const hex = (address ?? '').toUpperCase()
    if (!LOOPBACK[family].has(hex)) continue
    const port = Number.parseInt(portHex, 16)
    if (Number.isInteger(port) && port > 0) ports.push(port)
  }
  return ports
}

/** 只读响应体的前 limit 字节，读完就断开——探测不下载整页 */
async function readHead(response, limit) {
  if (!response.body) return ''
  const reader = response.body.getReader()
  const chunks = []
  let size = 0
  try {
    while (size < limit) {
      const { done, value } = await reader.read()
      if (done) break
      chunks.push(value)
      size += value.byteLength
    }
  } catch {
    // 对端半路断开：已经拿到的字节照样拿来判签名
  } finally {
    try {
      await reader.cancel()
    } catch {
      // 取消失败不影响结论
    }
  }
  return Buffer.concat(chunks).toString('utf8')
}

/** 对一个候选端口做 GET 签名探测；连不上/超时都算「没命中」，不抛 */
async function probePort(port) {
  const url = `http://127.0.0.1:${port}/`
  const startedAt = Date.now()
  try {
    const response = await fetch(url, {
      method: 'GET',
      redirect: 'manual',
      headers: { Accept: 'text/html,application/json;q=0.9,*/*;q=0.8' },
      signal: AbortSignal.timeout(PROBE_TIMEOUT_MS),
    })
    const body = await readHead(response, BODY_LIMIT_BYTES)
    return {
      port,
      url,
      reached: true,
      status: response.status,
      contentType: response.headers.get('content-type'),
      body,
      ms: Date.now() - startedAt,
      error: null,
    }
  } catch (err) {
    return {
      port,
      url,
      reached: false,
      status: null,
      contentType: null,
      body: '',
      ms: Date.now() - startedAt,
      error: err instanceof Error ? err.message : String(err),
    }
  }
}

function classify(probe) {
  return SIGNATURES.find((signature) => signature.hit(probe)) ?? null
}

function extractTitle(body) {
  const matched = /<title[^>]*>([^<]{1,120})<\/title>/i.exec(body)
  return matched ? matched[1].trim() : null
}

/** 命中的证据片段：压平空白后截断，回显在响应里供人核对 */
function evidence(probe, signature) {
  if (signature.id === 'dsh-auth-401') {
    return probe.body.split('\n').map((line) => line.trim()).find((line) => line.includes('dsh web authentication required')) ?? ''
  }
  const at = probe.body.indexOf('__DSH_BOOT__')
  return probe.body.slice(Math.max(0, at - 20), at + 40).replace(/\s+/g, ' ')
}

/** 按 limit 并发跑完所有候选，顺序与输入一致 */
async function probeAll(ports, limit) {
  const results = new Array(ports.length)
  let cursor = 0
  const workers = Array.from({ length: Math.min(limit, ports.length) }, async () => {
    while (cursor < ports.length) {
      const index = cursor
      cursor += 1
      results[index] = await probePort(ports[index])
    }
  })
  await Promise.all(workers)
  return results
}

/** 进程扫描只做补充：按端口和真实进程对上号才补 pid 与启动时长，对不上就留空 */
function supplementProcesses() {
  try {
    const scanned = readProcesses()
    const withPort = scanned.instances.filter((item) => item.port !== null)
    return {
      procRoot: scanned.procRoot,
      scanned: scanned.scanned,
      dshProcesses: scanned.instances.length,
      withPort: withPort.length,
      note: withPort.length > 0
        ? '读到了带 --port 的宿主 dsh 进程，按端口补 pid 与启动时长'
        : '没读到带 --port 的 dsh 进程（PID 命名空间可能被隔离），pid 与启动时长留空，不伪造',
      byPort: new Map(withPort.map((item) => [item.port, item])),
    }
  } catch (err) {
    return {
      procRoot: '/proc',
      scanned: 0,
      dshProcesses: 0,
      withPort: 0,
      note: `进程补充读取失败：${err instanceof Error ? err.message : String(err)}`,
      byPort: new Map(),
    }
  }
}

export async function readInstances() {
  const perFile = SOCKET_FILES.map(({ file, family }) => {
    const text = readText(file)
    return { file, family, readable: text !== null, ports: parseListenPorts(text, family) }
  })

  const unique = [...new Set(perFile.flatMap((item) => item.ports))].sort((a, b) => a - b)
  const truncated = unique.length > MAX_CANDIDATES
  const candidates = unique.slice(0, MAX_CANDIDATES)

  const probes = await probeAll(candidates, PROBE_CONCURRENCY)
  const supplement = supplementProcesses()

  const instances = []
  for (const probe of probes) {
    const signature = classify(probe)
    if (!signature) continue
    const proc = supplement.byPort.get(probe.port) ?? null
    instances.push({
      port: probe.port,
      url: probe.url,
      title: extractTitle(probe.body),
      httpStatus: probe.status,
      contentType: probe.contentType,
      signature: { id: signature.id, describe: signature.describe, evidence: evidence(probe, signature) },
      profile: proc?.profile ?? null,
      pid: proc?.pid ?? null,
      dshHome: proc?.dshHome ?? null,
      exePath: proc?.exePath ?? null,
      startedAt: proc?.startedAt ?? null,
      uptimeSeconds: proc?.uptimeSeconds ?? null,
      probeMs: probe.ms,
    })
  }

  return {
    sources: SOCKET_FILES.map((item) => item.file),
    // 逐个候选的探测结论（不含响应体）：口径可核对，「哪个端口命中、用哪条判据」一目了然
    probeResults: probes.map((probe) => ({
      port: probe.port,
      reached: probe.reached,
      httpStatus: probe.status,
      contentType: probe.contentType,
      signatureId: classify(probe)?.id ?? null,
      error: probe.error,
    })),
    perFile: perFile.map(({ file, family, readable, ports }) => ({ file, family, readable, listenPorts: ports.length })),
    scope: 'loopback（127.0.0.1 / ::1 / ::ffff:127.0.0.1）',
    listenState: `${LISTEN_STATE}（LISTEN）`,
    candidateLimit: MAX_CANDIDATES,
    truncated,
    truncatedNote: truncated
      ? `loopback LISTEN 端口共 ${unique.length} 个，超过上限 ${MAX_CANDIDATES}，只探测了前 ${MAX_CANDIDATES} 个`
      : null,
    candidates,
    candidateCount: candidates.length,
    probe: {
      method: 'GET',
      redirect: 'manual',
      timeoutMs: PROBE_TIMEOUT_MS,
      concurrency: PROBE_CONCURRENCY,
      probed: probes.length,
      reached: probes.filter((item) => item.reached).length,
      hits: instances.length,
    },
    signatures: SIGNATURES.map(({ id, describe }) => ({ id, describe })),
    processSupplement: {
      procRoot: supplement.procRoot,
      scanned: supplement.scanned,
      dshProcesses: supplement.dshProcesses,
      withPort: supplement.withPort,
      note: supplement.note,
    },
    instances,
  }
}

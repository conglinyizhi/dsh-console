// 派生副本时的端口探测（前端演示动作的一部分，只发 no-cors 请求探活，不改任何真实进程）。
/** 端口探测上限：最多往后试 20 个 */
const PORT_PROBE_LIMIT = 20
/** 探测超时：600ms 内没有应答就按空闲处理 */
const PORT_PROBE_TIMEOUT_MS = 600

/** 本次会话里已经认掉的端口，避免同一批派生撞到同一个号 */
const reservedPorts = new Set<number>()

/**
 * 探测单个候选端口。
 * no-cors 请求一旦 resolve，说明对端有东西在应答，按占用处理；
 * reject（连接被拒、超时）只说明这一次没听到应答，按大概空闲处理。
 */
async function isPortBusy(port: number): Promise<boolean> {
  try {
    await fetch(`http://127.0.0.1:${port}/`, {
      mode: 'no-cors',
      signal: AbortSignal.timeout(PORT_PROBE_TIMEOUT_MS),
    })
    return true
  } catch {
    return false
  }
}

export interface PortChoice {
  port: number
  /** 被跳过时记下第一个占用的端口，用于界面提示 */
  skipped: number | null
  /** 20 个候选全被占用时为真，此时只能给出一个没探测过的号 */
  exhausted: boolean
}

/** 从候选端口往后找第一个「探测下来没被占用」的端口 */
export async function pickPort(start: number): Promise<PortChoice> {
  let skipped: number | null = null
  for (let offset = 0; offset < PORT_PROBE_LIMIT; offset += 1) {
    const port = start + offset
    if (reservedPorts.has(port)) {
      skipped ??= port
      continue
    }
    const taken = await isPortBusy(port)
    if (taken) {
      skipped ??= port
      continue
    }
    reservedPorts.add(port)
    return { port, skipped, exhausted: false }
  }
  // 20 个候选全都有人应答：给一个连着往后排的号，并在界面上说清它是没探测过的
  const fallback = start + PORT_PROBE_LIMIT
  reservedPorts.add(fallback)
  return { port: fallback, skipped: start, exhausted: true }
}

/** 派生基线：现有实例里最大的端口号 + 1 */
export function nextPort(instances: { url: string }[]): number {
  let max = 0
  for (const item of instances) {
    const matched = /:(\d+)$/.exec(item.url)
    if (matched) max = Math.max(max, Number(matched[1]))
  }
  return max + 1
}

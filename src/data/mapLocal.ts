// 真实读数 → 实例卡的映射。真假数据在这里分开组装，调用方不做二次加工。
import type { LocalInstanceFact, LocalProfileFact, LocalRuntime } from '../api/local'
import type { Instance } from './types'

/** 真实读数换算出来的版本/来源文案，例如「0.2.0-rc.2（本机已安装）」 */
function versionText(runtime: LocalRuntime | null): string {
  if (!runtime) return '—'
  return `${runtime.dshVersion}（${runtime.dshSourceLabel}）`
}

/** ISO 时间 → 卡片上的短格式，例如 10-13 22:50 */
function shortTime(iso: string | null): string | null {
  if (!iso) return null
  const date = new Date(iso)
  if (Number.isNaN(date.getTime())) return null
  const pad = (n: number) => String(n).padStart(2, '0')
  return `${pad(date.getMonth() + 1)}-${pad(date.getDate())} ${pad(date.getHours())}:${pad(date.getMinutes())}`
}

/**
 * 正在运行的实例 = 监听端口 + HTTP 签名探测到的真实实例（不是 /proc 进程，也不是磁盘上的 profile）。
 * 拿不到的字段一律写「未知」/「—」：探测走的是一次未授权的 GET，读不到实例自己的版本、DSH_HOME 与插件数。
 */
export function runningInstances(facts: LocalInstanceFact[], profiles: LocalProfileFact[]): Instance[] {
  const byName = new Map(profiles.map((item) => [item.name, item]))
  return facts.map((fact) => {
    const profile = fact.profile ? byName.get(fact.profile) : undefined
    const minutes = fact.uptimeSeconds === null ? null : Math.floor(fact.uptimeSeconds / 60)
    return {
      id: `port:${fact.port}`,
      name: fact.profile ? `${fact.profile} :${fact.port}` : `dsh :${fact.port}`,
      kind: '本机监听的 dsh 实例',
      kindHint: `从 /proc/net/tcp(6) 的 loopback LISTEN 端口探测到，命中判据 ${fact.signature.id}：${fact.signature.describe}`,
      tone: 'accent' as const,
      status: 'running' as const,
      uptime: minutes,
      uptimeHint: minutes === null
        ? '探测到监听端口，但本进程读不到宿主进程（PID 命名空间被隔离），运行时长未知'
        : undefined,
      version: '未知',
      profile: fact.profile ?? '未知',
      home: fact.dshHome ?? '未知',
      url: fact.url,
      pluginCount: profile ? `声明 ${profile.bundles.declared} · 已装 ${profile.bundles.installed}` : '—',
      pluginDetail: profile?.bundles.missing.length
        ? `缺少的包：${profile.bundles.missing.join('、')}`
        : undefined,
      deletable: false,
    }
  })
}

/** 已停止的实例 = 磁盘上真实存在的 profile；没有进程，所以访问地址是「—」 */
export function profileInstances(
  profiles: LocalProfileFact[],
  runtime: LocalRuntime | null,
  dshHome: string,
): Instance[] {
  return profiles.map((fact) => {
    const { declared, installed, missing } = fact.bundles
    return {
      id: `profile:${fact.name}`,
      name: fact.name,
      kind: fact.isCurrent ? '本地 profile · 默认' : '本地 profile',
      // 「默认」只表示 DSH_PROFILE 指向它，跟「运行中」无关——这个词以前写成「当前」，会被读成正在跑
      kindHint: fact.isCurrent
        ? '环境变量 DSH_PROFILE 指向这只 profile：新起的实例默认用它，不代表它正在运行'
        : '磁盘上真实存在的 profile，当前没有对应的 dsh 进程',
      tone: 'violet' as const,
      status: 'stopped' as const,
      uptime: 0,
      version: versionText(runtime),
      profile: fact.name,
      home: dshHome,
      url: '—',
      pluginCount: `声明 ${declared} · 已装 ${installed}`,
      // 末轨第一行放这张卡另外两项真实读数，省略号截断，完整说明在悬停里
      idleNote: `cordis.patch.yml ${fact.patch.lines} 行 · ${
        fact.lock.exists ? `lock ${shortTime(fact.lock.mtime) ?? '—'}` : '无 pnpm-lock.yaml'
      }`,
      note: missing.length ? `缺 ${missing.length} 个包：${missing.join('、')}` : undefined,
      pluginDetail: missing.length ? `缺少的包：${missing.join('、')}` : `${fact.name} 声明的插件都已安装`,
      deletable: true,
    }
  })
}

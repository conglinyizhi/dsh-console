// 真实读数 → 实例卡的映射。真假数据在这里分开组装，调用方不做二次加工。
import type { LocalProcessFact, LocalProfileFact, LocalRuntime } from '../api/local'
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

/** 正在运行的实例 = /proc 里真实检测到的 dsh 进程 */
export function processInstances(
  processes: LocalProcessFact[],
  runtime: LocalRuntime | null,
  profiles: LocalProfileFact[],
): Instance[] {
  const byName = new Map(profiles.map((item) => [item.name, item]))
  return processes.map((proc) => {
    const profile = proc.profile ? byName.get(proc.profile) : undefined
    const minutes = Math.floor((proc.uptimeSeconds ?? 0) / 60)
    return {
      id: `proc:${proc.pid}`,
      name: proc.profile ? `${proc.profile} :${proc.port}` : `dsh :${proc.port}`,
      kind: '本机 dsh 进程',
      tone: 'accent',
      status: 'running',
      uptime: minutes,
      version: versionText(runtime),
      profile: proc.profile ?? `pid ${proc.pid}`,
      home: proc.dshHome ?? runtime?.dshHome ?? '—',
      url: `http://127.0.0.1:${proc.port}`,
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
      kind: fact.isCurrent ? '本地 profile · 当前' : '本地 profile',
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

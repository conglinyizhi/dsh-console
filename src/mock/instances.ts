export interface Instance {
  id: string
  name: string
  kind: string
  tone: 'accent' | 'violet'
  /** starting 仅用于「启动」后的前端演示等待态，没有真实进程可等 */
  status: 'running' | 'stopped' | 'starting'
  /** 已运行分钟数，写死的展示值，不做计时器 */
  uptime: number
  /** 派生时探测端口的结论，仅启动等待期间展示 */
  portNote?: string
  /** 该实例正在等待启动，行内按钮全部不可点 */
  busy?: boolean
  version: string
  profile: string
  home: string
  /** 实例入口，完整 URL（访问地址字段直接展示） */
  url: string
  pluginCount: string
  /** 是否允许删除。核心工作实例不给删除入口 */
  deletable: boolean
  /** 有值即表示已归档，移出运行/停止两个分组 */
  archivedAt?: string
}

/** 归档时间写死，不做真实时钟 */
export const ARCHIVED_AT = '2026-10-14 13:05'

export const instances: Instance[] = [
  {
    id: 'work-main',
    name: 'work-main',
    kind: '核心工作实例',
    tone: 'accent',
    status: 'running',
    uptime: 138,
    version: '0.2.0-rc.2（本地源码）',
    profile: 'main',
    home: '/Users/you/.dsh/work-main',
    url: 'http://127.0.0.1:8100',
    pluginCount: '5 个',
    deletable: false,
  },
  {
    id: 'plugin-dev',
    name: 'plugin-dev',
    kind: '插件开发（试验）',
    tone: 'violet',
    status: 'running',
    uptime: 42,
    version: '0.2.0-rc.2（本地源码）',
    profile: 'dev',
    home: '/Users/you/.dsh/plugin-dev',
    url: 'http://127.0.0.1:8200',
    pluginCount: '2 个（开发中）',
    deletable: true,
  },
]

export const safetyChecks = [
  '独立 DSH_HOME，会话与插件互不干扰',
  '各实例可用不同 DSH 版本或来源',
  '仅监听 127.0.0.1，不暴露到网络',
]

export const workflows = [
  {
    title: '从当前实例派生开发副本',
    detail: '派生隔离副本，用新端口与独立 DSH_HOME',
  },
  {
    title: '将插件交回主线实例',
    detail: '把插件提交回稳定实例',
  },
]

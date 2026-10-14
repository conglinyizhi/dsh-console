export interface Instance {
  id: string
  name: string
  kind: string
  tone: 'accent' | 'violet'
  status: 'running' | 'stopped'
  /** 已运行时长，写死的展示值，不做计时器 */
  uptime: string
  version: string
  profile: string
  home: string
  /** 实例入口，完整 URL（访问地址字段直接展示） */
  url: string
  pluginCount: string
}

export const instances: Instance[] = [
  {
    id: 'work-main',
    name: 'work-main',
    kind: '核心工作实例',
    tone: 'accent',
    status: 'running',
    uptime: '2 小时 18 分钟',
    version: '0.2.0-rc.2（本地源码）',
    profile: 'main',
    home: '/Users/you/.dsh/work-main',
    url: 'http://127.0.0.1:8100',
    pluginCount: '5 个',
  },
  {
    id: 'plugin-dev',
    name: 'plugin-dev',
    kind: '插件开发（试验）',
    tone: 'violet',
    status: 'running',
    uptime: '42 分钟',
    version: '0.2.0-rc.2（本地源码）',
    profile: 'dev',
    home: '/Users/you/.dsh/plugin-dev',
    url: 'http://127.0.0.1:8200',
    pluginCount: '2 个（开发中）',
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

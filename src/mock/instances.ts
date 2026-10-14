import type { Instance } from '../data/types'

/** 归档时间写死，不做真实时钟 */
export const ARCHIVED_AT = '2026-10-14 13:05'

/**
 * 演示数据：只在真实读取失败时兜底展示（运行中/已停止两组），归档区本轮不接真实数据、一直是演示。
 * 展示这几条时，界面上的数据源标记会变成「演示数据 · 真实读取失败」，不跟真实读数混在一起。
 */
export const demoRunning: Instance[] = [
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

export const demoStopped: Instance[] = [
  {
    id: 'staging',
    name: 'staging',
    kind: '插件开发（试验）',
    tone: 'violet',
    status: 'stopped',
    uptime: 0,
    version: '0.2.0-rc.2（本地源码）',
    profile: 'staging',
    home: '/Users/you/.dsh/staging',
    url: 'http://127.0.0.1:8300',
    pluginCount: '3 个',
    deletable: true,
  },
]

export const demoArchived: Instance[] = [
  {
    id: 'old-experiment',
    name: 'old-experiment',
    kind: '插件开发（试验）',
    tone: 'violet',
    status: 'stopped',
    uptime: 0,
    version: '0.2.0-rc.2（本地源码）',
    profile: 'dev',
    home: '/Users/you/.dsh/old-experiment',
    url: 'http://127.0.0.1:8400',
    pluginCount: '1 个（开发中）',
    deletable: true,
    archivedAt: ARCHIVED_AT,
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

/** 一张实例卡的形状：真实读数和演示数据共用同一个模型 */
export interface Instance {
  id: string
  name: string
  kind: string
  tone: 'accent' | 'violet'
  /** starting 仅用于「启动」后的前端演示等待态，本页不启动真实进程 */
  status: 'running' | 'stopped' | 'starting'
  /** 已运行分钟数；真实进程按 /proc 算出来的启动时刻换算 */
  uptime: number
  /** 派生时探测端口的结论，仅启动等待期间展示 */
  portNote?: string
  /** 已停止卡的末轨第一行：真实 profile 的 patch/锁文件读数；没有就显示「未运行」 */
  idleNote?: string
  /** 副标题末轨的第二行说明：真实读取的缺包提示等 */
  note?: string
  /** 该实例正在等待启动，行内按钮全部不可点 */
  busy?: boolean
  version: string
  profile: string
  home: string
  /** 实例入口，完整 URL；没有真实进程时是「—」，不编端口 */
  url: string
  pluginCount: string
  /** 插件数量字段的悬停说明（缺包全名单） */
  pluginDetail?: string
  /** 是否允许删除。核心工作实例与真实进程不给删除入口 */
  deletable: boolean
  /** 有值即表示已归档，移出运行/停止两个分组 */
  archivedAt?: string
}

/** 一处数据的数据源标记，界面上逐处标 */
export interface SourceTag {
  /** real = 真实读取；demo = 本轮仍是演示；fallback = 真实读取失败，显式退回演示 */
  kind: 'real' | 'demo' | 'fallback'
  label: string
  detail: string
}

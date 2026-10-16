// 应用状态、消息与更新循环。
//
// 导航既是状态切页也是 URL：page 是 model 里的字段，同时写进地址栏（见 route.mbt），
// 刷新与前进/后退都按地址复原页面。
// 三个只读接口在 init 里一次发出去；读不到就把原因留进 model，界面直接展示；
// 还没回来之前界面是加载态，不是空态（见 readings_pending）。

///|
pub(all) enum Page {
  Overview
  Logs
  Settings
  /// 回收站（第六轮）：删除进回收站的那些 profile 在这里看得见、能恢复、能彻底删掉
  Trash
  About
} derive(Eq)

pub extend Page with Eq::{ not_equal, equal }

///|
/// 行内动作通道的键（与现有 actions.ts 的 ActionKey 一一对应）。
priv enum ActionKey {
  OpenUi
  Toggle
  Restart
  Tab
  CopyUrl
  /// 复制带令牌的地址：只在真有 webUrl 时出现（读不到令牌就不摆这一项）
  CopyTokenUrl
  /// 复制开发指令：把一段给「另一个会话」的任务说明写进剪贴板（粘贴到别的 profile 的会话里，
  /// 让那边针对这一只 profile 开发）。认不出 profile 目录名时不摆这一项。
  CopyDev
  Fork
  Rename
  /// 编辑这只 profile 的备注（POST set-profile-note）
  Note
  Archive
  Unarchive
  Delete
  /// 切到日志页并把来源设成这一行对应的实例（第三轮：不再落进兜底）
  Logs
  /// 打开这只 profile 的工作目录（POST open-path，kind=dir）
  Dir
  /// 打开这只 profile 的 cordis.patch.yml（POST open-path，kind=config）
  Config
}

///|
/// starting 只用于「启动」后的前端演示等待态：本页不拉起真实进程。
enum RowStatus {
  Running
  Stopped
  Starting
} derive(Eq)

pub extend RowStatus with Eq::{ not_equal, equal }

///|
enum Tone {
  Accent
  Violet
} derive(Eq)

pub extend Tone with Eq::{ not_equal, equal }

///|
/// 卡片图标右上角那颗实心圆的档位（第七轮契约：绿 / 黄 / 红，三色 + 一档「没读到」）。
///
/// 判据来自契约，不在这里发挥：
///   * 绿 running —— 签名探测通过
///   * 黄 fault   —— b：端口在听、持有它的进程像 dsh，但签名探测不通过；
///                   c：解析出的 profile 缺包大于 0（或没有 cordis.patch.yml）
///   * 红 stopped —— 没有在跑
/// 另外两档是**状态灯自己需要的**，不是第四种颜色：
///   * starting —— 正在起来（前端启动等待态，也认后端 state=starting）。用同一支琥珀，
///     但文案是「正在启动」，不会被读成故障；它在动（dot-pulse），静止态一个动效都没有
///   * unknown  —— 后端的 state 字段还没落地。**这时不猜颜色**：
///     灯是空心的灰环，抽屉里写清「这一版后端还没给 state」（契约第七轮的要求）
enum Light {
  LightRun
  LightFault
  LightStart
  LightStop
  LightUnknown
} derive(Eq)

pub extend Light with Eq::{ not_equal, equal }

///|
/// 两档：真实读取失败退回演示 / 请求还在路上。
///
/// 「这一份是真读数」那一档已经删掉（使用者 2026-10-15 决定）：页面上读到的一切
/// 都是真读数，为「一切正常」再挂一个徽标，只是旧前端迁移到新前端时留下的历史产物。
/// 于是标记本身也跟着变成可选的 —— None 就是「读到了，没什么要说的」（见 SourceTag?）。
enum TagKind {
  /// 真实读取失败，这一份退回演示数据。**这一档必须留着**：
  /// 它说的是「你现在看到的是兜底数据」，删了失败就会伪装成正常。
  Fallback
  /// 读数还没回来：界面上说「读取中」
  Pending
} derive(Eq)

pub extend TagKind with Eq::{ not_equal, equal }

///|
/// 一处数据的数据源标记，界面上逐处标。
/// fallback = 真实读取失败，显式退回演示；pending = 请求还在路上
/// （这一档**不是**空数据：把「还在读」标成「没有」正是要修的那件事）。
///
/// 标记只在出岔子时才有：读到了就不摆徽标，模型里存 None（见各处的 tag_* 字段）。
struct SourceTag {
  kind : TagKind
  label : String
  detail : String
} derive(Eq)

pub extend SourceTag with Eq::{ not_equal, equal }

///|
/// 一张实例卡（现有 Instance 接口的对应物；真假数据共用同一个模型）。
struct Row {
  id : String
  name : String
  kind : String
  /// 类型标签的悬停说明：写清这个标签依据什么，避免被误读成运行状态
  kind_hint : String
  tone : Tone
  status : RowStatus
  /// 已运行分钟数；None = 端口探测到了实例但读不到宿主进程，时长未知，不编
  uptime : Int?
  uptime_hint : String
  /// 派生时探测端口的结论，仅启动等待期间展示
  port_note : String
  /// 已停止卡的末轨第一行：真实 profile 的 patch/锁文件读数
  idle_note : String
  /// 末轨第二行说明（缺包提示等）
  note : String
  /// 该实例正在等待启动，行内按钮全部不可点
  busy : Bool
  version : String
  profile : String
  home : String
  /// 三项字段的悬停说明：写清这个值是从哪读出来的，或者为什么读不到（后端原样给的原因）
  version_hint : String
  profile_hint : String
  home_hint : String
  url : String
  /// 带令牌的访问地址（能直接过握手）。None = 读不到令牌 ——
  /// 「打开 Web UI」这时**不打开任何标签页**，把原因与裸地址说清就停。
  web_url : String?
  /// 令牌从哪来 / 为什么读不到：卡上「访问地址」那行的悬停与提示条都用这一句
  web_url_source : String
  plugin_count : String
  plugin_detail : String
  deletable : Bool
  /// 有值即表示已归档，移出运行/停止两个分组
  archived_at : String?
  /// 写动作的目标：磁盘上的 profile 目录名。读不到就是 None ——
  /// 这时动作先在本地说清「没有可用的目标」，不发请求（也不拿演示数据里的名字去删真东西）。
  profile_name : String?
  /// 写动作的目标：实例端口（停止 / 重启按端口认）
  port_value : Int?
  /// 运行时登记（runtime.json）里有这一条 → 由本控制台启动
  console_started : Bool
  /// 用户给这只 profile 写的备注（读自 profiles 读数的 note）。
  /// 名字带 user_ 是为了跟上面那个 note（末轨第二行的读数说明）分开：两个都在卡上，
  /// 一个是后端读出来的运行事实，一个是用户自己写的自由文本。
  /// 空串 = 没备注：卡上那一行与删除确认框里那一段都不出现 ——
  /// 没有备注的卡片必须与以前逐像素一致。
  user_note : String
  /// 备注的来源 / 读不到的原因，挂在卡上那一行的悬停里（后端原样给）
  user_note_source : String
  /// 卡片字段区第六格「最近改动」的值：这只 profile **目录**的 mtime（毫秒时间戳）。
  /// None = 读不到（或没有可读的对象），由 mtime_missing 决定那一格写什么。
  ///
  /// 这一格的依据是**目录 mtime（最近改动），不是「创建时间」**：多数文件系统上
  /// 可靠的创建时间拿不到（ctime 会在 chmod / 改名时变，birth time 不通用）✗
  /// 目录 mtime 是能拿到、且不会骗人的那一个 ✓ 刚派生出来的 profile 一定是最新的，
  /// 所以它同时也回答了「哪个是刚弄的」。标签与注释都不许写成「创建时间」。
  mtime_ms : Double?
  /// 没有值时这一格显示的文本。两种缺法不是一回事：
  /// 停止卡是「读不到」（读了目录但拿不到 mtime），运行卡解析不出 profile 时是「—」
  /// （根本没有可读的对象）。混成一个词就把「读不到」与「不存在」说成同一件事了。
  mtime_missing : String
  /// 这一格的悬停：值从哪来、或为什么读不到（后端给的原因原样带上）
  mtime_hint : String
  // ── 状态灯（第七轮） ──
  /// 卡片图标右上角那颗实心圆的档位。判据与理由见 Light 的注释。
  light : Light
  /// **为什么是这个颜色** —— 抽屉里那一块的正文，一句话说清依据。
  /// 契约明确要求颜色不能是唯一信息，所以这一句不是装饰：黄的两个成因要能分开说。
  light_reason : String
  /// 抽屉里「后端 state：…」那一行要显示的原值。
  ///
  /// 两种「没有值」必须分开写：实例卡上后端没给（这一版还没落地）与 profile 行上
  /// **不适用**（它根本不是实例读数）—— 都写成「没有这个字段」就是把两件事说成一件。
  state_raw : String
  /// 后端给的 stateReason 原文；没给时是前端补的那句说明
  state_reason : String
  /// 抽屉「profile 健康」那一块的正文（缺包 / 有没有 cordis.patch.yml）
  health_text : String
  /// 上面那句话是从哪读出来的（instances 的 profileHealth 字段，还是 profiles 读数）
  health_source : String
} derive(Eq)

pub extend Row with Eq::{ not_equal, equal }

///|
/// 启动等待时长与重启按钮的自锁时长（前端演示，没有真实进程可等）。
pub let start_delay_ms : Int = 2500

///|
pub let restart_lock_ms : Int = 900

///|
/// 成功提示（toast）的寿命：出现之后这么多毫秒开始淡出。
///
/// 只有**成功**的提示会走：失败要留到使用者自己处理掉（见 app.mbt 的 update 外壳）。
pub let flash_ms : Int = 4000

///|
/// toast 淡出那一小段（毫秒）：先把不透明度收下去，再撤节点。
pub let flash_fade_ms : Int = 220

///|
/// 启动成功之后，最多重读几轮读数去等带令牌的地址。
///
/// 为什么要等：令牌不在启动响应里，它在实例日志里，由 /api/local/instances 现算
/// （后端的 weburl.mbt）。端口先监听、带令牌的横幅后落盘，在慢机器上是可能的 ——
/// 一轮没读到就认输会把一只真起来的实例说成没地址。有界：等满就认输并说清为什么。
pub let start_tab_max_tries : Int = 3

///|
/// 上面那几轮之间的间隔（毫秒）。
pub let start_tab_retry_ms : Int = 1200

///|
/// 控件里正在编辑的文本。键与文本分开存，保存成功或失败都要能把它清掉。
struct SettingDraft {
  key : String
  text : String
} derive(Eq)

pub extend SettingDraft with Eq::{ not_equal, equal }

///|
struct Model {
  page : Page
  /// 地址回落说明：URL 认不出来时写在这里，由外壳顶部那条提示显示（空串 = 没有要说的）
  route_notice : String
  // 三个只读读数：原始事实 + 失败原因 + 读数时刻
  runtime : RuntimeFacts?
  runtime_error : String
  runtime_time : String
  profiles : ProfilesFacts?
  profiles_error : String
  instances : InstancesFacts?
  instances_error : String
  // 五处数据源标记。None = 这一份读到了真读数，界面上不摆任何徽标
  tag_runtime : SourceTag?
  tag_instances : SourceTag?
  tag_profiles : SourceTag?
  tag_archived : SourceTag?
  tag_settings : SourceTag?
  // 三个读数是否都落地了：都落地才拼一次列表（Vue 版是 Promise.all 之后拼）
  read_runtime : Bool
  read_profiles : Bool
  read_instances : Bool
  built : Bool
  rows : Array[Row]
  // 交互状态
  /// 详情抽屉开着的是哪一行（row.id）；空串 = 抽屉关着。
  ///
  /// 抽屉是**覆盖式**的（position: fixed 贴右侧，不占文档流），卡片因此不必为它让位。
  /// 关抽屉时焦点回到触发它的那张卡 —— 卡有稳定的 DOM id（见 card_id），不必再存一个返回值。
  drawer_id : String
  restarting : String
  rename_id : String
  rename_draft : String
  rename_return : String
  // 备注（POST /api/local/action 的 set-profile-note）。note_open 非空 = 编辑框开着：
  // 与重命名同一套（预填、Esc 取消、关闭后焦点回触发元素），只是内容是自由文本。
  note_open : String
  note_draft : String
  note_return : String
  /// 上一次保存失败的原因（后端给的原文）；空串 = 没有要报的错
  note_error : String
  /// 正在保存哪一行的备注；空串 = 没有在保存
  note_saving : String
  confirm_id : String
  confirm_return : String
  // 回收站「彻底删除」的确认框：目标目录名（空串 = 框关着）与触发元素 id
  trash_purge_dir : String
  trash_purge_return : String
  archived_open : Bool
  /// 用户手动折过归档区没有：折过之后就不再被 ui.archiveOpenByDefault 覆盖
  archived_user_toggled : Bool
  // 设置页
  settings_loaded : Bool
  settings_loading : Bool
  settings : SettingsFacts?
  settings_error : String
  settings_status : Int
  settings_status_text : String
  settings_endpoint_missing : Bool
  settings_group : String
  /// 控件里正在编辑的文本（键 → 草稿）：保存失败要把草稿退回已保存的值
  settings_draft : Array[SettingDraft]
  settings_saving : String
  /// 正在保存的那个键准备写入的值（回执里没带新值时按它记账）
  settings_pending : SettingValue?
  settings_feedback : String
  settings_feedback_ok : Bool
  // 写动作（POST /api/local/action）
  /// 正在等响应的启动动作所在的行；空串表示没有
  act_pending : String
  /// 这一次启动的响应到了没有
  act_response : Bool
  /// 启动的展示计时到了没有（等待态至少显示 start_delay_ms）
  act_tick : Bool
  act_ok : Bool
  act_note : String
  /// 页面上那条动作结果提示
  act_notice : String
  act_notice_ok : Bool
  /// 提示条正文的悬停补充：删除回执里那些路径 / mode / hardDeleted 就收在这里，
  /// 不摊在正文上（第六轮契约第二节）。空串 = 这一条提示没有要补充的。
  act_notice_hint : String
  /// 上面那段悬停**属于哪一条提示文字**。与当前 act_notice 不一致时悬停不出现 ——
  /// 提示条被别的动作改写之后，那段路径说明自己失效，不留一段对不上号的悬停
  /// （与 notice_url_notice 同一套口径）。
  act_notice_hint_for : String
  /// 启动等待态里那句提示要用的两个词（回执与计时是两条路，各自都拿得到它们）：
  /// 谁（web-dev）与做了什么（启动）。组句见 app.mbt 的 action_receipt。
  act_name : String
  act_verb : String
  // 启动成功后自动开标页（占位页模式，见 dom.mbt 的 js_tab_hold）
  /// 点击启动时同步开的占位标页的结局：'held' / 'blocked' / 'error: …'；
  /// 空串 = 这一次点击没有开标页（读数里没有 profile 目录名，请求都没发出去）
  start_tab : String
  /// 那只占位标页是为哪个 profile 开的：启动成功之后按它去 instances 读数里找 webUrl
  start_tab_profile : String
  /// 启动成功、还在等 instances 读数把带令牌的地址给出来（拿到就填进占位标页）
  start_tab_waiting : Bool
  /// 等地址时重读了几轮读数（有界，见 start_tab_max_tries）
  start_tab_tries : Int
  /// 提示条里那颗「打开 Web UI」要开的地址（方案 B：用户再点一下 = 新手势，
  /// 一定不被弹窗拦截器吃掉）。None = 不摆按钮。
  notice_url : String?
  /// 上面那个地址属于哪一条提示条文字。与当前 act_notice 不一致时按钮不出现 ——
  /// 提示条被别的动作改写之后，按钮自己失效，不留一个对不上号的入口。
  notice_url_notice : String
  // 成功提示的 toast（外观与位置见 view_shell 的 flash_toast，计时见 app.mbt 的 flash_timer）
  /// 当前这条 toast 的序号。0 = 现在没有 toast。
  /// 到期消息带着它回来：号对不上就说明这一条已经被换掉了，那一枪作废。
  flash_serial : Int
  /// 鼠标正停在 toast 上：这一拍不许它消失（悬停时别让它正好在眼皮底下走掉）
  flash_hover : Bool
  /// 正在淡出（去掉节点前的最后一小段，见 flash_fade_ms）
  flash_fading : Bool
  // 控制台自己的状态读数（GET /api/local/console）：运行时登记 + 归档记录
  console : ConsoleFacts?
  console_error : String
  read_console : Bool
  // 日志页
  log_source : String
  log_user_picked : Bool
  /// 日志请求还在路上。**「还没读完」与「确实是空的」是两副样子**，界面按它分档。
  log_loading : Bool
  /// 现在 logs 里那份内容是哪个来源读回来的（空串 = 还没读到过）。
  /// 换了来源之后旧内容不能顶着新来源显示，要不要重读就看它。
  log_source_read : String
  logs : LogsFacts?
  log_error : String
  log_time : String
  log_tag : SourceTag?
  log_instance_note : String
} derive(Eq)

pub extend Model with Eq::{ not_equal, equal }

///|
priv enum Msg {
  RuntimeText(Result[String, Error])
  ProfilesText(Result[String, Error])
  ConsoleText(Result[String, Error])
  InstancesText(Result[String, Error])
  LogsText(Result[String, Error])
  Navigate(Page)
  /// 浏览器前进 / 后退（或手改了 path）：按当前地址复原页面，不写历史
  RouteChanged
  RowAction(String, ActionKey)
  /// 启动按钮的点击：行 id / profile 目录名 / 占位标页的结局。
  /// 占位标页是在 DOM 监听器里**同步**开好的（见 view_overview 的 start_click），
  /// 回执随这条消息进来 —— update 走 queueMicrotask，等不到用户手势那一栈。
  StartClicked(String, String, String)
  /// 启动成功但带令牌的地址还没到：再重读一轮读数（有界，见 start_tab_max_tries）
  StartTabRetry
  /// 提示条里那颗「打开 Web UI」被点了（方案 B 的兜底入口）
  NoticeOpenUi
  /// 成功提示（toast）到点了：序号对得上才收
  FlashExpire(Int)
  /// 淡出那一小段走完，节点可以撤了
  FlashRemove(Int)
  /// 鼠标进 / 出 toast（进去之后不许它正好消失）
  FlashHover(Bool)
  /// 点整张卡：开详情抽屉（第七轮 —— 卡片上不再有按钮与 ⋯ 菜单，点卡是唯一入口）
  DrawerOpen(String)
  /// 关抽屉：点外部 / Esc / 关闭按钮都走这一条。焦点回触发它的那张卡。
  DrawerClose
  StartTick(String)
  RestartTick
  RenameInput(String)
  RenameConfirm
  RenameCancel
  // 备注：打开（带触发元素 id）/ 输入 / 保存 / 取消
  NoteOpen(String)
  NoteInput(String)
  NoteConfirm
  NoteCancel
  DeleteOpen(String, String)
  DeleteConfirm
  DeleteCancel
  // 回收站（第六轮）：恢复某一条 / 点「彻底删除」先开确认框 / 框里的确定与取消
  TrashRestore(String)
  TrashPurgeOpen(String, String)
  TrashPurgeConfirm
  TrashPurgeCancel
  ToggleArchived
  LogSourcePicked(String)
  LogRefresh
  // 设置页
  SettingsText(Result[String, Error])
  SettingsSaved(String, Result[String, Error])
  SettingsRetry
  SettingsGroupPicked(String)
  SettingDraft(String, String)
  SettingCommit(String, String)
  SettingToggle(String, Bool)
  /// 把这一项写回后端给的缺省值（见 app.mbt 的 reset_setting）
  SettingReset(String)
  // 写动作的回执：row_id / action / 谁 / 做了什么（动词）/ 原始响应
  HttpDone(String, String, String, String, Result[String, Error])
  // 复制到剪贴板的回执：复制的是谁的那一条地址 / 传输层拿回来的那段 JSON
  CopyDone(String, Result[String, Error])
  Noop
}

///|
fn initial_model() -> Model {
  {
    page: Overview,
    route_notice: "",
    runtime: None,
    runtime_error: "",
    runtime_time: "—",
    profiles: None,
    profiles_error: "",
    instances: None,
    instances_error: "",
    // 初始那几副标记是「读取中」，不是「演示数据」：请求还在路上，
    // 这时候标成演示数据与标成空数据是同一个毛病 —— 把「还没读到」说成了别的。
    tag_runtime: pending_tag("GET /api/local/runtime 还没返回"),
    tag_instances: pending_tag("GET /api/local/instances 还没返回"),
    tag_profiles: pending_tag("GET /api/local/profiles 还没返回"),
    tag_archived: pending_tag("GET /api/local/console 还没返回"),
    tag_settings: pending_tag("GET /api/local/settings 还没读"),
    read_runtime: false,
    read_profiles: false,
    read_instances: false,
    built: false,
    rows: [],
    drawer_id: "",
    restarting: "",
    rename_id: "",
    rename_draft: "",
    rename_return: "",
    note_open: "",
    note_draft: "",
    note_return: "",
    note_error: "",
    note_saving: "",
    confirm_id: "",
    confirm_return: "",
    trash_purge_dir: "",
    trash_purge_return: "",
    // 归档区默认折叠：这一组目前固定是演示数据，短时间用不上；
    // 折叠起来不占视线，功能本身留着（展开即可用），比删掉合适。
    archived_open: false,
    archived_user_toggled: false,
    settings_loaded: false,
    settings_loading: false,
    settings: None,
    settings_error: "",
    settings_status: 0,
    settings_status_text: "",
    settings_endpoint_missing: false,
    settings_group: "instance",
    settings_draft: [],
    settings_saving: "",
    settings_pending: None,
    settings_feedback: "",
    settings_feedback_ok: false,
    act_pending: "",
    act_response: false,
    act_tick: false,
    act_ok: false,
    act_note: "",
    act_notice: "",
    act_notice_ok: false,
    act_notice_hint: "",
    act_notice_hint_for: "",
    act_name: "",
    act_verb: "",
    start_tab: "",
    start_tab_profile: "",
    start_tab_waiting: false,
    start_tab_tries: 0,
    notice_url: None,
    notice_url_notice: "",
    flash_serial: 0,
    flash_hover: false,
    flash_fading: false,
    console: None,
    console_error: "",
    read_console: false,
    log_source: "host",
    log_user_picked: false,
    log_loading: false,
    log_source_read: "",
    logs: None,
    log_error: "",
    log_time: "",
    log_tag: pending_tag("日志还没读"),
    log_instance_note: "",
  }
}

// ── 数据源标记 ──────────────────────────────────────────────

///|
/// 读失败那一档的标记（读成功那一侧写 None，不摆任何徽标）。
///
/// 返回的就是模型字段的值（SourceTag?），省得每个调用点再套一层 Some ——
/// 这一档只可能以标记的形式存在。
fn fallback_tag(detail : String) -> SourceTag? {
  Some({ kind: Fallback, label: "演示数据 | 真实读取失败", detail })
}

///|
/// 请求还在路上：读数没到之前的那一档。与「演示数据 / 读取失败」分开 ——
/// 那两档说的是「已经知道了什么」，这一档说的是「还不知道」。
fn pending_tag(detail : String) -> SourceTag? {
  Some({ kind: Pending, label: "读取中", detail })
}

///|
/// 几个只读读数是不是还没落地（runtime / profiles / instances / console 都算，
/// 列表就是等它们一起到了才拼的）。落地之前界面摆加载态：
/// 这一段空白不是「没有实例」，是「还没读到」。
fn readings_pending(model : Model) -> Bool {
  !model.built
}


// ── 拉取 ────────────────────────────────────────────────────

///|
fn load(emit : @cmd.Emit[Msg]) -> @cmd.Cmd {
  @cmd.batch([
    @http.get("/api/local/runtime").expect_text(emit.map(fn(res) { RuntimeText(res) })),
    load_console(emit),
    load_readings(emit),
  ])
}

///|
/// GET /api/local/console：运行时登记 + 归档记录。卡片上的「由本控制台启动」与归档区
/// 都按这份读数来；它读不到不影响别的读数，只是少这两处标记。
fn load_console(emit : @cmd.Emit[Msg]) -> @cmd.Cmd {
  @http.get("/api/local/console").expect_text(emit.map(fn(res) { ConsoleText(res) }))
}

///|
/// profiles + instances 两个读数。写动作成功之后单独重发这一对：
/// 「刷新读数」刷新的是这两份，runtime 不随动作变。
///
/// 重发之前要把 read_profiles / read_instances 重新置回未落地（见 app.mbt 的 refresh_readings）——
/// 否则先回来的那一份会拿着旧的另一份把列表拼一次，而 built 已经是 true，后回来的那份就白读了。
fn load_readings(emit : @cmd.Emit[Msg]) -> @cmd.Cmd {
  @cmd.batch([
    @http.get("/api/local/profiles").expect_text(emit.map(fn(res) { ProfilesText(res) })),
    @http.get("/api/local/instances").expect_text(emit.map(fn(res) { InstancesText(res) })),
  ])
}

///|
/// 日志页的读数：尾部行数由设置决定（读不到就是契约缺省 200），上限由接口负责截断并说明。
fn load_logs(source : String, tail : Int, emit : @cmd.Emit[Msg]) -> @cmd.Cmd {
  let query = "/api/local/logs?source=" + js_encode_uri_component(source) + "&tail=" +
    tail.to_string()
  @http.get(query).expect_text(emit.map(fn(res) { LogsText(res) }))
}

///|
/// 发起一次日志读取：先把加载态立起来（回执 LogsText 再放下去），读完滚到底。
///
/// 打开日志页、换来源、点刷新、点卡上的「查看日志」都走这一条 —— 四处各写一遍
/// 「记得置 log_loading」迟早会漏一处，漏掉的那处就会把「正在读」显示成「没有行」。
fn start_logs(model : Model, source : String, emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  (
    { ..model, log_source: source, log_loading: true },
    @cmd.batch([
      load_logs(source, log_tail_of(model), emit),
      scroll_bottom_after_render("dsh-log-box"),
    ]),
  )
}

///|
/// 日志页默认尾部行数：设置读到就用设置里的 logs.defaultTail，读不到用契约缺省 200。
/// 这一项是「真能配置」的：它在日志页的请求串上真的生效，不是只显示一个数字。
fn log_tail_of(model : Model) -> Int {
  match model.settings {
    Some(facts) =>
      match lookup_setting(facts.values, "logs.defaultTail") {
        Some(VInt(n)) => n
        _ => 200
      }
    None => 200
  }
}

///|
fn describe(err : Error) -> String {
  match err {
    Failure(msg) => msg
    _ => "未知错误"
  }
}

// ── 小工具 ─────────────────────────────────────────────────

///|
/// DOM 上的稳定 id：行 id 里带 ':'（port:3080），不能直接当选择器用。
fn dom_key(id : String) -> String {
  let buf = StringBuilder()
  for c in id {
    if c == ':' {
      buf.write_char('-')
    } else {
      buf.write_char(c)
    }
  }
  buf.to_string()
}

///|
/// 一张卡的 DOM id。关抽屉时焦点要回到触发它的那张卡，所以卡必须有个稳定的 id ——
/// 按 row.id 算（profile:web / port:3080），与语义路径同一口径，列表重排也不变。
fn card_id(id : String) -> String {
  "dsh-card-" + dom_key(id)
}

///|
/// 抽屉面板的 DOM id（同一时刻只开一个）。
fn drawer_panel_id() -> String {
  "dsh-drawer"
}

///|
/// 抽屉里那颗关闭键的 DOM id：打开时焦点落在它身上 ——
/// 焦点必须**真的进抽屉**（不然 Tab 还在背后的列表里走，Esc 也未必收得到）。
fn drawer_close_id() -> String {
  "dsh-drawer-close"
}

///|
fn archive_trigger_id(id : String) -> String {
  "dsh-archive-trigger-" + dom_key(id)
}


///|
fn find_row(rows : Array[Row], id : String) -> Row? {
  for row in rows {
    if row.id == id {
      return Some(row)
    }
  }
  None
}

///|
fn map_row(rows : Array[Row], id : String, f : (Row) -> Row) -> Array[Row] {
  rows.map(fn(row) { if row.id == id { f(row) } else { row } })
}


// ── 真实读数 → 卡片 ─────────────────────────────────────────

///|
fn version_text(runtime : RuntimeFacts?) -> String {
  match runtime {
    None => "—"
    Some(facts) => facts.dsh_version + "（" + facts.dsh_source_label + "）"
  }
}

///|
fn join_with(items : Array[String], sep : String) -> String {
  let buf = StringBuilder()
  let mut first = true
  for item in items {
    if !first {
      buf.write_string(sep)
    }
    buf.write_string(item)
    first = false
  }
  buf.to_string()
}

///|
/// 进程级原因码对应的短标签（卡上看得见的那一行）。空串 = 没有要说的。
/// 与后端 reason_text 同一套码；这里只缩短，不换意思。
fn process_note(fact : InstanceFact) -> String {
  match fact.process_reason_code {
    "port-join" =>
      if fact.profile is None {
        "cmdline 里没有 --profile"
      } else if fact.version is None {
        "入口包里读不到版本"
      } else {
        ""
      }
    "port-arg" => "进程是按 --port 匹配的，证据弱于 socket inode"
    "process-gone" => "进程不可见：已退出，或不在本 PID 命名空间"
    "fd-unreadable" => "/proc/<pid>/fd 读不到（权限不足）"
    "cmdline-unreadable" => "进程在，但 cmdline 读不到"
    "unscanned" => "没拿到该端口的 socket inode"
    _ => ""
  }
}

///|
/// 这一条是不是本控制台起的：runtime.json 的登记里有同一个端口，且那个 pid 还活着。
/// 只看端口不够 —— 登记过、后来那个 pid 退了端口被别人接走的情况也长得一样。
fn console_started(console : ConsoleFacts?, port : Int) -> Bool {
  match console {
    None => false
    Some(facts) => {
      let mut found = false
      for entry in facts.runtime {
        if entry.port == port && entry.alive {
          found = true
        }
      }
      found
    }
  }
}

// ── 状态灯（第七轮） ────────────────────────────────────────
//
// 卡片上只剩三样：图标 + 右上角那颗实心圆、profile 名、备注。所以「这只实例怎么样」
// 全部压进那颗圆里，**颜色不能是唯一信息** —— 每一档都带一句为什么（light_reason），
// 在抽屉里原样展示。
//
// 三色的判据来自契约（第七轮第一节），前端不改口径：
//   绿 = 签名探测通过；黄 = 故障（b 端口在听但签名不通过 / c profile 缺包）；红 = 没有在跑。
// 契约里 state 由后端给。**后端没给的时候前端不猜**：
// 实例卡走 unknown（空心灰环 + 一句「这一版后端还没给 state」）；
// 已停止的 profile 卡不一样 —— 它本来就不是实例读数，它的黄/红判据（缺包、有没有 patch）
// 全都在 profiles 读数里现成摆着，那是照契约算出来的事实，不是猜。

///|
/// 状态灯的类名后缀：样式表里 .dsh-dot.light-* 那一组。
fn light_class(light : Light) -> String {
  match light {
    LightRun => "light-run"
    LightFault => "light-fault"
    LightStart => "light-start"
    LightStop => "light-stop"
    LightUnknown => "light-unknown"
  }
}

///|
/// 状态灯写进 DOM 的档名（data-state）。探针与样式都按它认，不按颜色值猜。
fn light_key(light : Light) -> String {
  match light {
    LightRun => "running"
    LightFault => "fault"
    LightStart => "starting"
    LightStop => "stopped"
    LightUnknown => "unknown"
  }
}

///|
/// 档位的人话标签（悬停、抽屉标题都用它）。
fn light_label(light : Light) -> String {
  match light {
    LightRun => "绿 · 运行中"
    LightFault => "黄 · 故障"
    LightStart => "黄 · 正在启动"
    LightStop => "红 · 停用"
    LightUnknown => "未知（后端没给 state）"
  }
}

///|
/// 实例卡的状态灯：**只看后端的 state**。
///
/// 后端没给就返回 None —— 调用方据此走 unknown 并说清原因，不拿签名探测的结果去替它定色。
/// 「签名探测通过」确实是绿的判据，但「端口在听却探测不通过」这一半现在后端根本不列出来
/// （契约第七轮改的就是这条），前端只看得到一半的判据，据此上色就是把猜出来的颜色
/// 说得跟后端判的一样硬。
fn instance_light(fact : InstanceFact) -> (Light, String) {
  match fact.state {
    Some("running") =>
      (
        LightRun,
        "绿 · 运行中：签名探测通过（" +
        (if fact.signature_id == "" {
          "后端没给签名 id"
        } else {
          fact.signature_id + "：" + fact.signature_describe
        }) +
        "）。这一档由后端的 state 给（state=running）。",
      )
    Some("fault") =>
      (
        LightFault,
        "黄 · 故障：" + fact.state_reason +
        "。契约里黄的两种成因 —— b：端口在听、持有它的进程像 dsh，但签名探测不通过；" +
        "c：解析出的 profile 缺包大于 0（或没有 cordis.patch.yml）。",
      )
    Some("starting") =>
      (LightStart, "黄 · 正在启动（这一刻不是故障）：" + fact.state_reason)
    Some("stopped") => (LightStop, "红 · 停用：没有在跑。" + fact.state_reason)
    Some(other) =>
      (
        LightUnknown,
        "后端给的 state 是「" + other +
        "」，这一版前端认不出这一档 —— 颜色不猜。原样的理由：" + fact.state_reason,
      )
    None =>
      (
        LightUnknown,
        "这一版后端还没给 state 字段，颜色不猜（这一格是「未知」，不是三色里的任何一档）。" +
        "已有的读数里能说的只有：" +
        (if fact.signature_id == "" {
          "这个端口没有命中任何签名"
        } else {
          "签名探测通过（" + fact.signature_id + "）"
        }) +
        "；端口在听、持有它的进程像不像 dsh、profile 缺不缺包，要等后端把 state 接上才说得准。",
      )
  }
}

///|
/// 已停止的 profile 卡：状态灯由 profiles 读数自己算（契约黄的判据 c 与红的判据都在里面）。
///
/// 这不是「猜颜色」：没有在跑是这一组的分组条件（in_use_by 已经排掉了正在被用的那几只），
/// 缺包与 patch 是否存在是 GET /api/local/profiles 现成给的字段，一个字都没有编。
fn profile_light(fact : ProfileFact) -> (Light, String) {
  let missing = fact.bundles.missing
  if missing.length() > 0 {
    (
      LightFault,
      "黄 · 故障：没有在跑的实例，但这只 profile 缺 " + missing.length().to_string() +
      " 个包（" + join_with(missing, "、") + "）—— 契约里黄的成因 c。",
    )
  } else if !fact.patch_exists {
    (
      LightFault,
      "黄 · 故障：没有在跑的实例，但这只 profile 没有 cordis.patch.yml —— 契约里黄的成因 c。",
    )
  } else {
    (
      LightStop,
      "红 · 停用：没有在跑的实例，profile 的包也不缺、cordis.patch.yml 也在（契约里红的判据）。",
    )
  }
}

///|
/// 抽屉「profile 健康」那一块：正文 + 这句话是从哪读出来的。
///
/// 两个来源分开说，因为它们不是同一件事：instances 的 profileHealth 是后端按这只实例
/// 解析出来的；profiles 的 bundles/patch 是档案自己的读数。后端还没给前者时，
/// 用后者 join 出来的结论仍然是真的（同一个 profile 目录），但**要说清是这么来的**。
fn instance_health(fact : InstanceFact, profile_fact : ProfileFact?) -> (String, String) {
  match fact.profile_health {
    Some(health) =>
      (
        health_text_of(health.has_patch, health.missing_bundles, ""),
        "instances 读数的 profileHealth 字段（后端按这只实例解析出的 profile 给的）",
      )
    None =>
      match profile_fact {
        Some(item) =>
          (
            health_text_of(item.patch_exists, item.bundles.missing.length(), join_with(
              item.bundles.missing,
              "、",
            )),
            "instances 读数里没有 profileHealth 字段（这一版后端还没给）；这里按 GET /api/local/profiles 的 bundles / patch join 出来的",
          )
        None =>
          (
            "—",
            "这只实例没有解析出 profile，没有健康读数可读（profileHealth 字段这一版后端也还没给）",
          )
      }
  }
}

///|
/// 健康读数的正文：缺包优先报（一只缺包的 profile 比「patch 不在」更值得先看），
/// 都不缺才说「都对」。names 为空串表示手上没有包名清单（instances 的 profileHealth
/// 只给个数），这时不编名字。
fn health_text_of(has_patch : Bool, missing_count : Int, names : String) -> String {
  if missing_count > 0 {
    "缺 " + missing_count.to_string() + " 个包" +
    (if names == "" { "（后端只给了个数，没给名字）" } else { "：" + names })
  } else if !has_patch {
    "没有 cordis.patch.yml"
  } else {
    "声明的包都已安装，cordis.patch.yml 也在"
  }
}

///|
/// 正在运行的实例 = 监听端口 + HTTP 签名探测到的真实实例（不是 /proc 进程，也不是磁盘上的 profile）。
/// 实例的 Profile / DSH_HOME / DSH 版本 / 运行时长来自「端口 → socket inode → PID」这条 join；
/// 任一项拿不到就写「未知」，并把后端给的原因挂在悬停说明上 —— 不编值，也不留一个干巴巴的未知。
fn running_rows(
  facts : Array[InstanceFact],
  profiles : Array[ProfileFact],
  console : ConsoleFacts?,
) -> Array[Row] {
  facts.map(fn(fact) {
    let profile_fact = match fact.profile {
      Some(name) => {
        let mut found : ProfileFact? = None
        for item in profiles {
          if item.name == name {
            found = Some(item)
          }
        }
        found
      }
      None => None
    }
    let minutes = match fact.uptime_seconds {
      None => None
      Some(seconds) => Some(seconds / 60)
    }
    let name = match fact.profile {
      Some(profile) => profile + " :" + fact.port.to_string()
      None => "dsh :" + fact.port.to_string()
    }
    // 状态灯与「为什么是这个颜色」：实例卡只看后端的 state（后端没给就是 unknown，不猜）
    let (light, light_reason) = instance_light(fact)
    let (health_text, health_source) = instance_health(fact, profile_fact)
    {
      id: "port:" + fact.port.to_string(),
      name,
      kind: "本机监听的 dsh 实例",
      kind_hint: "从 /proc/net/tcp(6) 的 loopback LISTEN 端口探测到，命中判据 " +
        fact.signature_id + "：" + fact.signature_describe,
      tone: Accent,
      status: Running,
      uptime: minutes,
      uptime_hint: match minutes {
        None =>
          if fact.process_reason == "" {
            "运行时长读不到：没拿到该端口的 socket inode，也没对上进程"
          } else {
            "运行时长读不到：" + fact.process_reason
          }
        Some(_) => ""
      },
      port_note: "",
      // 档案的健康读数（patch/lock）搬到这张卡上：它对应的 profile 卡不再单独出现
      idle_note: match profile_fact {
        Some(item) => patch_lock_note(item)
        None => ""
      },
      // 这条是「一眼值得知道的那一条」：profile 解析出来时优先报它的缺包情况
      // （一只正在跑却缺 3 个包的实例，比进程备注更值得看）；解析不出来才退回进程备注。
      note: match profile_fact {
        Some(item) =>
          if item.bundles.missing.length() > 0 {
            "缺 " + item.bundles.missing.length().to_string() + " 个包：" +
            join_with(item.bundles.missing, "、")
          } else {
            ""
          }
        None => process_note(fact)
      },
      busy: false,
      version: match fact.version {
        Some(v) => v + "（入口包）"
        None => "未知"
      },
      version_hint: fact.version_source,
      profile: match fact.profile {
        Some(profile) => profile
        None => "未知"
      },
      profile_hint: fact.profile_source,
      home: match fact.dsh_home {
        Some(home) => home
        None => "未知"
      },
      home_hint: fact.dsh_home_source,
      url: fact.url,
      // 带令牌的地址来自后端（按实例端口对出来的那一条），前端不自己拼、也不缓存
      web_url: fact.web_url,
      web_url_source: fact.web_url_source,
      plugin_count: match profile_fact {
        Some(item) =>
          "声明 " + item.bundles.declared.to_string() + " | 已装 " +
          item.bundles.installed.to_string()
        None => "—"
      },
      plugin_detail: match profile_fact {
        Some(item) =>
          if item.bundles.missing.length() > 0 {
            "缺少的包：" + join_with(item.bundles.missing, "、")
          } else {
            ""
          }
        None => ""
      },
      deletable: false,
      archived_at: None,
      profile_name: fact.profile,
      port_value: Some(fact.port),
      console_started: fact.console_started || console_started(console, fact.port),
      // 运行中卡也要带备注：这只 profile 的目录就在磁盘上，备注读得到什么就写什么
      user_note: match profile_fact {
        Some(item) => item.note
        None => ""
      },
      user_note_source: match profile_fact {
        Some(item) => item.note_source
        None => ""
      },
      // 第六格：这只实例用的 profile 目录的最近改动。profile 解析得出就用它的 mtime；
      // 解析不出就写「—」（不是「读不到」）—— 没有可读的对象与读了拿不到，不是一件事。
      mtime_ms: match profile_fact {
        Some(item) => item.dir_mtime_ms
        None => None
      },
      mtime_missing: if profile_fact is Some(_) { "读不到" } else { "—" },
      mtime_hint: match profile_fact {
        Some(item) =>
          match item.dir_mtime_ms {
            Some(ms) => mtime_value_hint(ms, item.dir_mtime_source)
            None => mtime_missing_hint(item.dir_mtime_source)
          }
        None =>
          match fact.profile {
            Some(name) =>
              "这只实例解析出的 profile 名是「" + name + "」，但 profiles 读数里没有这一只，" +
              "没有目录可读最近改动" +
              (if fact.profile_source == "" { "" } else { "（" + fact.profile_source + "）" })
            None =>
              "实例读数里没解析出 profile 名，没有 profile 目录可读最近改动" +
              (if fact.profile_source == "" { "" } else { "（" + fact.profile_source + "）" })
          }
      },
      light,
      light_reason,
      state_raw: match fact.state {
        Some(state) => state
        None => "没有这个字段（这一版后端还没给）"
      },
      state_reason: fact.state_reason,
      health_text,
      health_source,
    }
  })
}

///|
/// patch 行数 / lock 时刻这一行：档案的健康读数，运行中卡与停止卡共用同一口径。
fn patch_lock_note(fact : ProfileFact) -> String {
  "cordis.patch.yml " + fact.patch_lines.to_string() + " 行 | " +
  (if fact.lock_exists {
    match fact.lock_mtime {
      Some(mtime) =>
        match js_short_time(mtime) {
          "" => "lock —"
          text => "lock " + text
        }
      None => "lock —"
    }
  } else {
    "无 pnpm-lock.yaml"
  })
}

///|
/// 这只 profile 是否正被某个可见进程用着。
/// 按名字比：控制台当前只读一个 DSH_HOME，同名即同一份档案。
/// 将来支持多 home 时，这里要改成「home + 名字」一起比。
fn in_use_by(fact : ProfileFact, running : Array[InstanceFact]) -> Bool {
  for inst in running {
    match inst.profile {
      Some(used) =>
        if used == fact.name {
          return true
        }
      None => ()
    }
  }
  false
}

// ── 卡片第六格「最近改动」 ──────────────────────────────────
//
// 卡片字段区是 2 列 × 3 行 = 6 格。前五格是 DSH 版本 / Profile / 访问地址 / DSH_HOME /
// 插件数量，第六格是「最近改动」：这只 profile **目录**的 mtime。
//
// **为什么不是「创建时间」**：多数文件系统上可靠的创建时间拿不到 ——
// ctime 记的是 inode 变更时间，chmod / 改名都会把它推新（不是出生时间）；
// birth time 不通用（不是每个文件系统都存，也不是每个平台都读得到）。
// 目录 mtime 是能拿到、且不会骗人的那一个 ✓
// 而且刚派生出来的 profile 一定是最新的，所以「最近改动」顺带回答了使用者那句
// 「我都不知道它忽然冒出来这个新的」—— 派生完它就排在最上面。
// 界面上这一格的标签、以及这里的所有注释，都不许写成「创建时间」✗

///|
/// 有值时那一格的悬停：说清这是什么数，并写明口径为什么是「最近改动」。
fn mtime_value_hint(ms : Double, source : String) -> String {
  let iso = js_iso_time_ms(ms)
  "这只 profile 目录的最近改动时刻（mtime" +
  (if iso == "" { "" } else { " " + iso }) +
  "，卡上按浏览器本地时间显示）。" +
  "口径是「最近改动」不是「创建时间」：多数文件系统上可靠的创建时间拿不到" +
  "（ctime 会在 chmod / 改名时变，birth time 不通用）；刚派生出来的 profile 一定是最新的。" +
  (if source == "" { "" } else { "来源：" + source })
}

///|
/// 读不到时那一格的悬停：把后端给的 dirMtimeSource 原样带上，不吞、也不换成一句空话。
fn mtime_missing_hint(source : String) -> String {
  "读不到这只 profile 目录的最近改动：" +
  (if source == "" { "后端没给原因" } else { source })
}

///|
/// 降序比较「最近改动」。None **不是 0**：读不到的要沉到最后，不许跟真有值的混在一起比 ✗
fn mtime_desc(a : Double?, b : Double?) -> Int {
  match (a, b) {
    (Some(x), Some(y)) => if x > y { -1 } else if x < y { 1 } else { 0 }
    (Some(_), None) => -1
    (None, Some(_)) => 1
    (None, None) => 0
  }
}

///|
/// 名字升序：同一档里（都没有 mtime）的兜底顺序，让刷新前后是同一个样子。
///
/// **必须用 lexical_compare，不能用 `<`**：MoonBit 的 `Compare` 对 String 是
/// shortlex —— 先比长度、长度相同再逐字符比。于是 `"web-dev" < "headless"` 成立
/// （7 < 8），排出来是「短的在前」，不是人说的「名字升序」。
/// lexical_compare 才是逐字符的字典序（同 Java 的 String.compareTo）。
/// 实测踩过：三张卡按名字升序排成了 web-dev / headless / review-dev。
fn name_asc(a : String, b : String) -> Int {
  a.lexical_compare(b)
}

///|
/// 已停止的实例 = 磁盘上真实存在的 profile，**且没有被任何可见进程用着**。
/// 被用着的那只不在这里出现：它的版本 / 插件 / patch / lock 都归到那张运行中卡上——
/// 同一个东西不能既「运行中」又「已停止」。
fn profile_rows(
  profiles : Array[ProfileFact],
  runtime : RuntimeFacts?,
  dsh_home : String,
  running : Array[InstanceFact],
) -> Array[Row] {
  let rows : Array[Row] = []
  for fact in profiles {
    if in_use_by(fact, running) {
      continue
    }
    let missing = fact.bundles.missing
    // 停止卡的状态灯：没有在跑 + 缺包/缺 patch 这两条判据都在 profiles 读数里（不是猜的）
    let (light, light_reason) = profile_light(fact)
    rows.push({
      id: "profile:" + fact.name,
      name: fact.name,
      // 「本地 profile」这个标签永远为真、从不提供信息（没有「远端 profile」这种东西）→ 删掉：
      // 一只磁盘上的 profile 当然是本地的，写出来只是噪声（与「真实数据」那一类同理）。
      // 留下的只有「默认」这半 —— 它是真信息：DSH_PROFILE 指向它。
      // 不是默认的卡片这一格**一个节点都不产出**：不留空 pill，也不摆一个空壳（见 view_overview
      // 的 sub_line —— 那一轨的宽度留着是为了状态点跨卡对齐，节点是真的没有）。
      kind: if fact.is_current { "默认 profile" } else { "" },
      // 「默认」只表示 DSH_PROFILE 指向它，跟「运行中」无关 —— 这个词以前写成「当前」，会被读成正在跑
      kind_hint: if fact.is_current {
        "环境变量 DSH_PROFILE 指向这只 profile：新起的实例默认用它，不代表它正在运行"
      } else {
        ""
      },
      tone: Violet,
      status: Stopped,
      uptime: Some(0),
      uptime_hint: "",
      port_note: "",
      idle_note: patch_lock_note(fact),
      note: if missing.length() > 0 {
        "缺 " + missing.length().to_string() + " 个包：" + join_with(missing, "、")
      } else {
        ""
      },
      busy: false,
      version: version_text(runtime),
      version_hint: "控制台后端读到的 dsh 版本与来源（这只 profile 没有运行中的进程，版本取的是控制台自身的读数）",
      profile: fact.name,
      profile_hint: "磁盘上真实存在的 profile 目录名：" + fact.name,
      home: dsh_home,
      home_hint: "控制台当前使用的 DSH_HOME（来源见「关于」页的 DSH_HOME 一行）",
      url: "已停用，无法访问",
      // 这只 profile 现在没有在跑的实例：没有地址可握手，也就没有令牌可读
      web_url: None,
      web_url_source: "这只 profile 现在没有在运行的实例，没有访问地址可握手",
      plugin_count: "声明 " + fact.bundles.declared.to_string() + " | 已装 " +
        fact.bundles.installed.to_string(),
      plugin_detail: if missing.length() > 0 {
        "缺少的包：" + join_with(missing, "、")
      } else {
        fact.name + " 声明的插件都已安装"
      },
      deletable: true,
      archived_at: None,
      profile_name: Some(fact.name),
      port_value: None,
      console_started: false,
      user_note: fact.note,
      user_note_source: fact.note_source,
      mtime_ms: fact.dir_mtime_ms,
      mtime_missing: "读不到",
      mtime_hint: match fact.dir_mtime_ms {
        Some(ms) => mtime_value_hint(ms, fact.dir_mtime_source)
        None => mtime_missing_hint(fact.dir_mtime_source)
      },
      light,
      light_reason,
      // 停止卡不是实例读数：没有 state 这回事，理由里写的是前端照契约算出来的依据
      state_raw: "不适用（这是磁盘上的 profile 行，不是实例读数）",
      state_reason: "这一行是磁盘上的 profile，不是实例读数：实例的 state 字段对它不适用；" +
        "状态灯按 profiles 读数里现成的两条判据给（缺包 / 有没有 cordis.patch.yml）",
      health_text: health_text_of(
        fact.patch_exists,
        missing.length(),
        join_with(missing, "、"),
      ),
      health_source: "GET /api/local/profiles 的 bundles / patch 字段",
    })
  }
  // 已停止这一组按**最近改动降序**：新的在最上面。
  //
  // 依据是目录 mtime（dirMtimeMs），**不是「创建时间」** —— 理由见本文件
  // 「卡片第六格『最近改动』」那段注释：ctime 会被 chmod / 改名推新，birth time 不通用。
  // 刚派生出来的 profile 一定是最新的，所以它排在第一个，一眼就能看到。
  //
  // 读不到 mtime 的（dirMtimeMs = null）一律沉底，同一档内按名字升序兜底 ——
  // 顺序必须是确定的，不然同一份读数每次刷新都可能换个样子。
  // 运行中那一组不在这里排：它按实例读数自己的顺序走，不掺进这条口径。
  rows.sort_by(fn(a, b) {
    let by_time = mtime_desc(a.mtime_ms, b.mtime_ms)
    if by_time != 0 { by_time } else { name_asc(a.name, b.name) }
  })
  rows
}

///|
/// 归档区的行：按 console 读数里的归档记录，把对应的 profile 行标上归档时间。
/// 行是按 profiles 读数重建的，归档记录在另一份读数里，所以每次重建都要重新标。
/// 磁盘上已经没有那只 profile 的记录另外补一行（记录要看得见，也才能取消归档）。
fn apply_archived_marks(model : Model, rows : Array[Row]) -> Array[Row] {
  let archive = match model.console {
    Some(facts) => facts.archive
    None => []
  }
  if archive.length() == 0 {
    return rows
  }
  let marked = rows.map(fn(row) {
    match row.profile_name {
      None => row
      Some(name) => {
        let mut stamp = ""
        for record in archive {
          if record.profile == name {
            stamp = record.archived_at
          }
        }
        if stamp == "" {
          row
        } else {
          { ..row, archived_at: Some(stamp) }
        }
      }
    }
  })
  for record in archive {
    let mut listed = false
    for row in marked {
      match row.profile_name {
        Some(name) =>
          if name == record.profile {
            listed = true
          }
        None => ()
      }
    }
    if !listed {
      marked.push(archived_orphan(record))
    }
  }
  marked
}

///|
/// 归档记录在、磁盘上的 profile 目录不在时的那一行：只为了让人看见这条记录并撤掉它。
fn archived_orphan(record : ConsoleArchive) -> Row {
  {
    id: "archived:" + record.profile,
    name: record.profile,
    kind: "已归档 | 磁盘上没有这只 profile",
    kind_hint: "archive.json 里有这只 profile 的归档记录，但 profiles 读数里没有对应的目录",
    tone: Violet,
    status: Stopped,
    uptime: Some(0),
    uptime_hint: "",
    port_note: "",
    idle_note: "",
    note: "",
    busy: false,
    version: "—",
    version_hint: "磁盘上没有这只 profile，没有版本可读",
    profile: record.profile,
    profile_hint: "archive.json 里的记录：" + record.profile,
    home: "—",
    home_hint: "磁盘上没有这只 profile",
    url: "—",
    web_url: None,
    web_url_source: "磁盘上没有这只 profile 的目录，没有实例可读，也没有令牌",
    plugin_count: "—",
    plugin_detail: "",
    deletable: true,
    archived_at: Some(record.archived_at),
    profile_name: Some(record.profile),
    port_value: None,
    console_started: false,
    // 磁盘上没有这只 profile，也就没有备注文件可读：不编
    user_note: "",
    user_note_source: "",
    // 同理：目录都不在了，没有最近改动可读
    mtime_ms: None,
    mtime_missing: "读不到",
    mtime_hint: "磁盘上没有这只 profile 的目录，没有最近改动可读（这一行来自 archive.json 的归档记录）",
    light: LightStop,
    light_reason: "红 · 停用：没有在跑的实例；磁盘上已经没有这只 profile，所以也没有健康读数可算" +
      "（这一行来自 archive.json 的归档记录）。",
    state_raw: "不适用（这一行来自 archive.json 的归档记录，不是实例读数）",
    state_reason: "这一行不是实例读数，没有 state；磁盘上也没有这只 profile 可供算健康",
    health_text: "—",
    health_source: "磁盘上没有这只 profile 的目录，没有健康读数可读",
  }
}

// ── 演示数据（真实读取失败时兜底） ─────────────────────────
//
// 这些行**没有写动作的目标**：profile_name / port_value 都是 None。
// 以前它们只是一排假读数，点了删除也只是从列表里消失；现在菜单上的按钮会真的
// POST /api/local/action，拿演示数据里的名字（main / dev / staging）去打真东西是不行的 ——
// 所以演示行的动作一律先在本地说清「读不到目标」，不发请求。
//
// 归档区不再是演示：它显示的只有本轮点过「归档」的行（见 app.mbt 的 apply_action_effect）。

///|
fn demo_running() -> Array[Row] {
  [
    {
      id: "work-main", name: "work-main", kind: "核心工作实例", kind_hint: "",
      tone: Accent, status: Running, uptime: Some(138), uptime_hint: "",
      port_note: "", idle_note: "", note: "", busy: false,
      version: "0.2.0-rc.2（本地源码）", version_hint: "演示数据，不是读数", profile_hint: "演示数据，不是读数", home_hint: "演示数据，不是读数", profile: "main", home: "/Users/you/.dsh/work-main",
      url: "http://127.0.0.1:8100", web_url: None,
      web_url_source: "演示数据：端口 8100 上没有真实实例，读不到令牌",
      plugin_count: "5 个", plugin_detail: "",
      deletable: false, archived_at: None,
      profile_name: None, port_value: None, console_started: false,
      user_note: "", user_note_source: "",
      mtime_ms: None, mtime_missing: "读不到",
      mtime_hint: "演示数据：不是真实读数，没有目录可读最近改动",
      light: LightUnknown,
      light_reason: "这是真实读取失败时兜底的演示数据，没有读数，颜色不猜。",
      state_raw: "没有（演示数据，不是读数）",
      state_reason: "演示数据：不是真实读数，没有 state 可读",
      health_text: "—",
      health_source: "演示数据：不是真实读数",
    },
    {
      id: "plugin-dev", name: "plugin-dev", kind: "插件开发（试验）", kind_hint: "",
      tone: Violet, status: Running, uptime: Some(42), uptime_hint: "",
      port_note: "", idle_note: "", note: "", busy: false,
      version: "0.2.0-rc.2（本地源码）", version_hint: "演示数据，不是读数", profile_hint: "演示数据，不是读数", home_hint: "演示数据，不是读数", profile: "dev", home: "/Users/you/.dsh/plugin-dev",
      url: "http://127.0.0.1:8200", web_url: None,
      web_url_source: "演示数据：端口 8200 上没有真实实例，读不到令牌",
      plugin_count: "2 个（开发中）", plugin_detail: "",
      deletable: true, archived_at: None,
      profile_name: None, port_value: None, console_started: false,
      user_note: "", user_note_source: "",
      mtime_ms: None, mtime_missing: "读不到",
      mtime_hint: "演示数据：不是真实读数，没有目录可读最近改动",
      light: LightUnknown,
      light_reason: "这是真实读取失败时兜底的演示数据，没有读数，颜色不猜。",
      state_raw: "没有（演示数据，不是读数）",
      state_reason: "演示数据：不是真实读数，没有 state 可读",
      health_text: "—",
      health_source: "演示数据：不是真实读数",
    },
  ]
}

///|
fn demo_stopped() -> Array[Row] {
  [
    {
      id: "staging", name: "staging", kind: "插件开发（试验）", kind_hint: "",
      tone: Violet, status: Stopped, uptime: Some(0), uptime_hint: "",
      port_note: "", idle_note: "", note: "", busy: false,
      version: "0.2.0-rc.2（本地源码）", version_hint: "演示数据，不是读数", profile_hint: "演示数据，不是读数", home_hint: "演示数据，不是读数", profile: "staging", home: "/Users/you/.dsh/staging",
      url: "http://127.0.0.1:8300", web_url: None,
      web_url_source: "演示数据：端口 8300 上没有真实实例，读不到令牌",
      plugin_count: "3 个", plugin_detail: "",
      deletable: true, archived_at: None,
      profile_name: None, port_value: None, console_started: false,
      user_note: "", user_note_source: "",
      mtime_ms: None, mtime_missing: "读不到",
      mtime_hint: "演示数据：不是真实读数，没有目录可读最近改动",
      light: LightUnknown,
      light_reason: "这是真实读取失败时兜底的演示数据，没有读数，颜色不猜。",
      state_raw: "没有（演示数据，不是读数）",
      state_reason: "演示数据：不是真实读数，没有 state 可读",
      health_text: "—",
      health_source: "演示数据：不是真实读数",
    },
  ]
}
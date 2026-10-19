// 应用状态、消息与更新循环。
//
// 导航既是状态切页也是 URL：page 是 model 里的字段，同时写进地址栏（见 route.mbt），
// 刷新与前进/后退都按地址复原页面。
// 三个只读接口在 init 里一次发出去；读不到就把原因留进 model，界面直接展示；
// 还没回来之前界面是加载态，不是空态（见 readings_pending）。

///|
pub(all) enum Page {
  Overview
  /// 维护（作业台）：按顺序做、每步有检查、失败能退回的作业都在这里
  Maintenance
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
  /// 隔离到独立 home（POST isolate-profile）
  IsolateHome
  /// 取消隔离（先开确认框，确认后 POST deisolate-profile）
  DeisolateHome
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
///   * starting —— 正在起来（前端启动等待态，也认读数给的 starting）。用同一支琥珀，
///     但文案是「正在启动」，不会被读成故障；它在动（dot-pulse），静止态一个动效都没有
///   * unknown  —— 读数里没有状态这一项。**这时不猜颜色**：
///     灯是空心的灰环，抽屉里写清「读不到状态，颜色不猜」
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
  /// 这一行的**归档记录**属于哪个 home（只有归档孤行用得上）。
  ///
  /// 为什么孤行要单独带一个：孤行的 home 就来自这条记录（磁盘上没有目录可读），
  /// 而取消归档必须说清撤的是哪一条记录 —— 同名两份档案在两个 home 里时，
  /// 只发名字会把另一份也撤掉。别处一律空串，那时用 row.home（就是这只 profile 所在的 home）。
  archive_home : String
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
  // ── 配置 home（design/deep-home-isolation.md 第 4、5 节）──
  /// 这只 profile 的 home 归属：isolated（独立）/ shared（共用）/ 空串（读数里没有这一项）
  home_kind : String
  /// 那一份 home 的路径（隔离 home 根，或控制台的 DSH_HOME）
  home_path : String
  /// 后端给的判断依据（进悬停）。空串 = 读数里没给
  home_kind_source : String
  /// 卡片第二行第三顺位的「上次启动」时刻（UTC ISO）。空串 = 取不到 ——
  /// 那一行就空着，**绝不写一个编出来的时间**。
  ///
  /// 取值优先级见 row_last_started：正在跑的那一只用它真实的启动时刻
  /// （instances 的 startedAt，后端从进程起始时间推出来）；其余按 port / profile
  /// 去控制台的 lastStarted 表里查（runtime.json 的 startedAt 与 audit.jsonl 的
  /// start-instance 合成的那一份）。两处都没有就是空串。
  last_started : String
  /// 上面那个时刻的来源（人话，进悬停）。空串 = 没有时刻，也就没有来源。
  last_started_source : String
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
  /// **为什么是这个颜色** —— 抽屉里那一块的正文：一行，说人话。
  /// 契约明确要求颜色不能是唯一信息，所以这一句不是装饰：黄的两个成因要能分开说。
  light_reason : String
  /// 上面那句话的技术依据：哪一条握手应答命中、探测回来的是什么、profile 那一侧怎么样。
  ///
  /// **只在悬停里出现，正文一个字都不占**：它回答的是「这个结论怎么来的」，
  /// 不是使用者要读的那句结论。
  light_basis : String
  /// 抽屉「profile 健康」那一块的正文。
  ///
  /// 分两副形状，判据是**我们预先知不知道它长什么样**（不是内容长短）：
  ///   已知且可枚举（缺 N 个包 / cordis.patch.yml 在不在）→ 压成一行摘要，清单进 health_hint；
  ///   自由文本（后端报回来的错误串）→ 最多两行，原文同样进 health_hint。
  /// 形状由 view 那边的 .dsh-problem 定，这里只给数据。
  health_text : String
  /// 上一句的**悬停全文**：已知那一类是完整清单，自由文本那一类就是原文。
  /// 正文被压掉的字一个都不丢，全在这里；空串 = 没什么可补的，那一格就不挂悬停。
  health_hint : String
  /// 正文是不是**自由文本**（未知那一类）。true → 最多两行、超出省略号；
  /// false → 一行摘要 + 省略号。已知那一类再长也不换形状。
  health_free : Bool
  /// 同一个进程的其余监听端口（如 "9230"）。空数组 = 只听着一个端口 ——
  /// 抽屉里那行「还听着 9230」只在非空时出现；卡片上一律不显示、也不因此变色。
  also_ports : Array[String]
  /// 上面那一行的悬停：每个端口各自是什么（后端给的那句话）
  also_ports_hint : String
} derive(Eq)

pub extend Row with Eq::{ not_equal, equal }

///|
/// 启动等待时长与重启按钮的自锁时长（前端演示，没有真实进程可等）。
pub let start_delay_ms : Int = 2500

///|
pub let restart_lock_ms : Int = 900

///|
/// 拖动排序的位移阈值（CSS 像素）。按下之后位移超过它才算拖动，没超过就还是点击。
///
/// 6 是手感数：小于它，手一抖就把点击吃成拖动（点卡开抽屉会时灵时不灵）；
/// 大于它，拖起来要先把指针甩出去一段才「咬住」。
pub let drag_threshold_px : Double = 6.0

///|
/// 窄到这一档就不响应拖动（CSS 像素）。
///
/// 726 就是样式里那个两列断点（.dsh-rows.dsh-card-grid 的 @media (min-width: 726px)）：
/// 低于它页面是单列，条目占满整幅宽，纵向拖动与页面滚动落在同一个手势上 ——
/// 拖一次条目，页面跟着往下滚。两处必须一起改。
pub let drag_min_viewport_width : Int = 726

///|
/// 条目让位那一段过渡的时长（毫秒）：别条从旧格子挪到新格子走这么久。
///
/// 与 style 里 .dsh-case 的 transition 时长、以及 dom.mbt 里 FLIP 动画的时长
/// 是同一个数（改一处得改另两处）。取值 150–200：再快看不清「谁让了谁」，
/// 再慢指针已经移到下一格了、上一段还没走完，落点会看着发黏。
/// **减少动效那一档不做过渡**（那条 media query 关掉 transition + FLIP 自己会跳过）。
pub let reorder_ms : Int = 180

///|
/// 键盘换位第一拍与第二拍之间留多久（毫秒）：占位块先亮出来，再落位。
///
/// 比 reorder_ms 略长一点：让位那一段走完，眼睛已经看见「落到这儿」，
/// 落位紧跟着发生；短于 reorder_ms 的话两段动画会叠在一起，看着像直接跳过去。
pub let reorder_preview_ms : Int = 190

///|
/// 成功提示（toast）的寿命：出现之后这么多毫秒开始淡出。
///
/// 只有**成功**的提示会走：失败要留到使用者自己处理掉（见 app.mbt 的 update 外壳）。
pub let flash_ms : Int = 4000

///|
/// toast 淡出那一小段（毫秒）：先把不透明度收下去，再撤节点。
pub let flash_fade_ms : Int = 220

///|
/// 详情抽屉开、合那一段动画的时长（毫秒）。
///
/// **出入同一条**：一个快一个慢看着别扭（进 200 / 出 100 像被弹回去）。
/// 取值在 180–240 之间（使用者给的范围），与样式里 .dsh-drawer 的 animation 时长
/// 是同一个数 —— 改一处得改另一处。
///
/// **上限是硬的**：收起来那一段走完之后节点才撤，验收探针在 Esc 之后等 700ms
/// 就断言「抽屉没了」；这个数超过 300 就会让那条判定误报。
pub let drawer_anim_ms : Int = 220

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
  /// 正在滑出、还没撤节点的那一行（空串 = 没有）。**这一格只是一段动画的寿命**：
  /// 关上之后节点还留 drawer_anim_ms，让滑出看得见；到点由 DrawerClosed 撤掉。
  /// 它不参与任何判定 —— 焦点、点击、键盘都按「抽屉已经关了」走。
  drawer_closing : String
  // ── 拖动排序（第十轮） ──
  //
  // 状态分三块：**表**（order）、**这一次拖动的过程**（drag_*）、**写回失败的回滚点**
  // （order_before）。三块分开存，是因为它们的寿命不一样：表是读数级别的（刷新会重读），
  // 过程是一次手势级别的（松手就清），回滚点只活到回执回来那一刻。
  /// 手动排序的顺序表。空 = 没拖过 = 两组各走各的自动排序（见 apply_order）
  order : Array[String]
  /// 正在按下的那一行（"" = 没按）。窄屏按下时这一格不置 —— 那一档不启动拖动
  drag_id : String
  /// 按下那一刻的视口坐标：判「位移过没过阈值」用
  drag_start_x : Double
  drag_start_y : Double
  /// 位移过阈值了。**只有它成立才叫拖动**；没过的按下-松开仍然是点击（开抽屉）
  drag_active : Bool
  /// 这一次拖动落在哪一组（"" = 没有）。占位块只插在这一组里。
  drag_group : String
  /// 被拖的那一条原来在第几格（0 起）：换位播报要说「从第几到第几」时用得上。
  drag_from : Int
  /// 落点那一格现在是哪一条（"" = 现在没有落点）。
  ///
  /// 只是给人读的读数（拖动过程里「要落到谁那儿」），不参与摆放：
  /// 占位块与落位都按 drag_at_index 那一个格子序号走（见 drop_cell），
  /// 两者必须是同一个决定的两个说法，不然画在最左边而落在最右边。
  drag_at : String
  /// 上面那个占位块所在的**格子序号**（0 起），也就是松手后被拖的那一条将落到的位次。
  ///
  /// 这一格是这一轮的**唯一判据**：占位块画在第 k 格、松手就落在第 k 格。
  /// -1 = 没有落点（指针横向出了这一组的栅格 / 跨组 / 还没过阈值）。纵向**不设界**：
  /// 越过最后一块 = 最后一格、越过第一块 = 第一格（第十三轮口径变更）。
  drag_at_index : Int
  /// 拖动中的虚影跟着指针走到哪儿了（视口坐标；按下那一刻虚影的中心就压在指针上）。
  /// 只是画：不参与任何判定。
  drag_ghost_x : Double
  drag_ghost_y : Double
  /// 虚影要不要画（过了阈值才算拖动，虚影跟着出现）
  drag_ghost : Bool
  /// 虚影的宽高（CSS 像素）：按下时从被拖的那一条身上量一次，整个拖动过程不变。
  /// 中途不再量，是因为列表正在让位 —— 再量一次会量到挪开后的格子，虚影会跟着跳。
  drag_ghost_w : Double
  drag_ghost_h : Double
  /// 这一次按下-松开不该再开抽屉（拖动过了）。**下一次按下会把它清掉** ——
  /// 不这么做的话，「拖完在卡片外松手、click 没来」会把这个标记一直留着，
  /// 吃掉使用者下一次真正的点击。
  drag_suppress_click : Bool
  /// 键盘换位正等着落位的那一步（-1 / +1；0 = 没有等着的那一步）。
  ///
  /// Ctrl+方向键分两拍：先摆出占位块让人看见「要落到哪儿」，190ms 之后才真的换。
  /// 这一格记的就是那第二拍要走的步长 —— 不记的话，第二拍只能现猜，
  /// 而这中间使用者可能又按了别的方向（那时预览已经跟着换了，落位必须听最后一次）。
  drag_key_dir : Int
  /// 提交前的那一份顺序。写回失败要按它回滚：失败之后页面必须回到原样，
  /// 停在「看着是新的、其实没存下」的状态比不做还糟。
  order_before : Array[String]
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
  // 取消隔离的确认框：目标行 id（空串 = 框关着）与触发元素 id。
  // 与删除确认框分开一格：两个框说的是两件事，共用一个字段会让「关掉一个，另一个也关了」。
  home_confirm_id : String
  home_confirm_return : String
  // 回收站「彻底删除」的确认框：目标目录名（空串 = 框关着）与触发元素 id
  trash_purge_dir : String
  trash_purge_return : String
  // ── 维护页（作业台） ──
  // 与 act_notice 分开：总览页那条提示条读的是 act_notice，借它的话，
  // 在维护页做完动作再切回总览会看到一条与那一页无关的话。
  /// 新作业表单里的目标版本（空串 = 没选）。**不在本地补一个「最新版」**：
  /// §4 说得很清楚，版本由使用者选，后端不猜。
  /// 第六版起这一格只由版本侧栏回填：表里点一版、或按自定义版本那一行。
  job_version : String
  /// 版本侧栏开着没有（§12.1：从居中弹层改成右侧栏，与配置侧栏同一套外壳）。
  /// 开着的时候焦点在搜索框里。
  version_sidebar : Bool
  /// 侧栏搜索框里的原文：输入即过滤，列表里没有就是自定义版本。
  version_query : String
  /// 版本表上的过滤 chip（§12.3）。**空数组 = 「全部」**：一个都不选就是不过滤。
  /// 元素只认 "installed" / "stable" / "prerelease" 三个键，多个之间是「或」。
  version_filters : Array[String]
  /// 版本表的排序档（§12.3）：new（从新到旧，缺省）/ old（从旧到新）/ published（按发布时间）。
  version_sort : String
  /// 版本来源读数（GET /api/local/dsh-releases）。后端只读进程内缓存、秒回，
  /// 所以「慢」不再是这一页的问题：读到的 state 说的是后台那一趟拉取的状态。
  /// None + 还在问 = 读取中；None + 问完了 = 没读到（releases_error 里有原因）
  releases : ReleasesFacts?
  releases_error : String
  releases_loading : Bool
  /// 上一次「重新拉取」那一枪没排上的原因（空串 = 没失败 / 已重试）。
  /// 与 releases_error 分开：那条说的是「读数读不到」，这条说的是「手动刷新没发出去」。
  releases_refresh_error : String
  /// 已经为「还在拉」补问了几次（进维护页 / 打开侧栏时清零）。
  /// 后端那条 GET 只回缓存，所以读到 loading 之后要隔一会儿再问一次才拿得到结果；
  /// 上限见 state.mbt 的 releases_poll_cap，免得某次真挂了把定时器挂成永动机。
  releases_ticks : Int
  /// 已经有一个补问的定时器排着了。**同一时刻只许排一个**：
  /// 进页面与打开侧栏会各发一次 GET，两个回执各排一个定时器的话，补问会翻倍
  /// （2、4、8…几拍就把上限吃完），列表还没落地就已经不再问了。
  releases_poll_pending : Bool
  /// 试跑用配置的右侧侧栏开着没有（§10.3）。开着的时候焦点在第一张可点的卡上。
  profile_sidebar : Bool
  /// 新作业表单里选的试跑 profile（空串 = 还没亲手选过，按「在跑的 → web → 第一份」推）。
  /// 存「用户亲手选的那一个」，不存推出来的那一个：推的那份随读数变，
  /// 存下来就成了「明明不是它却显示是它」。
  job_profile : String
  /// 正在发的那条作业动作："new" 或作业 id（空串 = 没有在发）
  job_busy : String
  /// 上一次作业动作的结果（正文；失败也走这里 —— 这一页没有别的地方能说）
  job_notice : String
  job_notice_ok : Bool
  /// 正文之外的细节（确切命令 / 包目录 / 体积 / 输出尾部）—— 只进悬停
  job_notice_hint : String
  /// 上面那段悬停属于哪一句正文。与当前 job_notice 不一致时不出现
  job_notice_hint_for : String
  /// 被使用者亲手收起的作业 id。**默认全部展开** —— 收起是一个显式动作，
  /// 记下收起的那几条就够了；不必再维护一份「展开着哪些」（新作业进来时它会漏掉）。
  job_collapsed : Array[String]
  /// 已经预演过的那条作业 + 预演的是哪一步（install / cleanup）。
  /// 「预演之后才让点确认执行」靠它：没预演过，确认键是灰的。
  job_previewed : String
  job_previewed_step : String
  archived_open : Bool
  /// 用户手动折过归档区没有：折过之后就不再被 ui.archiveOpenByDefault 覆盖
  archived_user_toggled : Bool
  // 关于页「这台的 dsh 版本」（指定用哪一版起实例）
  //
  // 这三格与 act_notice 分开：总览页那条提示条读的是 act_notice，
  // 在这里借它的话，改完版本切回总览会看到一条与那一页无关的话。
  /// 正在指定的那一份包目录（空串 = 没有在指定，按钮因此可点）
  dsh_pin_busy : String
  /// 上一次指定 / 撤指定之后那句话（失败也走这里 —— 那一页没有别的地方能说）
  dsh_pin_notice : String
  dsh_pin_notice_ok : Bool
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
  // 拖动排序（第十轮）：全程走指针事件。按下 / 移动 / 松开 / 取消四拍分开，
  // 「这一拍算点击还是算拖动」由 update 里的阈值判，视图只负责把事件送进来。
  /// 指针在某一行上按下（行 id / 视口坐标）
  DragDown(String, Double, Double)
  /// 指针移动（视口坐标 + 按键位掩码）。
  ///
  /// 位掩码不是装饰：松手若发生在**页面之外**（指针抬到窗口外面），那一下收不到，
  /// 拖动状态就会一直挂着（那一拍再划过列表，落位线还会跟着走）。
  /// 位掩码为 0 = 没有任何键按着 —— 那就是「其实早就松手了」，当场作废。
  DragMove(Double, Double, Int)
  /// 指针松开：占位块在哪一格就落到哪一格，立刻写回
  DragUp
  /// 指针被取消（触控被打断等）：这一次拖动作废，顺序一个字节都不动
  DragCancel
  /// 键盘换位第一拍：行 id + 方向（-1 往上 / +1 往下）。键盘用户没有鼠标，这条是他们的入口。
  /// 它**只摆占位块**，不动顺序 —— 让人先看见要落到哪儿，第二拍才落
  ReorderKey(String, Int)
  /// 键盘换位第二拍：预览摆够了，真的换。带方向，好与预览那一拍对上号
  ReorderCommit(Int)
  /// set-row-order 的回执：成功了保持新顺序，失败了回滚并如实报错
  OrderDone(Result[String, Error])
  /// 关抽屉：点外部 / Esc / 关闭按钮都走这一条。焦点回触发它的那张卡。
  DrawerClose
  /// 抽屉滑出那一段走完了，节点可以撤了（带的是正在收的那一行的 id：
  /// 号对不上说明这中间抽屉又开了，那一枪作废）。
  DrawerClosed(String)
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
  // 配置 home（design/deep-home-isolation.md）：隔离 / 取消隔离。
  // 隔离本身只建不改，点了就发（走 RowAction 里的 IsolateHome）；
  // 取消隔离是破坏性动作，先开确认框 —— 这三条是那个框的三拍。
  HomeDeisolateOpen(String, String)
  HomeDeisolateConfirm
  HomeDeisolateCancel
  // 回收站（第六轮）：恢复某一条 / 点「彻底删除」先开确认框 / 框里的确定与取消
  TrashRestore(String)
  TrashPurgeOpen(String, String)
  TrashPurgeConfirm
  TrashPurgeCancel
  // 维护页（作业台）：开始表单 / 展开步骤表 / 某条作业的一步 / 回执
  /// 打开版本侧栏：清空搜索框，焦点进搜索框，顺手再读一次后端缓存
  VersionSidebarOpen
  VersionSidebarClose
  /// 侧栏搜索框里的文本（输入即过滤）
  VersionQueryInput(String)
  /// 点一枚过滤 chip：带上那一枚的键（installed / stable / prerelease / all）
  VersionFilterToggle(String)
  /// 换排序档：new / old / published
  VersionSortPicked(String)
  /// 从侧栏里选中一版（写进 job_version）并关掉侧栏
  JobVersionPicked(String)
  /// 打开 / 关闭试跑用配置的右侧侧栏
  ProfileSidebarOpen
  ProfileSidebarClose
  /// 版本来源读数的回执（三个源的结果在里面，包括全都没答上来的那种）
  ReleasesText(Result[String, Error])
  /// 「还在拉」时补问一次的定时器到点了（上限见 state.mbt 的 releases_poll_cap）
  ReleasesTick
  /// 版本侧栏底部「重新拉取」：排一趟后台刷新，结果照旧靠轮询接上
  ReleasesRefresh
  /// 上面那一枪的回执（POST refresh-releases；成没排上都在这里判）
  ReleasesRefreshDone(Result[String, Error])
  JobProfilePicked(String)
  JobStart
  /// 作业 id + 这一步的动作（install-preview / install-confirm / test /
  /// commit / cleanup-preview / cleanup / abort）。后端动作名在 app.mbt 里映射。
  JobAction(String, String)
  /// 展开 / 收起一条作业的步骤表
  JobToggle(String)
  /// 作业动作的回执：动作名 + 原始响应（成败与文案在 update 里判）
  JobDone(String, Result[String, Error])
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
  // 关于页「这台的 dsh 版本」：把某一份指定成起实例用的那一版 / 撤掉指定回到自动。
  // 带的是包目录与版本号 —— 回执要说清「以后起实例用的是哪一版」，不能只说「成功了」。
  DshVersionPin(String, String)
  DshVersionUnpin
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
    tag_runtime: pending_tag("控制台自身的读数还没回来"),
    tag_instances: pending_tag("实例读数还没回来"),
    tag_profiles: pending_tag("profile 读数还没回来"),
    tag_archived: pending_tag("归档与回收站读数还没回来"),
    tag_settings: pending_tag("设置读数还没回来"),
    read_runtime: false,
    read_profiles: false,
    read_instances: false,
    built: false,
    rows: [],
    drawer_id: "",
    drawer_closing: "",
    order: [],
    drag_id: "",
    drag_start_x: 0.0,
    drag_start_y: 0.0,
    drag_active: false,
    drag_group: "",
    drag_from: -1,
    drag_at: "",
    drag_at_index: -1,
    drag_ghost_x: 0.0,
    drag_ghost_y: 0.0,
    drag_ghost: false,
    drag_ghost_w: 0.0,
    drag_ghost_h: 0.0,
    drag_key_dir: 0,
    drag_suppress_click: false,
    order_before: [],
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
    home_confirm_id: "",
    home_confirm_return: "",
    trash_purge_dir: "",
    trash_purge_return: "",
    job_version: "",
    version_sidebar: false,
    version_query: "",
    version_filters: [],
    version_sort: "new",
    releases: None,
    releases_error: "",
    releases_loading: false,
    releases_refresh_error: "",
    releases_ticks: 0,
    releases_poll_pending: false,
    profile_sidebar: false,
    job_profile: "",
    job_busy: "",
    job_notice: "",
    job_notice_ok: false,
    job_notice_hint: "",
    job_notice_hint_for: "",
    job_collapsed: [],
    job_previewed: "",
    job_previewed_step: "",
    // 归档区默认折叠：这一组目前固定是演示数据，短时间用不上；
    // 折叠起来不占视线，功能本身留着（展开即可用），比删掉合适。
    archived_open: false,
    archived_user_toggled: false,
    dsh_pin_busy: "",
    dsh_pin_notice: "",
    dsh_pin_notice_ok: false,
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
    load_runtime(emit),
    load_console(emit),
    load_readings(emit),
  ])
}

///|
/// 只重读 /api/local/runtime。
///
/// 单独一条是为了「改完生效版本」那一处（见 app.mbt 的 dsh_pin_settled）：
/// 版本变了只需要重读这一份读数，不该顺带把列表用的那三份读数重拼一遍 ——
/// 重拼会让总览页白白闪一次，而实例一只都没变。
fn load_runtime(emit : @cmd.Emit[Msg]) -> @cmd.Cmd {
  @http.get("/api/local/runtime").expect_text(emit.map(fn(res) { RuntimeText(res) }))
}

///|
/// 「还在拉」时补问的间隔与上限（design/ops-maintenance-jobs.md §10.1）。
///
/// 后端那条 GET 只回进程内缓存、秒回，所以第一趟可能还没落地：读到 loading 就隔一拍
/// 再问一次。上限 10 拍约 8 秒，长过三个源各自 6 秒的硬超时，也够网络慢的那一档回来；
/// 再读不到就停手，把「正在拉版本列表」留在页面上，等下一次打开侧栏或进这一页再问。
let releases_poll_ms : Int = 800

///|
let releases_poll_cap : Int = 10

///|
/// 读数里还写着「有一趟在路上」没有。没有读数（接口都没读到）不算在拉 —— 那一档
/// 走 releases_error，页面上有自己的说法，不该被轮询盖住。
fn releases_still_loading(model : Model) -> Bool {
  match model.releases {
    Some(facts) => facts.state == "loading"
    None => false
  }
}

///|
/// GET /api/local/dsh-releases：能装哪一版 dsh。
///
/// 后端起来时就在后台拉一次，这条接口只读进程内缓存、秒回；缓存空时也立刻回
/// state=loading（同时确保后台在拉）。所以这一条请求不会拖住首屏或侧栏 ——
/// 「还在拉」由上面的补问接上（见 app.mbt 的 ReleasesText / ReleasesTick）。
/// 三个源全没答上来也算读到了（回执里 sources 全是 ok=false，state=failed 带原因）。
fn load_releases(emit : @cmd.Emit[Msg]) -> @cmd.Cmd {
  @http.get("/api/local/dsh-releases").expect_text(emit.map(fn(res) { ReleasesText(res) }))
}

///|
/// 版本表过滤 chip 的键（§12.3）：installed / stable / prerelease。
/// 「全部」不在这里 —— 它是**清空选择**，不是一个与另外三个并列的过滤条件
/// （并列的话「全部 + 已安装」会互相打架）。
fn version_filter_known(key : String) -> Bool {
  key == "installed" || key == "stable" || key == "prerelease"
}

///|
/// 排序三档（§12.3）：new 从新到旧 / old 从旧到新 / published 按发布时间。
fn version_sort_known(key : String) -> Bool {
  key == "new" || key == "old" || key == "published"
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
/// 版本侧栏的搜索框：「选择版本」打开后焦点落在这儿（§12.1，与配置侧栏同一套焦点规则）。
fn version_search_id() -> String {
  "dsh-job-version-search"
}

///|
/// 版本侧栏的关闭键：搜索框落不到（不该发生）时的兜底落点，与配置侧栏同一套。
fn version_sidebar_close_id() -> String {
  "dsh-job-version-sidebar-close"
}

///|
/// 表单里「选择版本」那颗按钮的 id：侧栏关掉之后焦点回它身上。
fn version_choose_id() -> String {
  "dsh-job-version-choose"
}

///|
/// 表单里「选择配置」那颗按钮的 id：侧栏关掉之后焦点回它身上。
fn profile_choose_id() -> String {
  "dsh-job-profile-choose"
}

///|
/// 配置侧栏的关闭键 id：一只可用的 profile 都没有时，焦点落在这儿（总得有处可去）。
fn profile_sidebar_close_id() -> String {
  "dsh-job-profile-close"
}

///|
/// 配置侧栏里一颗卡的 DOM id：打开时焦点落在第一张可点的卡上。
/// 按 profile 名算（与语义路径同一口径），列表顺序变了也指得回同一只。
fn job_profile_card_id(name : String) -> String {
  "dsh-job-profile-card-" + dom_key(name)
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
/// 显示用换词：读数那句「这个值是从哪读出来的」里，**「字段」这类词要拿掉**。
///
/// 「字段」是数据形状的说法 —— 给改这个工具的人看的。使用者要的是「从哪读到的」，
/// 所以这里把「 字段」整段删掉（连前面那个空格一起，剩下的话照样通顺）：
/// 「入口包 package.json 的 version 字段：/path」→「入口包 package.json 的 version：/path」。
/// **路径、PID、文件名一个都不动**：那是这句话里真正有用的部分。
fn plain_source(text : String) -> String {
  let chars : Array[Char] = []
  for c in text {
    chars.push(c)
  }
  let out = StringBuilder()
  let mut i = 0
  while i < chars.length() {
    if i + 2 < chars.length() &&
      chars[i] == ' ' &&
      chars[i + 1] == '字' &&
      chars[i + 2] == '段' {
      i = i + 3
      continue
    }
    if i + 1 < chars.length() && chars[i] == '字' && chars[i + 1] == '段' {
      i = i + 2
      continue
    }
    out.write_char(chars[i])
    i = i + 1
  }
  out.to_string()
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
// 卡片上只剩三样：图标与它右上角那颗实心圆、profile 名（左上，右上另有一格端口）、
// 下面一行备注。所以「这只实例怎么样」
// 全部压进那颗圆里，**颜色不能是唯一信息** —— 每一档都带一句为什么，在抽屉里展示。
//
// 每一档给两句话，读者不是同一个人：
//   * light_reason —— 抽屉正文那一行，说人话（「它正在 :3080 上应答」）；
//   * light_basis  —— 悬停里的技术依据（哪一条握手应答命中、探测回来的是什么）。
// 正文一个字都不摆内部术语：成因编号、应答标识、组件名这些是给改这个工具的人看的。
//
// 三色的判据来自契约（第七轮第一节），前端不改口径：
//   绿 = 握手探测通过；黄 = 故障（端口在听但不应答 / profile 缺包）；红 = 没有在跑。
// 状态由读数给。**读数没给的时候前端不猜**：
// 实例卡走 unknown（空心灰环 + 一句「读不到状态，颜色不猜」）；
// 已停止的 profile 卡不一样 —— 它本来就不是实例读数，它的黄/红判据（缺包、有没有 patch）
// 全都在 profiles 读数里现成摆着，那是照判据算出来的事实，不是猜。

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
///
/// **只写状态，不写颜色**：颜色由那颗圆自己给（颜色不能是唯一信息，但颜色也不必
/// 在文字里再说一遍）。以前写成「绿 · 运行中」，读起来像在念色卡的编号。
fn light_label(light : Light) -> String {
  match light {
    LightRun => "运行中"
    LightFault => "故障"
    LightStart => "正在启动"
    LightStop => "已停止"
    LightUnknown => "状态未知"
  }
}

///|
/// 一条握手应答的人话说明：把读数给的那句 describe 里**括号那半句**去掉。
///
/// 括号里写的是「这条应答是谁发的」（组件内部名），那是给改这个工具的人看的；
/// 前半句是真的探测到了什么，使用者看得懂，也正好回答了「哪一条应答命中」。
fn signature_plain(fact : InstanceFact) -> String {
  let buf = StringBuilder()
  let mut stop = false
  for c in fact.signature_describe {
    if stop {
      continue
    }
    if c == '（' || c == '(' {
      stop = true
      continue
    }
    buf.write_char(c)
  }
  buf.to_string()
}
///|
/// profile 那一侧的毛病（空串 = 没毛病，或者手上没有健康读数）。
///
/// 缺包优先说：一只缺包的 profile 比「补丁文件不在」更值得先看。
fn profile_trouble(health : InstanceHealth?) -> String {
  match health {
    None => ""
    Some(h) =>
      if h.missing_bundles > 0 {
        "这只 profile 缺 " + h.missing_bundles.to_string() + " 个包"
      } else if !h.has_patch {
        "这只 profile 的 cordis.patch.yml 不在"
      } else {
        ""
      }
  }
}
///|
/// 实例的健康读数：先用实例自己带的那一份，没带就用同一只 profile 的读数顶上
/// （同一个目录，说的是同一件事）。两处都没有才是 None —— 不拿「0 个缺包」顶上：
/// 「读了、一个都不缺」与「没读到」不是一件事。
fn instance_health_facts(fact : InstanceFact, profile_fact : ProfileFact?) -> InstanceHealth? {
  match fact.profile_health {
    Some(health) => Some(health)
    None =>
      match profile_fact {
        Some(item) =>
          Some({
            missing_bundles: item.bundles.missing.length(),
            has_patch: item.patch_exists,
          })
        None => None
      }
  }
}
///|
/// 实例卡的状态灯：档位**只看读数里的状态**，前端不自己改口径。
///
/// 读数没给状态就走 unknown —— 调用方据此说清「读不到」，不拿握手探测的结果去替它定色。
/// 返回三样：档位、抽屉正文那一句（人话）、悬停里的技术依据（这个结论是怎么来的）。
fn instance_light(fact : InstanceFact, profile_fact : ProfileFact?) -> (Light, String, String) {
  let port = fact.port.to_string()
  let health = instance_health_facts(fact, profile_fact)
  let trouble = profile_trouble(health)
  let signature = signature_plain(fact)
  match fact.state {
    Some("running") =>
      (
        LightRun,
        "它正在 :" + port + " 上应答",
        "判据：探测这个端口时命中了 dsh 的握手应答" +
        (if signature == "" { "" } else { "（" + signature + "）" }) +
        "。" +
        (if trouble == "" {
          ""
        } else {
          "profile 那一侧还有一条：" + trouble + "。绿灯由应答给，缺包不改颜色。"
        }),
      )
    Some("fault") => {
      // 黄的两个成因分开算：握手不应答（端口在听、进程像 dsh、应答对不上），
      // 与 profile 那一侧有毛病（缺包 / 补丁文件不在）。两句长得不一样，
      // 不会被一起读成一句含糊的「有点问题」。
      let handshake_failed = fact.signature_id == ""
      let parts : Array[String] = []
      if handshake_failed {
        parts.push("端口在听，但不应答 dsh 的握手")
      }
      if trouble != "" {
        parts.push(trouble)
      }
      let reason = if parts.length() == 0 {
        "读数把这一档判成故障，但这一版界面读不出具体是哪一条"
      } else {
        join_with(parts, "；")
}
      let basis = if handshake_failed {
        "判据：这个端口在监听，但探测时没有命中 dsh 的应答" +
        (if fact.http_status > 0 {
          "（回的是 HTTP " + fact.http_status.to_string() + "）"
        } else {
          ""
        }) +
        "。"
      } else {
        "判据：握手应答是通的，这一档是 profile 那一侧给的。"
}
      (LightFault, reason, basis)
    }
    Some("starting") =>
      (
        LightStart,
        "正在起来，端口还没开始应答",
        "启动动作还没收尾：实例应答之后这一档会变成「运行中」。",
      )
    Some("stopped") => (LightStop, "没有在跑", "这个端口上现在没有实例在跑。")
    Some(_) =>
      (
        LightUnknown,
        "读到的状态这一版界面认不出，颜色不猜",
        "读数里的状态取值这一版界面没有对应的档位，所以不上颜色。",
      )
    None =>
      (
        LightUnknown,
        "读不到状态，颜色不猜",
        "这一版读数里没有状态这一项，所以不上颜色。" +
        (if signature == "" {
          "已有的探测结论：这个端口没有命中 dsh 的应答。"
        } else {
          "已有的探测结论：这个端口命中了 dsh 的应答（" + signature + "）。"
        }),
      )
  }
}

///|
/// 已停止的 profile 卡：状态灯由 profiles 读数自己算（黄的两条判据、红的那条都在里面）。
///
/// 这不是「猜颜色」：没有在跑是这一组的分组条件（in_use_by 已经排掉了正在被用的那几只），
/// 缺包与补丁文件在不在都是读数里现成给的，一个字都没有编。
fn profile_light(fact : ProfileFact) -> (Light, String, String) {
  let missing = fact.bundles.missing
  if missing.length() > 0 {
    (
      LightFault,
      "没有在跑；这只 profile 缺 " + missing.length().to_string() + " 个包",
      "判据：这只 profile 声明的包里有这些没装上：" + join_with(missing, "、") + "。",
    )
  } else if !fact.patch_exists {
    (
      LightFault,
      "没有在跑；这只 profile 的 cordis.patch.yml 不在",
      "判据：cordis.patch.yml 不在，这只 profile 起不来。",
    )
  } else {
    (
      LightStop,
      "没有在跑",
      "这只 profile 的包都装上了、cordis.patch.yml 也在；只是现在没有实例在用它。",
    )
  }
}

///|
/// 抽屉「profile 健康」那一块的正文：只说人话 —— 缺几个包（拿得到名字就带上名字）、
/// 补丁文件在不在。
///
/// 包名清单从 profiles 读数里拿（实例那一侧只给个数）：**名字的个数与手上这个数对得上才用**，
/// 对不上就只说个数 —— 宁可少一句，也不拿另一份读数里的名字去配这一份的个数。
fn instance_health(fact : InstanceFact, profile_fact : ProfileFact?) -> HealthNote {
  match fact.profile_health {
    Some(health) =>
      health_note_of(health.has_patch, health.missing_bundles, matching_names(
        profile_fact,
        health.missing_bundles,
      ))
    None =>
      match profile_fact {
        Some(item) =>
          health_note_of(
            item.patch_exists,
            item.bundles.missing.length(),
            join_with(item.bundles.missing, "、"),
          )
        None => no_reading_note()
      }
  }
}

///|
/// profiles 读数里的包名清单，仅当它的个数与手上这个数目一致时才用（见 instance_health）。
fn matching_names(profile_fact : ProfileFact?, count : Int) -> String {
  match profile_fact {
    Some(item) =>
      if item.bundles.missing.length() == count {
        join_with(item.bundles.missing, "、")
      } else {
        ""
      }
    None => ""
  }
}

///|
/// 抽屉「profile 健康」那一块要的三个值：正文 / 悬停全文 / 是不是自由文本。
///
/// 分类的判据是**我们预先知不知道它长什么样**，不是内容长短：
///   已知且可枚举（缺 N 个包 / cordis.patch.yml 在不在）→ 正文一行摘要，清单进悬停；
///   自由文本（后端报回来的错误串）→ 正文最多两行，原文进悬停。
/// 两类的正文都不许自己长高 —— 形状在 view 那边（.dsh-problem）定死。
priv struct HealthNote {
  text : String
  hint : String
  free : Bool
}

///|
/// 已知且可枚举的那一类：正文一句摘要，**完整内容进悬停**。
///
/// 缺包优先报（一只缺包的 profile 比「补丁文件不在」更值得先看），都不缺才说「都对」。
/// names 为空串 = 手上没有包名清单，这时正文只说个数，悬停也就没什么可补的
/// （为什么没有名字是这一版怎么实现的，不写在给使用者看的那句话里）。
fn health_note_of(has_patch : Bool, missing_count : Int, names : String) -> HealthNote {
  if missing_count > 0 {
    let count = "缺 " + missing_count.to_string() + " 个包"
    {
      text: count,
      hint: count + (if names == "" { "" } else { "：" + names }),
      free: false,
    }
  } else if !has_patch {
    settled_note("没有 cordis.patch.yml")
  } else {
    settled_note("声明的包都已安装，cordis.patch.yml 也在")
  }
}

///|
/// 一句话说完、没什么可补的已知项（悬停就不挂了：与正文逐字相同的一句不留）。
fn settled_note(text : String) -> HealthNote {
  { text, hint: "", free: false }
}

///|
/// 手里没有这只 profile 的健康读数：正文一个「—」，**不编一个「都对」顶上**。
fn no_reading_note() -> HealthNote {
  settled_note("—")
}

///|
/// 这一行属于哪一组。判据与总览页分两组那一处是同一把尺子（status 是 Running 的进
/// 「运行中」，其余含启动等待中进「已停止」）—— 两处各写一遍迟早会分叉，
/// 分组一旦分叉，拖动就会把一条行挪进它不在的那一组里。
fn group_of(row : Row) -> String {
  match row.status {
    Running => "running"
    _ => "stopped"
  }
}

///|
/// 已停止那一组的行 id：名字 + home（与后端 store/order.mbt 的 profile_row_id 一字不差）。
///
/// 顺序表是**按键逐字比对**的，两端拼法必须完全一致；home 是文件系统路径（绝对路径），
/// 直接拼进去，不加任何编码 —— 后端那边同样按原文拼、同样按原文校验。
/// home 为空串时给老形状（profile:<名字>）：那是「这一行没有 home 可比」的如实写法。
fn profile_row_id(name : String, home : String) -> String {
  if home == "" {
    "profile:" + name
  } else {
    "profile:" + name + "@" + home
  }
}

///|
/// 归档孤行的行 id：归档记录的名字 + 它属于哪个 home。
///
/// 与 profile 行的 id 分开一套前缀（archived:）：它是另一类行（磁盘上没有目录），
/// 不参与排序，也不该跟同名的那只已停止行撞 id。
fn archived_row_id(name : String, home : String) -> String {
  if home == "" {
    "archived:" + name
  } else {
    "archived:" + name + "@" + home
  }
}

///|
/// 一行「档案在哪」的 home：归档孤行用记录自带的那个，其余行用它自己那一格的值。
///
/// 空串 = 没有可比的值（读数为空 / 后端没给）：调用方据此退回「只按名字认」。
/// 卡片那一格显示的 home 文本是不是一个真路径。
///
/// 「—」与「未知」都是**显示文本**（不适用 / 读不到），不是路径：
/// 拿它们去拼 <home>/profiles/<名>、或者塞进 params.home，就是编一个不存在的目录出来 ✗
/// 凡是要把那一格当路径用（拼目录 / 发参数 / 比 home）都从这一个判断过。
fn home_is_path(text : String) -> Bool {
  text != "" && text != "—" && text != "未知"
}

///|
/// 两个 home 说的是不是同一个 home。
///
/// 只做「逐字相等，或只差一个尾部斜杠」：/a/b 与 /a/b/ 是同一个目录，
/// 多一个斜杠就判成两处，会把同一份档案拆成两份（卡上多一条、组里少一条）。
/// **不解析软链接**（浏览器里做不到，硬猜等于编）；空串（未知 / 没有）一律不算相等 ——
/// 不知道就不认，这正是本文件对 home 的一贯口径。
fn same_home(a : String, b : String) -> Bool {
  if a == "" || b == "" {
    return false
  }
  a == b || a + "/" == b || b + "/" == a
}

///|
/// 一行「档案在哪」的 home：归档孤行用记录自带的那个，其余行用它自己那一格的值。
///
/// 空串 = 没有可比的值（读数为空 / 后端没给 / 那一格写的是显示文本）：调用方据此退回
/// 「只按名字认」。**那一格是「—」/「未知」时不能当路径用**，见 home_is_path。
fn archive_home_of(row : Row) -> String {
  if row.archive_home != "" {
    row.archive_home
  } else if !home_is_path(row.home) {
    // 那一格是「值不存在 / 读不到」的显示文本，不是路径：拿它当 home 用就是编
    ""
  } else {
    row.home
  }
}

///|
/// 一条归档记录说的是不是这一行：名字要对上，home 也要对上。
///
/// 两种「只按名字认」的情形（与后端 archive_target_matches 同一口径）：
///   · 记录没带 home —— 本次改动之前的旧记录，那时只有一个 home 口径，说的就是它；
///   · 这一行给不出 home —— 没有可比的东西，硬比只会把该标成已归档的那一行漏掉。
/// 除了这两种，home 必须相等：同名两份档案在两个 home 里时，正是靠它分开。
fn archive_record_matches_row(record : ConsoleArchive, name : String, home : String) -> Bool {
  if record.profile != name {
    return false
  }
  if home == "" || record.home == "" {
    return true
  }
  record.home == home
}

///|
/// 一个行 id 在顺序表里排第几。-1 = 表里没有这一条。
fn order_rank(order : Array[String], id : String) -> Int {
  for i = 0; i < order.length(); i = i + 1 {
    if order[i] == id {
      return i
    }
  }
  -1
}

///|
/// 按顺序表把**一组**行排一遍。
///
/// 规则三条（两组各自排，绝不合并成一张表 —— 组是语义，不是排版）：
///   ① 表里没有的行（新出现的实例 / 新加的 profile）保持它们自己的自动顺序，
///      整体排在已排好的之后。这是一份**稳定的部分序**：没动过的那些不会因为
///      表里多了一条就乱跳。
///   ② 表里有的行按表里的次序排。
///   ③ 表为空 = 没拖过 = 原样返回（自动排序那条路一个字节都不动）。
fn apply_order(rows : Array[Row], order : Array[String]) -> Array[Row] {
  if order.length() == 0 || rows.length() < 2 {
    return rows
  }
  let ranked : Array[Row] = []
  let rest : Array[Row] = []
  for row in rows {
    if order_rank(order, row.id) >= 0 {
      ranked.push(row)
    } else {
      rest.push(row)
    }
  }
  // 表里的 id 互不重复（后端拒重复），所以每一行的名次都是唯一的：这是一份全序，
  // 排序算法稳不稳定都不影响结果。
  ranked.sort_by(fn(a, b) { order_rank(order, a.id) - order_rank(order, b.id) })
  let out : Array[Row] = []
  for row in ranked {
    out.push(row)
  }
  for row in rest {
    out.push(row)
  }
  out
}

///|
/// 按 id 去控制台的「上次启动」表里查一条。查不到给 ("", "")。
fn last_started_lookup(console : ConsoleFacts?, id : String) -> (String, String) {
  match console {
    None => ("", "")
    Some(facts) => {
      for item in facts.last_started {
        if item.id == id {
          return (item.at, item.source)
        }
      }
      ("", "")
    }
  }
}

///|
/// 卡片第二行第三顺位要用的那个时刻：先看这一行自己能不能给出**真实**的启动时刻，
/// 再看控制台的记录。都给不出就是 ("", "")，那一行空着。
///
/// 顺序不能反：正在跑的实例，进程起始时间是最准的那一个；控制台记录里那条
/// 可能是很久以前起的那一次（这一只后来被别人重启过）。反过来会把新时刻说成旧的。
///|
/// 按 profile 查「上次启动」要试的那几个行 id，按该试的先后排。
///
/// 新的形状（带 home）在前，老形状（只有名字）在后：后端那边的记录不一定都带 home
/// （audit.jsonl 里的 start-instance 流水就没有），那一条读数不该因为键换代就查不到。
fn profile_id_candidates(name : String, home : String) -> Array[String] {
  let out : Array[String] = []
  if home != "" {
    out.push(profile_row_id(name, home))
  }
  out.push("profile:" + name)
  out
}

///|
/// 同上，一行卡片的「上次启动」：正在跑的那一只按端口，其余按 profile。
fn row_last_started(
  instance_started : String?,
  port_id : String,
  profile_ids : Array[String],
  console : ConsoleFacts?,
) -> (String, String) {
  match instance_started {
    Some(at) =>
      if at != "" {
        return (at, "这只实例的启动时刻：后端从进程起始时间读出来的")
      }
    None => ()
  }
  let (at, source) = last_started_lookup(console, port_id)
  if at != "" {
    return (at, source)
  }
  for id in profile_ids {
    let (at2, source2) = last_started_lookup(console, id)
    if at2 != "" {
      return (at2, source2)
    }
  }
  ("", "")
}


///|
/// 总览页两组行的**当前显示顺序**（已按顺序表排过）。
///
/// 视图与拖动都从这里取：页面上看到的顺序只有这一个来源。
/// 排在 rebuild 里做不行 —— 顺序表在拖动之后会变，而 rebuild 一趟只跑一次，
/// 页面会停在旧顺序上（拖完看着没动）。这一处是纯读，随取随算。
fn display_groups(model : Model) -> (Array[Row], Array[Row]) {
  let running = model.rows.filter(fn(row) {
    row.archived_at is None && group_of(row) == "running"
  })
  let stopped = model.rows.filter(fn(row) {
    row.archived_at is None && group_of(row) == "stopped"
  })
  (apply_order(running, model.order), apply_order(stopped, model.order))
}

///|
/// 某一组**当前显示着**的行 id（顺序就是屏幕上的顺序）。
fn current_group_ids(model : Model, group : String) -> Array[String] {
  let (running, stopped) = display_groups(model)
  let rows = if group == "running" { running } else { stopped }
  let out : Array[String] = []
  for row in rows {
    out.push(row.id)
  }
  out
}

///|
/// 拖动的落点：从 js_drop_target 那段 JSON 里取出 (指针底下那一格的卡片 id, 组名, 格子序号)。
///
/// `index` 是**这一组按屏幕顺序数**的格子序号（0 起）：指针压在哪张卡上就占哪一格。
/// 取不到（指针横向出了这一组的栅格 / 进到另一组 / JSON 不合形状）给 ("", "", -1)，
/// 调用方据此既不画占位块也不落位。
fn drop_target_of(x : Double, y : Double) -> (String, String, Int) {
  let text = js_drop_target(x, y)
  if text == "" {
    return ("", "", -1)
  }
  let json = try @json.parse(text) catch {
    // 解析不出来就当没有落点：宁可这一次拖动不落位，也不拿一个猜的位置去插
    _ =>
      return ("", "", -1)
  }
  match json {
    Json::Object(fields) =>
      (
        str_field(fields, "row"),
        str_field(fields, "group"),
        // 没有 index（横向出栅格 / 跨组）就当没有落点
        match int_field(fields, "index") {
          Some(v) => v
          None => -1
        },
      )
    _ => ("", "", -1)
  }
}

///|
/// **落点的唯一算法**：js_drop_target 给的格子序号就是结果里的位次，这里只做边界收口。
///
/// 卡槽语义下「指针压在第 i 张卡上」= 被拖的那一条占第 i 格：它从原处抽走之后
/// 插进第 i 格，其余各条按原次序填满剩下的格子。预览与落位都取这一个数，
/// 所以「占位块画在第几格」与「松手落在第几格」不可能分叉。
///
/// 边界：小于 0 落到最前（0）；大于 n-1 落到最后（n-1）。
fn drop_cell(n : Int, index : Int) -> Int {
  if n <= 1 {
    return 0
  }
  if index < 0 {
    return 0
  }
  if index > n - 1 {
    return n - 1
  }
  index
}


///|
/// 把被拖的那一条插进 ids 的第 k 格，返回整组的新顺序。
///
/// k 由 drop_cell 收口，所以这里的 k 就是**格子序号**：结果数组的第 k 个元素
/// 就是被拖的那一条。占位块也摆在同一个 k 上 —— 预览与结果因此逐格一致。
fn insert_row_at(ids : Array[String], dragged : String, k : Int) -> Array[String] {
  let rest : Array[String] = []
  for id in ids {
    if id != dragged {
      rest.push(id)
    }
  }
  let out : Array[String] = []
  let mut placed = false
  for i = 0; i <= rest.length(); i = i + 1 {
    if i == k && !placed {
      out.push(dragged)
      placed = true
    }
    if i < rest.length() {
      out.push(rest[i])
    }
  }
  if !placed {
    out.push(dragged)
  }
  out
}

///|
/// 两份顺序表是不是逐格相同。拖动落在原位（指针在被拖的那张自己身上）时靠它
/// 认出「这一次没有挪动」，从而不发请求。
fn same_order(a : Array[String], b : Array[String]) -> Bool {
  if a.length() != b.length() {
    return false
  }
  for i = 0; i < a.length(); i = i + 1 {
    if a[i] != b[i] {
      return false
    }
  }
  true
}

///|
/// 被拖的那一条现在排在第几格（0 起）；不在组里给 -1。
fn index_of_row(ids : Array[String], id : String) -> Int {
  let mut at = -1
  for i = 0; i < ids.length(); i = i + 1 {
    if ids[i] == id {
      at = i
    }
  }
  at
}

///|
/// 占位块要摆在**谁的前面**：结果顺序里第 k 格那条，就是此刻屏幕上的第 k 格那一条。
///
/// 为什么是它：被拖的那一条在拖动期间还留在原地（画成虚影占着那一格），没有从序列里消失。
/// 所以「其余条各自占哪一格」与结果顺序里「它们各自占哪一格」是同一件事 ——
/// 结果顺序的第 k 格那条，此刻正站在第 k 格。占位块插在它前面，就正好落在第 k 格。
/// 同理插在最后一条前面 = 落在它那一格，也就是最后一格。
///
/// k 越界（理论上不会）给空串：视图拿到空串就不插占位块，宁可不画也不画错一格。
fn anchor_at(ids : Array[String], k : Int) -> String {
  if k < 0 || k >= ids.length() {
    return ""
  }
  ids[k]
}

///|
/// 被拖的那一条按下的那一刻有多大（宽, 高）—— 虚影照这个尺寸画，整个拖动过程不变。
///
/// 为什么要照抄而不是给虚影一个固定尺寸：虚影说的是「这一条被拿在手上」，
/// 尺寸与它自己不一样的话，看着像换了一条东西在拖。
/// 中途不再重量：列表正在让位，再量一次可能量到挪开后的格子，虚影会跟着跳。
fn lift_sizes_of(id : String) -> (Double, Double) {
  let text = js_card_box(card_id(id))
  if text == "" {
    return (0.0, 0.0)
  }
  let json = try @json.parse(text) catch {
    _ => return (0.0, 0.0)
  }
  match json {
    Json::Object(fields) =>
      (
        match num_field(fields, "w") {
          Some(v) => v
          None => 0.0
        },
        match num_field(fields, "h") {
          Some(v) => v
          None => 0.0
        },
      )
    _ => (0.0, 0.0)
  }
}

///|
/// 位移过没过阈值。**用平方比，不开方**：这一步每次指针移动都要算一遍，
/// 而开方在这里没有任何意义（阈值只是个手感数）。
fn drag_past_threshold(x0 : Double, y0 : Double, x1 : Double, y1 : Double) -> Bool {
  let dx = x1 - x0
  let dy = y1 - y0
  dx * dx + dy * dy > drag_threshold_px * drag_threshold_px
}

///|
/// 把被拖的那一条挪到第 k 格（占位块现在所在的那一格），返回这一组的新顺序。
///
/// k < 0 = 没有落点，作废。**k 与占位块用的是同一个数**（见 drag_drop_index），
/// 所以「看到的」与「落到的」是同一件事，不可能差一格。
fn moved_group_ids(model : Model, dragged : String, k : Int) -> Array[String]? {
  let group = group_of_row_id(model, dragged)
  if group == "" || k < 0 {
    return None
  }
  let ids = current_group_ids(model, group)
  if index_of_row(ids, dragged) < 0 {
    return None
  }
  Some(insert_row_at(ids, dragged, k))
}

///|
/// 这一条属于哪一组；行不在列表里给空串。
fn group_of_row_id(model : Model, id : String) -> String {
  match find_row(model.rows, id) {
    Some(row) =>
      if row.archived_at is None {
        group_of(row)
      } else {
        // 归档行不在两组里，拖动不该碰它
        ""
      }
    None => ""
  }
}

///|
/// 把「某一组的新顺序」拼成**整份**顺序表提交。
///
/// 为什么整份提交：后端的 set-row-order 收的就是整份 —— 增量式接口要后端先读一份
/// 当前顺序再算，两次并发拖动会互相覆盖。组内顺序换了的那一组用新的，
/// 另一组保持它现在显示的顺序（不因为动了一组就把另一组也重写一遍）。
fn compose_order(model : Model, group : String, moved : Array[String]) -> Array[String] {
  let out : Array[String] = []
  if group == "running" {
    for id in moved {
      out.push(id)
    }
    for id in current_group_ids(model, "stopped") {
      out.push(id)
    }
  } else {
    for id in current_group_ids(model, "running") {
      out.push(id)
    }
    for id in moved {
      out.push(id)
    }
  }
  out
}

///|
/// 提交一份新顺序：**先就地生效，再写回**；写回失败由 OrderDone 回滚。
///
/// 为什么要乐观更新：拖完松手那一刻列表必须已经在新位置上 —— 等一趟 HTTP
/// 再动，手上会有一段「拖了没反应」的空档。代价是失败时要自己擦干净，
/// 那一步在 OrderDone 里，且必须擦（见那里的注释）。
fn commit_order(
  model : Model,
  dragged : String,
  moved : Array[String],
  emit : @cmd.Emit[Msg],
) -> (Model, @cmd.Cmd) {
  let group = group_of_row_id(model, dragged)
  let full = compose_order(model, group, moved)
  let next = { ..model, order_before: model.order, order: full }
  // 焦点跟着**被挪的那一条**走：列表是按位置打补丁的，不补这一下，
  // 键盘用户按完 Ctrl+↓ 焦点还停在原来那一格上，而那一格现在是别的条目了。
  (
    next,
    @cmd.batch([
      order_action_cmd(full, emit),
      focus_after_render(card_id(dragged)),
      // 落位这一拍也让位：被拖的那一条回到占位块那一格、其余各挪一格，
      // 都是位置变化，一起交给 FLIP 演（撤格子排在 FLIP 之后：
      // 先按摆好的格子把这段变化演出来，撤掉之后就是文档流里的终局）。
      @cmd.batch([reorder_after_render(), clear_cells_after_render()]),
    ]),
  )
}

///|
/// 正在运行的实例 = 监听端口 + HTTP 签名探测到的真实实例（不是 /proc 进程，也不是磁盘上的 profile）。
/// 实例的 Profile / DSH_HOME / DSH 版本 / 运行时长来自「端口 → socket inode → PID」这条 join；
/// 任一项拿不到就写「未知」，并把后端给的原因挂在悬停说明上 —— 不编值，也不留一个干巴巴的未知。
fn running_rows(
  facts : Array[InstanceFact],
  profiles : Array[ProfileFact],
  console : ConsoleFacts?,
  profiles_home : String,
) -> Array[Row] {
  facts.map(fn(fact) {
    // 这一只实例自己的 home（运行时读出来的）。它同时是「按 profile 查上次启动」时要用的那一段：
    // 后端那张表里的键是 (名字, home)，少一段就对不上 —— 查不到就直接空着，不拿别的凑
    let instance_home = match fact.dsh_home {
      Some(h) => h
      None => ""
    }
    // 挑这只实例对应的 profile 读数：**名字与 home 都要对上**。
    //
    // 只按名字配是错的（多 home 之后）：另一 home 的同名 profile 的缺包数 / 插件数 /
    // 备注 / 最近改动会挂到这只实例的卡上 —— 那就是拿别处的读数当这一只的读数 ✗
    // 实例自己的 home 认不出（dsh_home = None）时一只都不配：读不到就说读不到，
    // 不拿控制台这一份顶上（口径与后端 a 那一条一致）。
    let home_matches = same_home(instance_home, profiles_home)
    let profile_fact = match fact.profile {
      Some(name) => {
        let mut found : ProfileFact? = None
        for item in profiles {
          // 名字与 home 都要对上，但「这个 home」有两档合法答案：
          //   ① 控制台的 home（共用这一档，实例跑在 DSH_HOME 里）
          //   ② 这只 profile 自己的 home（隔离这一档，实例的 DSH_HOME 就是那条隔离路径）
          // 只认 ① 的话，隔离起来的那只实例反而配不上自己的 profile 读数 ——
          // 备注 / 缺包 / 配置 home 全变成「读不到」，而答案明明就在读数里。
          let matches_home = home_matches ||
            (item.home_path != "" && same_home(instance_home, item.home_path))
          if item.name == name && matches_home {
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
    let (light, light_reason, light_basis) = instance_light(fact, profile_fact)
    let health = instance_health(fact, profile_fact)
    // 第二行第三顺位：这一只真实的启动时刻优先（进程起始时间），取不到才去查控制台的记录
    let (last_started, last_started_source) = row_last_started(
      fact.started_at,
      "port:" + fact.port.to_string(),
      match fact.profile {
        Some(name) => profile_id_candidates(name, instance_home)
        None => []
      },
      console,
    )
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
      version_hint: plain_source(fact.version_source),
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
      archive_home: "",
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
      // 配置 home：试跑的一次性 home 由实例读数自己说（§11.1）——
      // 那份 home 不属于任何一只 profile 的隔离 home，按 profile 读数配只能配成「读不到」。
      // 其余两档照 profile 读数（与已停止那张卡同一个口径）；解析不出就三格空着
      // （界面那一格写「读不到」，不按实例的 dshHome 反推归属）。
      home_kind: if fact.home_kind == "trial" {
        fact.home_kind
      } else {
        match profile_fact {
          Some(item) => item.home_kind
          None => ""
        }
      },
      home_path: if fact.home_kind == "trial" {
        instance_home
      } else {
        match profile_fact {
          Some(item) => item.home_path
          None => ""
        }
      },
      home_kind_source: if fact.home_kind == "trial" {
        fact.home_kind_source
      } else {
        match profile_fact {
          Some(item) => item.home_kind_source
          None => ""
        }
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
      light_basis,
      health_text: health.text,
      health_hint: health.hint,
      health_free: health.free,
      // 同一个进程的其余监听端口：只作附注（抽屉里一行「还听着 9230」），
      // 卡片上不显示、也不因此变色 —— 那一行说的是这只实例，不是那个端口。
      also_ports: fact.also_ports.map(fn(p) { p.port.to_string() }),
      also_ports_hint: join_with(
        fact.also_ports.map(fn(p) { "端口 " + p.port.to_string() + "：" + p.note }),
        " | ",
      ),
      last_started,
      last_started_source,
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
///
/// 判据是 **(名字, home)**：一份档案的身份是两段，同名不同 home 是两份。
/// 只按名字比是错的 —— 多 home 之后，另一 home 的同名实例在跑就会把这一行整条藏掉 ✗
fn in_use_by(fact : ProfileFact, running : Array[InstanceFact], profiles_home : String) -> Bool {
  for inst in running {
    match inst.profile {
      Some(used) =>
        if used == fact.name {
          // home 也要对上：同名不同 home 是两份档案，另一 home 的那只在跑，
          // 不等于这一只被用着。对不上就**不认**（含两边任一认不出 home 的情形）——
          // 认了就等于把这一行从列表里藏掉，而它其实规规矩矩地躺在磁盘上
          let inst_home = match inst.dsh_home {
            Some(h) => h
            None => ""
          }
          if same_home(inst_home, profiles_home) {
            return true
          }
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
  (if source == "" { "读数里没写原因" } else { source })
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
  profiles_home : String,
  running : Array[InstanceFact],
  console : ConsoleFacts?,
) -> Array[Row] {
  let rows : Array[Row] = []
  for fact in profiles {
    if in_use_by(fact, running, profiles_home) {
      continue
    }
    let missing = fact.bundles.missing
    // 停止卡的状态灯：没有在跑 + 缺包/缺 patch 这两条判据都在 profiles 读数里（不是猜的）
    let (light, light_reason, light_basis) = profile_light(fact)
    let health = health_note_of(fact.patch_exists, missing.length(), join_with(missing, "、"))
    // 第二行第三顺位：这一只现在没有实例可问，只能按 profile 名去控制台的记录里查
    // 「上次启动」。查不到就是空串 —— 那一行空着，不拿最近改动之类的时刻顶上
    //（最近改动是另一回事，它在抽屉第六格，口径不同）。
    let (last_started, last_started_source) = row_last_started(
      None,
      "",
      profile_id_candidates(fact.name, profiles_home),
      console,
    )
    rows.push({
      // 行 id 带上 home：同名两份档案在两个 home 里时，它们是两行，各排各的
      id: profile_row_id(fact.name, profiles_home),
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
      version_hint: "控制台读到的 dsh 版本与来源（这只 profile 没有运行中的进程，版本取的是控制台自身的读数）",
      profile: fact.name,
      profile_hint: "磁盘上真实存在的 profile 目录名：" + fact.name,
      // 这一行的 home：**它自己的** —— 这只 profile 就是从 profiles_home 的 profiles/ 下被列出来的。
      // 读数的 home 也给不出时那一格写「未知」：读不到就说读不到，
      // 绝不拿控制台自己的 home 顶替 ✗（那会把这只 profile 说成属于一个它不属于的地方）
      home: if profiles_home == "" { "未知" } else { profiles_home },
      home_hint: if profiles_home == "" {
        "这一版 profiles 读数里没有 dshHome：不知道这批 profile 是从哪个 home 的 profiles/ 下读出来的，" +
        "所以这一格写「未知」。不拿控制台自己的 home 顶上，那只是把别处的 home 说成它的"
      } else {
        "这只 profile 自己的 home：profiles 读数就是在 " + profiles_home +
        "/profiles 下把这只列出来的（读数里的 dshHome / dshHomeSource）。" +
        "它与控制台自己的 home 可以相同、也可以不同。这一格说的是这一只属于哪儿，不是控制台在用什么"
      },
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
      archive_home: "",
      profile_name: Some(fact.name),
      port_value: None,
      console_started: false,
      user_note: fact.note,
      user_note_source: fact.note_source,
      // 配置 home：后端 profiles 读数里每只一项（home.kind / path / homeKindSource）
      home_kind: fact.home_kind,
      home_path: fact.home_path,
      home_kind_source: fact.home_kind_source,
      mtime_ms: fact.dir_mtime_ms,
      mtime_missing: "读不到",
      mtime_hint: match fact.dir_mtime_ms {
        Some(ms) => mtime_value_hint(ms, fact.dir_mtime_source)
        None => mtime_missing_hint(fact.dir_mtime_source)
      },
      light,
      light_reason,
      light_basis,
      last_started,
      last_started_source,
      health_text: health.text,
      health_hint: health.hint,
      health_free: health.free,
      // 没有在跑的实例，也就没有「同一个进程的另一个端口」这回事
      also_ports: [],
      also_ports_hint: "",
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
          if archive_record_matches_row(record, name, archive_home_of(row)) {
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
          if archive_record_matches_row(record, name, archive_home_of(row)) {
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
    // id 带上记录里的 home：同名两份档案在两个 home 里时，两条孤行是两个 id
    //（列表按 id 打补丁，撞 id 会让其中一条静默消失），取消归档也靠它认准是哪一条。
    id: archived_row_id(record.profile, record.home),
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
    // 这一行的 home 来自**归档记录自己**：磁盘上没有目录可读，但记录说了它属于哪个 home。
    // 记录里没写（改动之前写下的那条旧记录）就如实写「—」—— 不拿控制台自己的 home 顶上 ✗：
    // 那会把一个它不属于的 home 说成它的，开发指令也会照着那个错的 home 拼。
    home: if record.home == "" { "—" } else { record.home },
    home_hint: if record.home == "" {
      "archive.json 里这条记录没写它属于哪个 home，磁盘上也没有这只 profile 的目录。" +
      "这一格没有可写的值（拿控制台自己的 home 来填，就是给它安一个它不属于的 home）"
    } else {
      "这只 profile 属于哪个 home：读自 archive.json 的这条归档记录（磁盘上已经没有它的目录，没有别处可读）。" +
      "这是这一只自己的 home，不是控制台当前在用的那一个"
    },
    url: "—",
    web_url: None,
    web_url_source: "磁盘上没有这只 profile 的目录，没有实例可读，也没有令牌",
    plugin_count: "—",
    plugin_detail: "",
    deletable: true,
    archived_at: Some(record.archived_at),
    // 记录自带的 home 也放这里：它既是「取消归档撤的是哪一条」的判据（同名两份档案靠它分开），
    // 也是这一行 home 那一格的值（见上面）。
    archive_home: record.home,
    profile_name: Some(record.profile),
    port_value: None,
    console_started: false,
    // 磁盘上没有这只 profile，也就没有备注文件可读：不编
    user_note: "",
    user_note_source: "",
    // 同理：没有 profile 目录，就没有「这只 profile 的 home」这一项读数
    home_kind: "",
    home_path: "",
    home_kind_source: "",
    // 磁盘上连目录都没有，控制台的启动记录里也不会有这只 profile：那一行空着
    last_started: "",
    last_started_source: "",
    // 同理：目录都不在了，没有最近改动可读
    mtime_ms: None,
    mtime_missing: "读不到",
    mtime_hint: "磁盘上没有这只 profile 的目录，没有最近改动可读（这一行来自 archive.json 的归档记录）",
    light: LightStop,
    light_reason: "没有在跑；磁盘上已经没有这只 profile 了",
    light_basis: "这一行来自归档记录：磁盘上没有对应的 profile 目录，所以没有运行读数，也没有健康读数。",
    health_text: "—",
    health_hint: "",
    health_free: false,
    also_ports: [],
    also_ports_hint: "",
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
      deletable: false, archived_at: None, archive_home: "",
      profile_name: None, port_value: None, console_started: false,
      user_note: "", user_note_source: "",
      // 演示数据不是读数：home 归属也没有读数，三格空着（界面写「读不到」）
      home_kind: "", home_path: "", home_kind_source: "",
      // 演示数据不是读数：没有真实的启动记录可查，那一行空着（不编一个时间）
      last_started: "", last_started_source: "",
      mtime_ms: None, mtime_missing: "读不到",
      mtime_hint: "演示数据：不是真实读数，没有目录可读最近改动",
      light: LightUnknown,
      light_reason: "这是读取失败时兜底的演示数据，没有读数，颜色不猜。",
      light_basis: "演示数据：不是真实读数，所以没有可依据的判据。",
      health_text: "—",
      health_hint: "",
      health_free: false,
      also_ports: [],
      also_ports_hint: "",
    },
    {
      id: "plugin-dev", name: "plugin-dev", kind: "插件开发（试验）", kind_hint: "",
      tone: Violet, status: Running, uptime: Some(42), uptime_hint: "",
      port_note: "", idle_note: "", note: "", busy: false,
      version: "0.2.0-rc.2（本地源码）", version_hint: "演示数据，不是读数", profile_hint: "演示数据，不是读数", home_hint: "演示数据，不是读数", profile: "dev", home: "/Users/you/.dsh/plugin-dev",
      url: "http://127.0.0.1:8200", web_url: None,
      web_url_source: "演示数据：端口 8200 上没有真实实例，读不到令牌",
      plugin_count: "2 个（开发中）", plugin_detail: "",
      deletable: true, archived_at: None, archive_home: "",
      profile_name: None, port_value: None, console_started: false,
      user_note: "", user_note_source: "",
      // 演示数据不是读数：home 归属也没有读数，三格空着（界面写「读不到」）
      home_kind: "", home_path: "", home_kind_source: "",
      // 演示数据不是读数：没有真实的启动记录可查，那一行空着（不编一个时间）
      last_started: "", last_started_source: "",
      mtime_ms: None, mtime_missing: "读不到",
      mtime_hint: "演示数据：不是真实读数，没有目录可读最近改动",
      light: LightUnknown,
      light_reason: "这是读取失败时兜底的演示数据，没有读数，颜色不猜。",
      light_basis: "演示数据：不是真实读数，所以没有可依据的判据。",
      health_text: "—",
      health_hint: "",
      health_free: false,
      also_ports: [],
      also_ports_hint: "",
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
      deletable: true, archived_at: None, archive_home: "",
      profile_name: None, port_value: None, console_started: false,
      user_note: "", user_note_source: "",
      // 演示数据不是读数：home 归属也没有读数，三格空着（界面写「读不到」）
      home_kind: "", home_path: "", home_kind_source: "",
      // 演示数据不是读数：没有真实的启动记录可查，那一行空着（不编一个时间）
      last_started: "", last_started_source: "",
      mtime_ms: None, mtime_missing: "读不到",
      mtime_hint: "演示数据：不是真实读数，没有目录可读最近改动",
      light: LightUnknown,
      light_reason: "这是读取失败时兜底的演示数据，没有读数，颜色不猜。",
      light_basis: "演示数据：不是真实读数，所以没有可依据的判据。",
      health_text: "—",
      health_hint: "",
      health_free: false,
      also_ports: [],
      also_ports_hint: "",
    },
  ]
}
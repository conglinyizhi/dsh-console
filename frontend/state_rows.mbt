// 行模型：Row 结构与两张卡的构造函数（running_rows / profile_rows）、行 id 与候选 id、
// 分组与拖动顺序、归档标记、演示数据，以及读数加载那几条（行就是这些读数拼出来的）。
//
// 2026-10-20 从 state.mbt 拆出来：那个文件 3324 行，Model/Msg 与行模型混在一起；
// 拆开之后「一行长什么样、怎么拼出来」只在这一份里找。只搬位置，函数体一个字没改。


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
  /// 「有地址可复制」这个标记：只有**真在跑、地址不是占位串**的行才是 true。
  ///
  /// 为什么要有它：停用行的 url 是「已停用，无法访问」这个占位串，抽屉里那颗
  /// 「复制访问地址」却亮着，点下去把这句占位话写进剪贴板（design/ops-maintenance-jobs.md §13.1）。
  /// 判据放在行上，视图按它置灰、复制动作自己也按它拦一道 —— 两道都从这一个值走。
  url_copyable : Bool
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
  /// 缺几个包（读数的 bundles.missing 条数）。>0 时抽屉「状态」组里多一颗
  /// 「安装缺的包（N）」（design/design-fixes.md §39）。
  missing_count : Int
  /// 补包会在 profile 目录里跑的那条命令（后端 repairCommand，同一处口径）
  repair_command : String
  /// 补包要带的 home：这只 profile 自己的 home（隔离的那只是它的隔离 home）
  repair_home : String
  /// 命令行型：bundles 里没有 `@deepseek-ai/dsh-web-app`（读数 webApp === false）。
  /// 这种 profile 没有网页入口，起不成常驻实例；卡上给它一枚蓝色小标（design/design-fixes.md §41）。
  /// 读不到这一项（None）时算 false：不确定就不贴标签，不替它下结论。
  cli_only : Bool
  /// 这一格是**按实例自己的 home 认定**的（design/design-fixes.md §33.1）：
  /// 运行中那一行在 profiles 读数里配不上自家 profile（它来自别处 home），
  /// 于是按实例进程的 DSH_HOME 算成「共用（<那份 home>）」。false = 照 profile 读数。
  home_from_instance : Bool
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
  // ── 配置快照（design/ops-maintenance-jobs.md §16.2）──
  /// 这只 profile 的快照列表，从新到旧。空数组 = 还没拍过（或读数里没有这一项，
  /// 两种情况由 snapshots_source 分开说 —— 空态文案只给「还没拍过」那一档）。
  snapshots : Array[SnapshotFact]
  /// 快照读数的来源 / 读不到的原因（后端原样给，进悬停）
  snapshots_source : String
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
/// 3.5 秒是规格 14.1 定的数（旧版 4 秒）。
pub let flash_ms : Int = 3500

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
/// 设置页一颗开关的 DOM id（§51）：保存成功之后把焦点送回它 ——
/// 保存会让这一行多出「恢复默认」那颗按钮，节点结构一变焦点就掉到 body，
/// 键盘用户按一次空格就「走丢」了（§51.4 要空格与回车都能切）。
fn setting_switch_id(key : String) -> String {
  "dsh-switch-" + key
}

///|
/// 抽屉里「安装缺的包（N）」那颗按钮的 DOM id（§39）：确认框关掉之后焦点回它。
fn drawer_repair_id() -> String {
  "dsh-drawer-repair"
}

///|
/// 补包确认框里「安装」那颗按钮的 DOM id：打开时焦点落在它上面。
fn repair_dialog_ok_id() -> String {
  "dsh-repair-dialog-ok"
}

///|
/// 顶栏那颗铃铛的 DOM id（§36）：通知侧栏关掉之后焦点回它身上。
fn notice_bell_id() -> String {
  "dsh-notice-bell"
}

///|
/// 通知侧栏里关闭键的 DOM id：打开时焦点落在它上面（与抽屉同一套）。
fn notice_panel_close_id() -> String {
  "dsh-notice-panel-close"
}

///|
/// 抽屉里「重命名 / 备注 / 删除」三颗按钮的 DOM id（§30.1）：抽屉不再因为开对话框而收起，
/// 关框之后焦点要回到按下它的那一颗按钮，而不是回卡片。
fn drawer_rename_id() -> String {
  "dsh-drawer-rename"
}

///|
fn drawer_note_id() -> String {
  "dsh-drawer-note"
}

///|
fn drawer_delete_id() -> String {
  "dsh-drawer-delete"
}

///|
/// 「打开 Web UI」右段 chevron 的 DOM id：菜单收起之后焦点回它身上。
fn split_menu_btn_id(row_id : String) -> String {
  "dsh-split-menu-btn-" + dom_key(row_id)
}

///|
/// 那份菜单里「强制启动」的 DOM id：展开时焦点落进它（键盘用户按 Enter 就能走这条路）。
fn split_menu_item_id(row_id : String) -> String {
  "dsh-split-menu-item-" + dom_key(row_id)
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
/// 整体替换侧栏的关闭键 id：一只可选的源都没有时，焦点落在这儿（总得有处可去）。
fn promote_close_id() -> String {
  "dsh-promote-close"
}

///|
/// 整体替换侧栏里一颗源卡的 DOM id（按 profile 名算，焦点打开时落在第一张）。
fn promote_card_id(name : String) -> String {
  "dsh-promote-card-" + dom_key(name)
}

///|
/// 抽屉里「用另一只配置替换这一只」那颗按钮的 id：关掉侧栏之后焦点回它身上。
fn promote_open_id(row_id : String) -> String {
  "dsh-promote-open-" + dom_key(row_id)
}

///|
/// 确认框里「确认替换」那颗键的 id（打开时焦点落在它上面）。
fn promote_confirm_ok_id() -> String {
  "dsh-promote-confirm-ok"
}

///|
fn archive_trigger_id(id : String) -> String {
  "dsh-archive-trigger-" + dom_key(id)
}

///|
/// 页头那颗「＋新建实例」的 id：对话框关掉之后焦点回它（与重命名 / 备注同一套）。
fn new_instance_btn_id() -> String {
  "dsh-new-instance-btn"
}

///|
/// 新建实例框里一颗源卡的 DOM id（按 profile 名算，打开时焦点落在第一张可点的卡上）。
fn new_instance_card_id(name : String) -> String {
  "dsh-new-instance-card-" + dom_key(name)
}

///|
/// 名字输入框的 id：选中源之后焦点与光标送进来，默认那段 <源>-dev 全选，直接打字就是换名。
fn new_instance_name_id() -> String {
  "dsh-new-instance-name"
}

///|
/// 「创建」那颗键的 id。
fn new_instance_ok_id() -> String {
  "dsh-new-instance-ok"
}

///|
/// 新建实例框左下角那枚「从基础实例开始」复选框的 id（label 的 for 指向它）。
/// 一只可用的 profile 都没有、读数又还没落地时，打开框的焦点落在这儿
/// （那一刻框里只有它还能点）。
fn new_instance_base_id() -> String {
  "dsh-new-instance-base"
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
  ignore_missing : Bool,
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
    let (light, light_reason, light_basis) = instance_light(fact, profile_fact, ignore_missing)
    let health = instance_health(fact, profile_fact, ignore_missing)
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
      // 「有地址可复制」= 真在跑 **且** 这一格不是占位串。两个条件都要看：
      // 判据是地址本身，不是「这一行走到了哪个分支」——实例读数理论上也可能给不出地址，
      // 那时按钮照旧不该亮（§13.1 的口径）。
      url_copyable: fact.url != "" && fact.url != "—" && fact.url != "已停用，无法访问",
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
        None => not_in_console_home_note
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
      // 配置 home（§33.1）：先在 profiles 读数里找这只 profile（控制台 home 或它的隔离 home）。
      // 找不到、而实例自己的 DSH_HOME 读得到时，就**按实例的 home 认定**成「共用（那份 home）」；
      // 一只从别处 home 起来的实例，它的 profile 本来就不在控制台的 DSH_HOME 里，
      // 那时写「读不到」等于把手上明明有的答案说成没有。连实例 home 都认不出才留空。
      // 试跑那一档照旧由实例读数自己说（§11.1）。
      home_kind: if fact.home_kind == "trial" {
        fact.home_kind
      } else {
        match profile_fact {
          Some(item) => item.home_kind
          None => if home_is_path(instance_home) { "shared" } else { "" }
        }
      },
      home_path: if fact.home_kind == "trial" {
        instance_home
      } else {
        match profile_fact {
          Some(item) => item.home_path
          None => if home_is_path(instance_home) { instance_home } else { "" }
        }
      },
      home_kind_source: if fact.home_kind == "trial" {
        fact.home_kind_source
      } else {
        match profile_fact {
          Some(item) => item.home_kind_source
          None =>
            if home_is_path(instance_home) {
              "按实例的 home 认定：profiles 读数里没有这只 profile（" + fact.dsh_home_source + "）"
            } else {
              "实例的 home 读不到（" + fact.dsh_home_source + "），profiles 读数里也没有这只 profile"
            }
        }
      },
      home_from_instance: fact.home_kind != "trial" &&
        profile_fact is None &&
        home_is_path(instance_home),
      // 运行中的实例必然有网页入口（没有入口的 profile 起不出常驻实例）
      cli_only: false,
      // 补包（§39）：只在 profiles 读数配得上这一只时才知道缺几个、也知道该用哪条命令；
      // 配不上（别处 home 的实例）就不摆那颗按钮 —— 数不出来就别许诺能修。
      missing_count: match profile_fact {
        Some(item) => item.bundles.missing.length()
        None => 0
      },
      repair_command: match profile_fact {
        Some(item) => item.repair_command
        None => ""
      },
      repair_home: match profile_fact {
        Some(item) => if item.home_path != "" { item.home_path } else { instance_home }
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
          if home_is_path(instance_home) {
            // 这一只跑在别处的 home 里：它的 profile 不在控制台读数里，这两格是「读不到」，
            // 不是「没有」——§33.2 要求这句话写进悬停。
            not_in_console_home_note
          } else {
            match fact.profile {
              Some(name) =>
                "这只实例解析出的 profile 名是「" + name + "」，但 profiles 读数里没有这一只，" +
                "没有目录可读最近改动" +
                (if fact.profile_source == "" { "" } else { "（" + fact.profile_source + "）" })
              None =>
                "实例读数里没解析出 profile 名，没有 profile 目录可读最近改动" +
                (if fact.profile_source == "" { "" } else { "（" + fact.profile_source + "）" })
            }
          }
      },
      light,
      light_reason,
      light_basis,
      health_text: health.text,
      health_hint: health.hint,
      health_free: health.free,
      last_started,
      last_started_source,
      // 配置快照跟着那只 profile 走：实例解析出 profile 就用它的读数
      snapshots: match profile_fact {
        Some(item) => item.snapshots
        None => []
      },
      snapshots_source: match profile_fact {
        Some(item) => item.snapshots_source
        None => "profiles 读数里没有这只实例的 profile，读不到它的配置快照"
      },
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
/// 已停止的实例 = 磁盘上真实存在的 profile，**且没有被任何可见进程用着**。
/// 被用着的那只不在这里出现：它的版本 / 插件 / patch / lock 都归到那张运行中卡上——
/// 同一个东西不能既「运行中」又「已停止」。
fn profile_rows(
  profiles : Array[ProfileFact],
  runtime : RuntimeFacts?,
  profiles_home : String,
  running : Array[InstanceFact],
  console : ConsoleFacts?,
  ignore_missing : Bool,
) -> Array[Row] {
  let rows : Array[Row] = []
  for fact in profiles {
    // 这一行属于哪个 home：读数里的 home_path 就是答案（隔离的那只在它自己的 home 里）。
    // 后面「这只 profile 有没有在跑」「行 id」「上次启动」全都要用同一个值 ——
    // 拿控制台 home 去配对，隔离的那只会既配不上运行中那一只（多出一行），
    // 行 id 也会指到它不在的地方。
    let row_home = if fact.home_path != "" { fact.home_path } else { profiles_home }
    if in_use_by(fact, running, row_home) {
      continue
    }
    let missing = fact.bundles.missing
    // 停止卡的状态灯：没有在跑 + 缺包/缺 patch 这两条判据都在 profiles 读数里（不是猜的）
    let (light, light_reason, light_basis) = profile_light(fact, ignore_missing)
    let health = health_note_of(
      fact.patch_exists,
      missing.length(),
      join_with(missing, "、"),
      ignore_missing,
    )
    // 第二行第三顺位：这一只现在没有实例可问，只能按 profile 名去控制台的记录里查
    // 「上次启动」。查不到就是空串 —— 那一行空着，不拿最近改动之类的时刻顶上
    //（最近改动是另一回事，它在抽屉第六格，口径不同）。
    let (last_started, last_started_source) = row_last_started(
      None,
      "",
      profile_id_candidates(fact.name, row_home),
      console,
    )
    rows.push({
      // 行 id 带上 home：同名两份档案在两个 home 里时，它们是两行，各排各的
      id: profile_row_id(fact.name, row_home),
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
      // 这一行的 home：**它自己的**。读数的 home_path 就是答案（隔离的那只在那里、共用的那只
      // 是控制台 home）；只有它给不出来时才退回「这批 profile 是从哪个 home 列出来的」。
      // 两种情况都读不到就写「未知」：绝不拿控制台自己的 home 顶替 ✗
      // （那会把这只 profile 说成属于一个它不属于的地方，开发指令也会因此指错目录）。
      home: if row_home == "" { "未知" } else { row_home },
      home_hint: if profiles_home == "" {
        "这一版 profiles 读数里没有 dshHome：不知道这批 profile 是从哪个 home 的 profiles/ 下读出来的，" +
        "所以这一格写「未知」。不拿控制台自己的 home 顶上，那只是把别处的 home 说成它的"
      } else {
        "这只 profile 自己的 home：profiles 读数就是在 " + profiles_home +
        "/profiles 下把这只列出来的（读数里的 dshHome / dshHomeSource）。" +
        "它与控制台自己的 home 可以相同、也可以不同。这一格说的是这一只属于哪儿，不是控制台在用什么"
      },
      url: "已停用，无法访问",
      // 占位串不是地址：这一行**没有**可复制的东西（§13.1）。
      // 「复制访问地址」按这一格置灰，复制动作也按它拦一道 —— 不许把这句占位话写进剪贴板。
      url_copyable: false,
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
      home_from_instance: false,
      // 命令行型（§41）：读数是 webApp === false 才算；None（旧后端）不算
      cli_only: match fact.web_app {
        Some(has) => !has
        None => false
      },
      // 补包（§39）：缺几个、用哪条命令、带哪个 home。home 用这一行自己的
      // （隔离的那只在自己的 home 里，共用的是控制台 home）—— 与「配置 home」同一格值。
      missing_count: missing.length(),
      repair_command: fact.repair_command,
      repair_home: row_home,
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
      // 配置快照：profiles 读数里每只一份，从新到旧
      snapshots: fact.snapshots,
      snapshots_source: fact.snapshots_source,
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
    url_copyable: false,
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
    home_from_instance: false,
    cli_only: false,
    missing_count: 0,
    repair_command: "",
    repair_home: "",
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
    // 磁盘上没有目录，没有 .snapshots 可读
    snapshots: [],
    snapshots_source: "磁盘上没有这只 profile 的目录，没有配置快照可读",
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
      // 演示行不是读数：没有真在跑的实例，地址是编的 —— 不当成「有地址可复制」
      url: "http://127.0.0.1:8100", url_copyable: false, web_url: None,
      web_url_source: "演示数据：端口 8100 上没有真实实例，读不到令牌",
      plugin_count: "5 个", plugin_detail: "",
      deletable: false, archived_at: None, archive_home: "",
      profile_name: None, port_value: None, console_started: false,
      user_note: "", user_note_source: "",
      // 演示数据不是读数：home 归属也没有读数，三格空着（界面写「读不到」）
      home_kind: "", home_path: "", home_kind_source: "", home_from_instance: false, cli_only: false,
      missing_count: 0, repair_command: "", repair_home: "",
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
      // 演示数据不是读数：没有快照可读（空数组 + 原因，界面据此不摆列表）
      snapshots: [],
      snapshots_source: "演示数据：不是真实读数，没有配置快照可读",
    },
    {
      id: "plugin-dev", name: "plugin-dev", kind: "插件开发（试验）", kind_hint: "",
      tone: Violet, status: Running, uptime: Some(42), uptime_hint: "",
      port_note: "", idle_note: "", note: "", busy: false,
      version: "0.2.0-rc.2（本地源码）", version_hint: "演示数据，不是读数", profile_hint: "演示数据，不是读数", home_hint: "演示数据，不是读数", profile: "dev", home: "/Users/you/.dsh/plugin-dev",
      url: "http://127.0.0.1:8200", url_copyable: false, web_url: None,
      web_url_source: "演示数据：端口 8200 上没有真实实例，读不到令牌",
      plugin_count: "2 个（开发中）", plugin_detail: "",
      deletable: true, archived_at: None, archive_home: "",
      profile_name: None, port_value: None, console_started: false,
      user_note: "", user_note_source: "",
      // 演示数据不是读数：home 归属也没有读数，三格空着（界面写「读不到」）
      home_kind: "", home_path: "", home_kind_source: "", home_from_instance: false, cli_only: false,
      missing_count: 0, repair_command: "", repair_home: "",
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
      // 演示数据不是读数：没有快照可读（空数组 + 原因，界面据此不摆列表）
      snapshots: [],
      snapshots_source: "演示数据：不是真实读数，没有配置快照可读",
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
      url: "http://127.0.0.1:8300", url_copyable: false, web_url: None,
      web_url_source: "演示数据：端口 8300 上没有真实实例，读不到令牌",
      plugin_count: "3 个", plugin_detail: "",
      deletable: true, archived_at: None, archive_home: "",
      profile_name: None, port_value: None, console_started: false,
      user_note: "", user_note_source: "",
      // 演示数据不是读数：home 归属也没有读数，三格空着（界面写「读不到」）
      home_kind: "", home_path: "", home_kind_source: "", home_from_instance: false, cli_only: false,
      missing_count: 0, repair_command: "", repair_home: "",
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
      // 演示数据不是读数：没有快照可读（空数组 + 原因，界面据此不摆列表）
      snapshots: [],
      snapshots_source: "演示数据：不是真实读数，没有配置快照可读",
    },
  ]
}

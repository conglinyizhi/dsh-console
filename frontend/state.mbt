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
/// 三档：真实读取 / 真实读取失败退回演示 / 请求还在路上。
/// （以前还有一档「演示数据」，只被「接口还没返回」那个初始态用着 ——
/// 初始态现在是「读取中」，那一档就没有生产者了，随它一起去掉。）
enum TagKind {
  Real
  Fallback
  /// 读数还没回来：既不是真实数据，也不是演示数据，界面上说「读取中」
  Pending
} derive(Eq)

pub extend TagKind with Eq::{ not_equal, equal }

///|
/// 一处数据的数据源标记，界面上逐处标。
/// real = 真实读取；fallback = 真实读取失败，显式退回演示；
/// pending = 请求还在路上（这一档**不是**空数据：把「还在读」标成「没有」正是要修的那件事）。
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
} derive(Eq)

pub extend Row with Eq::{ not_equal, equal }

///|
/// 启动等待时长与重启按钮的自锁时长（前端演示，没有真实进程可等）。
pub let start_delay_ms : Int = 2500

///|
pub let restart_lock_ms : Int = 900

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
  // 三处数据源标记
  tag_runtime : SourceTag
  tag_instances : SourceTag
  tag_profiles : SourceTag
  tag_archived : SourceTag
  tag_settings : SourceTag
  // 三个读数是否都落地了：都落地才拼一次列表（Vue 版是 Promise.all 之后拼）
  read_runtime : Bool
  read_profiles : Bool
  read_instances : Bool
  built : Bool
  rows : Array[Row]
  // 交互状态
  menu_open : String
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
  /// 启动等待态里那句提示要用的动作名（回执与计时是两条路，各自都拿得到它）
  act_label : String
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
  log_tag : SourceTag
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
  MenuToggle(String)
  MenuClose
  MenuCloseBack(String)
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
  // 写动作的回执：row_id / action / label / 原始响应
  HttpDone(String, String, String, Result[String, Error])
  // 复制到剪贴板的回执：那一项的名字（动作 + 行名）/ 传输层拿回来的那段 JSON
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
    menu_open: "",
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
    act_label: "",
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
fn real_tag(detail : String) -> SourceTag {
  { kind: Real, label: "真实数据", detail }
}

///|
fn fallback_tag(detail : String) -> SourceTag {
  { kind: Fallback, label: "演示数据 · 真实读取失败", detail }
}

///|
/// 请求还在路上：读数没到之前的那一档。与「演示数据 / 读取失败」分开 ——
/// 那两档说的是「已经知道了什么」，这一档说的是「还不知道」。
fn pending_tag(detail : String) -> SourceTag {
  { kind: Pending, label: "读取中", detail }
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
fn trigger_id(id : String) -> String {
  "dsh-trigger-" + dom_key(id)
}

///|
fn archive_trigger_id(id : String) -> String {
  "dsh-archive-trigger-" + dom_key(id)
}

///|
fn menu_id(id : String) -> String {
  "dsh-menu-" + dom_key(id)
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

///|
/// 运行时长简写：分钟 → 小时加分钟；读不到宿主进程就不给数字。
fn duration_text(minutes : Int) -> String {
  if minutes < 60 {
    minutes.to_string() + " 分钟"
  } else {
    (minutes / 60).to_string() + " 小时 " + (minutes % 60).to_string() + " 分钟"
  }
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
          "声明 " + item.bundles.declared.to_string() + " · 已装 " +
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
    }
  })
}

///|
/// patch 行数 / lock 时刻这一行：档案的健康读数，运行中卡与停止卡共用同一口径。
fn patch_lock_note(fact : ProfileFact) -> String {
  "cordis.patch.yml " + fact.patch_lines.to_string() + " 行 · " +
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
    rows.push({
      id: "profile:" + fact.name,
      name: fact.name,
      kind: if fact.is_current { "本地 profile · 默认" } else { "本地 profile" },
      // 「默认」只表示 DSH_PROFILE 指向它，跟「运行中」无关 —— 这个词以前写成「当前」，会被读成正在跑
      kind_hint: if fact.is_current {
        "环境变量 DSH_PROFILE 指向这只 profile：新起的实例默认用它，不代表它正在运行"
      } else {
        "磁盘上真实存在的 profile，当前没有对应的 dsh 进程"
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
      plugin_count: "声明 " + fact.bundles.declared.to_string() + " · 已装 " +
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
    })
  }
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
    kind: "已归档 · 磁盘上没有这只 profile",
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
    },
  ]
}

///|
/// 界面上的工作流入口与「关于实例」说明（与 Vue 版同为固定文案）。
pub let workflows : Array[(String, String)] = [
  ("从当前实例派生开发副本", "派生隔离副本，用新端口与独立 DSH_HOME"),
  ("将插件交回主线实例", "把插件提交回稳定实例"),
]

///|
pub let safety_checks : Array[String] = [
  "独立 DSH_HOME，会话与插件互不干扰",
  "各实例可用不同 DSH 版本或来源",
  "仅监听 127.0.0.1，不暴露到网络",
]
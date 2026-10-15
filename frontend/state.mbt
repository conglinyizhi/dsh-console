// 应用状态、消息与更新循环。
//
// 导航是状态切页（没有 URL 路由）：page 就是 model 里的一个字段，刷新回到总览。
// 三个只读接口在 init 里一次发出去；读不到就把原因留进 model，界面直接展示。

///|
pub(all) enum Page {
  Overview
  Logs
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
  Fork
  Rename
  Archive
  Unarchive
  Delete
  Logs
  Dir
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
enum TagKind {
  Real
  Demo
  Fallback
} derive(Eq)

pub extend TagKind with Eq::{ not_equal, equal }

///|
/// 一处数据的数据源标记，界面上逐处标。
/// real = 真实读取；demo = 本轮仍是演示；fallback = 真实读取失败，显式退回演示。
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
  plugin_count : String
  plugin_detail : String
  deletable : Bool
  /// 有值即表示已归档，移出运行/停止两个分组
  archived_at : String?
} derive(Eq)

pub extend Row with Eq::{ not_equal, equal }

///|
/// 启动等待时长与重启按钮的自锁时长（前端演示，没有真实进程可等）。
pub let start_delay_ms : Int = 2500

///|
pub let restart_lock_ms : Int = 900

///|
/// 派生副本的端口探测上限：最多往后试 20 个（与 Vue 版的 portProbe.ts 一致）。
pub let port_probe_limit : Int = 20

///|
pub let demo_archived_at : String = "2026-10-14 13:05"

///|
struct Model {
  page : Page
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
  confirm_id : String
  confirm_return : String
  archived_open : Bool
  // 派生：正在探测的端口
  probe_id : String
  probe_base : Int
  probe_offset : Int
  probe_skipped : Int
  // 日志页
  log_source : String
  log_user_picked : Bool
  log_loaded : Bool
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
  InstancesText(Result[String, Error])
  LogsText(Result[String, Error])
  Navigate(Page)
  RowAction(String, ActionKey)
  MenuToggle(String)
  MenuClose
  MenuCloseBack(String)
  StartTick(String)
  RestartTick
  RenameInput(String)
  RenameConfirm
  RenameCancel
  DeleteOpen(String, String)
  DeleteConfirm
  DeleteCancel
  ToggleArchived
  LogSourcePicked(String)
  LogRefresh
  ProbeTick(String, Bool)
  Noop
}

///|
fn initial_model() -> Model {
  {
    page: Overview,
    runtime: None,
    runtime_error: "",
    runtime_time: "—",
    profiles: None,
    profiles_error: "",
    instances: None,
    instances_error: "",
    tag_runtime: demo_tag("本地只读接口还没返回"),
    tag_instances: demo_tag("本地只读接口还没返回"),
    tag_profiles: demo_tag("本地只读接口还没返回"),
    tag_archived: demo_tag(
      "归档区本轮不接真实数据：磁盘上没有「归档记录」这种概念，这组一直是前端演示",
    ),
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
    confirm_id: "",
    confirm_return: "",
    // 归档区默认折叠：这一组目前固定是演示数据，短时间用不上；
    // 折叠起来不占视线，功能本身留着（展开即可用），比删掉合适。
    archived_open: false,
    probe_id: "",
    probe_base: 0,
    probe_offset: 0,
    probe_skipped: -1,
    log_source: "host",
    log_user_picked: false,
    log_loaded: false,
    logs: None,
    log_error: "",
    log_time: "",
    log_tag: fallback_tag("日志还没读"),
    log_instance_note: "",
  }
}

// ── 数据源标记 ──────────────────────────────────────────────

///|
fn real_tag(detail : String) -> SourceTag {
  { kind: Real, label: "真实数据", detail }
}

///|
fn demo_tag(detail : String) -> SourceTag {
  { kind: Demo, label: "演示数据", detail }
}

///|
fn fallback_tag(detail : String) -> SourceTag {
  { kind: Fallback, label: "演示数据 · 真实读取失败", detail }
}

// ── 拉取 ────────────────────────────────────────────────────

///|
fn load(emit : @cmd.Emit[Msg]) -> @cmd.Cmd {
  @cmd.batch([
    @http.get("/api/local/runtime").expect_text(emit.map(fn(res) { RuntimeText(res) })),
    @http.get("/api/local/profiles").expect_text(emit.map(fn(res) { ProfilesText(res) })),
    @http.get("/api/local/instances").expect_text(emit.map(fn(res) { InstancesText(res) })),
  ])
}

///|
/// 日志页的读数：尾部 200 行，上限由接口负责截断并说明。
fn load_logs(source : String, emit : @cmd.Emit[Msg]) -> @cmd.Cmd {
  let query = "/api/local/logs?source=" + js_encode_uri_component(source) + "&tail=200"
  @http.get(query).expect_text(emit.map(fn(res) { LogsText(res) }))
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
/// 正在运行的实例 = 监听端口 + HTTP 签名探测到的真实实例（不是 /proc 进程，也不是磁盘上的 profile）。
/// 实例的 Profile / DSH_HOME / DSH 版本 / 运行时长来自「端口 → socket inode → PID」这条 join；
/// 任一项拿不到就写「未知」，并把后端给的原因挂在悬停说明上 —— 不编值，也不留一个干巴巴的未知。
fn running_rows(facts : Array[InstanceFact], profiles : Array[ProfileFact]) -> Array[Row] {
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
      idle_note: "",
      note: process_note(fact),
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
    }
  })
}

///|
/// 已停止的实例 = 磁盘上真实存在的 profile；没有进程，所以访问地址是「—」。
fn profile_rows(
  profiles : Array[ProfileFact],
  runtime : RuntimeFacts?,
  dsh_home : String,
) -> Array[Row] {
  profiles.map(fn(fact) {
    let missing = fact.bundles.missing
    {
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
      idle_note: "cordis.patch.yml " + fact.patch_lines.to_string() + " 行 · " +
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
        }),
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
      url: "—",
      plugin_count: "声明 " + fact.bundles.declared.to_string() + " · 已装 " +
        fact.bundles.installed.to_string(),
      plugin_detail: if missing.length() > 0 {
        "缺少的包：" + join_with(missing, "、")
      } else {
        fact.name + " 声明的插件都已安装"
      },
      deletable: true,
      archived_at: None,
    }
  })
}

// ── 演示数据（真实读取失败时兜底；归档区一直是演示） ─────────

///|
fn demo_running() -> Array[Row] {
  [
    {
      id: "work-main", name: "work-main", kind: "核心工作实例", kind_hint: "",
      tone: Accent, status: Running, uptime: Some(138), uptime_hint: "",
      port_note: "", idle_note: "", note: "", busy: false,
      version: "0.2.0-rc.2（本地源码）", version_hint: "演示数据，不是读数", profile_hint: "演示数据，不是读数", home_hint: "演示数据，不是读数", profile: "main", home: "/Users/you/.dsh/work-main",
      url: "http://127.0.0.1:8100", plugin_count: "5 个", plugin_detail: "",
      deletable: false, archived_at: None,
    },
    {
      id: "plugin-dev", name: "plugin-dev", kind: "插件开发（试验）", kind_hint: "",
      tone: Violet, status: Running, uptime: Some(42), uptime_hint: "",
      port_note: "", idle_note: "", note: "", busy: false,
      version: "0.2.0-rc.2（本地源码）", version_hint: "演示数据，不是读数", profile_hint: "演示数据，不是读数", home_hint: "演示数据，不是读数", profile: "dev", home: "/Users/you/.dsh/plugin-dev",
      url: "http://127.0.0.1:8200", plugin_count: "2 个（开发中）", plugin_detail: "",
      deletable: true, archived_at: None,
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
      url: "http://127.0.0.1:8300", plugin_count: "3 个", plugin_detail: "",
      deletable: true, archived_at: None,
    },
  ]
}

///|
fn demo_archived() -> Array[Row] {
  [
    {
      id: "old-experiment", name: "old-experiment", kind: "插件开发（试验）", kind_hint: "",
      tone: Violet, status: Stopped, uptime: Some(0), uptime_hint: "",
      port_note: "", idle_note: "", note: "", busy: false,
      version: "0.2.0-rc.2（本地源码）", version_hint: "演示数据，不是读数", profile_hint: "演示数据，不是读数", home_hint: "演示数据，不是读数", profile: "dev", home: "/Users/you/.dsh/old-experiment",
      url: "http://127.0.0.1:8400", plugin_count: "1 个（开发中）", plugin_detail: "",
      deletable: true, archived_at: Some(demo_archived_at),
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

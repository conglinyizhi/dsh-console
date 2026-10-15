// 只读接口的数据模型与解析。
//
// 纪律（与后端、与 Vue 版一致）：读不到就写「未知」并把原因留在界面上，不编数字。
// 这里只做「外壳 → 字段」的取值，不做业务推导。
//
// 五个接口都在这个文件里：runtime / profiles / logs / processes / instances。
// JSON 走 moonbitlang/core/json 的 parse；字段取值显式写出来，不用 derive(FromJson)——
// 这几个接口 null 很密（uptimeSeconds / title / contentType / profile / fileSize 都可能
// 是 null），而界面要区分「读到了一个空值」与「字段根本不在」，derive 出来的结构没法表达
// 这个区别。

// ── 取值助手 ────────────────────────────────────────────────

///|
fn str_field(obj : Map[String, Json], key : String) -> String {
  match obj.get(key) {
    Some(Json::String(s)) => s
    _ => ""
  }
}

///|
/// 字符串或 null：null 与缺失都给 None（界面据此写「未知」，不写空串）。
fn opt_str_field(obj : Map[String, Json], key : String) -> String? {
  match obj.get(key) {
    Some(Json::String(s)) => Some(s)
    _ => None
  }
}

///|
/// 只读接口的 JSON 数值都是整数读法：带小数就取整，别处用不到小数。
fn int_field(obj : Map[String, Json], key : String) -> Int? {
  match obj.get(key) {
    Some(Json::Number(n, ..)) => Some(n.to_int())
    _ => None
  }
}

///|
/// 可能很大的数值（毫秒时间戳）：**不能走 int_field**，Int 装不下 1.7e12。
/// 只在这里读时间戳用，别处的整数读法维持 int_field 不动。
fn num_field(obj : Map[String, Json], key : String) -> Double? {
  match obj.get(key) {
    Some(Json::Number(n, ..)) => Some(n)
    _ => None
  }
}

///|
/// 键在不在（用来区分「字段是 null」与「这个字段根本不在响应里」）。
fn has_key(obj : Map[String, Json], key : String) -> Bool {
  match obj.get(key) {
    Some(_) => true
    None => false
  }
}

///|
fn bool_field(obj : Map[String, Json], key : String) -> Bool {
  match obj.get(key) {
    Some(Json::True) => true
    _ => false
  }
}

///|
fn arr_field(obj : Map[String, Json], key : String) -> Array[Json] {
  match obj.get(key) {
    Some(Json::Array(items)) => items
    _ => []
  }
}

///|
fn obj_field(obj : Map[String, Json], key : String) -> Map[String, Json] {
  match obj.get(key) {
    Some(Json::Object(inner)) => inner
    _ => Map([])
  }
}

///|
fn int_or(obj : Map[String, Json], key : String, fallback : Int) -> Int {
  match int_field(obj, key) {
    Some(v) => v
    None => fallback
  }
}

///|
/// 外壳里 ok=false 时的错误文案：优先用接口给的 message，其次 code，都没有才兜底。
fn envelope_error(envelope : Map[String, Json]) -> String {
  match envelope.get("error") {
    Some(Json::Object(err)) =>
      match (str_field(err, "code"), str_field(err, "message")) {
        ("", "") => "接口返回 ok=false"
        (code, "") => code
        ("", message) => message
        (code, message) => code + ": " + message
      }
    _ => "接口返回 ok=false"
  }
}

///|
/// 打开响应外壳，拿到 data 对象。
///
/// 三个失败点各自有话说：不是 JSON、不是外壳、ok=false —— 都带上能对上号的措辞，
/// 界面直接展示，不吞。
fn open_envelope(text : String) -> Result[Map[String, Json], String] {
  let root = try @json.parse(text) catch {
    _ => return Err("响应不是合法 JSON")
  }
  guard root is Json::Object(envelope) else {
    return Err("响应外壳不是 JSON 对象")
  }
  match envelope.get("ok") {
    Some(Json::True) => ()
    _ => return Err(envelope_error(envelope))
  }
  match envelope.get("data") {
    Some(Json::Object(data)) => Ok(data)
    _ => Err("响应里没有 data 对象")
  }
}

// ── GET /api/local/runtime ──────────────────────────────────

///|
pub(all) struct RuntimeFacts {
  dsh_version : String
  dsh_package_name : String
  dsh_source_label : String
  console_version : String?
  console_package_name : String
  console_version_source : String
  backend_runtime : String
  backend_version : String
  dsh_home : String
  dsh_home_source : String
  dsh_profile : String?
  platform : String
} derive(Eq)

pub extend RuntimeFacts with Eq::{ not_equal, equal }

///|
pub fn parse_runtime(text : String) -> Result[RuntimeFacts, String] {
  let data = match open_envelope(text) {
    Ok(data) => data
    Err(reason) => return Err(reason)
  }
  Ok({
    dsh_version: str_field(data, "dshVersion"),
    dsh_package_name: str_field(data, "dshPackageName"),
    dsh_source_label: str_field(data, "dshSourceLabel"),
    console_version: opt_str_field(data, "consoleVersion"),
    console_package_name: str_field(data, "consolePackageName"),
    console_version_source: str_field(data, "consoleVersionSource"),
    backend_runtime: str_field(data, "backendRuntime"),
    backend_version: str_field(data, "backendVersion"),
    dsh_home: str_field(data, "dshHome"),
    dsh_home_source: str_field(data, "dshHomeSource"),
    dsh_profile: opt_str_field(data, "dshProfile"),
    platform: str_field(data, "platform"),
  })
}

// ── GET /api/local/profiles ─────────────────────────────────

///|
pub(all) struct ProfileBundles {
  declared : Int
  installed : Int
  missing : Array[String]
} derive(Eq)

pub extend ProfileBundles with Eq::{ not_equal, equal }

///|
pub(all) struct ProfileFact {
  name : String
  is_current : Bool
  patch_exists : Bool
  patch_lines : Int
  lock_exists : Bool
  lock_mtime : String?
  bundles : ProfileBundles
  /// 用户给这只 profile 写的备注（<profile 目录>/.dsh-note.txt）。空串 = 没写备注。
  note : String
  /// 备注的读取口径 / 读不到的原因，后端原样给；空串表示没什么要说的
  note_source : String
  /// 这只 profile **目录**的最近改动时刻（mtime，毫秒时间戳）。None = 读不到。
  ///
  /// 为什么是「最近改动」而不是「创建时间」：多数文件系统上可靠的创建时间拿不到
  /// （ctime 会在 chmod / 改名时变，birth time 不通用）。目录 mtime 是能拿到、
  /// 且不会骗人的那一个 —— 刚派生出来的 profile 一定是最新的，所以它同时回答了
  /// 「哪个是刚弄的」。卡上那一格的标签因此写「最近改动」，不许写成「创建时间」。
  dir_mtime_ms : Double?
  /// 这个时刻从哪来 / 为什么读不到，后端原样给（dirMtimeSource）；
  /// 字段**根本不在响应里**时由前端补一句说明（见 parse_profiles），别处不改写它。
  dir_mtime_source : String
} derive(Eq)

pub extend ProfileFact with Eq::{ not_equal, equal }

///|
pub(all) struct ProfilesFacts {
  dsh_home : String
  dsh_home_source : String
  profiles_root : String
  current_profile : String?
  profiles : Array[ProfileFact]
} derive(Eq)

pub extend ProfilesFacts with Eq::{ not_equal, equal }

///|
pub fn parse_profiles(text : String) -> Result[ProfilesFacts, String] {
  let data = match open_envelope(text) {
    Ok(data) => data
    Err(reason) => return Err(reason)
  }
  let list : Array[ProfileFact] = []
  for item in arr_field(data, "profiles") {
    guard item is Json::Object(fact) else { continue }
    let bundles = obj_field(fact, "bundles")
    let patch = obj_field(fact, "patch")
    let lock = obj_field(fact, "lock")
    let missing : Array[String] = []
    for m in arr_field(bundles, "missing") {
      match m {
        Json::String(s) => missing.push(s)
        _ => ()
      }
    }
    list.push({
      name: str_field(fact, "name"),
      is_current: bool_field(fact, "isCurrent"),
      patch_exists: bool_field(patch, "exists"),
      patch_lines: int_or(patch, "lines", 0),
      lock_exists: bool_field(lock, "exists"),
      lock_mtime: opt_str_field(lock, "mtime"),
      bundles: {
        declared: int_or(bundles, "declared", 0),
        installed: int_or(bundles, "installed", 0),
        missing,
      },
      // note 是这一轮新增的字段：后端还没给就是空串（没备注），界面按「没有备注」办
      note: str_field(fact, "note"),
      note_source: str_field(fact, "noteSource"),
      dir_mtime_ms: num_field(fact, "dirMtimeMs"),
      // 后端给了 dirMtimeSource 就照它说；字段**整个不在响应里**（这一版后端还没落地）
      // 补一句前端自己的话 —— 那与「后端读了但读不到」不是同一件事，不能都写成「读不到」。
      dir_mtime_source: if has_key(fact, "dirMtimeMs") || has_key(fact, "dirMtimeSource") {
        str_field(fact, "dirMtimeSource")
      } else {
        "profiles 读数里没有 dirMtimeMs 字段（后端这一版还没给）"
      },
    })
  }
  Ok({
    dsh_home: str_field(data, "dshHome"),
    dsh_home_source: str_field(data, "dshHomeSource"),
    profiles_root: str_field(data, "profilesRoot"),
    current_profile: opt_str_field(data, "currentProfile"),
    profiles: list,
  })
}

// ── GET /api/local/instances ────────────────────────────────

///|
pub(all) struct InstanceFact {
  id : String
  port : Int
  url : String
  http_status : Int
  signature_id : String
  signature_describe : String
  profile : String?
  dsh_home : String?
  uptime_seconds : Int?
  /// 入口包 …/node_modules/@deepseek-ai/dsh/package.json 的 version；读不到是 None
  version : String?
  /// 下面几条都是「这个值是从哪读出来的 / 为什么读不到」，原样来自后端，不在前端编
  version_source : String
  profile_source : String
  dsh_home_source : String
  /// 进程级原因码：port-join / port-arg / process-gone / fd-unreadable / cmdline-unreadable / unscanned
  process_reason_code : String
  process_reason : String
  /// 运行时登记（$XDG_STATE_HOME/dsh-console/runtime.json）里有这一条 → 由本控制台启动。
  /// 后端把登记结果并进 instances 的这个字段上（见 README「还缺什么」一节）；
  /// 字段不在就是 false —— 宁可少一个标记，也不拿 profile 名字去猜。
  console_started : Bool
  /// 带令牌的完整地址（`http://<host>:<port>/?token=…`），新标签页打开它才能过首次握手。
  /// null / 字段不在 = 读不到令牌：这时**不拿裸地址冒充**（裸地址打开就是一个 401 页面）。
  web_url : String?
  /// 令牌从哪来，或为什么读不到（后端原样给；这一版后端还没这个字段时也补一句人话）。
  web_url_source : String
} derive(Eq)

pub extend InstanceFact with Eq::{ not_equal, equal }

///|
pub(all) struct InstancesFacts {
  sources : Array[String]
  candidate_count : Int
  probe_hits : Int
  process_note : String
  signature_ids : Array[String]
  instances : Array[InstanceFact]
} derive(Eq)

pub extend InstancesFacts with Eq::{ not_equal, equal }

///|
pub fn parse_instances(text : String) -> Result[InstancesFacts, String] {
  let data = match open_envelope(text) {
    Ok(data) => data
    Err(reason) => return Err(reason)
  }
  let sources : Array[String] = []
  for s in arr_field(data, "sources") {
    match s {
      Json::String(text) => sources.push(text)
      _ => ()
    }
  }
  let signature_ids : Array[String] = []
  for s in arr_field(data, "signatures") {
    guard s is Json::Object(sig) else { continue }
    signature_ids.push(str_field(sig, "id"))
  }
  let probe = obj_field(data, "probe")
  let supplement = obj_field(data, "processSupplement")
  let list : Array[InstanceFact] = []
  for item in arr_field(data, "instances") {
    guard item is Json::Object(fact) else { continue }
    let sig = obj_field(fact, "signature")
    let reason = obj_field(fact, "processReason")
    list.push({
      id: str_field(fact, "id"),
      port: int_or(fact, "port", 0),
      url: str_field(fact, "url"),
      http_status: int_or(fact, "httpStatus", 0),
      signature_id: str_field(sig, "id"),
      signature_describe: str_field(sig, "describe"),
      profile: opt_str_field(fact, "profile"),
      dsh_home: opt_str_field(fact, "dshHome"),
      uptime_seconds: int_field(fact, "uptimeSeconds"),
      version: opt_str_field(fact, "version"),
      version_source: str_field(fact, "versionSource"),
      profile_source: str_field(fact, "profileSource"),
      dsh_home_source: str_field(fact, "dshHomeSource"),
      process_reason_code: str_field(reason, "code"),
      process_reason: str_field(reason, "message"),
      console_started: bool_field(fact, "consoleStarted") ||
        bool_field(fact, "startedByConsole"),
      web_url: opt_str_field(fact, "webUrl"),
      web_url_source: web_url_source_of(fact),
    })
  }
  Ok({
    sources,
    candidate_count: int_or(data, "candidateCount", 0),
    probe_hits: int_or(probe, "hits", 0),
    process_note: str_field(supplement, "note"),
    signature_ids,
    instances: list,
  })
}

///|
/// webUrl 那对字段的来源说明：后端给了 webUrlSource 就用它（它就是「令牌从哪来 / 为什么读不到」）。
///
/// 两个字段都不在时（这一版后端还没这一轮的能力）现编一句 —— 「读不到令牌」这件事
/// 不能只留一个空串：那句原因正是按钮与悬停要展示的东西，空着就成了没有理由的失败。
fn web_url_source_of(fact : Map[String, Json]) -> String {
  let source = str_field(fact, "webUrlSource")
  if source != "" {
    return source
  }
  match fact.get("webUrl") {
    Some(Json::String(_)) => ""
    _ => "instances 读数里这一条没有 webUrl / webUrlSource 字段（后端没给这两个字段）"
  }
}

// ── GET /api/local/processes ────────────────────────────────

///|
/// 进程扫描的一条读数。当前界面不直接渲染它（运行中实例的主口径是端口 + HTTP 签名，
/// Vue 版同样没用这个接口），数据层照样解析，免得接口在白名单里却没有客户端。
pub(all) struct ProcessFact {
  pid : Int
  port : Int
  profile : String?
  uptime_seconds : Int?
} derive(Eq)

pub extend ProcessFact with Eq::{ not_equal, equal }

///|
pub(all) struct ProcessesFacts {
  proc_root : String
  scanned : Int
  matcher : String
  instances : Array[ProcessFact]
} derive(Eq)

pub extend ProcessesFacts with Eq::{ not_equal, equal }

///|
pub fn parse_processes(text : String) -> Result[ProcessesFacts, String] {
  let data = match open_envelope(text) {
    Ok(data) => data
    Err(reason) => return Err(reason)
  }
  let list : Array[ProcessFact] = []
  for item in arr_field(data, "instances") {
    guard item is Json::Object(fact) else { continue }
    list.push({
      pid: int_or(fact, "pid", 0),
      port: int_or(fact, "port", 0),
      profile: opt_str_field(fact, "profile"),
      uptime_seconds: int_field(fact, "uptimeSeconds"),
    })
  }
  Ok({
    proc_root: str_field(data, "procRoot"),
    scanned: int_or(data, "scanned", 0),
    matcher: str_field(data, "matcher"),
    instances: list,
  })
}

// ── GET /api/local/logs ─────────────────────────────────────

///|
/// 级别只在接口真读得出时才有值：error / warn，其余是 None（界面写「··」并压成次级灰）。
pub(all) struct LogLine {
  time : String?
  level : String?
  text : String
} derive(Eq)

pub extend LogLine with Eq::{ not_equal, equal }

///|
pub(all) struct LogsFacts {
  source : String
  label : String?
  kind : String
  instance_port : Int?
  detected_instances : Int?
  path : String?
  home_source : String?
  effective_tail : Int
  max_tail : Int
  read_ok : Bool
  error_code : String?
  read_error : String?
  file_size : Int?
  window_bytes : Int
  lines : Array[LogLine]
  truncated : Bool
  truncated_note : String?
  tail_note : String?
} derive(Eq)

pub extend LogsFacts with Eq::{ not_equal, equal }

///|
pub fn parse_logs(text : String) -> Result[LogsFacts, String] {
  let data = match open_envelope(text) {
    Ok(data) => data
    Err(reason) => return Err(reason)
  }
  let lines : Array[LogLine] = []
  for item in arr_field(data, "lines") {
    guard item is Json::Object(line) else { continue }
    lines.push({
      time: opt_str_field(line, "time"),
      level: opt_str_field(line, "level"),
      text: str_field(line, "text"),
    })
  }
  let instance = obj_field(data, "instance")
  Ok({
    source: str_field(data, "source"),
    label: opt_str_field(data, "label"),
    kind: str_field(data, "kind"),
    instance_port: int_field(instance, "port"),
    detected_instances: int_field(data, "detectedInstances"),
    path: opt_str_field(data, "path"),
    home_source: opt_str_field(data, "homeSource"),
    effective_tail: int_or(data, "effectiveTail", 0),
    max_tail: int_or(data, "maxTail", 0),
    read_ok: bool_field(data, "readOk"),
    error_code: opt_str_field(data, "errorCode"),
    read_error: opt_str_field(data, "readError"),
    file_size: int_field(data, "fileSize"),
    window_bytes: int_or(data, "windowBytes", 0),
    lines,
    truncated: bool_field(data, "truncated"),
    truncated_note: opt_str_field(data, "truncatedNote"),
    tail_note: opt_str_field(data, "tailNote"),
  })
}

// ── GET /api/local/console ──────────────────────────────────

///|
/// 运行时登记里的一条：控制台自己起过的实例（runtime.json）。
pub(all) struct ConsoleRuntime {
  pid : Int
  port : Int
  profile : String
  alive : Bool
} derive(Eq)

pub extend ConsoleRuntime with Eq::{ not_equal, equal }

///|
/// 一条归档记录（archive.json）：只记「这只 profile 已归档」，磁盘上的目录不动。
///
/// 第二轮起没有「已合并」标记了（使用者的决定）：归档就是归档，成没成果不在这条记录里。
/// 旧的 archive.json 里可能还带着 merged 字段，读的时候直接忽略 —— 少读一个字段不算错。
pub(all) struct ConsoleArchive {
  profile : String
  archived_at : String
} derive(Eq)

pub extend ConsoleArchive with Eq::{ not_equal, equal }

///|
/// 控制台自己的状态读数。这一份不在契约里那五个只读接口之列：
/// runtime.json / archive.json 是两份状态文件，浏览器读不到文件系统，
/// 后端为此单开了一个只读端点（GET /api/local/console）。
pub(all) struct ConsoleFacts {
  state_dir : String
  settings_path : String
  archive_path : String
  runtime : Array[ConsoleRuntime]
  archive : Array[ConsoleArchive]
  notes : Array[String]
} derive(Eq)

pub extend ConsoleFacts with Eq::{ not_equal, equal }

///|
pub fn parse_console(text : String) -> Result[ConsoleFacts, String] {
  let data = match open_envelope(text) {
    Ok(data) => data
    Err(reason) => return Err(reason)
  }
  let runtime : Array[ConsoleRuntime] = []
  for item in arr_field(data, "runtime") {
    guard item is Json::Object(entry) else { continue }
    runtime.push({
      pid: int_or(entry, "pid", 0),
      port: int_or(entry, "port", 0),
      profile: str_field(entry, "profile"),
      alive: bool_field(entry, "alive"),
    })
  }
  let archive : Array[ConsoleArchive] = []
  for item in arr_field(data, "archive") {
    guard item is Json::Object(entry) else { continue }
    archive.push({
      profile: str_field(entry, "profile"),
      archived_at: str_field(entry, "archivedAt"),
    })
  }
  let notes : Array[String] = []
  for note in arr_field(data, "notes") {
    match note {
      Json::String(text) => notes.push(text)
      _ => ()
    }
  }
  Ok({
    state_dir: str_field(data, "stateDir"),
    settings_path: str_field(data, "settingsPath"),
    archive_path: str_field(data, "archivePath"),
    runtime,
    archive,
    notes,
  })
}

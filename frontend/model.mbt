// 只读接口的数据模型与解析。
//
// 纪律（与后端、与 Vue 版一致）：读不到就写「未知」并把原因留在界面上，不编数字。
// 这里只做「外壳 → 字段」的取值，不做业务推导。
//
// 六个接口都在这个文件里：runtime / profiles / logs / processes / instances / dsh-releases。
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
/// 布尔或缺失：字段不在 / 不是布尔都是 None。
/// 与 bool_field 的区别是「明确给了 false」与「根本没这个字段」分得开 ——
/// 删除方式这种「不知道就不能乱说」的读数必须分开，不能把没给读成 false。
fn opt_bool_field(obj : Map[String, Json], key : String) -> Bool? {
  match obj.get(key) {
    Some(Json::True) => Some(true)
    Some(Json::False) => Some(false)
    _ => None
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
        ("", "") => "读数报告了失败"
        (code, "") => code
        ("", message) => message
        (code, message) => code + ": " + message
      }
    _ => "读数报告了失败"
  }
}

///|
/// 打开响应外壳，拿到 data 对象。
///
/// 三个失败点各自有话说：不是 JSON、不是外壳、ok=false —— 都带上能对上号的措辞，
/// 界面直接展示，不吞。
fn open_envelope(text : String) -> Result[Map[String, Json], String] {
  let root = try @json.parse(text) catch {
    _ => return Err("回执不是合法 JSON")
  }
  guard root is Json::Object(envelope) else {
    return Err("回执不是 JSON 对象")
  }
  match envelope.get("ok") {
    Some(Json::True) => ()
    _ => return Err(envelope_error(envelope))
  }
  match envelope.get("data") {
    Some(Json::Object(data)) => Ok(data)
    _ => Err("回执里没有读数")
  }
}

// ── GET /api/local/runtime ──────────────────────────────────

///|
/// 这台机器上装着的一份 dsh（读数里的 dshCandidates 一项）。
///
/// active / running 都是后端给的事实，前端不按版本号自己推：
///   active  起实例（启动 / 重启）会用这一份
///   running 有在跑的实例，它的入口包就是这一份
/// 版本号相同、目录不同的两份 dsh 不是同一份（一份是软链、一份在别的全局根里），
/// 所以「是不是同一份」永远看后端怎么判。
pub(all) struct DshCandidate {
  version : String
  name : String
  dir : String
  /// 这份是怎么找到的（后端原样给，进悬停）
  source : String
  active : Bool
  running : Bool
} derive(Eq)

pub extend DshCandidate with Eq::{ not_equal, equal }

///|
pub(all) struct RuntimeFacts {
  dsh_version : String
  dsh_package_name : String
  dsh_source_label : String
  /// 这台机器上装着的 dsh（可能不止一份）。空数组 = 这一版读数里没有候选这一项
  dsh_candidates : Array[DshCandidate]
  /// 生效版本的状态：auto（没指定）/ pinned（按你指定的那一版）/ pin-missing（指定过、那份没了）。
  /// 空串 = 这一版读数里没有这一项（界面按「不知道」处理，不猜成 auto）
  dsh_pin_state : String
  /// 指定失效时后端给的那句人话；其余空串
  dsh_pin_note : String
  /// 这份 dsh 是怎么装上去的：pnpm / npm / yarn / unknown。
  /// 空串 = 这一版读数里没有这一项（不是「未知」——界面那一行要分开说）
  dsh_install_kind : String
  /// 凭什么这么判（后端原样给，进悬停）
  dsh_install_kind_source : String
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
  let candidates : Array[DshCandidate] = []
  for item in arr_field(data, "dshCandidates") {
    guard item is Json::Object(cand) else { continue }
    candidates.push({
      version: str_field(cand, "version"),
      name: str_field(cand, "name"),
      dir: str_field(cand, "dir"),
      source: str_field(cand, "source"),
      active: bool_field(cand, "active"),
      running: bool_field(cand, "running"),
    })
  }
  Ok({
    dsh_version: str_field(data, "dshVersion"),
    dsh_package_name: str_field(data, "dshPackageName"),
    dsh_source_label: str_field(data, "dshSourceLabel"),
    dsh_candidates: candidates,
    dsh_pin_state: str_field(data, "dshPinState"),
    dsh_pin_note: str_field(data, "dshPinNote"),
    dsh_install_kind: str_field(data, "dshInstallKind"),
    dsh_install_kind_source: str_field(data, "dshInstallKindSource"),
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

// ── GET /api/local/dsh-releases ─────────────────────────────

///|
/// 一个候选版本（读数里的 versions 一项）。
///
/// 五个字段都是后端的判定，前端不自己再推：
///   prerelease  GitHub 的 release 标记 / registry 上版本号带 "-"（后端按各自的形状判）
///   latest      registry 的 dist-tags.latest 是不是它
///   next        registry 的 dist-tags.next 是不是它
///   installed   这台机器上装着这一版（与 dshCandidates 同一条链）
pub(all) struct ReleaseVersion {
  version : String
  prerelease : Bool
  latest : Bool
  next : Bool
  installed : Bool
} derive(Eq)

pub extend ReleaseVersion with Eq::{ not_equal, equal }

///|
/// 一个来源问下来的结果。ok=false 时 error 是后端给的那句人话（超时 / 连不上 / 格式不对）。
pub(all) struct ReleaseSource {
  id : String
  ok : Bool
  /// 这个源这一趟花了多少毫秒（后端量的，含 curl 起进程与解析）
  ms : Int
  error : String
  /// 这个源给出几条版本
  count : Int
} derive(Eq)

pub extend ReleaseSource with Eq::{ not_equal, equal }

///|
/// 版本来源读数（GET /api/local/dsh-releases）。
///
/// chosen 空串 = 三个源全没答上来（那时 versions 是空的 —— 界面据此换一句话，
/// 不许把「没问到」写成「没有新版」）。
pub(all) struct ReleasesFacts {
  chosen : String
  /// 采用那个源给的版本，按版本号从新到旧
  versions : Array[ReleaseVersion]
  /// registry 的 dist-tags：latest / next（GitHub 没有这两条，空串 = 没有）
  latest : String
  next : String
  /// 这台机器上装着哪几版 dsh（与 runtime 的 dshCandidates 同一条链）
  installed : Array[String]
  /// 三个源各自的结果与耗时，顺序固定 github → npm → mirror
  sources : Array[ReleaseSource]
  read_at : String
} derive(Eq)

pub extend ReleasesFacts with Eq::{ not_equal, equal }

///|
pub fn parse_releases(text : String) -> Result[ReleasesFacts, String] {
  let data = match open_envelope(text) {
    Ok(data) => data
    Err(reason) => return Err(reason)
  }
  let versions : Array[ReleaseVersion] = []
  for item in arr_field(data, "versions") {
    guard item is Json::Object(v) else { continue }
    versions.push({
      version: str_field(v, "version"),
      prerelease: bool_field(v, "prerelease"),
      latest: bool_field(v, "latest"),
      next: bool_field(v, "next"),
      installed: bool_field(v, "installed"),
    })
  }
  let sources : Array[ReleaseSource] = []
  for item in arr_field(data, "sources") {
    guard item is Json::Object(s) else { continue }
    sources.push({
      id: str_field(s, "id"),
      ok: bool_field(s, "ok"),
      ms: int_or(s, "ms", 0),
      error: str_field(s, "error"),
      count: int_or(s, "count", 0),
    })
  }
  let installed : Array[String] = []
  for item in arr_field(data, "installed") {
    match item {
      Json::String(s) => installed.push(s)
      _ => ()
    }
  }
  Ok({
    chosen: str_field(data, "chosen"),
    versions,
    latest: str_field(data, "latest"),
    next: str_field(data, "next"),
    installed,
    sources,
    read_at: str_field(data, "readAt"),
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
  // ── 配置 home（design/deep-home-isolation.md 第 4 节）──
  //
  // 后端每只 profile 给一个 home 对象：{ kind, path, profileDir, createdAt }。
  //   kind = "isolated" 这只 profile 有自己的隔离 home（<DSH_CONSOLE_HOMES_ROOT>/<名字>/）
  //   kind = "shared"   与控制台共用 DSH_HOME
  // 空串 = 这一版后端没给这一项（按「读不到」处理，界面不猜一个归属出来）。
  /// isolated / shared / 空串（读数里没有）
  home_kind : String
  /// 隔离 home 根，或控制台的 DSH_HOME
  home_path : String
  /// 实例真正读配置的目录（<path>/profiles/<名字>）
  home_profile_dir : String
  /// 隔离记录里的时刻；共用那一档没有（后端给 null）
  home_created_at : String?
  /// 后端给的一句判断依据（homeKindSource）；空串 = 这一版后端没给
  home_kind_source : String
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
    let home = obj_field(fact, "home")
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
        "这一版读数里没有「最近改动」可读"
      },
      // home 整个不在（这一版后端还没有隔离 home）时三格都是空串：
      // 界面那一格写「读不到」，**不按 dshHome 猜一个归属**出来
      home_kind: str_field(home, "kind"),
      home_path: str_field(home, "path"),
      home_profile_dir: str_field(home, "profileDir"),
      home_created_at: opt_str_field(home, "createdAt"),
      home_kind_source: str_field(fact, "homeKindSource"),
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
/// 实例对应的 profile 的健康读数（profileHealth，第七轮契约新增）。
///
/// 只报两个事实：缺几个包、有没有 cordis.patch.yml —— 卡片上那颗状态灯「黄」的
/// 成因 c 就是它们（契约里写死的判据）。包名清单不在这里：它在 profiles 读数里。
pub(all) struct InstanceHealth {
  missing_bundles : Int
  has_patch : Bool
} derive(Eq)

pub extend InstanceHealth with Eq::{ not_equal, equal }

///|
/// 同一只进程的另一个监听端口（读数里的 alsoPorts 一项）。
///
/// 后端按 pid 把条目归并成一行：只有主端口那一条成行，其余端口收在这里当附注。
/// 卡片上不显示、也不因它变色 —— 那一行说的是「这一只实例」，不是「一个端口」。
pub(all) struct AlsoPortFact {
  port : Int
  http_status : Int?
  /// 这个端口命中的判据（没命中是空串）
  signature_id : String
  /// 后端给的一句人话：这个端口是什么、这一次探测拿到了什么
  note : String
} derive(Eq)

pub extend AlsoPortFact with Eq::{ not_equal, equal }

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
  /// 这只实例**真实**的启动时刻（UTC ISO）。后端从进程起始时间推出来，不是控制台记的。
  /// None = 读不到 —— 卡片第二行的「上次启动」这时才退回控制台自己的记录
  /// （runtime.json 的 startedAt / audit.jsonl 的 start-instance）；两处都没有就不写那一行，
  /// **绝不拿一个别的时刻顶上**。
  started_at : String?
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
  /// 状态灯的三档（第七轮契约）：running / fault / starting。
  /// None = 这一版后端还没给这个字段（或给了个不是字符串的值）——
  /// 这时**不许猜颜色**：卡上那颗灯走「未知」那一档，抽屉里说清是后端没给。
  state : String?
  /// 为什么是这个状态（读数原样给；界面不直接渲染它，见 state_reason_of）。
  state_reason : String
  /// 实例对应的 profile 健康读数；None = 这一版后端没给 profileHealth。
  /// None 与「给了但缺 0 个包」不是一件事，所以用 Option 而不是拿 0 顶上。
  profile_health : InstanceHealth?
  /// 同一只进程的其余监听端口。空数组 = 这只进程只听着这一个端口，
  /// 或者这一版后端还没做归并（那一种会各占一行，不会进这里）
  also_ports : Array[AlsoPortFact]
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
      started_at: opt_str_field(fact, "startedAt"),
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
      state: state_of(fact),
      state_reason: state_reason_of(fact),
      profile_health: health_of(fact),
      also_ports: also_ports_of(fact),
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
    _ => "这一版读数里没有带令牌的地址"
  }
}

///|
/// state 字段的取值：只看它是不是一个非空字符串。
///
/// None 有两种来路，界面都要说清「不猜颜色」：字段**根本不在响应里**（这一版后端还没落地），
/// 以及字段在、但值不是能认的字符串（null / 数字 / 空串）。
/// 取值本身不在前端做业务推导 —— running / fault / starting 的判据在后端（见契约第七轮）。
fn state_of(fact : Map[String, Json]) -> String? {
  match fact.get("state") {
    Some(Json::String(s)) => if s == "" { None } else { Some(s) }
    _ => None
  }
}

///|
/// stateReason：读数给了就原样留着；字段不在时补一句人话。
///
/// **界面不再直接渲染这一句**：它是给改这个工具的人看的原文（里面有成因编号、
/// 应答标识这些内部名），抽屉正文用的是重写过的人话、悬停里是结构化的判据。
/// 留着它是为了让数据层忠实反映这一份读数，将来要给排查面板用也不必回头补。
fn state_reason_of(fact : Map[String, Json]) -> String {
  let reason = str_field(fact, "stateReason")
  if has_key(fact, "state") {
    if reason != "" {
      reason
    } else {
      "读数给了状态，但没给「为什么」"
    }
  } else {
    "这一版读数里没有状态这一项"
  }
}

///|
/// profileHealth：只在它真是一个对象时才有值。
/// 字段不在 = None（界面说「这一版后端还没给」），**不拿 missingBundles:0 顶上**：
/// 「读了、一个都不缺」与「没读到」不是一件事，顶上就把后者说成了前者。
fn health_of(fact : Map[String, Json]) -> InstanceHealth? {
  match fact.get("profileHealth") {
    Some(Json::Object(health)) =>
      Some({
        missing_bundles: int_or(health, "missingBundles", 0),
        has_patch: bool_field(health, "hasPatch"),
      })
    _ => None
  }
}

///|
/// alsoPorts：同一只进程的其余监听端口。
///
/// 字段不在 / 不是数组 = 这一版后端还没做归并 → 空数组（界面按「只听着一个端口」办）。
/// 每一项都按后端给的原文解析，缺字段不猜：端口读不出整数的那一项直接跳过，
/// 不拿 0 顶上（0 不是合法端口，写上去就是一个假端口）。
fn also_ports_of(fact : Map[String, Json]) -> Array[AlsoPortFact] {
  let out : Array[AlsoPortFact] = []
  for item in arr_field(fact, "alsoPorts") {
    guard item is Json::Object(extra) else { continue }
    match int_field(extra, "port") {
      Some(port) =>
        out.push({
          port,
          http_status: int_field(extra, "httpStatus"),
          signature_id: str_field(extra, "signatureId"),
          note: str_field(extra, "note"),
        })
      None => ()
    }
  }
  out
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
///
/// home 是这份档案属于哪个 home（多 home 之后，一份档案的身份是 home + 名字）。
/// 空串 = 这条记录没有 home：本次改动之前写下的旧记录 —— 那种记录按名字参与匹配，
/// 见 state.mbt 的 archive_record_matches_row。**字段不在就是空串**，不拿别的值顶上。
pub(all) struct ConsoleArchive {
  profile : String
  home : String
  archived_at : String
} derive(Eq)

pub extend ConsoleArchive with Eq::{ not_equal, equal }

///|
/// 回收站里的一条（GET /api/local/console 的 trash[]，第六轮契约）。
///
/// profile 名与删除时刻是后端从目录名（`<profile>-<epochMs>`）里切出来的：
/// profile 名自己允许带 `-`，所以按**最后一个** `-` 切 —— 切不出来时后端给的是
/// 「原目录名 + 时间 null」，这里照收，不在前端猜一个时刻出来。
pub(all) struct ConsoleTrash {
  /// trash 下的目录名，恢复 / 彻底删除时的 dir 参数
  dir : String
  profile : String
  /// 删除时刻（毫秒时间戳）；None = 目录名里读不出来
  deleted_at_ms : Double?
  /// 上面那个时间的来源，或读不出来的原因（后端原样给）
  deleted_at_source : String
  /// 递归数出来的普通文件个数；None = 数不动
  file_count : Int?
  /// 递归求和的字节数；None = 数不动
  bytes : Double?
  /// 文件数与体积的来源，或数不动的原因（后端原样给）
  size_source : String
} derive(Eq)

pub extend ConsoleTrash with Eq::{ not_equal, equal }

///|
/// 一条「上次启动」读数（GET /api/local/console 的 lastStarted[]）。
///
/// 后端把两份控制台记录并成一张表（runtime.json 的 startedAt、audit.jsonl 里
/// start-instance 且成功的那一笔），同一个 id 只留最近的那一条。前端只负责按 id 查。
pub(all) struct LastStartedFact {
  /// 行 id，与 Row.id 同一套：port:<端口号> / profile:<名字>
  id : String
  /// 启动时刻（UTC ISO，后端原样给）。空串 = 这一条没有可用时刻，不渲染。
  at : String
  /// 这个时刻从哪读出来的（人话，直接进悬停）
  source : String
} derive(Eq)

pub extend LastStartedFact with Eq::{ not_equal, equal }

///|
/// 一步的 evidence 对象压成一行「键=值 | 键=值」：只进悬停，不在正文里摊开。
fn evidence_text(step : Map[String, Json]) -> String {
  let parts : Array[String] = []
  for entry in step.iter() {
    let (key, value) = entry
    let text = match value {
      Json::String(s) => s
      _ => ""
    }
    parts.push(key + "=" + text)
  }
  join_with(parts, " | ")
}

///|
/// 一条作业的一句话结果：某一步的结论（维护页作业卡第二行用它）。
fn job_result_line(steps : Array[JobStepFact]) -> String {
  // 从后往前找第一条有结论的步骤：最后落定的那一步才是「现在到哪了」
  let mut text = ""
  for step in steps {
    if step.note != "" && step.state != "not-run" {
      text = step.note
    }
  }
  text
}

///|
/// 维护作业的一步（后端 jobs[].steps[] 的一项）。
///
/// evidence 已经在解析时拼成一行「键=值 | 键=值」：界面只把它放进悬停，
/// 不在正文里摊开（§6：目录路径 / 命令原文不进正文）。
pub(all) struct JobStepFact {
  key : String
  /// running / passed / failed / skipped / not-run。不认识的取值原样留着，
  /// 界面按「没验到」显示 —— 不认识的不能读成通过。
  state : String
  at : String
  note : String
  evidence : String
} derive(Eq)

pub extend JobStepFact with Eq::{ not_equal, equal }

///|
/// 一条维护作业（GET /api/local/console 的 jobs[]）。
///
/// unreadable = true 的那条是「记录读不出来」：只有 id 与 reason，没有步骤表。
/// 这种记录也必须出现在列表里（§3 第 2 条），不能因为它读不出来就当作不存在。
pub(all) struct JobFact {
  id : String
  kind : String
  title : String
  created_at : String
  updated_at : String
  step : String
  steps : Array[JobStepFact]
  anchor_version : String
  anchor_dir : String
  target_version : String
  target_dir : String
  /// 试跑用哪一只 profile（job-start 时选定）
  profile : String
  /// 开工前 dsh-pin.json 里指定过哪一版（空串 = 开工前没指定，或者那份文件读不出来）
  pin_before_version : String
  /// 开工前到底有没有那份文件。**与「有文件但里面是空」分开**：
  /// 回滚那句「恢复成开工前」到底意味着「写回一条」还是「删掉」，全看这一格
  pin_before_existed : Bool
  /// 试跑实例（pid ≤ 0 = 还没有试跑过）
  trial_pid : Int
  trial_port : Int
  trial_url : String
  trial_profile : String
  trial_started_at : String
  /// 我们收过它的时刻（空串 = 没收到过）。**它不说「现在还在不在」**
  trial_stopped_at : String
  /// 读数那一刻这只试跑实例还活着吗（后端现查进程表，见 console_api 的 trialAlive）。
  /// 这一格是「试跑实例还在跑」唯一可信的判据 —— stoppedAt 反推不出来
  trial_alive : Bool
  /// 用户给的结论：good / bad / later（空串 = 还没给）
  verdict_value : String
  unreadable : Bool
  reason : String
} derive(Eq)

pub extend JobFact with Eq::{ not_equal, equal }

///|
/// 控制台自己的状态读数。这一份不在契约里那五个只读接口之列：
/// runtime.json / archive.json 是两份状态文件，浏览器读不到文件系统，
/// 后端为此单开了一个只读端点（GET /api/local/console）。
pub(all) struct ConsoleFacts {
  state_dir : String
  settings_path : String
  archive_path : String
  /// 生效的删除方式：true = 删了进回收站，false = 硬删。None = 这一版后端没给这个字段。
  ///
  /// 为什么从这儿取：设置是懒加载的（进过设置页才有值），而删除确认框在打开之前
  /// 就得说清「删了会怎样」。这个端点在页面加载时就读了，所以它总能给一个生效值。
  delete_to_trash : Bool?
  /// 上面那个值来自文件还是默认（后端原样给）。空串 = 后端没给这一项。
  delete_to_trash_source : String
  runtime : Array[ConsoleRuntime]
  archive : Array[ConsoleArchive]
  /// 回收站条目（后端按删除时刻倒序给，最近删的在前）
  trash : Array[ConsoleTrash]
  /// 手动排序的顺序表（order.json 的原样：一个行 id 的数组，顺序即使用者拖出来的顺序）。
  ///
  /// **空数组 = 没拖过** —— 那时列表走自动排序（运行中按实例、已停止按最近改动降序）。
  /// 字段不在（这一版后端还没有它）与空数组在这里是同一件事：都退回自动排序，
  /// 因为两者的行为要求完全一样：没有顺序可用就用自动的。
  order : Array[String]
  /// order.json 的路径（后端原样给；空串 = 这一版后端没给）。只在提示里出现。
  order_path : String
  /// 每只实例 / 每只 profile 最后一次被启动的时刻（后端已按 at 降序并去重）
  last_started : Array[LastStartedFact]
  /// 维护作业（后端按 createdAt 倒序给；读不出来的记录也在这张表里，unreadable=true）
  jobs : Array[JobFact]
  /// 响应里**有没有** jobs 这个字段。与「字段在、但为空」分开：字段不在 = 这一版后端
  /// 还没有作业读数（不能说成「还没有作业」）
  jobs_present : Bool
  /// 作业文件的落盘目录（只在「记录读不出来」那一类提示里出现）
  jobs_dir : String
  /// 响应里**有没有** trash 这个字段。
  ///
  /// 与「字段在、但为空」分开：字段不在 = 这一版后端还没有这个读数（页面上要说清是读不到，
  /// 不是「回收站是空的」）；字段在且为空 = 回收站真的是空的。两种都写成空态，
  /// 就是把「还没读到」说成了「没有」✗（加载态与空态分开同一条道理）。
  trash_present : Bool
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
      home: str_field(entry, "home"),
      archived_at: str_field(entry, "archivedAt"),
    })
  }
  let trash : Array[ConsoleTrash] = []
  for item in arr_field(data, "trash") {
    guard item is Json::Object(entry) else { continue }
    trash.push({
      dir: str_field(entry, "dir"),
      profile: str_field(entry, "profile"),
      deleted_at_ms: num_field(entry, "deletedAtMs"),
      deleted_at_source: str_field(entry, "deletedAtSource"),
      file_count: int_field(entry, "fileCount"),
      bytes: num_field(entry, "bytes"),
      size_source: str_field(entry, "sizeSource"),
    })
  }
  let order : Array[String] = []
  for item in arr_field(data, "order") {
    match item {
      Json::String(id) => order.push(id)
      _ => ()
    }
  }
  let last_started : Array[LastStartedFact] = []
  for item in arr_field(data, "lastStarted") {
    guard item is Json::Object(entry) else { continue }
    let at = str_field(entry, "at")
    let id = str_field(entry, "id")
    // 没有 id 或没有时刻的条目直接丢掉：一条查不到的读数，摆在表里只会让查表的人以为有
    if id != "" && at != "" {
      last_started.push({ id, at, source: str_field(entry, "source") })
    }
  }
  let jobs : Array[JobFact] = []
  for item in arr_field(data, "jobs") {
    match item {
      Json::Object(entry) => {
        let steps : Array[JobStepFact] = []
        for step_json in arr_field(entry, "steps") {
          match step_json {
            Json::Object(step) =>
              steps.push({
                key: str_field(step, "key"),
                state: str_field(step, "state"),
                at: str_field(step, "at"),
                note: str_field(step, "note"),
                evidence: evidence_text(step),
              })
            _ => ()
          }
        }
        let anchor = obj_field(entry, "rollbackAnchor")
        let target = obj_field(entry, "target")
        let pin_before = obj_field(entry, "pinBefore")
        let trial = obj_field(entry, "trial")
        let verdict = obj_field(entry, "verdict")
        jobs.push({
          id: str_field(entry, "id"),
          kind: str_field(entry, "kind"),
          title: str_field(entry, "title"),
          created_at: str_field(entry, "createdAt"),
          updated_at: str_field(entry, "updatedAt"),
          step: str_field(entry, "step"),
          steps,
          anchor_version: str_field(anchor, "version"),
          anchor_dir: str_field(anchor, "dir"),
          target_version: str_field(target, "version"),
          target_dir: str_field(target, "dir"),
          profile: str_field(entry, "profile"),
          pin_before_version: str_field(pin_before, "version"),
          pin_before_existed: bool_field(pin_before, "existed"),
          trial_pid: int_or(trial, "pid", 0),
          trial_port: int_or(trial, "port", 0),
          trial_url: str_field(trial, "url"),
          trial_profile: str_field(trial, "profile"),
          trial_started_at: str_field(trial, "startedAt"),
          trial_stopped_at: str_field(trial, "stoppedAt"),
          trial_alive: bool_field(entry, "trialAlive"),
          verdict_value: str_field(verdict, "value"),
          unreadable: bool_field(entry, "unreadable"),
          reason: str_field(entry, "reason"),
        })
      }
      _ => ()
    }
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
    // 字段不在就是 None（界面说「暂时读不到删除方式」），不拿 false 顶上
    delete_to_trash: opt_bool_field(data, "deleteToTrash"),
    delete_to_trash_source: str_field(data, "deleteToTrashSource"),
    runtime,
    archive,
    trash,
    order,
    order_path: str_field(data, "orderPath"),
    last_started,
    jobs,
    jobs_present: has_key(data, "jobs"),
    jobs_dir: str_field(data, "jobsDir"),
    trash_present: has_key(data, "trash"),
    notes,
  })
}

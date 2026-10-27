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
fn int_field(obj : Map[String, Json], key : String) -> Int32? {
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
fn int_or(obj : Map[String, Json], key : String, fallback : Int32) -> Int32 {
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
  let root = @json.parse(text) catch {
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
      // 字段不在（这一版后端还没给）就是空串 = 不知道，与「后端读了但没这版的时间」同一副样子
      published_at: str_field(v, "publishedAt"),
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
    state: str_field(data, "state"),
    fetched_at: str_field(data, "fetchedAt"),
    stale: bool_field(data, "stale"),
    fetch_error: str_field(data, "error"),
  })
}

// ── GET /api/local/profiles ─────────────────────────────────

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
    let last_start = match fact.get("lastStart") {
      Some(Json::Object(record)) =>
        Some({
          ok: bool_field(record, "ok"),
          at: str_field(record, "at"),
          code: str_field(record, "code"),
          message: str_field(record, "message"),
          home: str_field(record, "home"),
        })
      _ => None
    }
    let snapshots : Array[SnapshotFact] = []
    for item in arr_field(fact, "snapshots") {
      guard item is Json::Object(snapshot) else { continue }
      let diffs : Array[SnapshotDiffFact] = []
      for d in arr_field(snapshot, "diff") {
        guard d is Json::Object(entry) else { continue }
        diffs.push({
          name: str_field(entry, "name"),
          state: str_field(entry, "state"),
          added: int_or(entry, "added", 0),
          removed: int_or(entry, "removed", 0),
        })
      }
      snapshots.push({
        id: str_field(snapshot, "id"),
        at: str_field(snapshot, "at"),
        reason: str_field(snapshot, "reason"),
        files: int_or(snapshot, "files", 0),
        bytes: match num_field(snapshot, "bytes") {
          Some(value) => value
          None => 0.0
        },
        diff: diffs,
      })
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
      dir_mtime_source: if has_key(fact, "dirMtimeMs") ||
        has_key(fact, "dirMtimeSource") {
        str_field(fact, "dirMtimeSource")
      } else {
        "这一版读数里没有「最近改动」可读"
      },
      // 这两格字段不在 = None：不拿 false 顶上（false 会被读成「不可用」）
      package_json_ok: opt_bool_field(fact, "packageJson"),
      web_app: opt_bool_field(fact, "webApp"),
      // home 整个不在（这一版后端还没有隔离 home）时三格都是空串：
      // 界面那一格写「读不到」，**不按 dshHome 猜一个归属**出来
      home_kind: str_field(home, "kind"),
      home_path: str_field(home, "path"),
      home_profile_dir: str_field(home, "profileDir"),
      home_created_at: opt_str_field(home, "createdAt"),
      home_kind_source: str_field(fact, "homeKindSource"),
      repair_command: str_field(fact, "repairCommand"),
      external_links: int_or(fact, "externalLinks", 0),
      broken_links: int_or(fact, "brokenLinks", 0),
      snapshots,
      last_start,
      // 字段整个不在（这一版后端还没落地）时补一句前端自己的话：
      // 那与「后端读了但没有」不是同一件事，不能都写成空。
      last_start_source: if has_key(fact, "lastStartSource") {
        str_field(fact, "lastStartSource")
      } else if has_key(fact, "lastStart") {
        "读数里没有给这条记录的来源"
      } else {
        "这一版读数里没有「上一次启动」这一项"
      },
      snapshots_source: if has_key(fact, "snapshotsSource") {
        str_field(fact, "snapshotsSource")
      } else if has_key(fact, "snapshots") {
        "读数里没有给快照来源"
      } else {
        "这一版读数里没有「配置快照」这一项"
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

// ── 整体替换的预览（design/ops-maintenance-jobs.md §17.1）──────────
//
// 预览是后端算好的一整份事实（promote-preview 的 outcome），前端只负责摆：
// 文件 / 插件清单 / 覆盖项 / 本地包 / blockers。**不在前端自己比一遍** ——
// 两边各算一次迟早会与真正会写到磁盘上的那一份对不上。

///|
/// 取一个字符串数组字段（不是数组 / 元素不是字符串都按空处理）。
fn json_str_array(obj : Map[String, Json], key : String) -> Array[String] {
  let out : Array[String] = []
  for item in arr_field(obj, key) {
    match item {
      Json::String(text) => out.push(text)
      _ => ()
    }
  }
  out
}

///|
/// 预览里的一边。
fn parse_promote_side(obj : Map[String, Json]) -> PromoteSide {
  {
    name: str_field(obj, "name"),
    dir: str_field(obj, "dir"),
    home_kind: str_field(obj, "homeKind"),
    home_path: str_field(obj, "homePath"),
    profile_dir: str_field(obj, "profileDir"),
    config_ok: bool_field(obj, "configOk"),
  }
}

///|
/// 覆盖项里的两种行（新增 / 移除 / 改写）。
fn parse_patch_entries(
  obj : Map[String, Json],
  key : String,
) -> Array[PromotePatchEntry] {
  let out : Array[PromotePatchEntry] = []
  for item in arr_field(obj, key) {
    guard item is Json::Object(entry) else { continue }
    out.push({ id: str_field(entry, "id"), text: str_field(entry, "text"), })
  }
  out
}

///|
fn parse_patch_changes(
  obj : Map[String, Json],
  key : String,
) -> Array[PromotePatchChange] {
  let out : Array[PromotePatchChange] = []
  for item in arr_field(obj, key) {
    guard item is Json::Object(entry) else { continue }
    out.push({
      id: str_field(entry, "id"),
      source_text: str_field(entry, "sourceText"),
      target_text: str_field(entry, "targetText"),
    })
  }
  out
}

///|
fn parse_package_versions(
  obj : Map[String, Json],
  key : String,
) -> Array[PromotePackageVersion] {
  let out : Array[PromotePackageVersion] = []
  for item in arr_field(obj, key) {
    guard item is Json::Object(entry) else { continue }
    out.push({
      name: str_field(entry, "name"),
      source_version: str_field(entry, "sourceVersion"),
      target_version: str_field(entry, "targetVersion"),
    })
  }
  out
}

///|
/// promote-preview 的回执 → 预览读数。
///
/// 输的是传输层原样带回来的那段 JSON（{status,statusText,body,transportError}）：
/// 非 2xx 时把后端错误壳里的 code 与 message 原样交回去（blockers 那句话就在这里）。
pub fn parse_promote_preview(raw : String) -> Result[PromotePreview, String] {
  let got = parse_http_result(raw)
  if got.status == 0 {
    return Err("这一步没发出去（" + got.transport_error + "）")
  }
  if got.status < 200 || got.status >= 300 {
    return Err(failure_note(got))
  }
  let data = match open_envelope(got.body) {
    Ok(data) => data
    Err(reason) => return Err(reason)
  }
  let outcome = obj_field(data, "outcome")
  let bundles = obj_field(outcome, "bundles")
  let patches = obj_field(outcome, "patches")
  let packages = obj_field(outcome, "packages")
  Ok({
    source: parse_promote_side(obj_field(outcome, "from")),
    target: parse_promote_side(obj_field(outcome, "to")),
    files: json_str_array(outcome, "files"),
    files_written: json_str_array(outcome, "filesWritten"),
    files_target_only: json_str_array(outcome, "filesTargetOnly"),
    bundles_added: json_str_array(bundles, "added"),
    bundles_removed: json_str_array(bundles, "removed"),
    bundles_reordered: bool_field(bundles, "reordered"),
    bundles_from: json_str_array(bundles, "fromOrder"),
    bundles_to: json_str_array(bundles, "toOrder"),
    patches_added: parse_patch_entries(patches, "added"),
    patches_changed: parse_patch_changes(patches, "changed"),
    patches_removed: parse_patch_entries(patches, "removed"),
    patches_anonymous: int_or(patches, "anonymous", 0),
    packages_added: json_str_array(packages, "added"),
    packages_mismatch: parse_package_versions(packages, "versionMismatch"),
    blockers: json_str_array(outcome, "blockers"),
    notes: json_str_array(outcome, "notes"),
  })
}

// ── GET /api/local/instances ────────────────────────────────

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
      home_kind: str_field(fact, "homeKind"),
      home_kind_source: str_field(fact, "homeKindSource"),
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
      last_started.push({ id, at, source: str_field(entry, "source"), })
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
          trial_home: str_field(trial, "home"),
          trial_home_kind: str_field(trial, "homeKind"),
          trial_profile_copy: str_field(trial, "profileCopy"),
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
    build_sha: str_field(data, "buildSha"),
    build_at: str_field(data, "buildAt"),
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

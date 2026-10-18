// GET /api/local/profiles 的数据体。
//
// 字段与 Node 版 server/readProfiles.mjs 的返回值逐字段一致：
//   { dshHome, dshHomeSource, profilesRoot, currentProfile, profiles: [...] }
// 每个 profile：
//   { name, dir, isCurrent, packageName, bundles: { declared, installed,
//     installedInProfile, installedHoisted, missing }, patch: { exists, lines },
//     lock: { exists, mtime }, note, noteSource, dirMtimeMs, dirMtimeSource }
// 读不到的字段给 null / 0 / []，不编造。
//
// note / noteSource 是第二轮契约新增的加字段（旧消费者忽略即可）：
// 备注放在 <profile 目录>/.dsh-note.txt，读到了给原文 + "文件"；
// 没有这个文件给空串 + "默认"；有文件读不动给空串 + "默认（原因）"——
// 与设置那边的 sources 口径一致，读不到就说读不到，不编内容。
//
// dirMtimeMs / dirMtimeSource 是第五轮契约新增的加字段：profile **目录**的 mtime
// （毫秒），卡片第六格「最近改动」用它，列表排序也用它——口径是"最近改动"而不是
// "创建时间"（见 README：多数文件系统上可靠的创建时间拿不到）。读不到给 null + 原因。

///|
/// 扫描时跳过的目录（与 Node 版 SKIP_DIRS 一致，不做递归）。
let skip_dirs : Array[String] = ["node_modules", ".git", ".cache"]

///|
/// profile 备注文件名（第二轮契约）：<profile 目录>/.dsh-note.txt。
/// 放在目录里的理由只有一个 —— 派生是整目录拷贝、改名是整目录改名，备注跟着走。
pub let note_file_name : String = ".dsh-note.txt"

///|
/// 备注长度上限。按 UTF-16 码元数（String::length）算，写侧与读侧同一把尺子。
pub let note_max_chars : Int = 2000

///|
/// 读一个 profile 目录里的备注，返回 (备注文本, 来源)。
///   有文件且读得动 -> (原文, "文件")
///   没有这个文件   -> ("", "默认")
///   有文件读不动   -> ("", "默认（读取失败：…）")
pub async fn read_profile_note(dir : String) -> (String, String) noraise {
  let path = @json.join_path(dir, note_file_name)
  if !@json.exists(path) {
    return ("", "默认")
  }
  match @json.read_text_file(path) {
    Ok(text) => (text, "文件")
    Err(e) => ("", "默认（" + path + " 读取失败：" + e + "）")
  }
}

///|
/// 读一个 profile **目录**的 mtime（毫秒），返回 (毫秒, 来源说明)。
///   读得到 -> (Some ms, "<路径> 的 mtime")
///   读不到 -> (None,   "<路径> 读不到 mtime：…")
///
/// 为什么用目录 mtime：契约第五轮写明"最近改动"是能拿到且不会骗人的那个值
/// （ctime 会在 chmod / 改名时变，birth time 不通用）。派生会写进这个目录，
/// 所以刚派生出来的 profile 一定是 mtime 最新的那一个。
pub async fn read_profile_dir_mtime(dir : String) -> (Int64?, String) noraise {
  match @json.mtime_ms(dir) {
    Some(ms) => (Some(ms), dir + " 的 mtime")
    None => (None, dir + " 读不到 mtime")
  }
}

///|
/// 一个已解析 profile 的体检结论（第七轮契约第一节的 profileHealth）：
///   缺包数 = package.json 里 dsh.profile.bundles 声明了、但 profile 自己的 node_modules
///   与共享的 profiles/node_modules 里都没有 package.json 的包个数；
///   hasPatch = profile 目录里有没有 cordis.patch.yml。
/// 缺的包名一并带上，状态原因里才说得清是哪几个（前端只读 missingBundles / hasPatch）。
pub(all) struct ProfileHealth {
  missing_bundles : Int
  missing_names : Array[String]
  has_patch : Bool
  dir : String
}

///|
/// 把 profile 名解析成 <dsh_home>/profiles/<name>；名字必须是单段（防目录穿越）。
/// 空名、"."、".."、带路径分隔符的都拒 —— 与 set-profile-note / open-path 同款的一道校验。
pub fn profile_dir_of(dsh_home : String, name : String) -> String? {
  if name == "" || name == "." || name == ".." {
    return None
  }
  if @json.index_of(name, "/") is Some(_) {
    return None
  }
  if @json.index_of(name, "\\") is Some(_) {
    return None
  }
  Some(@json.join_all([dsh_home, "profiles", name]))
}

///|
/// 体检一只已经解析出来的 profile。目录不存在、名字不合法都给 None（不编值）。
pub async fn profile_health(dsh_home : String, name : String) -> ProfileHealth? noraise {
  let dir = match profile_dir_of(dsh_home, name) {
    Some(d) => d
    None => return None
  }
  if !@json.is_dir(dir) {
    return None
  }
  let shared = @json.join_all([dsh_home, "profiles", "node_modules"])
  let missing : Array[String] = []
  for b in declared_bundles(dir) {
    if locate_bundle_nr(b, dir, shared) == "missing" {
      missing.push(b)
    }
  }
  Some({
    missing_bundles: missing.length(),
    missing_names: missing,
    has_patch: @json.exists(@json.join_path(dir, "cordis.patch.yml")),
    dir,
  })
}

///|
/// 派生时给新 profile 写的备注（第五轮契约第二节）：
/// 第一行是它的来历 `从 <源> 派生 · <本地时间>`，源 profile 原有的备注**原样接在后面**。
///
/// 为什么覆盖而不是不管：派生是整目录拷贝，源 profile 的备注会被一起拷过来，
/// 那条备注讲的是**源**的事，直接留着会误导 —— 所以新 profile 的第一行必须是它的来历。
/// 总长按备注上限（`note_max_chars`）截断：第一行短、永远是完整的，被截掉的只会是尾部。
pub fn fork_note_text(source_name : String, stamp : String, source_note : String) -> String {
  let head = "从 " + source_name + " 派生 · " + stamp
  if source_note == "" {
    return @json.slice(head, 0, note_max_chars)
  }
  @json.slice(head + "\n" + source_note, 0, note_max_chars)
}

///|
/// 按 UTF-16 码元逐位比较，等同 JS 的 `a < b` 字符串序。
/// 不能用 String::compare：core 的实现先比长度再比字符，
/// 对 "web" / "headless" 会给出与 JS 相反的顺序。
fn compare_code_units(a : String, b : String) -> Int {
  let n = if a.length() < b.length() { a.length() } else { b.length() }
  for i = 0; i < n; i = i + 1 {
    let x = a.unsafe_get(i).to_int()
    let y = b.unsafe_get(i).to_int()
    if x != y {
      return if x < y { -1 } else { 1 }
    }
  }
  if a.length() == b.length() {
    0
  } else if a.length() < b.length() {
    -1
  } else {
    1
  }
}

///|
/// 一个被声明的 bundle 及其安装位置。
priv struct Bundle {
  name : String
  installed : String
}

///|
/// 一个包的落盘位置：profile 自己的 node_modules -> hoisted（profiles/ 共享）-> missing。
async fn locate_bundle_nr(name : String, profile_dir : String, shared_dir : String) -> String noraise {
  if @json.exists(@json.join_all([profile_dir, "node_modules", name, "package.json"])) {
    return "profile"
  }
  if @json.exists(@json.join_all([shared_dir, name, "package.json"])) {
    return "hoisted"
  }
  "missing"
}

///|
/// 读 profile 的 package.json，取 dsh.profile.bundles 声明（不是数组就按空处理）。
async fn declared_bundles(dir : String) -> Array[String] noraise {
  let text = match @json.read_text_file(@json.join_path(dir, "package.json")) {
    Ok(t) => t
    Err(_) => return []
  }
  let json = match @json.json_parse(text) {
    Some(j) => j
    None => return []
  }
  let dsh = match @json.json_field(json, "dsh") {
    Some(v) => v
    None => return []
  }
  let profile = match @json.json_field(dsh, "profile") {
    Some(v) => v
    None => return []
  }
  let bundles = match @json.json_field(profile, "bundles") {
    Some(v) => v
    None => return []
  }
  let out : Array[String] = []
  for item in @json.json_array(Some(bundles)) {
    match @json.json_string(item) {
      Some(s) => out.push(s)
      None => ()
    }
  }
  out
}

///|
/// package.json 里的 name 字段；读不到给 None（Node 侧给 null）。
async fn package_name(dir : String) -> String? noraise {
  let text = match @json.read_text_file(@json.join_path(dir, "package.json")) {
    Ok(t) => t
    Err(_) => return None
  }
  let json = match @json.json_parse(text) {
    Some(j) => j
    None => return None
  }
  match @json.json_field(json, "name") {
    Some(v) => @json.json_string(v)
    None => None
  }
}

///|
/// 数一份文本的行数，与 Node 版一致：去掉末尾单个换行后再数。
/// Node: `text === '' ? 0 : text.replace(/\n$/, '').split('\n').length`
fn count_lines(text : String) -> Int {
  let t = if text.has_suffix("\n") {
    text[:text.length() - 1].to_owned()
  } else {
    text
  }
  if t == "" {
    0
  } else {
    t.split("\n").count()
  }
}

///|
/// 描述一个 profile。
async fn describe_profile(
  name : String,
  dir : String,
  shared_dir : String,
  current_profile : String?,
  dsh_home : String,
  dsh_home_source : String,
) -> @json.JsonVal noraise {
  let declared = declared_bundles(dir)
  let bundles : Array[Bundle] = []
  for b in declared {
    bundles.push({ name: b, installed: locate_bundle_nr(b, dir, shared_dir) })
  }
  let missing : Array[String] = []
  let mut installed_in_profile = 0
  let mut installed_hoisted = 0
  for b in bundles {
    match b.installed {
      "profile" => installed_in_profile = installed_in_profile + 1
      "hoisted" => installed_hoisted = installed_hoisted + 1
      _ => missing.push(b.name)
    }
  }

  let patch_file = @json.join_path(dir, "cordis.patch.yml")
  let patch_exists = @json.exists(patch_file)
  let mut patch_lines = 0
  if patch_exists {
    match @json.read_text_file(patch_file) {
      Ok(text) => patch_lines = count_lines(text)
      Err(_) => patch_lines = 0
    }
  }

  let (note, note_source) = read_profile_note(dir)
  let (dir_mtime, dir_mtime_source) = read_profile_dir_mtime(dir)

  let lock_exists = @json.exists(@json.join_path(dir, "pnpm-lock.yaml"))
  let lock_mtime = if lock_exists {
    @json.mtime_ms(@json.join_path(dir, "pnpm-lock.yaml"))
  } else {
    None
  }

  // 这只 profile 的 home 归属（隔离 / 共用）：判据与读数都在 homes.mbt，前端不自己再推一遍。
  // dsh_home 是控制台自己的 home —— 「共用」那一档的 path 就是它。
  let home = home_fact_in(name, dsh_home, dsh_home_source)

  @json.JObj([
    ("name", @json.JStr(name)),
    ("dir", @json.JStr(dir)),
    // 隔离 home 读数（design/deep-home-isolation.md 第 4 节）：
    //   kind        isolated / shared
    //   path        隔离 home 根 或 控制台的 DSH_HOME
    //   profileDir  实例真正读配置的目录（<path>/profiles/<名字>）
    //   createdAt   隔离记录里的时刻（没有隔离就是 null，那一档没有「建于」可言）
    ("home", @json.JObj([
      ("kind", @json.JStr(home.kind)),
      ("path", @json.JStr(home.path)),
      ("profileDir", @json.JStr(home.profile_dir)),
      ("createdAt", @json.str_or_null(home.created_at)),
    ])),
    // 一句判断依据：这一档是凭什么判出来的（前端只显示，不再推）
    ("homeKindSource", @json.JStr(home.source)),
    (
      "isCurrent",
      @json.JBool(match current_profile {
        Some(c) => c == name
        None => false
      }),
    ),
    ("packageName", @json.str_or_null(package_name(dir))),
    ("bundles", @json.JObj([
      ("declared", @json.jint(bundles.length())),
      ("installed", @json.jint(bundles.length() - missing.length())),
      ("installedInProfile", @json.jint(installed_in_profile)),
      ("installedHoisted", @json.jint(installed_hoisted)),
      ("missing", @json.JArr(missing.map(fn(m) { @json.JStr(m) }))),
    ])),
    ("patch", @json.JObj([
      ("exists", @json.JBool(patch_exists)),
      ("lines", @json.jint(patch_lines)),
    ])),
    ("note", @json.JStr(note)),
    ("noteSource", @json.JStr(note_source)),
    ("dirMtimeMs", @json.int64_or_null(dir_mtime)),
    ("dirMtimeSource", @json.JStr(dir_mtime_source)),
    ("lock", @json.JObj([
      ("exists", @json.JBool(lock_exists)),
      (
        "mtime",
        @json.str_or_null(match lock_mtime {
          Some(ms) => Some(@json.iso_from_epoch_ms(ms))
          None => None
        }),
      ),
    ])),
  ])
}

///|
/// 组装 /api/local/profiles 的 data 对象。
pub async fn read_profiles() -> @json.JsonVal raise @localapi.ReadError {
  let (dsh_home, dsh_home_source) = @runtime.resolve_dsh_home()
  let root = @json.join_path(dsh_home, "profiles")
  if !@json.is_dir(root) {
    @localapi.fail_read("profiles-missing", "profiles 目录不存在：\{root}")
  }
  let current_profile = @json.env_raw("DSH_PROFILE")
  let shared_dir = @json.join_path(root, "node_modules")
  let entries = @json.list_entries(root)
  let names : Array[String] = []
  for entry in entries {
    let is_skipped = skip_dirs.any(fn(s) { s == entry.0 })
    if entry.1 && !is_skipped {
      names.push(entry.0)
    }
  }
  names.sort_by(compare_code_units)
  let profiles : Array[@json.JsonVal] = []
  for name in names {
    profiles.push(
      describe_profile(
        name,
        @json.join_path(root, name),
        shared_dir,
        current_profile,
        dsh_home,
        dsh_home_source,
      ),
    )
  }
  @json.JObj([
    ("dshHome", @json.JStr(dsh_home)),
    ("dshHomeSource", @json.JStr(dsh_home_source)),
    ("profilesRoot", @json.JStr(root)),
    ("currentProfile", @json.str_or_null(current_profile)),
    ("profiles", @json.JArr(profiles)),
  ])
}
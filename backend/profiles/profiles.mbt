// GET /api/local/profiles 的数据体。
//
// 字段与 Node 版 server/readProfiles.mjs 的返回值逐字段一致：
//   { dshHome, dshHomeSource, profilesRoot, currentProfile, profiles: [...] }
// 每个 profile：
//   { name, dir, isCurrent, packageName, bundles: { declared, installed,
//     installedInProfile, installedHoisted, missing }, patch: { exists, lines },
//     lock: { exists, mtime } }
// 读不到的字段给 null / 0 / []，不编造。

///|
/// 扫描时跳过的目录（与 Node 版 SKIP_DIRS 一致，不做递归）。
let skip_dirs : Array[String] = ["node_modules", ".git", ".cache"]

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

  let lock_exists = @json.exists(@json.join_path(dir, "pnpm-lock.yaml"))
  let lock_mtime = if lock_exists {
    @json.mtime_ms(@json.join_path(dir, "pnpm-lock.yaml"))
  } else {
    None
  }

  @json.JObj([
    ("name", @json.JStr(name)),
    ("dir", @json.JStr(dir)),
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
    profiles.push(describe_profile(name, @json.join_path(root, name), shared_dir, current_profile))
  }
  @json.JObj([
    ("dshHome", @json.JStr(dsh_home)),
    ("dshHomeSource", @json.JStr(dsh_home_source)),
    ("profilesRoot", @json.JStr(root)),
    ("currentProfile", @json.str_or_null(current_profile)),
    ("profiles", @json.JArr(profiles)),
  ])
}
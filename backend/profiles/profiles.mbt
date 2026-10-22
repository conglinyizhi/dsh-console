// GET /api/local/profiles 的数据体。
//
// 字段与 Node 版 server/readProfiles.mjs 的返回值逐字段一致：
//   { dshHome, dshHomeSource, profilesRoot, currentProfile, profiles: [...] }
// 每个 profile：
//   { name, dir, isCurrent, packageName, bundles: { declared, installed,
//     installedInProfile, installedHoisted, missing }, patch: { exists, lines },
//     lock: { exists, mtime }, note, noteSource, dirMtimeMs, dirMtimeSource,
//     packageJson, webApp }
//
// packageJson / webApp 是维护页试跑那一块要用的两条事实（design/ops-maintenance-jobs.md §9.3）：
//   packageJson  package.json 在、且读得动（false = 这只配置读不到）
//   webApp       dsh.profile.bundles 里有没有 @deepseek-ai/dsh-web-app
//                （false = 这只起的是命令行型，没有网页入口）
// 缺包（bundles.missing 非空）不算不可用，前端自己旁边注一句。
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
/// 起网页实例用的那只 bundle 名（§9.3 第 2 条判据：bundles 里没有它 = 命令行型）。
pub let web_app_bundle : String = "@deepseek-ai/dsh-web-app"

///|
/// 扫描时跳过的目录（与 Node 版 SKIP_DIRS 一致，不做递归）。
let skip_dirs : Array[String] = ["node_modules", ".git", ".cache"]

///|
/// profile 备注文件名（第二轮契约）：<profile 目录>/.dsh-note.txt。
/// 放在目录里的理由只有一个 —— 派生是整目录拷贝、改名是整目录改名，备注跟着走。
pub let note_file_name : String = ".dsh-note.txt"

///|
/// 备注长度上限。按 UTF-16 码元数（String::length）算，写侧与读侧同一把尺子。
pub let note_max_chars : Int32 = 2000

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
  match @json.read_text_file_fs(path) {
    Ok(text) => (text, "文件")
    Err(_) => ("", "默认（" + path + " 读取失败）")
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
  missing_bundles : Int32
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
pub async fn profile_health(
  dsh_home : String,
  name : String,
) -> ProfileHealth? noraise {
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
/// 去掉末尾多余的斜杠（保留根 /）：/a/b 与 /a/b/ 是同一个 home。
fn trim_home_slash(path : String) -> String {
  let mut end = path.length()
  while end > 1 && @json.slice(path, end - 1, end) == "/" {
    end = end - 1
  }
  @json.slice(path, 0, end)
}

///|
/// 两个 home 说的是不是同一个目录：只做「逐字相等，或只差一个尾部斜杠」。
/// 空串一律不算相等（不知道就不认 —— 与界面那一侧 same_home 同一口径）。
fn same_home_text(a : String, b : String) -> Bool {
  if a == "" || b == "" {
    return false
  }
  trim_home_slash(a) == trim_home_slash(b)
}

///|
/// 这只 profile **最近一次启动**的结局（design/design-fixes.md §26.1、§27.1）：
///   最近一条启动记录是失败 → 红灯「上次启动失败」（失败之后没有成功过：
///   真有过一次成功，那一次就是最近那一条）；
///   最近一条是成功 → 不是故障，按其余三档；
///   一条记录都没有 → None（没有证据就不点红灯）。
///
/// 「启动记录」两种都算：start-instance 与 restart-instance（§27.1 之前只认前者，
/// 一次失败的重启因此改不了判据）。来源说明里点名这一笔是哪种动作。
///
/// 一行审计算不算这只 profile 的启动记录，按它带的 home 分三种：
///   ① 带 home，且等于这只 profile 自己的 home（隔离的那一档）：算，最准；
///   ② 没带 home（调用方只发了名字的老记录，或界面起共用那一只时的口径）：按名字算；
///   ③ 带的是控制台的 home（共用那一档）：按名字算；
///   其余（别的 home 里同名的那一只、试跑的一次性 home）：不算，别拿它顶。
///
/// **「最近」是这些行里 at 最大的那一条**，不是「先按 home 筛一遍再比」：
/// 同一只 profile 的记录会落在不同的 home 槽里（start-instance 带不带 home 看调用方，
/// restart-instance 一定带），分槽各留一条之后，先按 home 筛出来的那一条可能比
/// 无 home 槽里那条更旧。§27.1 的验收正是踩在这一条上：失败的重启之后成功启动一次，
/// 判据必须回到不红。
///
/// attempts 已按 at 降序（见 store/startattempt.mbt），所以顺着走、第一条算数的就是最近的。
fn last_start_of(
  name : String,
  profile_home : String,
  console_home : String,
  attempts : Array[@store.StartAttempt],
  notes : Array[String],
) -> (@store.StartAttempt?, String) {
  for a in attempts {
    if a.profile != name {
      continue
    }
    if profile_home != "" && same_home_text(a.home, profile_home) {
      return (
        Some(a),
        "audit.jsonl 里最近一条启动记录（action=" +
        a.action +
        "）：params.home 就是这只 profile 的 home（" +
        a.home +
        "）",
      )
    }
    if a.home == "" {
      return (
        Some(a),
        "audit.jsonl 里最近一条启动记录（action=" +
        a.action +
        "）；那一笔没带 home，按 profile 名对上",
      )
    }
    if same_home_text(a.home, console_home) {
      return (
        Some(a),
        "audit.jsonl 里最近一条启动记录（action=" +
        a.action +
        "）：params.home 是控制台的 home（" +
        a.home +
        "）",
      )
    }
  }
  if notes.length() > 0 {
    return (None, notes.join("；"))
  }
  if attempts.length() == 0 {
    return (
      None,
      "audit.jsonl 里没有启动记录（start-instance 与 restart-instance 都没有，这台机器还没用控制台起过实例）",
    )
  }
  (
    None,
    "audit.jsonl 里没有这只 profile（" +
    name +
    "）的启动记录（start-instance 与 restart-instance 都没有）",
  )
}

///|
/// 派生时给新 profile 写的备注（第五轮契约第二节）：
/// 第一行是它的来历 `从 <源> 派生 · <本地时间>`，源 profile 原有的备注**原样接在后面**。
///
/// 为什么覆盖而不是不管：派生是整目录拷贝，源 profile 的备注会被一起拷过来，
/// 那条备注讲的是**源**的事，直接留着会误导 —— 所以新 profile 的第一行必须是它的来历。
/// 总长按备注上限（`note_max_chars`）截断：第一行短、永远是完整的，被截掉的只会是尾部。
pub fn fork_note_text(
  source_name : String,
  stamp : String,
  source_note : String,
) -> String {
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
fn compare_code_units(a : String, b : String) -> Int32 {
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
async fn locate_bundle_nr(
  name : String,
  profile_dir : String,
  shared_dir : String,
) -> String noraise {
  if @json.exists(
      @json.join_all([profile_dir, "node_modules", name, "package.json"]),
    ) {
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
  let text = match @json.read_text_file_fs(@json.join_path(dir, "package.json")) {
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
/// 这只 profile 该用哪条命令补包（design/design-fixes.md §39.2）：
/// 有 pnpm-lock.yaml 用 pnpm、有 package-lock.json 用 npm，都没有按 pnpm
/// （控制台自己这套生态就是 pnpm，缺 lock 时它最可能是这个项目的包管理器）。
pub async fn repair_command_of(dir : String) -> String noraise {
  repair_manager_of(dir) + " install --prefer-offline"
}

///|
/// 这只 profile 该用哪个包管理器（§F）：
/// 先认 package.json 的 packageManager 字段（"pnpm@9.1.0" → "pnpm"），
/// 再按 lock 文件：pnpm-lock.yaml → pnpm、package-lock.json → npm，都没有按 pnpm。
pub async fn repair_manager_of(dir : String) -> String noraise {
  match package_manager_field(dir) {
    Some(name) => name
    None =>
      if @json.exists(@json.join_path(dir, "package-lock.json")) &&
        !@json.exists(@json.join_path(dir, "pnpm-lock.yaml")) {
        "npm"
      } else {
        "pnpm"
      }
  }
}

///|
/// package.json 里声明的 packageManager（只取 @ 前面那段；读不到给 None）。
async fn package_manager_field(dir : String) -> String? noraise {
  let text = match @json.read_text_file_fs(@json.join_path(dir, "package.json")) {
    Ok(t) => t
    Err(_) => return None
  }
  let json = match @json.json_parse(text) {
    Some(j) => j
    None => return None
  }
  let raw = match @json.json_field(json, "packageManager") {
    Some(v) =>
      match @json.json_string(v) {
        Some(s) => s
        None => return None
      }
    None => return None
  }
  let trimmed = @json.trim_both(raw)
  if trimmed == "" {
    return None
  }
  match @json.index_of(trimmed, "@") {
    Some(i) => Some(@json.slice(trimmed, 0, i))
    None => Some(trimmed)
  }
}

///|
/// 这个可执行文件在不在 PATH 上（返回找到的绝对路径，找不到给 None）。
/// 不跑子进程：直接扫 PATH 里的目录，省得等一次 spawn。
pub async fn manager_in_path(name : String) -> String? noraise {
  let path = match @json.env_value("PATH") {
    Some(p) => p
    None => return None
  }
  for part in path.split(":") {
    let dir = @json.owned(part)
    let candidate = @json.join_path(dir, name)
    if @json.exists(candidate) {
      return Some(candidate)
    }
  }
  None
}

///|
/// 补包前先拦住的那几种情况（§F）：真拦下来时给一句人话，能跑就给 None。
/// · 这只 profile 用 Yarn PnP（有 .pnp.cjs）→ 不走 node_modules，控制台不代跑；
/// · 选中的包管理器不在 PATH 上 → 直接说「这台机器上没有包管理器」，别等超时。
pub async fn repair_refusal(dir : String) -> (String, String)? noraise {
  let manager = repair_manager_of(dir)
  if manager == "yarn" && @json.exists(@json.join_path(dir, ".pnp.cjs")) {
    return Some(
      (
        "unsupported-manager",
        "这只 profile 用的是 Yarn PnP（有 .pnp.cjs）：包不在 node_modules 里，补包得用它自己的 yarn，" +
        "控制台不代跑。",
      ),
    )
  }
  match manager_in_path(manager) {
    Some(_) => None
    None =>
      Some(
        (
          "no-package-manager",
          "这台机器上没有包管理器：" +
          manager +
          " 不在 PATH 上（补包要它；先装上或换一只 profile）",
        ),
      )
  }
}

///|
/// 同一条命令的 argv 形状（跑的时候用这个，不经过 shell）。
pub async fn repair_argv_of(dir : String) -> Array[String] noraise {
  if @json.exists(@json.join_path(dir, "pnpm-lock.yaml")) {
    ["pnpm", "install", "--prefer-offline"]
  } else if @json.exists(@json.join_path(dir, "package-lock.json")) {
    ["npm", "install", "--prefer-offline"]
  } else {
    ["pnpm", "install", "--prefer-offline"]
  }
}

///|
/// 这只 profile 现在缺哪些包：按 package.json 里 dsh.profile.bundles 逐条看落盘位置
/// （profile 自己的 node_modules → hoisted → 缺）。与读数那一份同一把尺子（locate_bundle_nr），
/// 所以「修完还剩几个」与界面上那个数永远对得上。
pub async fn missing_bundles_in(
  dir : String,
  shared_dir : String,
) -> Array[String] noraise {
  let out : Array[String] = []
  for name in declared_bundles(dir) {
    if locate_bundle_nr(name, dir, shared_dir) == "missing" {
      out.push(name)
    }
  }
  out
}

///|
/// package.json 在不在、读不读得动（"这只 profile 的配置读得到吗"的判据）。
/// 只 stat + 解析，不改内容。
async fn package_json_ok(dir : String) -> Bool noraise {
  match @json.read_text_file_fs(@json.join_path(dir, "package.json")) {
    Err(_) => false
    Ok(text) =>
      match @json.json_parse(text) {
        Some(_) => true
        None => false
      }
  }
}

///|
/// 试跑 / 开工前的硬校验（design/ops-maintenance-jobs.md §11.2）：
/// 这只 profile 的配置读得到吗、是不是网页型。
///
/// 返回 None = 通过；Some(一句人话) = 拒掉的原因。两条判据都只看读到的事实：
///   1. 目录在、package.json 读得动且是合法 JSON（缺一样都算「读不到配置」）；
///   2. dsh.profile.bundles 里有 @deepseek-ai/dsh-web-app（没有就起不了网页实例）。
/// 缺包（bundles.missing 非空）**不算**不通过：那只影响「可能起不来」，由界面另行注明。
pub async fn trial_profile_blocker(
  dsh_home : String,
  name : String,
) -> String? noraise {
  // 目录按这只 profile **现在在哪儿**取：隔离的那一只在自己的 home 里（真移动之后
  // 共用 home 的 profiles/ 下没有它，按 dsh_home 拼就会把一个好好的配置报成「读不到」）。
  // profile_dir_of 那一道仍先过：名字不合法的直接拒，不往下走。
  let dir = match profile_dir_of(dsh_home, name) {
    Some(_) => {
      let (resolved, _home) = profile_location(name)
      resolved
    }
    None =>
      return Some(
        "这只配置读不到，没法试跑（profile 名认不出来：" +
        name +
        "）",
      )
  }
  if !@json.is_dir(dir) {
    return Some(
      "这只配置读不到，没法试跑（" + dir + " 不存在）",
    )
  }
  if !package_json_ok(dir) {
    return Some(
      "这只配置读不到，没法试跑（" +
      dir +
      "/package.json 读不出来或不是合法 JSON）",
    )
  }
  if !declared_bundles(dir).contains(web_app_bundle) {
    return Some("这只配置起不了网页实例：没有 " + web_app_bundle)
  }
  None
}

///|
/// package.json 里的 name 字段；读不到给 None（Node 侧给 null）。
async fn package_name(dir : String) -> String? noraise {
  let text = match @json.read_text_file_fs(@json.join_path(dir, "package.json")) {
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
fn count_lines(text : String) -> Int32 {
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
  attempts : Array[@store.StartAttempt],
  attempts_note : Array[String],
) -> @json.JsonVal noraise {
  let declared = declared_bundles(dir)
  let bundles : Array[Bundle] = []
  for b in declared {
    bundles.push({ name: b, installed: locate_bundle_nr(b, dir, shared_dir), })
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
    match @json.read_text_file_fs(patch_file) {
      Ok(text) => patch_lines = count_lines(text)
      Err(_) => patch_lines = 0
    }
  }

  // 外部 / 坏软链接（§60.1）：派生副本前要告知「藕断丝连」。坏链接只进读数供排查。
  let (external, broken) = link_counts_in(dir)
  let pkg_ok = package_json_ok(dir)
  let (note, note_source) = read_profile_note(dir)
  let (dir_mtime, dir_mtime_source) = read_profile_dir_mtime(dir)
  // 配置快照（design/ops-maintenance-jobs.md 第 16.2 节）：从新到旧，读不出来给空数组与原因。
  let (snapshots, snapshots_source) = read_snapshots(dir)

  let lock_exists = @json.exists(@json.join_path(dir, "pnpm-lock.yaml"))
  let lock_mtime = if lock_exists {
    @json.mtime_ms(@json.join_path(dir, "pnpm-lock.yaml"))
  } else {
    None
  }

  // 这只 profile 的 home 归属（隔离 / 共用）：判据与读数都在 homes.mbt，前端不自己再推一遍。
  // dsh_home 是控制台自己的 home —— 「共用」那一档的 path 就是它。
  let home = home_fact_in(name, dsh_home, dsh_home_source)
  // 最近一次启动的结局（design/design-fixes.md §26.1、§27.1）：从审计流水里取这只
  // (home, profile) 最近一条启动记录（start-instance 或 restart-instance），成败由那一笔自己说。
  let (last_start, last_start_source) = last_start_of(
    name,
    home.path,
    dsh_home,
    attempts,
    attempts_note,
  )

  @json.JObj([
    ("name", @json.JStr(name)),
    ("dir", @json.JStr(dir)),
    // 隔离 home 读数（design/deep-home-isolation.md 第 4 节）：
    //   kind        isolated / shared
    //   path        隔离 home 根 或 控制台的 DSH_HOME
    //   profileDir  实例真正读配置的目录（<path>/profiles/<名字>）
    //   createdAt   隔离记录里的时刻（没有隔离就是 null，那一档没有「建于」可言）
    (
      "home",
      @json.JObj([
        ("kind", @json.JStr(home.kind)),
        ("path", @json.JStr(home.path)),
        ("profileDir", @json.JStr(home.profile_dir)),
        ("createdAt", @json.str_or_null(home.created_at)),
      ]),
    ),
    // 一句判断依据：这一档是凭什么判出来的（前端只显示，不再推）
    ("homeKindSource", @json.JStr(home.source)),
    // 最近一次启动的结局（design/design-fixes.md §26.1）：红灯的判据只要这一条 ——
    // ok == false 且它就是最近那一条，就是「上一次启动失败、之后没有成功过」。
    // 一条记录都没有时给 null（不是 false：没有证据与「失败了」不是一件事）。
    (
      "lastStart",
      match last_start {
        Some(a) =>
          @json.JObj([
            // 这一笔是哪种动作写下的：start-instance 或 restart-instance（§27.1）
            ("action", @json.JStr(a.action)),
            ("ok", @json.JBool(a.ok)),
            ("at", @json.JStr(a.at)),
            ("code", @json.JStr(a.code)),
            ("message", @json.JStr(a.message)),
            // 那一笔带的 home；空串 = 那一笔没带（老记录）
            ("home", @json.JStr(a.home)),
          ])
        None => @json.JNull
      },
    ),
    // 上面那一格的来源 / 为什么没有：audit.jsonl 取的是哪一条、按什么对上的
    ("lastStartSource", @json.JStr(last_start_source)),
    (
      "isCurrent",
      @json.JBool(
        match current_profile {
          Some(c) => c == name
          None => false
        },
      ),
    ),
    ("packageName", @json.str_or_null(package_name(dir))),
    // 试跑那一块的判据（§9.3）：配置读不读得到、能不能起网页实例。
    // 两条都只报事实；「缺包」仍然可用，不该混进这两条里。
    ("packageJson", @json.JBool(pkg_ok)),
    ("webApp", @json.JBool(declared.contains(web_app_bundle))),
    (
      "bundles",
      @json.JObj([
        ("declared", @json.jint(bundles.length())),
        ("installed", @json.jint(bundles.length() - missing.length())),
        ("installedInProfile", @json.jint(installed_in_profile)),
        ("installedHoisted", @json.jint(installed_hoisted)),
        ("missing", @json.JArr(missing.map(fn(m) { @json.JStr(m) }))),
      ]),
    ),
    (
      "patch",
      @json.JObj([
        ("exists", @json.JBool(patch_exists)),
        ("lines", @json.jint(patch_lines)),
      ]),
    ),
    // 补包那条命令（§39）：界面拿它写确认框与悬停，口径与后端动作完全同一处
    // （repair_command_of），前端不自己按 lock 文件猜一遍。
    ("repairCommand", @json.JStr(repair_command_of(dir))),
    // 外部 / 坏软链接条数（§60.1）：brokenLinks 只进读数供排查，界面不显示。
    ("externalLinks", @json.jint(external)),
    ("brokenLinks", @json.jint(broken)),
    ("note", @json.JStr(note)),
    ("noteSource", @json.JStr(note_source)),
    // 配置快照（design/ops-maintenance-jobs.md 第 16.2 节）：每份 { id, at, reason, files, bytes }，
    // 按时间从新到旧。读不出来给空数组，原因在 snapshotsSource 里 ——
    // 「没拍过」与「读不到」不是一件事，界面按来源串分得开。
    (
      "snapshots",
      @json.JArr(
        snapshots.map(fn(s) {
          @json.JObj([
            ("id", @json.JStr(s.id)),
            ("at", @json.JStr(s.at)),
            ("reason", @json.JStr(s.reason)),
            ("files", @json.jint(s.files)),
            ("bytes", @json.JNum(s.bytes.to_int().to_double())),
          ])
        }),
      ),
    ),
    ("snapshotsSource", @json.JStr(snapshots_source)),
    ("dirMtimeMs", @json.int64_or_null(dir_mtime)),
    ("dirMtimeSource", @json.JStr(dir_mtime_source)),
    (
      "lock",
      @json.JObj([
        ("exists", @json.JBool(lock_exists)),
        (
          "mtime",
          @json.str_or_null(
            match lock_mtime {
              Some(ms) => Some(@json.iso_from_epoch_ms(ms))
              None => None
            },
          ),
        ),
      ]),
    ),
  ])
}

///|
/// 组装 /api/local/profiles 的 data 对象。
pub async fn read_profiles() -> @json.JsonVal raise @localapi.ReadError {
  let (dsh_home, dsh_home_source) = @runtime.resolve_dsh_home()
  let root = @json.join_path(dsh_home, "profiles")
  if !@json.is_dir(root) {
    @localapi.fail_read(
      "profiles-missing",
      "profiles 目录不存在：\{root}",
    )
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
  // 隔离的那几只：目录已经搬进各自的 home（真移动，不是复制），共用 home 的 profiles/ 下
  // 不再有它们。名册从 homes root 读 —— 不把它们列上，总览里就少了几只 profile，
  // 「金色描边 + 移回共用 home」也就无处可点（design/deep-home-isolation.md §9.6）。
  for name in isolated_profile_names() {
    if !names.contains(name) {
      names.push(name)
    }
  }
  names.sort_by(compare_code_units)
  // 启动结局只读一遍审计文件，逐只 profile 里再按 (home, 名字) 去对
  // （每只都读一遍整份流水的话，一只 profile 一次全文件扫描）。
  let (attempts, attempts_note) = @store.load_start_attempts()
  let profiles : Array[@json.JsonVal] = []
  for name in names {
    // 目录按**它自己现在在哪儿**取：隔离的那一个在 <homes root>/<名字>/profiles/<名字>。
    let (dir, _home) = profile_location(name)
    profiles.push(
      describe_profile(
        name, dir, shared_dir, current_profile, dsh_home, dsh_home_source, attempts,
        attempts_note,
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

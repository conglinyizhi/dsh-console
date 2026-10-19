// profile 的磁盘动作：派生 / 重命名 / 删除（回收站或硬删）。
//
// 这三条是唯一会碰 profile 目录的写路径，作用对象就是被点名的那一个目录，别处不动。
// 共同的两条规矩：
//   · 名字先过白名单（字母数字 . _ -，不以点开头），空名 / 越界 / 带斜杠一律 bad-params；
//   · 正在跑的 profile 不重命名、不删除（conflict）—— 运行时把它的目录抽走，出的错比省下的这一步贵。

///|
/// profile 根目录：$DSH_HOME/profiles。
pub async fn profiles_root() -> String noraise {
  let (home, _) = @runtime.resolve_dsh_home()
  @json.join_path(home, "profiles")
}

///|
/// profile 名白名单。空名、带斜杠、带别的字符、以点开头都拒。
pub fn validate_profile_name(name : String) -> Unit raise ActionError {
  if name == "" {
    fail("bad-params", "profile 名不能为空")
  }
  if name.length() > 64 {
    fail("bad-params", "profile 名太长（上限 64）：" + name)
  }
  if name == "." || name == ".." {
    fail("bad-params", "profile 名不能是 " + name)
  }
  if name.has_prefix(".") {
    fail("bad-params", "profile 名不能以点开头：" + name)
  }
  for ch in name {
    let code = ch.to_int()
    let ok = (code >= 48 && code <= 57) ||
      (code >= 65 && code <= 90) ||
      (code >= 97 && code <= 122) ||
      ch == '.' ||
      ch == '_' ||
      ch == '-'
    if !ok {
      fail("bad-params", "profile 名里有不允许的字符：" + ch.to_string() + "（只允许字母数字与 . _ -）")
    }
  }
}

///|
/// 派生：新名字默认 <原名>-dev，重名自动加序号。node_modules 整棵不复制
/// （那是 pnpm 的安装产物，profiles/node_modules 的提升目录仍然解析得到；要自带依赖就在新 profile 里再装一次）。
pub struct ForkOutcome {
  profile : String
  new_name : String
  dir : String
  files : Int
  dirs : Int
  skipped : Array[String]
  started : SpawnOutcome?
  /// 新 profile 的"出生证明"备注全文（第五轮契约第二节）
  note_text : String
  /// 备注落点：<新 profile 目录>/.dsh-note.txt
  note_path : String
  /// 备注写失败时的原因（人话）。写失败**不算派生失败**，这里如实带出来
  note_error : String?
  /// 新 profile 目录复制完之后的 mtime（毫秒）；读不到给 None
  dir_mtime_ms : Int64?
  /// mtime 的来源或读不到的原因
  dir_mtime_source : String
  /// 派生之后顺手建好的隔离 home 路径（规格第 8 节：派生的 profile 默认隔离）。
  /// None = 没建成，原因在 home_error —— 建失败**不影响派生本身**。
  home_path : String?
  /// 隔离没建成的原因（人话）。派生成功但 home 没建成时，回执里要照实说清。
  home_error : String?
}

///|
/// 见上。port 给了就顺手把新 profile 起起来（在同一台机器上跑 dev 副本的常见用法）。
pub async fn fork_profile(
  profile : String,
  new_name : String?,
  port : Int?,
) -> ForkOutcome raise ActionError {
  let source_name = @json.trim_both(profile)
  validate_profile_name(source_name)
  // 派生的源按**它自己现在在哪儿**取（隔离的那一只在自己 home 里）；
  // 新副本一律落在共用 home 的 profiles/ 下，随后照旧"派生即隔离"。
  let (source_dir, _source_home) = @profiles.profile_location(source_name)
  let root = profiles_root()
  if !@json.is_dir(source_dir) {
    fail("not-found", "profile 目录不存在：" + source_dir)
  }
  let wanted = match new_name {
    Some(v) =>
      if @json.trim_both(v) == "" {
        source_name + "-dev"
      } else {
        @json.trim_both(v)
      }
    None => source_name + "-dev"
  }
  validate_profile_name(wanted)
  let target_name = unique_profile_name(root, wanted)
  let target_dir = @json.join_path(root, target_name)
  // 源备注在拷贝**之前**读：拷完之后目标目录里也有一份同样的内容，那时再读就分不清是谁的
  let (source_note, _) = @profiles.read_profile_note(source_dir)
  // .snapshots 不复制（design/ops-maintenance-jobs.md 16.1）：那是源 profile 的历史，
  // 带过去只会让人以为新 profile 也拍过那些。
  let stats = match @fsx.copy_tree(source_dir, target_dir, ["node_modules", @profiles.snapshots_dir_name]) {
    Ok(s) => s
    Err(e) => {
      fail("io-error", e)
      abort("unreachable: fail 一定抛错")
    }
  }
  let note_path = @json.join_path(target_dir, @profiles.note_file_name)
  let stamp = match @json.local_stamp_from_epoch_ms(@async.now()) {
    Some(s) =>
      match @json.local_zone_name() {
        Some(zone) => s + " " + zone
        None => s
      }
    None => @json.iso_from_epoch_ms(@async.now()) + "（本地时区读不到，按 UTC）"
  }
  let note_text = @profiles.fork_note_text(source_name, stamp, source_note)
  // 备注写失败不许让派生失败：目录已经拷好了，为了一个备注把整次派生报成失败是假报。
  // 这里把失败收成一个原因字符串，调用方原样写进 outcome。
  let note_error = match @fsx.write_text_atomic(note_path, note_text) {
    Ok(_) => None
    Err(e) => Some(e)
  }
  // mtime 在拷贝与写备注**之后**读：这才是这一趟真实留下的"最近改动"，
  // 也正是它在列表里排最前面的依据。读不到给 None + 原因，不拿当前时间冒充。
  let (dir_mtime_ms, dir_mtime_source) = @profiles.read_profile_dir_mtime(target_dir)
  // 派生出来的 profile 默认隔离（design/deep-home-isolation.md 第 8 节）：顺手把 home 建好。
  // 建失败不许让派生失败 —— 目录已经拷好了，为了一个 home 把整次派生报成失败是假报；
  // 原因原样带出去，回执里说清楚「派生成功、隔离没建成」。
  let (home_path, home_error) = match @profiles.isolate_profile(target_name) {
    Ok(home) => (Some(home.path), None)
    Err((_code, message)) => (None, Some(message))
  }
  let started = match port {
    None => None
    Some(_) =>
      Some(
        start_instance(
          target_name,
          None,
          port,
        ),
      )
  }
  {
    profile: source_name,
    new_name: target_name,
    dir: target_dir,
    files: stats.files,
    dirs: stats.dirs,
    skipped: stats.skipped,
    started,
    note_text,
    note_path,
    note_error,
    dir_mtime_ms,
    dir_mtime_source,
    home_path,
    home_error,
  }
}

///|
/// 重名时加序号：<名>-2、<名>-3 …… 最多试 200 个，全都撞上就报 conflict。
async fn unique_profile_name(root : String, wanted : String) -> String noraise {
  if !@json.exists(@json.join_path(root, wanted)) {
    return wanted
  }
  let mut index = 2
  while index <= 200 {
    let candidate = wanted + "-" + index.to_string()
    if !@json.exists(@json.join_path(root, candidate)) {
      return candidate
    }
    index = index + 1
  }
  wanted + "-" + @async.now().to_string()
}

///|
/// 重命名的结果。
pub struct RenameOutcome {
  profile : String
  new_name : String
  from : String
  to : String
}

///|
/// 改磁盘上的 profile 目录名。
pub async fn rename_profile(profile : String, new_name : String) -> RenameOutcome raise ActionError {
  let from_name = @json.trim_both(profile)
  let to_name = @json.trim_both(new_name)
  validate_profile_name(from_name)
  validate_profile_name(to_name)
  if from_name == to_name {
    fail("bad-params", "新旧名字一样：" + from_name)
  }
  // 移进独立 home 的那一只不许直接改名：它的目录名与 home 目录名是一对（<root>/<名字>/
  // profiles/<名字>），只改一半会让这份 home 谁也对不上。先移回共用 home 再改名。
  match @profiles.isolated_home_of(from_name) {
    Some(home) =>
      fail(
        "conflict",
        from_name + " 移到了独立 home（" + home + "），先移回共用 home 再改名（" +
        "home 目录名与 profile 名是一对，只改一半会对不上）",
      )
    None => ()
  }
  let root = profiles_root()
  // 守卫比的是 (home, 名字)：home 就是 profiles 根的父目录，与下面要动的那个目录同源算一次。
  // 不让守卫自己再解析一遍 —— 分叉出来正好是「判的是这一处、动的是另一处」。
  let home = @json.dirname(root)
  let from = @json.join_path(root, from_name)
  let to = @json.join_path(root, to_name)
  if !@json.is_dir(from) {
    fail("not-found", "profile 目录不存在：" + from)
  }
  if @json.exists(to) {
    fail("conflict", "目标名字已经有人用了：" + to)
  }
  match running_for_profile_in(from_name, Some(home)) {
    Some(hit) =>
      fail(
        "conflict",
        "profile " + from_name + " 正在运行（PID " + hit.pid.to_string() +
        "），先停掉再改名",
      )
    None => ()
  }
  match @fsx.rename_path(from, to) {
    Ok(_) => ()
    Err(e) => fail("io-error", e)
  }
  { profile: from_name, new_name: to_name, from, to }
}

///|
/// 删除的结果。
pub struct DeleteOutcome {
  profile : String
  dir : String
  /// trash（移进回收站）或 hard-delete（递归删掉）
  mode : String
  /// 回收站落点；硬删时为空串
  trash_path : String
  /// 这一份是从哪个 home 删的（就是 dir 所在的那个 home）。
  /// 删进回收站时它会被记进 trash-origins.json，恢复按它归位 —— 同名两份档案
  /// 各自回各自的家，靠的就是这个值，不是靠「控制台自己现在是哪个 home」。
  home : String
  /// 记来源 home 失败的原因（None = 记上了 / 不需要记）。
  ///
  /// 记不上**不算删除失败**：目录已经进回收站了，为了一个标记把整次删除报成失败是假报。
  /// 但也不能吞 —— 不说出来的话，恢复那一步就会落到控制台自己的 home 上（旧行为），
  /// 而使用者以为它会回原处。
  origin_error : String?
  /// 硬删时确实要求过的二次确认串
  confirm : String
}

///|
/// 删一个 profile：按 safety.deleteToTrash 决定进回收站还是硬删。
/// 硬删必须带 confirm = "DELETE"（契约第二节的 destructive 要求）。
pub async fn delete_profile(profile : String, confirm : String?) -> DeleteOutcome raise ActionError {
  let name = @json.trim_both(profile)
  validate_profile_name(name)
  // home 与 root 同源算一次：分开各算一遍迟早会分叉，而分叉出来正好是
  // 「删的是这一处、记下的来源却是另一处」—— 那比不记还坏。
  // 目录与 home 一起取：真移动之后隔离的那一只在自己的 home 里，
  // 按 DSH_HOME 拼会指到一个已经不存在的目录（或者更坏：同名的另一份）。
  let (dir, home) = @profiles.profile_location(name)
  let root = @json.join_path(home, "profiles")
  if !dir.has_prefix(root + "/") || dir == root {
    fail("bad-params", "profile 名解析到了 " + root + " 之外：" + dir)
  }
  if !@json.is_dir(dir) {
    fail("not-found", "profile 目录不存在：" + dir)
  }
  // 守卫比 (home, 名字)：home 用的是上面算出来的那一个，与目录同源。
  match running_for_profile_in(name, Some(home)) {
    Some(hit) =>
      fail(
        "conflict",
        "profile " + name + " 正在运行（PID " + hit.pid.to_string() +
        "），先停掉再删除",
      )
    None => ()
  }
  let settings = @store.load_settings().values
  if settings.safety_delete_to_trash {
    let paths = @store.state_paths()
    let stamp = @async.now().to_string()
    let trash_dir_name = name + "-" + stamp
    let trash_path = @json.join_path(paths.trash, trash_dir_name)
    match @fsx.ensure_dir(paths.trash) {
      Ok(_) => ()
      Err(e) => fail("io-error", e)
    }
    match @fsx.rename_path(dir, trash_path) {
      Ok(_) => ()
      Err(first) => {
        // 状态目录与 profile 目录不同文件系统时 rename 会 EXDEV：退回复制再删
        match @fsx.copy_tree(dir, trash_path, []) {
          Ok(_) =>
            match @fsx.remove_tree(dir) {
              Ok(_) => ()
              Err(e) => fail("io-error", first + "；退回复制也失败：" + e)
            }
          Err(e) => fail("io-error", first + "；退回复制也失败：" + e)
        }
      }
    }
    // 记下「这一条是从哪个 home 删的」。恢复时按它归位，所以这一步就是
    // 「删了隔离那份、恢复却回到主线上」那个错的正面修法。
    let origin_error = match @store.put_trash_origin(trash_dir_name, home) {
      Ok(_) => None
      Err(e) => Some(e)
    }
    return {
      profile: name,
      dir,
      mode: "trash",
      trash_path,
      home,
      origin_error,
      confirm: "",
    }
  }
  let given = match confirm {
    Some(v) => @json.trim_both(v)
    None => ""
  }
  if given != "DELETE" {
    fail(
      "bad-params",
      "safety.deleteToTrash=false 时删除是硬删，body 里必须再带 \"confirm\":\"DELETE\"",
    )
  }
  match @fsx.remove_tree(dir) {
    Ok(_) => ()
    Err(e) => fail("io-error", e)
  }
  { profile: name, dir, mode: "hard-delete", trash_path: "", home, origin_error: None, confirm: given }
}

///|
/// 写备注的结果。
pub struct NoteOutcome {
  profile : String
  dir : String
  /// 备注文件路径：<profile 目录>/.dsh-note.txt
  path : String
  /// true = 这次是「空串」语义，文件被删掉了（本来就没有也算）
  removed : Bool
  /// 落盘后的字符数；removed 时为 0
  chars : Int
}

///|
/// 设一个 profile 的备注（第二轮契约第二节）。
///   text 非空 -> 原子写进 <profile 目录>/.dsh-note.txt（覆盖旧内容）
///   text 为空串 -> 删掉那个文件
///
/// 名字先过白名单，再确认拼出来的目录就是 <profilesRoot>/<name> —— 目录穿越在这里被挡掉：
/// 白名单不接受斜杠、"." 、".."，所以「解析到 profilesRoot 之外」的名字根本走不到这一步。
pub async fn set_profile_note(profile : String, text : String) -> NoteOutcome raise ActionError {
  let name = @json.trim_both(profile)
  validate_profile_name(name)
  // 隔离的那一只：备注写在它自己那份目录里（备注跟着目录走，这也是它一直的口径）
  let (dir, home) = @profiles.profile_location(name)
  let root = @json.join_path(home, "profiles")
  // 防目录穿越的第二道：白名单已经保证 name 是单段（无斜杠、不是 . / ..），
  // 这里再确认拼出来的路径确实在 profilesRoot 里面，两道都留着。
  if !dir.has_prefix(root + "/") || dir == root {
    fail("bad-params", "profile 名解析到了 profilesRoot 之外：" + dir)
  }
  if !@json.is_dir(dir) {
    fail("not-found", "profile 目录不存在：" + dir)
  }
  let path = @json.join_path(dir, @profiles.note_file_name)
  if text == "" {
    // 空串 = 删文件。本来就没有这个文件也算成：这一步是幂等的，不给前端制造无谓的 not-found
    if @json.exists(path) {
      match @fsx.remove_file(path) {
        Ok(_) => ()
        Err(e) => fail("io-error", e)
      }
    }
    return { profile: name, dir, path, removed: true, chars: 0 }
  }
  let chars = text.length()
  if chars > @profiles.note_max_chars {
    fail(
      "bad-params",
      "备注太长：" + chars.to_string() + " 字符，上限 " +
      @profiles.note_max_chars.to_string() + " 字符",
    )
  }
  match @fsx.write_text_atomic(path, text) {
    Ok(_) => ()
    Err(e) => fail("io-error", e)
  }
  { profile: name, dir, path, removed: false, chars }
}

// ── 从基础模板新建（design/design-fixes.md 第 20 节）──────────────────
//
// 前置条件：现有 profile 全坏、或全不可用时，用户仍要能建一只新的。
// 做法是用**已安装的 dsh 自带的基础模板**新建一份，不读任何现有配置：
//
//   node <包目录>/lib/bin.js --profile <名字> --from-default-profile web --dump-config
//
// · DSH_HOME 用控制台自己的那一份，所以新 profile 与别的一样落在 <DSH_HOME>/profiles/ 下；
// · --dump-config 让 dsh 把组合出来的配置打到 stdout 就退出：这一条**只写 profile、不启动**
//   （已实测：退出码 0，没有进程留下）。我们要的就是「退出码 0 + 三样文件在」；
// · 任何一步不过都把刚建的目录删掉再报，不留半成品 —— 半成品在列表里长得跟建成了的一样。

///|
/// 从基础模板新建时 --from-default-profile 的取值：dsh 自带的那份叫 web。
pub let base_template_profile : String = "web"

///|
/// 跑 dsh 建这份 profile 的上限（规格第 20.1 节写的是 60 秒）。
/// 卡住的 dsh 不能把动作请求挂死：到点按失败处理，并把目录收掉。
let base_profile_timeout_ms : Int = 60000

///|
/// 一次「从基础模板新建」的结果。
pub struct BaseProfileOutcome {
  name : String
  dir : String
  /// 隔离 home 路径（None = 没建成，原因在 home_error）。隔离失败**不影响**建成功。
  home_path : String?
  home_error : String?
  /// 核对时读到的 bundles（回执里点名 @deepseek-ai/dsh-web-app 在不在）
  bundles : Array[String]
  /// 这一趟用的 dsh 包目录与版本：核对时能对上号，不用事后猜
  package_dir : String
  dsh_version : String
  /// dsh 那一步花了多少毫秒
  ms : Int
}

///|
/// package.json 里的 dsh.profile.bundles（字段不在 / 不是数组就给空表）。
fn base_bundles_of(json : Json) -> Array[String] {
  let out : Array[String] = []
  let dsh = match @json.json_field(json, "dsh") {
    Some(v) => v
    None => return out
  }
  let profile = match @json.json_field(dsh, "profile") {
    Some(v) => v
    None => return out
  }
  let bundles = match @json.json_field(profile, "bundles") {
    Some(v) => v
    None => return out
  }
  for item in @json.json_array(Some(bundles)) {
    match @json.json_string(item) {
      Some(s) => out.push(s)
      None => ()
    }
  }
  out
}

///|
/// 核对刚建出来的那份 profile（规格第 20.1 节第 3 条）：目录在、package.json 读得出、
/// bundles 里有 @deepseek-ai/dsh-web-app、cordis.patch.yml 在。
///
/// 返回 (不过的原因, 读到的 bundles)。原因非空时调用方要删目录再报。
async fn check_base_profile(dir : String) -> (String?, Array[String]) noraise {
  if !@json.is_dir(dir) {
    return (Some("profile 目录没建出来：" + dir), [])
  }
  let text = match @json.read_text_file(@json.join_path(dir, "package.json")) {
    Ok(t) => t
    Err(e) => return (Some("package.json 读不出来（" + e + "）"), [])
  }
  let json = match @json.json_parse(text) {
    Some(j) => j
    None => return (Some("package.json 不是合法 JSON"), [])
  }
  let bundles = base_bundles_of(json)
  if !bundles.contains(@profiles.web_app_bundle) {
    let seen = if bundles.length() == 0 { "空表" } else { bundles.join("、") }
    return (
      Some("bundles 里没有 " + @profiles.web_app_bundle + "（读到的是 " + seen + "）"),
      bundles,
    )
  }
  let patch = @json.join_path(dir, "cordis.patch.yml")
  if !@json.exists(patch) {
    return (Some("cordis.patch.yml 不在：" + patch), bundles)
  }
  (None, bundles)
}

///|
/// 把刚建的 profile 目录删掉，并把「删没删掉」写成一句话（进失败回执，别让人自己去猜）。
async fn remove_failed_base_profile(dir : String) -> String noraise {
  if !@json.exists(dir) {
    return "刚建的 " + dir + " 本来就没留下"
  }
  match @fsx.remove_tree(dir) {
    Ok(_) => "刚建的 " + dir + " 已经删掉，没留半成品"
    Err(e) => "刚建的 " + dir + " 没删掉：" + e + "（要手动删）"
  }
}

///|
/// dsh 那一步的失败证据：stderr 尾部（stderr 是空的时候退回 stdout 尾部）。
/// 只取尾部几行 —— 整份 --dump-config 有几十 KB，整段丢进回执只是噪声。
fn base_profile_evidence(stdout : String, stderr : String) -> String {
  let err_tail = job_tail_lines(stderr, 6)
  if err_tail != "" {
    return err_tail
  }
  let out_tail = job_tail_lines(stdout, 6)
  if out_tail != "" {
    return out_tail
  }
  "dsh 什么都没写"
}

///|
/// 从基础模板新建一只 profile（规格第 20.1 节）。
///
/// 顺序照规格写死，不并、不省：
///   1. 名字按既有白名单校验；同名（共用 home 的目录、或同名的隔离 home）一律 conflict；
///   2. 用生效的那一份 dsh 跑 --from-default-profile web --dump-config（DSH_HOME = 控制台的 home，
///      60 秒上限，不启动）；退出码非 0 / 超时 / 起不来都算失败；
///   3. 核对三条：package.json 读得出、bundles 里有 @deepseek-ai/dsh-web-app、cordis.patch.yml 在；
///   4. 默认隔离（复用 isolate_profile）：**隔离失败不影响建成功**，原因原样带回去；
///   5. 任何一步失败都删掉刚建的目录，回 io-error 并带 stderr 尾部。
pub async fn create_base_profile(name_in : String) -> BaseProfileOutcome raise ActionError {
  let name = @json.trim_both(name_in)
  validate_profile_name(name)
  let (dsh_home, dsh_home_source) = @runtime.resolve_dsh_home()
  let root = profiles_root()
  let dir = @json.join_path(root, name)
  // 硬约束：拼出来的目录必须正好是 <profilesRoot>/<单段名字>
  if !dir.has_prefix(root + "/") || dir == root {
    fail("bad-params", "profile 名拼出来的目录不在 " + root + " 下：" + dir)
    abort("unreachable: fail 一定抛错")
  }
  if @json.exists(dir) {
    fail(
      "conflict",
      "profile " + name + " 已经存在：" + dir + "；从基础模板只建新的一份，不覆盖，换个名字再来",
    )
    abort("unreachable: fail 一定抛错")
  }
  // 同名的隔离 home 也占着这个名字：那一份的目录已经在 <root>/<名字>/profiles/<名字>，
  // 再建一只同名的共用 profile 只会让「这只 profile 是谁」变成两个答案。
  match @profiles.isolated_home_of(name) {
    Some(home) => {
      fail(
        "conflict",
        "名字 " + name + " 已经有一份隔离 home：" + home + "（同名的那一份还在，换个名字再来）",
      )
      abort("unreachable: fail 一定抛错")
    }
    None => ()
  }
  let command = match resolve_dsh_command() {
    Some(c) => c
    None => {
      fail(
        "io-error",
        "这台机器上找不到能跑基础模板的 dsh：PATH 上的 dsh 命令解不出包目录，pnpm 全局根下也没有 " +
        "@deepseek-ai/dsh/lib/bin.js（DSH_HOME 来自 " + dsh_home_source + "：" + dsh_home + "）",
      )
      abort("unreachable: fail 一定抛错")
    }
  }
  let env : Map[String, String] = Map([])
  env["DSH_HOME"] = dsh_home
  let argv : Array[String] = [
    command.node,
    command.script,
    "--profile",
    name,
    "--from-default-profile",
    base_template_profile,
    "--dump-config",
  ]
  let began = @async.now()
  let ran = run_capture(argv, env, dsh_home, base_profile_timeout_ms)
  let ms = (@async.now() - began).to_int()
  let (code, stdout, stderr) = match ran {
    Ok(triple) => triple
    Err(why) => {
      let cleaned = remove_failed_base_profile(dir)
      fail("io-error", "跑 dsh 建基础模板没成：" + why + "；" + cleaned)
      abort("unreachable: fail 一定抛错")
    }
  }
  if code != 0 {
    let cleaned = remove_failed_base_profile(dir)
    fail(
      "io-error",
      "dsh 建基础模板失败（退出码 " + code.to_string() + "），stderr 尾部：" +
      base_profile_evidence(stdout, stderr) + "；" + cleaned,
    )
    abort("unreachable: fail 一定抛错")
  }
  let (problem, bundles) = check_base_profile(dir)
  match problem {
    Some(why) => {
      let cleaned = remove_failed_base_profile(dir)
      fail(
        "io-error",
        "dsh 退出码是 0，但新建出来的这一份对不上：" + why + "；" + cleaned,
      )
      abort("unreachable: fail 一定抛错")
    }
    None => ()
  }
  // 默认隔离，与派生同一档（design/deep-home-isolation.md 第 8 节）。
  // 隔离失败不许让「建成了」变成「失败了」：profile 已经在磁盘上、也核对过了，
  // 为了一个 home 把整件事报成失败是假报 —— 原因原样带回去，回执照实说。
  let (home_path, home_error) = match @profiles.isolate_profile(name) {
    Ok(home) => (Some(home.path), None)
    Err((_code, message)) => (None, Some(message))
  }
  {
    name,
    dir,
    home_path,
    home_error,
    bundles,
    package_dir: command.package_dir,
    dsh_version: command.version,
    ms,
  }
}


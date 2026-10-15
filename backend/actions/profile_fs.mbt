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
  let root = profiles_root()
  let source_dir = @json.join_path(root, source_name)
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
  let stats = match @fsx.copy_tree(source_dir, target_dir, ["node_modules"]) {
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
  let root = profiles_root()
  let from = @json.join_path(root, from_name)
  let to = @json.join_path(root, to_name)
  if !@json.is_dir(from) {
    fail("not-found", "profile 目录不存在：" + from)
  }
  if @json.exists(to) {
    fail("conflict", "目标名字已经有人用了：" + to)
  }
  match running_for_profile(from_name) {
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
  /// 硬删时确实要求过的二次确认串
  confirm : String
}

///|
/// 删一个 profile：按 safety.deleteToTrash 决定进回收站还是硬删。
/// 硬删必须带 confirm = "DELETE"（契约第二节的 destructive 要求）。
pub async fn delete_profile(profile : String, confirm : String?) -> DeleteOutcome raise ActionError {
  let name = @json.trim_both(profile)
  validate_profile_name(name)
  let root = profiles_root()
  let dir = @json.join_path(root, name)
  if !@json.is_dir(dir) {
    fail("not-found", "profile 目录不存在：" + dir)
  }
  match running_for_profile(name) {
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
    let trash_path = @json.join_path(paths.trash, name + "-" + stamp)
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
    return {
      profile: name,
      dir,
      mode: "trash",
      trash_path,
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
  { profile: name, dir, mode: "hard-delete", trash_path: "", confirm: given }
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
  let root = profiles_root()
  let dir = @json.join_path(root, name)
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

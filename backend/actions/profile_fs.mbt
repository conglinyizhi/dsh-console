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
  let stats = match @fsx.copy_tree(source_dir, target_dir, ["node_modules"]) {
    Ok(s) => s
    Err(e) => {
      fail("io-error", e)
      abort("unreachable: fail 一定抛错")
    }
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

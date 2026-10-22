// 回收站：列出 trash/ 里的条目、把一份移回 profile 目录、彻底删掉一份（第六轮契约）。
//
// 落点是 $XDG_STATE_HOME/dsh-console/trash，目录名形如 <profile>-<epochMs>（delete-profile 写的）。
// 这里只有三件事：读（给 GET /api/local/console 的 trash 字段用）、移回、真删。
//
// 多 home（Phase 3）：目录名里**没有 home**，所以「这一条是从哪个 home 删的」由 delete-profile
// 另记一份（trash-origins.json，见 store/trash_origins.mbt）。恢复按**记下来的那个 home**归位，
// 不按控制台自己现在是哪个 home —— 删了隔离那份、恢复却落到主线上，正是这么来的。
// 没记来源的条目（本次改动之前删的）落回控制台自己的 home，并把这件事如实写出来。
//
// 两条与既有写路径同款的纪律：
//   · dir 只当成 trash 下的**一个目录名**看：先过白名单（单段、不带斜杠、不是 . / ..），
//     再确认拼出来的路径落在 trash 之内 —— 客户端给不出路径，给一个 ../profiles/web 也走不通；
//   · 目录名里 profile 那段按**最后一个** '-' 切：profile 名自己就允许带 '-'（web-dev 是合法名字），
//     从前头切会把 web 当成 profile。
//
// 数不出来的数（文件数 / 体积）一律给「读不到」并把原因带出去，不给一个偏小的数冒充真实体积。

///|
/// 回收站根下那一格「整份额外 home」的容器目录名（与 profiles/homes.mbt 的
/// trash_homes_dir 是同一个名字）。它自己不是一条条目：列表、恢复、彻底删除都跳过它。
fn is_trash_bucket(name : String) -> Bool {
  name == @profiles.trash_homes_dir
}

///|
/// 一条回收站读数。
pub struct TrashEntry {
  /// trash 下的目录名，也就是恢复 / 彻底删除时的 dir 参数
  dir : String
  /// 目录名切出来的 profile 名；切不出来就给原目录名
  profile : String
  /// 目录名末段的 epoch 毫秒；切不出来给 None
  deleted_at_ms : Int64?
  /// 上面那个时间的来源，或切不出来的原因
  deleted_at_source : String
  /// 这一条是从哪个 home 删的（绝对路径）。空串 = 没记下来源 —— 见 home_source
  home : String
  /// 上面那个 home 的来源，或没有它的原因（人话）
  home_source : String
  /// 递归数出来的普通文件个数；数不动给 None
  file_count : Int32?
  /// 递归求和的字节数；数不动给 None
  bytes : Int64?
  /// 文件数与体积的来源，或数不动的原因
  size_source : String
}

///|
/// 回收站根目录。
pub async fn trash_root() -> String noraise {
  @store.state_paths().trash
}

///|
/// 目录名里最后一个 '-' 的下标。没有给 None。
fn last_dash_index(text : String) -> Int32? {
  let mut found : Int32? = None
  let mut i = 0
  for ch in text {
    if ch == '-' {
      found = Some(i)
    }
    i = i + 1
  }
  found
}

///|
/// 把目录名切成 (profile, epochMs, 来源说明)。
///
/// 按**最后一个** '-' 切：profile 名允许带 '-'（web-dev、web-dev-2 都是合法名字），
/// 从第一个 '-' 切会把 "web-dev-1792070484767" 切成 profile="web" ✗。
/// 末段必须是纯数字才算 epoch；切不出来（没有 '-'、末段不是数字、'-' 在最前）
/// 就 profile 给原目录名、时间给 None —— 不拿别的数顶上。
pub fn split_trash_name(dir : String) -> (String, Int64?, String) {
  match last_dash_index(dir) {
    Some(idx) =>
      if idx <= 0 || idx + 1 >= dir.length() {
        (
          dir,
          None,
          "目录名里没有 <profile>-<epochMs> 这样的时间戳（'-' 的位置切不出两段），按原目录名当 profile",
        )
      } else {
        let tail = @json.slice(dir, idx + 1, dir.length())
        if @json.is_all_digits(tail) {
          (
            @json.slice(dir, 0, idx),
            Some(@json.parse_dec64(tail)),
            "目录名末段就是删除那一刻的毫秒时间戳",
          )
        } else {
          (
            dir,
            None,
            "目录名末段「" +
            tail +
            "」不是纯数字，读不出删除时刻，按原目录名当 profile",
          )
        }
      }
    None =>
      (
        dir,
        None,
        "目录名里没有 '-'，读不出删除时刻，按原目录名当 profile",
      )
  }
}

///|
/// 数一份回收站条目：给 (文件数, 字节数, 来源说明)。数不出来两个都给 None 并写明原因。
async fn measure_entry(path : String) -> (Int32?, Int64?, String) noraise {
  match @fsx.measure_tree(path) {
    Ok(pair) =>
      (
        Some(pair.0),
        Some(pair.1),
        "递归数了这一份里的普通文件（软链等非普通文件不计入）",
      )
    Err(reason) => (None, None, reason)
  }
}

///|
/// 列出回收站里的条目，最近删的在前。
///
/// 时间读不到的排最后并按名字升序兜底 —— 与「已停止的实例」那一组同一套口径：
/// 排不出先后的时候要有个确定的顺序，不然刷新一次换一个样子。
pub async fn list_trash() -> Array[TrashEntry] noraise {
  let root = trash_root()
  let out : Array[TrashEntry] = []
  if !@json.is_dir(root) {
    return out
  }
  // 来源表读一次给所有条目用（条目可能很多，一条读一次盘不合适）
  let origin_file = @store.load_trash_origins()
  let origins_path = @store.state_paths().trash_origins
  for entry in @json.list_entries(root) {
    let (name, is_dir) = entry
    // 只认目录：trash 里混进来的散文件不是一条可恢复的条目（也不该被这里当成一条）
    if !is_dir {
      continue
    }
    // homes/ 是「整份额外 home」那一格的容器目录（design/deep-home-isolation.md 第 9.4 节），
    // 它自己不是一条可恢复的条目：条目是它里面的 <名字>-<毫秒>，恢复与彻底删除都不从这里走。
    if is_trash_bucket(name) {
      continue
    }
    let path = @json.join_path(root, name)
    let (profile, deleted_at_ms, deleted_at_source) = split_trash_name(name)
    let (file_count, bytes, size_source) = measure_entry(path)
    // 来源 home 是按**目录名**查的（不是路径）：查不到就说查不到，不拿控制台自己的 home 冒充
    let (home, home_source) = match origin_file.origins.get(name) {
      Some(h) =>
        (h, "删除那一刻记下的来源 home（" + origins_path + "）")
      None => {
        let reason = match origin_file.note {
          Some(why) => "这一条没有来源 home 记录（" + why + "）"
          None =>
            "这一条没有来源 home 记录：本次改动之前删的条目，那时还记不了 home"
        }
        ("", reason)
      }
    }
    out.push({
      dir: name,
      profile,
      deleted_at_ms,
      deleted_at_source,
      home,
      home_source,
      file_count,
      bytes,
      size_source,
    })
  }
  out.sort_by(fn(a, b) {
    match (a.deleted_at_ms, b.deleted_at_ms) {
      (Some(x), Some(y)) =>
        if x > y {
          -1
        } else if x < y {
          1
        } else {
          @json.compare_code_units(a.dir, b.dir)
        }
      (Some(_), None) => -1
      (None, Some(_)) => 1
      (None, None) => @json.compare_code_units(a.dir, b.dir)
    }
  })
  out
}

///|
/// 校验 dir：只接受 trash 下的**一个目录名**。
///
/// 两道与 set-profile-note / open-path 同款：白名单挡住斜杠与 . / ..（所以 ../profiles/web
/// 连第一步都过不去），再确认拼出来的路径确实落在 trash 之内。客户端给不出路径 ✗。
pub async fn resolve_trash_dir(dir : String) -> String raise ActionError {
  let name = @json.trim_both(dir)
  if name == "" {
    fail("bad-params", "dir 不能为空")
  }
  if name.length() > 160 {
    fail("bad-params", "dir 太长（上限 160）：" + name)
  }
  if name == "." || name == ".." {
    fail("bad-params", "dir 不能是 " + name)
  }
  if name.has_prefix(".") {
    fail("bad-params", "dir 不能以点开头：" + name)
  }
  if is_trash_bucket(name) {
    fail(
      "bad-params",
      "「" +
      name +
      "」是回收站里放整份额外 home 的那一格，不是一条可恢复的条目：" +
      "恢复 / 彻底删除都不对它下手",
    )
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
      fail(
        "bad-params",
        "dir 里有不允许的字符：" +
        ch.to_string() +
        "（只允许字母数字与 . _ -，回收站条目名就是这两样拼的）",
      )
    }
  }
  let root = trash_root()
  let path = @json.join_path(root, name)
  if !path.has_prefix(root + "/") || path == root {
    fail("bad-params", "dir 解析到了回收站目录之外：" + path)
  }
  path
}

///|
/// 恢复的结果。
pub struct RestoreOutcome {
  dir : String
  profile : String
  /// 恢复到的路径：<home>/profiles/<profile>
  to : String
  /// 恢复到了哪个 home（就是拼 to 用的那个值）。空串不会出现 —— 认不出 home 时不恢复
  home : String
  /// 上面那个 home 是哪来的（人话：记下来的来源 / 没记来源时的退路）
  home_source : String
  /// true = home 来自删除那一刻记下的记录；false = 没记来源，落回了控制台自己的 home。
  /// 界面上要说的那句话不同（一个是「回原处了」，一个是「没记来源，按本控制台的 home 恢复的」），
  /// 所以这件事不能只写在人话字符串里让调用方去认字。
  home_recorded : Bool
  /// 恢复之后没能把来源记录清掉的原因（None = 清掉了 / 本来就没有）
  origin_error : String?
  files : Int32?
  bytes : Int64?
  /// 文件数 / 体积的来源或读不到的原因
  size_source : String
}

///|
/// 把回收站里的一份移回它**来的那个** home 的 profile 目录（第六轮契约第一节）。
///
/// **目标已存在时必须拒绝**：恢复不是覆盖 —— 盖掉一份同名 profile 是那种事后无法解释的操作。
/// 跨文件系统时 rename 会 EXDEV，退回复制再删（与 delete-profile 进回收站同款退路）。
///
/// home 的选择只有两条路，都不猜：
///   ① 删的时候记下了来源（trash-origins.json）→ 回它那儿；
///   ② 没记下来源（本次改动之前删的旧条目）→ 落回控制台自己的 home，并把这件事写进
///      home_source，界面上说得出来「这一份不是回到它原来的地方，而是回到这儿」。
pub async fn restore_from_trash(
  dir : String,
) -> RestoreOutcome raise ActionError {
  let name = @json.trim_both(dir)
  let path = resolve_trash_dir(name)
  if !@json.is_dir(path) {
    fail("not-found", "回收站里没有这一份：" + path)
  }
  let (profile, _, _) = split_trash_name(name)
  validate_profile_name(profile)
  let origin_file = @store.load_trash_origins()
  let (home, home_recorded, home_source) = match origin_file.origins.get(name) {
    Some(recorded) =>
      (
        recorded, true, "这一条删的时候记下了来源 home，恢复就回它那儿",
      )
    None => {
      let (console_home, _) = @runtime.resolve_dsh_home()
      let reason = match origin_file.note {
        Some(why) =>
          "这一条没有来源 home 记录（" +
          why +
          "），只能落回控制台自己的 home"
        None =>
          "这一条没有来源 home 记录（本次改动之前删的条目），只能落回控制台自己的 home"
      }
      (console_home, false, reason)
    }
  }
  let root = @json.join_path(home, "profiles")
  let target = @json.join_path(root, profile)
  if !target.has_prefix(root + "/") || target == root {
    fail(
      "bad-params",
      "恢复目标解析到了这个 home 的 profiles 之外：" + target,
    )
  }
  if @json.exists(target) {
    fail(
      "conflict",
      "已经有同名的 profile 了（" +
      target +
      "），先给它改名或删掉它，再恢复这一份",
    )
  }
  let (files, bytes, size_source) = measure_entry(path)
  match @fsx.rename_path(path, target) {
    Ok(_) => ()
    Err(first) =>
      match @fsx.copy_tree(path, target, []) {
        Ok(_) =>
          match @fsx.remove_tree_fs(path) {
            Ok(_) => ()
            Err(e) => {
              note_raw(e.raw)
              fail("io-error", first + "；退回复制之后删源头也失败")
            }
          }
        Err(e) => {
          note_raw(e)
          fail("io-error", first + "；退回复制也失败")
        }
      }
  }
  // 这一条已经不在回收站里了，来源记录跟着清掉。清不掉不算恢复失败（那一份确实回去了），
  // 但原因要带出去：留着一条指向已不存在目录的记录不会误导谁，可不说就是瞒。
  let origin_error = match @store.drop_trash_origin(name) {
    Ok(_) => None
    Err(e) => Some(e)
  }
  {
    dir: name,
    profile,
    to: target,
    home,
    home_source,
    home_recorded,
    origin_error,
    files,
    bytes,
    size_source,
  }
}

///|
/// 彻底删除的结果。
pub struct PurgeOutcome {
  dir : String
  profile : String
  /// 被真删掉的那条路径
  path : String
  /// 删完之后没能把来源记录清掉的原因（None = 清掉了 / 本来就没有）
  origin_error : String?
  files : Int32?
  bytes : Int64?
  size_source : String
}

///|
/// 真删掉回收站里的一份。**必须带 confirm = "PURGE"**（与 delete-profile 的硬删同一风险等级）。
pub async fn purge_trash_item(
  dir : String,
  confirm : String?,
) -> PurgeOutcome raise ActionError {
  let path = resolve_trash_dir(dir)
  let given = match confirm {
    Some(v) => @json.trim_both(v)
    None => ""
  }
  if given != "PURGE" {
    fail(
      "bad-params", "彻底删除不可恢复，body 里必须再带 \"confirm\":\"PURGE\"",
    )
  }
  if !@json.is_dir(path) {
    fail("not-found", "回收站里没有这一份：" + path)
  }
  let name = @json.trim_both(dir)
  let (profile, _, _) = split_trash_name(name)
  let (files, bytes, size_source) = measure_entry(path)
  match @fsx.remove_tree_fs(path) {
    Ok(_) => ()
    Err(e) => {
      note_raw(e.raw)
      fail("io-error", "删目录失败")
    }
  }
  // 连来源记录一起清掉：这一份已经不存在了，留着一条指向它的记录只是垃圾。
  // 清不掉不算删除失败（东西确实没了），原因照旧带出去。
  let origin_error = match @store.drop_trash_origin(name) {
    Ok(_) => None
    Err(e) => Some(e)
  }
  { dir: name, profile, path, origin_error, files, bytes, size_source, }
}

// 配置快照的两个动作：snapshot-profile / restore-snapshot
// （design/ops-maintenance-jobs.md 第 16.3 节）。
//
// 两条都先过同一道守卫：这只 profile 有实例在跑就拒 —— 拍照读的是磁盘上的三个文件，
// 还原直接写它们，而实例下一次读配置就会撞上换了一半的内容。
// 守卫按 (home, 名字) 认，两个 home 都查：隔离的那一只实例跑在自己的 home 里。
//
// 还原的二次确认串（顶层 confirm:"RESTORE"）在动作层判，不在 profiles 包里：
// 那一层只管文件，不知道怎么回前端。

///|
/// 动配置之前的守卫：这只 profile 有实例在跑就拒（conflict）。
async fn config_write_guard(profile : String) -> Unit raise ActionError {
  let (console_home, _) = @runtime.resolve_dsh_home()
  let homes : Array[String] = [console_home]
  match @profiles.isolated_home_of(profile) {
    Some(isolated) => if isolated != console_home { homes.push(isolated) }
    None => ()
  }
  for home in homes {
    match running_for_profile_in(profile, Some(home)) {
      Some(hit) => {
        let port_text = match hit.port {
          Some(p) => "端口 " + p.to_string()
          None => "端口未识别"
        }
        fail(
          "conflict",
          "profile " +
          profile +
          " 正在跑（PID " +
          hit.pid.to_string() +
          "，" +
          port_text +
          "，home " +
          home +
          "）；先停掉它再动配置",
        )
      }
      None => ()
    }
  }
}

///|
/// 一次拍照的 outcome。
fn snapshot_outcome_json(
  profile : String,
  o : @profiles.SnapshotOutcome,
  keep : Int32,
) -> @json.JsonVal {
  @json.JObj([
    ("profile", @json.JStr(profile)),
    ("id", @json.JStr(o.id)),
    ("at", @json.JStr(o.at)),
    ("reason", @json.JStr(o.reason)),
    ("dir", @json.JStr(o.dir)),
    ("files", @json.jint(o.files)),
    ("bytes", @json.JNum(o.bytes.to_int().to_double())),
    ("copied", @json.jstr_array(o.copied)),
    ("missing", @json.jstr_array(o.missing)),
    ("pruned", @json.jstr_array(o.pruned)),
    ("skipped", @json.JBool(o.skipped)),
    ("keep", @json.jint(keep)),
  ])
}

///|
/// 拍照那一句回执：存了几份、落在哪、这次淘汰了几份旧的。
fn snapshot_note(
  profile : String,
  o : @profiles.SnapshotOutcome,
  keep : Int32,
) -> String {
  if o.skipped {
    return "当前状态和最近一份快照的内容完全一致（" +
      o.at +
      "，原因「" +
      o.reason +
      "」），没有新建"
  }
  let mut text = "已记录 " +
    profile +
    " 的当前状态作为快照：" +
    o.files.to_string() +
    " 个文件 · " +
    o.bytes.to_string() +
    " 字节，存在 " +
    o.dir
  if o.missing.length() > 0 {
    text = text +
      "（这只 profile 里没有：" +
      o.missing.join("、") +
      "）"
  }
  if o.pruned.length() > 0 {
    text = text +
      "；超过 " +
      keep.to_string() +
      " 份，淘汰了最旧的 " +
      o.pruned.length().to_string() +
      " 份（" +
      o.pruned.join("、") +
      "）"
  }
  text
}

///|
/// snapshot-profile：拍一张。reason 空则写「手动快照」。
pub async fn snapshot_profile_action(
  params : Json,
) -> @json.JsonVal raise ActionError {
  ensure_action_params(params, "创建快照：", ["profile", "reason"])
  let profile = require_string(params, "profile")
  validate_profile_name(profile)
  config_write_guard(profile)
  // 目录按它**现在在哪儿**取（隔离的那一只在自己的 home 里）
  let (dir, _home) = @profiles.profile_location(profile)
  if !@json.is_dir(dir) {
    fail("not-found", "profile 目录不存在：" + dir)
  }
  let reason = match optional_string(params, "reason") {
    Some(v) => v
    None => ""
  }
  let outcome = match @profiles.create_snapshot(dir, reason) {
    Ok(o) => o
    Err(e) => {
      fail("io-error", "快照没拍成：" + e)
      abort("unreachable: fail 一定抛错")
    }
  }
  let keep = @store.load_settings().values.snapshot_keep
  @json.JObj([
    ("action", @json.JStr("snapshot-profile")),
    ("outcome", snapshot_outcome_json(profile, outcome, keep)),
    ("note", @json.JStr(snapshot_note(profile, outcome, keep))),
  ])
}

///|
/// restore-snapshot：先拍「还原前」，再把快照里那三个文件写回去。
pub async fn restore_snapshot_action(
  params : Json,
  confirm : String?,
) -> @json.JsonVal raise ActionError {
  ensure_action_params(params, "还原快照：", ["profile", "snapshot"])
  let profile = require_string(params, "profile")
  validate_profile_name(profile)
  let id = require_string(params, "snapshot")
  if !@json.is_all_digits(id) {
    fail(
      "bad-params",
      "快照 id 只认数字，并且必须正好在 .snapshots 下：收到了 " +
      id,
    )
  }
  let given = match confirm {
    Some(v) => @json.trim_both(v)
    None => ""
  }
  if given != "RESTORE" {
    fail(
      "bad-params", "还原会用快照里的三个文件覆盖现在的内容；这是破坏性动作，body 顶层必须带 confirm 字段，值是 RESTORE",
    )
  }
  config_write_guard(profile)
  let (dir, _home) = @profiles.profile_location(profile)
  if !@json.is_dir(dir) {
    fail("not-found", "profile 目录不存在：" + dir)
  }
  match @profiles.snapshot_path_checked(dir, id) {
    None => {
      fail(
        "bad-params",
        "快照 id 拼出来的路径不在 .snapshots 下：" + id,
      )
      abort("unreachable: fail 一定抛错")
    }
    Some(_) => ()
  }
  let outcome = match @profiles.restore_snapshot(dir, id) {
    Ok(o) => o
    Err((code, message)) => {
      fail(code, message)
      abort("unreachable: fail 一定抛错")
    }
  }
  let restored = if outcome.restored.length() == 0 {
    "一个都没有（快照里那三个文件都不在）"
  } else {
    outcome.restored.join("、")
  }
  // 还原前那张：拍成功了说「记录了什么」，内容一致被去重命中时说「沿用了哪一份」
  let pre_text = if outcome.pre_snapshot.skipped {
    "当前状态和最近一份快照的内容完全一致（" +
    outcome.pre_snapshot.at +
    "，原因「" +
    outcome.pre_snapshot.reason +
    "」），沿用它作为还原前的那张"
  } else {
    "已记录 " +
    profile +
    " 的当前状态作为「还原前」快照（" +
    outcome.pre_snapshot.id +
    "）"
  }
  let mut note = pre_text +
    "，再把 " +
    outcome.at +
    " 那一份写回去；恢复了 " +
    outcome.restored.length().to_string() +
    " 个文件：" +
    restored
  if outcome.missing_in_snapshot.length() > 0 {
    note = note +
      "。快照里本来就没有：" +
      outcome.missing_in_snapshot.join("、") +
      "（profile 里这几份没动）"
  }
  @json.JObj([
    ("action", @json.JStr("restore-snapshot")),
    (
      "outcome",
      @json.JObj([
        ("profile", @json.JStr(profile)),
        ("id", @json.JStr(outcome.id)),
        ("at", @json.JStr(outcome.at)),
        ("reason", @json.JStr(outcome.reason)),
        ("dir", @json.JStr(outcome.dir)),
        ("restored", @json.jstr_array(outcome.restored)),
        ("missingInSnapshot", @json.jstr_array(outcome.missing_in_snapshot)),
        (
          "preSnapshot",
          snapshot_outcome_json(
            profile,
            outcome.pre_snapshot,
            @store.load_settings().values.snapshot_keep,
          ),
        ),
      ]),
    ),
    ("note", @json.JStr(note)),
  ])
}

///|
/// delete-snapshot：删掉一份快照。
///
/// 快照本身就是备份，所以这里不弹确认框；但 id 必须过 snapshot_path_checked ——
/// 只认纯数字、且拼出来的路径正好在 <profile>/.snapshots 下。
pub async fn delete_snapshot_action(
  params : Json,
) -> @json.JsonVal raise ActionError {
  ensure_action_params(params, "删除快照：", ["profile", "snapshot"])
  let profile = require_string(params, "profile")
  validate_profile_name(profile)
  let id = require_string(params, "snapshot")
  if !@json.is_all_digits(id) {
    fail(
      "bad-params",
      "快照 id 只认数字，并且必须正好在 .snapshots 下：收到了 " +
      id,
    )
  }
  config_write_guard(profile)
  let (dir, _home) = @profiles.profile_location(profile)
  if !@json.is_dir(dir) {
    fail("not-found", "profile 目录不存在：" + dir)
  }
  let path = match @profiles.snapshot_path_checked(dir, id) {
    Some(p) => p
    None => {
      fail(
        "bad-params",
        "快照 id 拼出来的路径不在 .snapshots 下：" + id,
      )
      abort("unreachable: fail 一定抛错")
    }
  }
  if !@json.is_dir(path) {
    fail("not-found", "快照不存在：" + path)
  }
  match @fsx.remove_tree_fs(path) {
    Ok(_) => ()
    Err(e) => {
      @store.note_raw(e.raw)
      fail("io-error", "删这份快照失败，磁盘上还在：" + path)
    }
  }
  @json.JObj([
    ("action", @json.JStr("delete-snapshot")),
    (
      "outcome",
      @json.JObj([
        ("profile", @json.JStr(profile)),
        ("snapshot", @json.JStr(id)),
      ]),
    ),
    (
      "note",
      @json.JStr(
        "已删掉 " +
        @json.iso_from_epoch_ms(@json.parse_dec64(id)) +
        " 那一份快照",
      ),
    ),
  ])
}

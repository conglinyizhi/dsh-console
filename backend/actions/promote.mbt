// 整体替换的两个动作：promote-preview（只读）/ promote-profile（写）
// （design/ops-maintenance-jobs.md 第 17 节）。
//
// 差异怎么算、文件怎么写都在 profiles/promote.mbt；这里负责三件它管不了的事：
//   1. blockers：目标有实例在跑 / 源与目标是同一只 / 源读不到配置 —— 要进程表才判得出；
//   2. 回执的形状（前端照这份 JSON 摆预览、写提示）；
//   3. 二次确认串 PROMOTE（body 顶层）与失败时的错误码。
//
// 预览只读：这个动作里一个写调用都没有，也不拍快照。快照只在 promote-profile 里拍。

///|
/// 三条 blocker 的原话（design/ops-maintenance-jobs.md §17.4，一字不改）。
pub let promote_blocker_running : String = "目标这只正在跑，先停掉它再替换"

///|
pub let promote_blocker_same : String = "源与目标是同一只"

///|
pub let promote_blocker_unreadable : String = "源这只读不到配置"

///|
/// 这只 profile 在**任何一个 home** 里有没有实例在跑。
///
/// 两个 home 都查（与控制台起实例、改配置的那几条守卫同一口径）：隔离的那一只跑在
/// 自己的 home 里，只按控制台的 home 查会把它说成没在跑。
async fn running_any_home(profile : String) -> Target? noraise {
  let (console_home, _) = @runtime.resolve_dsh_home()
  let homes : Array[String] = [console_home]
  match @profiles.isolated_home_of(profile) {
    Some(isolated) => if isolated != console_home { homes.push(isolated) }
    None => ()
  }
  for home in homes {
    match running_for_profile_in(profile, Some(home)) {
      Some(hit) => return Some(hit)
      None => ()
    }
  }
  None
}

///|
/// 这一趟能不能应用。空数组 = 能。
async fn promote_blockers(
  source : String,
  target : String,
  source_ok : Bool,
) -> Array[String] noraise {
  let out : Array[String] = []
  match running_any_home(target) {
    Some(_) => out.push(promote_blocker_running)
    None => ()
  }
  if source == target {
    out.push(promote_blocker_same)
  }
  if !source_ok {
    out.push(promote_blocker_unreadable)
  }
  out
}

///|
/// 一边的身份（名字 / 目录 / home 归属）。
fn promote_side_json(side : @profiles.PromoteSide) -> @json.JsonVal {
  @json.JObj([
    ("name", @json.JStr(side.name)),
    ("dir", @json.JStr(side.dir)),
    ("homeKind", @json.JStr(side.home_kind)),
    ("homePath", @json.JStr(side.home_path)),
    ("profileDir", @json.JStr(side.profile_dir)),
    ("configOk", @json.JBool(side.config_ok)),
  ])
}

///|
/// 一条覆盖项的原文。
fn patch_entry_json(entry : @profiles.PromotePatchEntry) -> @json.JsonVal {
  @json.JObj([("id", @json.JStr(entry.id)), ("text", @json.JStr(entry.text))])
}

///|
/// 同 id 两边原文不一样的那一条：两边全文都给（界面并排摆）。
fn patch_change_json(change : @profiles.PromotePatchChange) -> @json.JsonVal {
  @json.JObj([
    ("id", @json.JStr(change.id)),
    ("sourceText", @json.JStr(change.source_text)),
    ("targetText", @json.JStr(change.target_text)),
  ])
}

///|
/// 同名不同版本的一个包。
fn package_version_json(
  item : @profiles.PromotePackageVersion,
) -> @json.JsonVal {
  @json.JObj([
    ("name", @json.JStr(item.name)),
    ("sourceVersion", @json.JStr(item.source_version)),
    ("targetVersion", @json.JStr(item.target_version)),
  ])
}

///|
/// 预览的 outcome（§17.1 的四段 + 身份 + blockers）。
fn promote_facts_json(
  facts : @profiles.PromoteFacts,
  blockers : Array[String],
) -> @json.JsonVal {
  @json.JObj([
    ("from", promote_side_json(facts.source)),
    ("to", promote_side_json(facts.target)),
    // 文件：源里有目标没有的 / 会被写过去的 / 目标有源里没有的（不删）
    ("files", @json.jstr_array(facts.files_new)),
    ("filesWritten", @json.jstr_array(facts.files_write)),
    ("filesTargetOnly", @json.jstr_array(facts.files_target_only)),
    ("filesMissingInSource", @json.jstr_array(facts.files_missing_in_source)),
    (
      "bundles",
      @json.JObj([
        ("added", @json.jstr_array(facts.bundles.added)),
        ("removed", @json.jstr_array(facts.bundles.removed)),
        ("reordered", @json.JBool(facts.bundles.reordered)),
        ("fromOrder", @json.jstr_array(facts.bundles.from_order)),
        ("toOrder", @json.jstr_array(facts.bundles.to_order)),
      ]),
    ),
    (
      "patches",
      @json.JObj([
        ("added", @json.JArr(facts.patches.added.map(patch_entry_json))),
        ("changed", @json.JArr(facts.patches.changed.map(patch_change_json))),
        ("removed", @json.JArr(facts.patches.removed.map(patch_entry_json))),
        ("anonymous", @json.jint(facts.patches.anonymous)),
      ]),
    ),
    (
      "packages",
      @json.JObj([
        ("added", @json.jstr_array(facts.packages.added)),
        (
          "versionMismatch",
          @json.JArr(facts.packages.version_mismatch.map(package_version_json)),
        ),
      ]),
    ),
    ("blockers", @json.jstr_array(blockers)),
    ("notes", @json.jstr_array(facts.notes)),
  ])
}

///|
/// 预览那一句人话（进回执的悬停，也给 curl 直接看）。
fn preview_note(
  facts : @profiles.PromoteFacts,
  blockers : Array[String],
) -> String {
  if blockers.length() > 0 {
    return "这一趟不能应用：" + blockers.join("；")
  }
  let parts : Array[String] = []
  parts.push(
    "写 " + facts.files_write.length().to_string() + " 份配置文件",
  )
  parts.push(
    "插件 " +
    facts.bundles.added.length().to_string() +
    " 个会多出来、" +
    facts.bundles.removed.length().to_string() +
    " 个会丢",
  )
  parts.push(
    "覆盖项 " +
    facts.patches.added.length().to_string() +
    " 条新增、" +
    facts.patches.changed.length().to_string() +
    " 条改写、" +
    facts.patches.removed.length().to_string() +
    " 条移除",
  )
  parts.push(
    "本地包 " +
    facts.packages.added.length().to_string() +
    " 个会搬过去",
  )
  "用 " +
  facts.source.name +
  " 的配置替换 " +
  facts.target.name +
  "：" +
  parts.join("，")
}

///|
/// promote-preview（只读）：算一遍差异，不写任何文件。
pub async fn promote_preview_action(
  params : Json,
) -> @json.JsonVal raise ActionError {
  ensure_action_params(params, "整体替换预览：", ["from", "to"])
  let source = require_string(params, "from")
  let target = require_string(params, "to")
  validate_profile_name(source)
  validate_profile_name(target)
  // 预览同样要名字先过白名单：它虽然不写，但它会把拼出来的目录原样回给界面
  let facts = @profiles.promote_facts(source, target)
  let blockers = promote_blockers(source, target, facts.source.config_ok)
  @json.JObj([
    ("action", @json.JStr("promote-preview")),
    ("outcome", promote_facts_json(facts, blockers)),
    ("note", @json.JStr(preview_note(facts, blockers))),
  ])
}

///|
/// 应用的回执（§17.2 第 5 条 + §17.4 那一句）。
fn promote_outcome_json(o : @profiles.PromoteOutcome) -> @json.JsonVal {
  let snapshot = o.snapshot
  @json.JObj([
    ("from", @json.JStr(o.source_name)),
    ("to", @json.JStr(o.target_name)),
    ("targetDir", @json.JStr(o.target_dir)),
    ("written", @json.jstr_array(o.written)),
    ("missingInSource", @json.jstr_array(o.missing_in_source)),
    ("packagesMoved", @json.jstr_array(o.packages_moved)),
    ("packagesSkipped", @json.jstr_array(o.packages_skipped)),
    ("packageNotes", @json.jstr_array(o.package_notes)),
    // 源这一边只读过：这一句讲的是这一趟做过什么，不是猜的
    (
      "sourceNote",
      @json.JStr("源 profile 只读：这一趟只写目标那一边"),
    ),
    (
      "snapshot",
      @json.JObj([
        ("id", @json.JStr(snapshot.id)),
        ("at", @json.JStr(snapshot.at)),
        ("reason", @json.JStr(snapshot.reason)),
        ("dir", @json.JStr(snapshot.dir)),
        ("files", @json.jint(snapshot.files)),
        ("bytes", @json.JNum(snapshot.bytes.to_int().to_double())),
        ("copied", @json.jstr_array(snapshot.copied)),
        ("missing", @json.jstr_array(snapshot.missing)),
        ("keep", @json.jint(@profiles.snapshot_keep)),
      ]),
    ),
  ])
}

///|
/// 应用的回执那一段话。原话照 §17.4：
///   <目标> 的配置已用 <源> 替换（写了 N 份文件，搬了 N 个包，跳过 N 个已存在的包）；替换前快照 <id>
fn promote_receipt_note(o : @profiles.PromoteOutcome) -> String {
  o.target_name +
  " 的配置已用 " +
  o.source_name +
  " 替换（写了 " +
  o.written.length().to_string() +
  " 份文件，搬了 " +
  o.packages_moved.length().to_string() +
  " 个包，跳过 " +
  o.packages_skipped.length().to_string() +
  " 个已存在的包）；替换前快照 " +
  o.snapshot.id
}

///|
/// promote-profile（写）：重跑检查、拍快照、写三份配置、搬本地包。
pub async fn promote_profile_action(
  params : Json,
  confirm : String?,
) -> @json.JsonVal raise ActionError {
  ensure_action_params(params, "整体替换：", ["from", "to"])
  let source = require_string(params, "from")
  let target = require_string(params, "to")
  validate_profile_name(source)
  validate_profile_name(target)
  let given = match confirm {
    Some(v) => @json.trim_both(v)
    None => ""
  }
  if given != "PROMOTE" {
    fail(
      "bad-params", "整体替换会改写目标 profile 的配置；这是破坏性动作，body 顶层必须带 confirm 字段，值是 PROMOTE",
    )
  }
  // 重跑一遍预览的检查（§17.2 第 1 条）：预览之后目标可能被起了实例，也可能源被删了
  let facts = @profiles.promote_facts(source, target)
  let blockers = promote_blockers(source, target, facts.source.config_ok)
  if blockers.length() > 0 {
    fail("conflict", blockers.join("；"))
  }
  let outcome = match @profiles.apply_promote(source, target) {
    Ok(o) => o
    Err((code, message)) => {
      fail(code, message)
      abort("unreachable: fail 一定抛错")
    }
  }
  @json.JObj([
    ("action", @json.JStr("promote-profile")),
    ("outcome", promote_outcome_json(outcome)),
    ("note", @json.JStr(promote_receipt_note(outcome))),
  ])
}

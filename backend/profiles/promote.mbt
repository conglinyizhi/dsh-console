// 整体替换：把一只 profile 的配置换成另一只的（design/ops-maintenance-jobs.md 第 17 节）。
//
// 这一层只管磁盘，两层分开：
//   promote_facts   只读：把两边的差异算出来（文件 / 插件清单 / 覆盖项 / 本地包）
//   apply_promote   写：先给目标拍一张快照，再写三份配置、搬本地包
//
// 源 profile 一个字节都不动：这里只读它，写只写目标那一边。
// 「谁在跑」的判据不在这层：那要进程表，见 actions/promote.mbt 的 blockers。

///|
/// 整体替换会写过去的三份配置文件（有才写，与快照存的那三份同一套名字）。
pub let promote_config_files : Array[String] = [
  "package.json", "cordis.patch.yml", "pnpm-workspace.yaml",
]

///|
/// 替换之前给目标拍的那张快照，reason 固定写它（规格 17.2 第 2 条）。
pub let pre_promote_reason : String = "替换前"

///|
/// 一边（源或目标）的身份：名字、现在所在的目录、home 归属、配置读不读得到。
pub(all) struct PromoteSide {
  name : String
  dir : String
  home_kind : String
  home_path : String
  profile_dir : String
  /// package.json 在、且解析得动（与读数里的 packageJson 同一把尺子）
  config_ok : Bool
}

///|
/// 插件清单的三档差异（package.json 的 dsh.profile.bundles）。
pub(all) struct PromoteBundleDiff {
  /// 源里有、目标里没有（替换之后会多出来）
  added : Array[String]
  /// 目标里有、源里没有（替换之后会丢的就是这几条）
  removed : Array[String]
  /// 两边是同一批包，但顺序不一样
  reordered : Bool
  from_order : Array[String]
  to_order : Array[String]
}

///|
/// cordis.patch.yml 里的一条：id 与这一条的原文（含下面几行）。
pub(all) struct PromotePatchEntry {
  /// 条目没有 id 时给空串（原文照旧带出来，比对按整段原文）
  id : String
  text : String
}

///|
/// 同 id 两边原文不一样的那一条：两边都给全文，界面并排摆。
pub(all) struct PromotePatchChange {
  id : String
  source_text : String
  target_text : String
}

///|
/// 覆盖项的三档。
pub(all) struct PromotePatchDiff {
  added : Array[PromotePatchEntry]
  changed : Array[PromotePatchChange]
  removed : Array[PromotePatchEntry]
  /// 没有 id 的条目条数（这类只能按整段原文比，界面上要说清）
  anonymous : Int32
}

///|
/// 同名但版本不一样的一个包。
pub(all) struct PromotePackageVersion {
  name : String
  source_version : String
  target_version : String
}

///|
/// 本地包的两档。
pub(all) struct PromotePackageDiff {
  /// 源有目标没有：这些会被搬过去
  added : Array[String]
  /// 同名不同版本：不搬也不覆盖，单独列出来
  version_mismatch : Array[PromotePackageVersion]
}

///|
/// 一次预览算出来的全部事实（只读，不写任何文件）。
pub(all) struct PromoteFacts {
  source : PromoteSide
  target : PromoteSide
  /// 源里有、目标里没有的文件名（这三份里）
  files_new : Array[String]
  /// 源里有、会被写过去的文件名
  files_write : Array[String]
  /// 目标有、源里没有（不删，替换之后仍然在）
  files_target_only : Array[String]
  /// 源里没有的那几份（这一趟不写）
  files_missing_in_source : Array[String]
  bundles : PromoteBundleDiff
  patches : PromotePatchDiff
  packages : PromotePackageDiff
  /// 算的过程中读不到的地方（人话，照实摆出来，不编内容）
  notes : Array[String]
}

///|
/// 一次应用的结果。
pub(all) struct PromoteOutcome {
  source_name : String
  target_name : String
  target_dir : String
  /// 真的写过去的那几份配置文件
  written : Array[String]
  /// 源里本来就没有、没写的（不算错）
  missing_in_source : Array[String]
  /// 搬过去的包名
  packages_moved : Array[String]
  /// 同名已存在、没覆盖的包名
  packages_skipped : Array[String]
  /// 搬的过程里要说清的事（软链按原样重建、包里跳过了非普通文件之类）
  package_notes : Array[String]
  /// 替换前那张快照
  snapshot : SnapshotOutcome
}

///|
/// 路径在不在，**不跟随软链**：一条断掉的软链也算「在」。
/// 目标里已经有这个名字就不覆盖，判断必须按这一条来（follow 之后断链会被当成不存在）。
async fn path_present(path : String) -> Bool noraise {
  let kind = @fs.kind(path, follow_symlink=false) catch { _ => Unknown }
  match kind {
    Unknown => false
    _ => true
  }
}

///|
/// 读一份配置文件的原文；不在 / 读不动给 None。
async fn read_config_text(dir : String, name : String) -> String? noraise {
  match @json.read_text_file(@json.join_path(dir, name)) {
    Ok(text) => Some(text)
    Err(_) => None
  }
}

///|
/// 一边的身份（名字、目录、home 归属、配置读不读得到）。
async fn promote_side(name : String) -> PromoteSide noraise {
  let (dsh_home, dsh_home_source) = @runtime.resolve_dsh_home()
  let (dir, _home) = profile_location(name)
  let home = home_fact_in(name, dsh_home, dsh_home_source)
  let ok = @json.is_dir(dir) && package_json_ok(dir)
  {
    name,
    dir,
    home_kind: home.kind,
    home_path: home.path,
    profile_dir: home.profile_dir,
    config_ok: ok,
  }
}

///|
/// 两个字符串数组是不是逐项相同（Array 的 == 在 core 里不是逐项比较，这里自己走一遍）。
fn same_strings(a : Array[String], b : Array[String]) -> Bool {
  if a.length() != b.length() {
    return false
  }
  let mut i = 0
  while i < a.length() {
    if a[i] != b[i] {
      return false
    }
    i = i + 1
  }
  true
}

///|
/// 插件清单的差异。
fn bundle_diff(
  from_order : Array[String],
  to_order : Array[String],
) -> PromoteBundleDiff {
  let added : Array[String] = []
  for name in from_order {
    if !to_order.contains(name) {
      added.push(name)
    }
  }
  let removed : Array[String] = []
  for name in to_order {
    if !from_order.contains(name) {
      removed.push(name)
    }
  }
  let reordered = added.length() == 0 &&
    removed.length() == 0 &&
    !same_strings(from_order, to_order)
  { added, removed, reordered, from_order, to_order, }
}

///|
/// 一行是不是 patch 里一条**顶层**列表项：连字符顶在行首（缩进的 - 是上一条里的嵌套列表）。
fn is_patch_entry_start(line : String) -> Bool {
  if line == "-" {
    return true
  }
  line.has_prefix("- ")
}

///|
/// 去掉一层引号（id 写成 "credentials" 与 credentials 都算同一个）。
fn unquote_id(value : String) -> String {
  if value.length() >= 2 && value.has_prefix("\"") && value.has_suffix("\"") {
    @json.slice(value, 1, value.length() - 1)
  } else {
    value
  }
}

///|
/// 一条 patch 条目的 id：块里第一处 id: 那一行的值；没有就给空串。
fn patch_entry_id(text : String) -> String {
  for raw in text.split("\n") {
    let line = @json.trim_both(@json.owned(raw))
    let body = if line.has_prefix("- ") {
      @json.trim_both(@json.slice_from(line, 2))
    } else if line == "-" {
      ""
    } else {
      line
    }
    if body.has_prefix("id:") {
      return unquote_id(@json.trim_both(@json.slice_from(body, 3)))
    }
  }
  ""
}

///|
/// 拼回一条条目的原文：去掉末尾的空行（文件末尾那一行换行不是内容）。
fn trim_block(lines : Array[String]) -> String {
  let mut end = lines.length()
  while end > 0 && @json.trim_both(lines[end - 1]) == "" {
    end = end - 1
  }
  let kept : Array[String] = []
  for i = 0; i < end; i = i + 1 {
    kept.push(lines[i])
  }
  kept.join("\n")
}

///|
/// 把 cordis.patch.yml 拆成条目。只认顶层的 “- ”（缩进的那些是上一条的嵌套列表）。
///
/// 拆不出来（不是 YAML、或这里认得的形状之外）时返回空数组并把原因写进第二个返回值：
/// 「这份 patch 一条都没解析出来」与「它本来就是空的」不是一件事。
fn parse_patch_entries(text : String) -> (Array[PromotePatchEntry], String) {
  let lines : Array[String] = []
  for raw in text.split("\n") {
    lines.push(@json.owned(raw))
  }
  let out : Array[PromotePatchEntry] = []
  let n = lines.length()
  let mut i = 0
  while i < n {
    if is_patch_entry_start(lines[i]) {
      let body : Array[String] = [lines[i]]
      let mut j = i + 1
      while j < n && !is_patch_entry_start(lines[j]) {
        body.push(lines[j])
        j = j + 1
      }
      let block = trim_block(body)
      out.push({ id: patch_entry_id(block), text: block, })
      i = j
    } else {
      i = i + 1
    }
  }
  let trimmed = @json.trim_both(text)
  let note = if out.length() > 0 {
    ""
  } else if trimmed == "" || trimmed == "[]" {
    ""
  } else {
    "这份 cordis.patch.yml 里没有认出任何一条顶层条目（只认行首的 “- ”）"
  }
  (out, note)
}

///|
/// 按 id 找一条。
fn find_patch_entry(
  entries : Array[PromotePatchEntry],
  id : String,
) -> PromotePatchEntry? {
  for entry in entries {
    if entry.id == id {
      return Some(entry)
    }
  }
  None
}

///|
/// 覆盖项的差异。同 id 的两条比对时先各自去掉首尾空白：文件末尾多一个换行不算「改了内容」，
/// 但两边原文仍旧整段带出来（界面要并排给人看）。
fn patch_diff(
  source_entries : Array[PromotePatchEntry],
  target_entries : Array[PromotePatchEntry],
) -> PromotePatchDiff {
  let added : Array[PromotePatchEntry] = []
  let changed : Array[PromotePatchChange] = []
  let removed : Array[PromotePatchEntry] = []
  let mut anonymous = 0
  for entry in source_entries {
    if entry.id == "" {
      anonymous = anonymous + 1
      let found = target_entries.any(fn(other) {
        other.id == "" &&
        @json.trim_both(other.text) == @json.trim_both(entry.text)
      })
      if !found {
        added.push(entry)
      }
      continue
    }
    match find_patch_entry(target_entries, entry.id) {
      Some(other) =>
        if @json.trim_both(other.text) != @json.trim_both(entry.text) {
          changed.push({
            id: entry.id,
            source_text: entry.text,
            target_text: other.text,
          })
        }
      None => added.push(entry)
    }
  }
  for other in target_entries {
    if other.id == "" {
      // 没有 id 的已经在上面的循环里按整段原文对过了，这里不重复算
      continue
    }
    match find_patch_entry(source_entries, other.id) {
      Some(_) => ()
      None => removed.push(other)
    }
  }
  { added, changed, removed, anonymous, }
}

///|
/// 一份 node_modules 下认得出来的包名（跳过以点开头的条目：.bin、.pnpm 这些是安装工具的目录）。
/// @scope 这一层不进包名，包里那一层才是（@scope/name）。
async fn package_names(node_modules : String) -> Array[String] noraise {
  let out : Array[String] = []
  if !@json.is_dir(node_modules) {
    return out
  }
  for entry in @json.list_entries(node_modules) {
    let (name, _is_dir) = entry
    if name == "" || name.has_prefix(".") {
      continue
    }
    if name.has_prefix("@") {
      let scope_dir = @json.join_path(node_modules, name)
      for sub in @json.list_entries(scope_dir) {
        let (child, _child_is_dir) = sub
        if child != "" && !child.has_prefix(".") {
          out.push(name + "/" + child)
        }
      }
    } else {
      out.push(name)
    }
  }
  out.sort_by(compare_code_units)
  out
}

///|
/// 一个包目录里 package.json 的 version；读不到给空串（不编一个版本号）。
async fn package_version(pkg_dir : String) -> String noraise {
  match @json.read_text_file(@json.join_path(pkg_dir, "package.json")) {
    Err(_) => ""
    Ok(text) =>
      match @json.json_parse(text) {
        None => ""
        Some(json) =>
          match @json.json_field(json, "version") {
            Some(value) =>
              match @json.json_string(value) {
                Some(s) => s
                None => ""
              }
            None => ""
          }
      }
  }
}

///|
/// 本地包的差异：源里有目标没有的（会被搬过去）、同名不同版本的（单独列出）。
async fn package_diff(
  source_nm : String,
  target_nm : String,
) -> PromotePackageDiff noraise {
  let added : Array[String] = []
  let mismatch : Array[PromotePackageVersion] = []
  for name in package_names(source_nm) {
    let source_pkg = @json.join_path(source_nm, name)
    let target_pkg = @json.join_path(target_nm, name)
    if !path_present(target_pkg) {
      added.push(name)
      continue
    }
    let from_version = package_version(source_pkg)
    let to_version = package_version(target_pkg)
    if from_version != "" && to_version != "" && from_version != to_version {
      mismatch.push({
        name,
        source_version: from_version,
        target_version: to_version,
      })
    }
  }
  { added, version_mismatch: mismatch, }
}

///|
/// 算一次预览的全部事实。**只读**：这里一个写调用都没有。
pub async fn promote_facts(
  source_name : String,
  target_name : String,
) -> PromoteFacts noraise {
  let source = promote_side(source_name)
  let target = promote_side(target_name)
  let notes : Array[String] = []
  let files_new : Array[String] = []
  let files_write : Array[String] = []
  let files_target_only : Array[String] = []
  let files_missing : Array[String] = []
  for name in promote_config_files {
    let in_source = @json.exists(@json.join_path(source.dir, name))
    let in_target = @json.exists(@json.join_path(target.dir, name))
    if in_source {
      files_write.push(name)
      if !in_target {
        files_new.push(name)
      }
    } else {
      files_missing.push(name)
      if in_target {
        files_target_only.push(name)
      }
    }
  }
  if files_write.length() == 0 {
    notes.push(
      "源 profile 的三份配置文件一份都没有，这一趟没有可写的",
    )
  }
  // 插件清单从 package.json 的 dsh.profile.bundles 读（与读数那一侧同一个判据）
  let bundles = bundle_diff(
    declared_bundles(source.dir),
    declared_bundles(target.dir),
  )
  // 覆盖项：两边各拆一次 cordis.patch.yml
  let source_patch_entries = match
    read_config_text(source.dir, "cordis.patch.yml") {
    None => {
      notes.push(
        "源 profile 里没有 cordis.patch.yml，覆盖项只能按目标那一边列",
      )
      ([] : Array[PromotePatchEntry])
    }
    Some(text) => {
      let (entries, note) = parse_patch_entries(text)
      if note != "" {
        notes.push("源 profile 的：" + note)
      }
      entries
    }
  }
  let target_patch_entries = match
    read_config_text(target.dir, "cordis.patch.yml") {
    None => ([] : Array[PromotePatchEntry])
    Some(text) => {
      let (entries, note) = parse_patch_entries(text)
      if note != "" {
        notes.push("目标 profile 的：" + note)
      }
      entries
    }
  }
  let patches = patch_diff(source_patch_entries, target_patch_entries)
  if patches.anonymous > 0 {
    notes.push(
      "覆盖项里有 " +
      patches.anonymous.to_string() +
      " 条没有 id 的条目：这几条按整段原文比，同 id 并排的那一套对它们不适用",
    )
  }
  // 本地包：两边的 node_modules（profile 自己那一份；没有就按「没有包可比」算）
  let source_nm = @json.join_path(source.dir, "node_modules")
  let target_nm = @json.join_path(target.dir, "node_modules")
  let packages = if @json.is_dir(source_nm) {
    package_diff(source_nm, target_nm)
  } else {
    notes.push(
      "源 profile 里没有 node_modules，这一趟没有本地包要搬",
    )
    (
      {
        added: ([] : Array[String]),
        version_mismatch: ([] : Array[PromotePackageVersion]),
      } : PromotePackageDiff)
  }
  if !@json.is_dir(target_nm) && packages.added.length() > 0 {
    notes.push(
      "目标 profile 里没有 node_modules，搬包时会把这一层建出来：" +
      target_nm,
    )
  }
  {
    source,
    target,
    files_new,
    files_write,
    files_target_only,
    files_missing_in_source: files_missing,
    bundles,
    patches,
    packages,
    notes,
  }
}

///|
/// 搬一个包：源里有、目标里没有的那一个目录。
///
/// 三种形状分开处理（只复制目录、或按原样重建软链，不跟随软链把 .pnpm 里那份整棵抄过来）：
///   普通目录 -> 递归复制（非普通文件跳过并记名）
///   软链     -> 按原样重建一条同样的软链（目标字符串逐字保留）
///   普通文件 -> 复制这一份文件
async fn move_package(
  source_pkg : String,
  target_pkg : String,
) -> Result[Array[String], String] noraise {
  let notes : Array[String] = []
  match @fsx.to_result_unit(@fsx.ensure_dir_fs(@json.dirname(target_pkg))) {
    Ok(_) => ()
    Err(e) => return Err(e)
  }
  let kind = @fs.kind(source_pkg, follow_symlink=false) catch { _ => Unknown }
  match kind {
    Directory =>
      match @fsx.copy_tree(source_pkg, target_pkg, []) {
        Ok(stats) =>
          if stats.skipped.length() > 0 {
            notes.push(
              "包里的非普通文件跳过了：" + stats.skipped.join("、"),
            )
          }
        Err(e) => return Err(e)
      }
    SymLink => {
      let link_target = match @json.read_link(source_pkg) {
        Ok(value) => value
        Err(e) => return Err(e)
      }
      match @fsx.to_result_unit(@fsx.make_symlink_fs(link_target, target_pkg)) {
        Ok(_) => ()
        Err(e) => return Err(e)
      }
      notes.push(
        "这是一条软链，按原样重建（指向 " + link_target + "）",
      )
    }
    Regular =>
      match @fsx.copy_file(source_pkg, target_pkg) {
        Ok(_) => ()
        Err(e) => return Err(e)
      }
    _ =>
      return Err(
        "这一条既不是目录也不是软链，没有搬：" + source_pkg,
      )
  }
  Ok(notes)
}

///|
/// 应用一次替换（规格 17.2 的第 2 到第 4 步）：
///   1. 先把源的三份读进内存（读失败时目标一个文件都还没动）；
///   2. 给目标拍一张快照，reason「替换前」（拍不成就不往下走）；
///   3. 把三份写过去；
///   4. 把源里目标没有的本地包搬过去，同名已存在的不覆盖、列进跳过项。
///
/// blockers（谁在跑 / 同一只 / 源读不到）由调用方先判：那一层要进程表。
async fn apply_promote_inner(
  source_name : String,
  target_name : String,
) -> Result[PromoteOutcome, (String, String)] noraise {
  let source = promote_side(source_name)
  let target = promote_side(target_name)
  if !source.config_ok {
    return Err(
      (
        "conflict",
        "源这只读不到配置：" +
        source.dir +
        " 的 package.json 读不出来",
      ),
    )
  }
  if !@json.is_dir(target.dir) {
    return Err(("not-found", "目标 profile 目录不存在：" + target.dir))
  }
  // 1. 先把源读进内存
  let payloads : Array[(String, Bytes)] = []
  let missing : Array[String] = []
  for name in promote_config_files {
    let path = @json.join_path(source.dir, name)
    if !@json.exists(path) {
      missing.push(name)
      continue
    }
    match @fsx.read_bytes(path) {
      Ok(data) => payloads.push((name, data))
      Err(e) =>
        return Err(
          (
            "io-error",
            "读源 profile 的 " +
            name +
            " 失败（" +
            e +
            "）；目标里一个文件都没动",
          ),
        )
    }
  }
  // 2. 替换前快照
  let snapshot = match create_snapshot(target.dir, pre_promote_reason) {
    Ok(o) => o
    Err(e) =>
      return Err(
        (
          "io-error",
          "替换前那张快照没拍成（" +
          e +
          "）；目标里一个文件都没动",
        ),
      )
  }
  // 3. 写三份配置
  let written : Array[String] = []
  for pair in payloads {
    let (name, data) = pair
    match @fsx.to_result_unit(@fsx.write_bytes_fs(@json.join_path(target.dir, name), data)) {
      Ok(_) => written.push(name)
      Err(e) =>
        return Err(
          (
            "io-error",
            "写 " +
            name +
            " 失败（" +
            e +
            "）；已经写了：" +
            describe_files(written) +
            "；替换前快照 " +
            snapshot.id,
          ),
        )
    }
  }
  // 4. 搬本地包：源 node_modules 里有、目标里没有的
  let moved : Array[String] = []
  let skipped : Array[String] = []
  let package_notes : Array[String] = []
  let source_nm = @json.join_path(source.dir, "node_modules")
  let target_nm = @json.join_path(target.dir, "node_modules")
  if @json.is_dir(source_nm) {
    for name in package_names(source_nm) {
      let source_pkg = @json.join_path(source_nm, name)
      let target_pkg = @json.join_path(target_nm, name)
      if path_present(target_pkg) {
        skipped.push(name)
        continue
      }
      match move_package(source_pkg, target_pkg) {
        Ok(notes) => {
          moved.push(name)
          for note in notes {
            package_notes.push(name + "：" + note)
          }
        }
        Err(e) =>
          return Err(
            (
              "io-error",
              "搬包 " +
              name +
              " 失败（" +
              e +
              "）；已经搬了：" +
              describe_files(moved) +
              "；跳过了：" +
              describe_files(skipped) +
              "；替换前快照 " +
              snapshot.id,
            ),
          )
      }
    }
  }
  Ok({
    source_name,
    target_name,
    target_dir: target.dir,
    written,
    missing_in_source: missing,
    packages_moved: moved,
    packages_skipped: skipped,
    package_notes,
    snapshot,
  })
}

///|
/// 对外的应用入口。名字先过单段那一关（拼出来的路径只可能是 profile 目录那一条）。
pub async fn apply_promote(
  source_name : String,
  target_name : String,
) -> Result[PromoteOutcome, (String, String)] noraise {
  let source = @json.trim_both(source_name)
  let target = @json.trim_both(target_name)
  if !single_segment(source) || !single_segment(target) {
    return Err(
      (
        "bad-params",
        "源与目标都要是单段的 profile 名：" +
        source +
        " / " +
        target,
      ),
    )
  }
  apply_promote_inner(source, target)
}

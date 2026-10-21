// 配置快照：拍一张 / 读出来 / 还原（design/ops-maintenance-jobs.md 第 16 节）。
//
// 落点：<profile 目录>/.snapshots/<毫秒时间戳>/
//   package.json / cordis.patch.yml / pnpm-workspace.yaml   有才存
//   meta.json            { "at": "<ISO>", "reason": "...", "files": N, "bytes": N }
// 保留最近 20 份，超出的按时间删最旧 —— 删除只限 .snapshots/ 下的数字目录。
//
// 三件事都不碰 git，也不动 profile 里别的东西：还原只写上面那三个文件。
// 候选快照 id 只认 [0-9]+，拼出来的路径必须正好是 <profile>/.snapshots/<id>；
// 这一道在这里（snapshot_path_checked），动作层不再自己拼一遍路径。

///|
/// 快照目录名（放在 profile 目录里，跟着目录走：改名、搬进隔离 home 都跟着）。
pub let snapshots_dir_name : String = ".snapshots"

///|
/// 保留最近多少份。超出的按 id（毫秒时间戳）从旧到新删。
pub let snapshot_keep : Int32 = 20

///|
/// 一份快照里要存的三个文件（有才存，缺的不算错）。
pub let snapshot_file_names : Array[String] = [
  "package.json", "cordis.patch.yml", "pnpm-workspace.yaml",
]

///|
/// 没写 reason 时用的那一个词（规格 16.3：reason 空则写「手动快照」）。
pub let default_snapshot_reason : String = "手动快照"

///|
/// 还原之前自动拍的那一张，reason 固定写它（规格 16.3）。
pub let pre_restore_reason : String = "还原前"

///|
/// 读数里的一份快照。at / reason / files / bytes 读自 meta.json；
/// meta.json 读不出来时 at 按目录名（毫秒时间戳）折算，其余给空 / 0，并在来源串里说清。
pub(all) struct SnapshotEntry {
  id : String
  at : String
  reason : String
  files : Int32
  bytes : Int64
}

///|
/// meta.json 的内容。
priv struct SnapshotMeta {
  at : String
  reason : String
  files : Int32
  bytes : Int64
}

///|
/// 拍一张的结果。
pub(all) struct SnapshotOutcome {
  id : String
  dir : String
  at : String
  reason : String
  files : Int32
  bytes : Int64
  /// 真的存进去的文件名（快照目录里的那几份）
  copied : Array[String]
  /// profile 目录里本来就没有的那几个（没存，不算错）
  missing : Array[String]
  /// 这一趟按上限淘汰掉的旧快照 id（从旧到新）
  pruned : Array[String]
}

///|
/// 还原的结果。
pub(all) struct RestoreOutcome {
  id : String
  at : String
  reason : String
  dir : String
  /// 真的写回 profile 目录的文件名
  restored : Array[String]
  /// 快照里本来就没有的那几个（没写，profile 里那一份原样留着）
  missing_in_snapshot : Array[String]
  /// 还原之前自动拍的那一张（「还原前」）
  pre_snapshot : SnapshotOutcome
}

///|
/// <profile 目录>/.snapshots。
pub fn snapshots_dir_of(profile_dir : String) -> String {
  @json.join_path(profile_dir, snapshots_dir_name)
}

///|
/// 快照 id 的校验：只认 [0-9]+，且拼出来的路径必须**正好**是 <profile>/.snapshots/<id>。
///
/// 两道都留着：is_all_digits 已经挡住 ".." / "../../x" / "a/b" 这类输入，
/// 下面再按 dirname / basename 对一次 —— 这一条是「路径落点」的正面判据，
/// 不依赖「数字串天然安全」这个推断。
pub fn snapshot_path_checked(profile_dir : String, id : String) -> String? {
  if !@json.is_all_digits(id) {
    return None
  }
  let base = snapshots_dir_of(profile_dir)
  let path = @json.join_path(base, id)
  if @json.dirname(path) != base {
    return None
  }
  if @json.basename(path) != id {
    return None
  }
  Some(path)
}

///|
/// 从 Json 取整数：数字（整数值）或纯数字串都认；别的给 0。
fn int_field(json : Json, key : String) -> Int32 {
  match @json.json_field(json, key) {
    Some(Number(d, ..)) =>
      if d == d.to_int().to_double() {
        d.to_int()
      } else {
        0
      }
    Some(String(s)) =>
      if @json.is_all_digits(s) {
        @json.parse_dec(s)
      } else {
        0
      }
    _ => 0
  }
}

///|
/// 从 Json 取 64 位整数（bytes 可能很大）：数字或纯数字串都认；别的给 0。
fn int64_field(json : Json, key : String) -> Int64 {
  match @json.json_field(json, key) {
    Some(Number(d, ..)) => d.to_int64()
    Some(String(s)) =>
      if @json.is_all_digits(s) {
        @json.parse_dec(s).to_int64()
      } else {
        0L
      }
    _ => 0L
  }
}

///|
/// 从 Json 取字符串；不是字符串给空串。
fn str_field(json : Json, key : String) -> String {
  match @json.json_field(json, key) {
    Some(v) =>
      match @json.json_string(v) {
        Some(s) => s
        None => ""
      }
    None => ""
  }
}

///|
/// 读一份 meta.json；读不到 / 解析不了给 None（调用方按「读不出来」处理，不编内容）。
async fn read_meta(path : String) -> SnapshotMeta? noraise {
  let text = match @json.read_text_file(path) {
    Ok(t) => t
    Err(_) => return None
  }
  let json = match @json.json_parse(text) {
    Some(j) => j
    None => return None
  }
  Some({
    at: str_field(json, "at"),
    reason: str_field(json, "reason"),
    files: int_field(json, "files"),
    bytes: int64_field(json, "bytes"),
  })
}

///|
/// 按 id（毫秒时间戳）从新到旧比较。
///
/// **必须用 parse_dec64**：MoonBit 的 Int 是 32 位，13 位的毫秒时间戳塞进去会被截断，
/// 截断之后排序与「最新是哪一份」都会悄悄错掉（实测拍出来的 id 只剩 10 位）。
fn snapshot_desc(a : String, b : String) -> Int32 {
  let x = @json.parse_dec64(a)
  let y = @json.parse_dec64(b)
  if x > y {
    -1
  } else if x < y {
    1
  } else {
    0
  }
}

///|
/// 读一只 profile 的快照列表（从新到旧），返回 (列表, 来源串)。
///
/// 读不出来给空数组，并把原因写进来源串 —— 「还没有 .snapshots」与「有目录但列不动」
/// 是两件事，来源串里分开说。单份 meta.json 读不出来时这一份照样列出
/// （at 按目录名折算，reason 空、files / bytes 给 0），原因也进来源串：
/// 那一条快照的文件还在，藏起来反而让人以为它没拍过。
pub async fn read_snapshots(
  profile_dir : String,
) -> (Array[SnapshotEntry], String) noraise {
  let dir = snapshots_dir_of(profile_dir)
  if !@json.is_dir(dir) {
    return ([], "还没有 " + dir + "（这只 profile 没拍过快照）")
  }
  let names = match @json.list_dir_result(dir) {
    Ok(list) => list
    Err(e) => return ([], "读不到 " + dir + "：" + e)
  }
  let entries : Array[SnapshotEntry] = []
  let problems : Array[String] = []
  for name in names {
    if !@json.is_all_digits(name) {
      continue
    }
    let snapshot_dir = @json.join_path(dir, name)
    if !@json.is_dir(snapshot_dir) {
      continue
    }
    let (at, reason, files, bytes) = match
      read_meta(@json.join_path(snapshot_dir, "meta.json")) {
      Some(meta) => (meta.at, meta.reason, meta.files, meta.bytes)
      None => {
        problems.push(name + "/meta.json 读不出来")
        (@json.iso_from_epoch_ms(@json.parse_dec64(name)), "", 0, 0L)
      }
    }
    entries.push({ id: name, at, reason, files, bytes, })
  }
  entries.sort_by(fn(a, b) { snapshot_desc(a.id, b.id) })
  let count = entries.length().to_string()
  let source = if problems.length() == 0 {
    "读自 " + dir + "（" + count + " 份）"
  } else {
    "读自 " + dir + "（" + count + " 份；" + problems.join("；") + "）"
  }
  (entries, source)
}

///|
/// 按上限淘汰：.snapshots 下按 id 从新到旧排，第 snapshot_keep 份之后的删掉。
///
/// 删除目标只可能是 .snapshots/<纯数字>/：名字与落点都由上面这条规则定，
/// 不接受任何外部给的名字。删不动的照样往下走（不因为收不掉一份旧快照把这次拍照报成失败）。
///
/// keep_id 是「这一次正在还原的那一份」：它刚好排在第 21 位时不能删 ——
/// 还原第一步会先拍一张「还原前」，要是那张把正被还原的这一份挤掉，
/// 后面就会对着一个空目录读文件，回一句「快照里一个都没有」，而用户要的正是它。
/// 跳过它、删下一份旧的，条数下一次拍照时自然收敛回上限。
async fn prune_snapshots(
  dir : String,
  keep_id : String,
) -> Array[String] noraise {
  let pruned : Array[String] = []
  let names = match @json.list_dir_result(dir) {
    Ok(list) => list
    Err(_) => return pruned
  }
  let ids : Array[String] = []
  for name in names {
    if @json.is_all_digits(name) && @json.is_dir(@json.join_path(dir, name)) {
      ids.push(name)
    }
  }
  ids.sort_by(fn(a, b) { snapshot_desc(a, b) })
  // 从最旧的一端往前删，删到份数回到上限为止；碰到正在还原的那一份就跳过它、
  // 接着删下一份旧的 —— 于是份数仍然是 20，被还原的那一份也还在。
  let mut remaining = ids.length()
  let mut pos = ids.length() - 1
  while remaining > snapshot_keep && pos >= 0 {
    let id = ids[pos]
    pos = pos - 1
    if id == keep_id {
      continue
    }
    match @fsx.remove_tree(@json.join_path(dir, id)) {
      Ok(_) => {
        pruned.push(id)
        remaining = remaining - 1
      }
      Err(_) => ()
    }
  }
  pruned
}

///|
/// 拍一张快照。
///
/// 目录名取当前毫秒；同一毫秒里连拍两张时往后挪一毫秒（名字仍然是纯数字，
/// 也仍然是「拍下来的时刻」，不会撞目录）。
pub async fn create_snapshot(
  profile_dir : String,
  reason_in : String,
  keep_id~ : String = "",
) -> Result[SnapshotOutcome, String] noraise {
  let trimmed = @json.trim_both(reason_in)
  let reason = if trimmed == "" { default_snapshot_reason } else { trimmed }
  let dir = snapshots_dir_of(profile_dir)
  match @fsx.ensure_dir(dir) {
    Ok(_) => ()
    Err(e) => return Err(e)
  }
  let mut ms = @async.now()
  while @json.exists(@json.join_path(dir, ms.to_string())) {
    ms = ms + 1L
  }
  let id = ms.to_string()
  let target = @json.join_path(dir, id)
  match @fsx.ensure_dir(target) {
    Ok(_) => ()
    Err(e) => return Err(e)
  }
  let copied : Array[String] = []
  let missing : Array[String] = []
  let mut files = 0
  let mut bytes : Int64 = 0L
  for name in snapshot_file_names {
    let source = @json.join_path(profile_dir, name)
    if !@json.exists(source) {
      missing.push(name)
      continue
    }
    let data = match @fsx.read_bytes(source) {
      Ok(d) => d
      Err(e) => return Err(e)
    }
    match @fsx.write_bytes(@json.join_path(target, name), data) {
      Ok(_) => ()
      Err(e) => return Err(e)
    }
    copied.push(name)
    files = files + 1
    bytes = bytes + data.length().to_int64()
  }
  let at = @json.iso_from_epoch_ms(ms)
  let meta = @json.encode(
    @json.JObj([
      ("at", @json.JStr(at)),
      ("reason", @json.JStr(reason)),
      ("files", @json.jint(files)),
      ("bytes", @json.JNum(bytes.to_int().to_double())),
    ]),
  )
  match @fsx.write_text_atomic(@json.join_path(target, "meta.json"), meta) {
    Ok(_) => ()
    Err(e) => return Err("meta.json 没写进去：" + e)
  }
  let pruned = prune_snapshots(dir, keep_id)
  Ok({ id, dir: target, at, reason, files, bytes, copied, missing, pruned, })
}

///|
/// 还原到某一份快照（id 已经由调用方过了 snapshot_path_checked）。
///
/// 顺序是硬的：**先拍「还原前」**，那张拍不成就不动任何文件；
/// 再只写快照里有的那三个文件（缺的那几个保持 profile 现在的内容）。
/// 中途写失败时把已经写回的文件名带进错误里 —— 不说清「已经写了哪几份」，等于让人去猜现状。
pub async fn restore_snapshot(
  profile_dir : String,
  id : String,
) -> Result[RestoreOutcome, (String, String)] noraise {
  let snapshot_dir = match snapshot_path_checked(profile_dir, id) {
    Some(p) => p
    None =>
      return Err(
        (
          "bad-params",
          "快照 id 只认数字，且必须正好在 .snapshots 下：收到了 " +
          id,
        ),
      )
  }
  if !@json.is_dir(snapshot_dir) {
    return Err(("not-found", "快照不存在：" + snapshot_dir))
  }
  let meta = read_meta(@json.join_path(snapshot_dir, "meta.json"))
  let at = match meta {
    Some(m) =>
      if m.at == "" {
        @json.iso_from_epoch_ms(@json.parse_dec64(id))
      } else {
        m.at
      }
    None => @json.iso_from_epoch_ms(@json.parse_dec64(id))
  }
  let reason = match meta {
    Some(m) => m.reason
    None => ""
  }
  // keep_id：这一张不能把正在还原的那一份挤掉（见 prune_snapshots 的注释）
  let pre = match create_snapshot(profile_dir, pre_restore_reason, keep_id=id) {
    Ok(o) => o
    Err(e) =>
      return Err(
        (
          "io-error",
          "还原前那张快照没拍成（" +
          e +
          "），profile 里三个文件一个都没动",
        ),
      )
  }
  let restored : Array[String] = []
  let missing : Array[String] = []
  for name in snapshot_file_names {
    let source = @json.join_path(snapshot_dir, name)
    if !@json.exists(source) {
      missing.push(name)
      continue
    }
    let data = match @fsx.read_bytes(source) {
      Ok(d) => d
      Err(e) =>
        return Err(
          (
            "io-error",
            "读快照里的 " +
            name +
            " 失败（" +
            e +
            "）；已经写回：" +
            describe_files(restored),
          ),
        )
    }
    match @fsx.write_bytes(@json.join_path(profile_dir, name), data) {
      Ok(_) => restored.push(name)
      Err(e) =>
        return Err(
          (
            "io-error",
            "写回 " +
            name +
            " 失败（" +
            e +
            "）；已经写回：" +
            describe_files(restored),
          ),
        )
    }
  }
  Ok({
    id,
    at,
    reason,
    dir: snapshot_dir,
    restored,
    missing_in_snapshot: missing,
    pre_snapshot: pre,
  })
}

///|
/// 错误串里那半句「已经写回：…」。空的时候明说一个都没写，不留一句没说完的话。
fn describe_files(names : Array[String]) -> String {
  if names.length() == 0 {
    "一个都没有"
  } else {
    names.join("、")
  }
}

// 归档记录：archive.json —— 只记一条「这只 profile 已归档」，不动磁盘上的 profile。
//
// 第二轮契约：归档不再有「已合并」标记，记录是 { profile, archivedAt }。
// 多 home（Phase 3）之后，一份档案的身份是 **(home, profile 名)**，记录因此多一个 home：
// 同名不同 home 是两条，各归各的 —— 归档其中一只不再顶掉另一只，取消归档也只动对应那一条。
//
// 旧文件里残留的 merged 字段一律忽略：读侧只取自己认识的键，多出来的键不报错。
// **没有 home 的旧记录照样读得出来**（读成 home = ""）：判重与取消归档时按名字认。
// 少一个键不该让已有的归档凭空消失 —— 存档键升级的第一条纪律就是不丢旧数据。

///|
/// 一条归档。
pub(all) struct ArchiveRecord {
  profile : String
  /// 这只 profile 属于哪个 home（绝对路径）。
  ///
  /// 空串 = 这一条没有 home：本次改动之前写的旧记录，或者调用方没给。
  /// 它按名字参与判重与取消归档，见 archive_target_matches。
  home : String
  archived_at : String
}

///|
pub struct LoadedArchive {
  entries : Array[ArchiveRecord]
  note : String?
}

///|
pub fn archive_json(r : ArchiveRecord) -> @json.JsonVal {
  @json.JObj([
    ("profile", @json.JStr(r.profile)),
    ("home", @json.JStr(r.home)),
    ("archivedAt", @json.JStr(r.archived_at)),
  ])
}

///|
fn archive_of(json : Json) -> ArchiveRecord? {
  let profile = match field_of(json, "profile") {
    Some(v) => as_string(v)
    None => None
  }
  match profile {
    Some(name) =>
      // 这里只认 profile / home / archivedAt：旧文件里带的 merged（或任何别的键）
      // 不读、不校验、不报错。home 不在（旧记录）就是空串，不拿别的东西顶上。
      Some({
        profile: name,
        home: match field_of(json, "home") {
          Some(v) =>
            match as_string(v) {
              Some(s) => @json.trim_both(s)
              None => ""
            }
          None => ""
        },
        archived_at: match field_of(json, "archivedAt") {
          Some(v) =>
            match as_string(v) {
              Some(s) => s
              None => ""
            }
          None => ""
        },
      })
    None => None
  }
}

///|
/// 这条归档记录是不是在说「(home, profile) 这一份档案」——判重与取消归档都用它。
///
/// 两种「只按名字认」的情形，都是兼容口径：
///   · 记录自己没标 home（旧文件）—— 那时全仓只有一个 home 口径，这条记录说的就是它；
///   · 调用方没给 home（旧客户端 / 没带这个参数的请求）—— 同样退回按名字认。
/// 除了这两种，home 必须相等：这正是「同名不同 home 不串」那一条。
pub fn archive_target_matches(
  r : ArchiveRecord,
  home : String,
  profile : String,
) -> Bool {
  if r.profile != profile {
    return false
  }
  if home == "" || r.home == "" {
    return true
  }
  r.home == home
}

///|
pub async fn load_archive() -> LoadedArchive noraise {
  let paths = state_paths()
  let (file, file_error) = read_state_json(paths.archive)
  let entries : Array[ArchiveRecord] = []
  let mut note = file_error
  match file {
    None => ()
    Some(json) =>
      match json {
        Array(items) => {
          let mut dropped = 0
          for item in items {
            match archive_of(item) {
              Some(r) => entries.push(r)
              None => dropped = dropped + 1
            }
          }
          if dropped > 0 {
            note = Some(
              "archive.json 里有 " +
              dropped.to_string() +
              " 条读不出来的记录，已跳过",
            )
          }
        }
        _ =>
          note = Some(
            "archive.json 顶层不是数组，按空表处理：" +
            paths.archive,
          )
      }
  }
  { entries, note, }
}

///|
pub async fn save_archive(
  entries : Array[ArchiveRecord],
) -> Result[Unit, String] noraise {
  let paths = state_paths()
  let items : Array[@json.JsonVal] = []
  for r in entries {
    items.push(archive_json(r))
  }
  match @fsx.write_text_atomic_fs(paths.archive, @json.encode(@json.JArr(items)) + "\n") {
    Ok(_) => Ok(())
    Err(e) => {
      note_raw(e.raw)
      Err("写文件失败")
    }
  }
}

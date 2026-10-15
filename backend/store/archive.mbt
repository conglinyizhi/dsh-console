// 归档记录：archive.json —— 只记一条「这个 profile 已归档」，不动磁盘上的 profile。
//
// 第二轮契约：归档不再有「已合并」标记，记录只剩 { profile, archivedAt }。
// 旧文件里残留的 merged 字段一律忽略：读侧只取自己认识的键，多出来的键不报错。

///|
/// 一条归档。
pub(all) struct ArchiveRecord {
  profile : String
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
      // 这里只认 profile / archivedAt：旧文件里带的 merged（或任何别的键）不读、不校验、不报错
      Some({
        profile: name,
        archived_at: match field_of(json, "archivedAt") {
          Some(v) => match as_string(v) {
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
            note = Some("archive.json 里有 " + dropped.to_string() + " 条读不出来的记录，已跳过")
          }
        }
        _ => note = Some("archive.json 顶层不是数组，按空表处理：" + paths.archive)
      }
  }
  { entries, note }
}

///|
pub async fn save_archive(entries : Array[ArchiveRecord]) -> Result[Unit, String] noraise {
  let paths = state_paths()
  let items : Array[@json.JsonVal] = []
  for r in entries {
    items.push(archive_json(r))
  }
  @fsx.write_text_atomic(paths.archive, @json.encode(@json.JArr(items)) + "\n")
}

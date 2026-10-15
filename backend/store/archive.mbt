// 归档记录：archive.json —— 只记一条「这个 profile 已归档」，不动磁盘上的 profile。

///|
/// 一条归档。merged 表示成果是否已回灌主线。
pub(all) struct ArchiveRecord {
  profile : String
  merged : Bool
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
    ("merged", @json.JBool(r.merged)),
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
      Some({
        profile: name,
        merged: match field_of(json, "merged") {
          Some(v) => match as_bool(v) {
            Some(b) => b
            None => false
          }
          None => false
        },
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

// 运行时登记：runtime.json —— 只记控制台自己起过的实例。
//
// 用途三条（契约第四节）：① 停止 / 重启要知道它是不是我们起的；② 页面可以标出
// 「由本控制台启动」；③ 进程已消失时能对账清理。外部已有的实例不写进这个文件。
//
// 这份文件只由动作改写（起 / 停 / 重启）。GET 不写它 —— 读接口保持纯只读，
// 对账（pid 已消失就清理）发生在下一次动作里，注册表里的陈旧条目在读取时按 alive 标注。

///|
/// 一条登记。JSON 字段名见 to_json。
pub(all) struct InstanceRecord {
  pid : Int
  port : Int
  home : String
  profile : String
  started_at : String
  log_path : String
  detached : Bool
}

///|
/// 读出来的登记表 + 文件级问题。
pub struct LoadedRegistry {
  entries : Array[InstanceRecord]
  note : String?
}

///|
/// 一条登记的 JSON 形状（键序与契约一致）。
pub fn record_json(r : InstanceRecord) -> @json.JsonVal {
  @json.JObj([
    ("pid", @json.jint(r.pid)),
    ("port", @json.jint(r.port)),
    ("home", @json.JStr(r.home)),
    ("profile", @json.JStr(r.profile)),
    ("startedAt", @json.JStr(r.started_at)),
    ("logPath", @json.JStr(r.log_path)),
    ("detached", @json.JBool(r.detached)),
  ])
}

///|
/// 从一条 JSON 解析登记；字段不全或类型不对给 None（不编值）。
fn record_of(json : Json) -> InstanceRecord? {
  let pid = match field_of(json, "pid") {
    Some(v) => as_int(v)
    None => None
  }
  let port = match field_of(json, "port") {
    Some(v) => as_int(v)
    None => None
  }
  let profile = match field_of(json, "profile") {
    Some(v) => as_string(v)
    None => None
  }
  match (pid, port, profile) {
    (Some(p), Some(pt), Some(name)) =>
      Some({
        pid: p,
        port: pt,
        home: match field_of(json, "home") {
          Some(v) => match as_string(v) {
            Some(s) => s
            None => ""
          }
          None => ""
        },
        profile: name,
        started_at: match field_of(json, "startedAt") {
          Some(v) => match as_string(v) {
            Some(s) => s
            None => ""
          }
          None => ""
        },
        log_path: match field_of(json, "logPath") {
          Some(v) => match as_string(v) {
            Some(s) => s
            None => ""
          }
          None => ""
        },
        detached: match field_of(json, "detached") {
          Some(v) => match as_bool(v) {
            Some(b) => b
            None => false
          }
          None => false
        },
      })
    _ => None
  }
}

///|
/// 读登记表。文件不存在 -> 空表（不是错误）；坏了 -> 空表 + note。
pub async fn load_registry() -> LoadedRegistry noraise {
  let paths = state_paths()
  let (file, file_error) = read_state_json(paths.runtime)
  let entries : Array[InstanceRecord] = []
  let mut note = file_error
  match file {
    None => ()
    Some(json) =>
      match json {
        Array(items) => {
          let mut dropped = 0
          for item in items {
            match record_of(item) {
              Some(r) => entries.push(r)
              None => dropped = dropped + 1
            }
          }
          if dropped > 0 {
            note = Some("runtime.json 里有 " + dropped.to_string() + " 条读不出来的登记，已跳过")
          }
        }
        _ => note = Some("runtime.json 顶层不是数组，按空表处理：" + paths.runtime)
      }
  }
  { entries, note }
}

///|
/// 整表落盘（原子写）。
pub async fn save_registry(entries : Array[InstanceRecord]) -> Result[Unit, String] noraise {
  let paths = state_paths()
  let items : Array[@json.JsonVal] = []
  for r in entries {
    items.push(record_json(r))
  }
  @fsx.write_text_atomic(paths.runtime, @json.encode(@json.JArr(items)) + "\n")
}

///|
/// 加一条（同 pid 或同 profile 的老条目先去掉，不留重复）。
pub async fn add_record(entry : InstanceRecord) -> Result[Unit, String] noraise {
  let loaded = load_registry()
  let kept : Array[InstanceRecord] = []
  for r in loaded.entries {
    if r.pid != entry.pid && r.profile != entry.profile {
      kept.push(r)
    }
  }
  kept.push(entry)
  save_registry(kept)
}

///|
/// 按 pid 去掉一条；没这条也算成功。
pub async fn remove_by_pid(pid : Int) -> Result[Unit, String] noraise {
  let loaded = load_registry()
  let kept : Array[InstanceRecord] = []
  for r in loaded.entries {
    if r.pid != pid {
      kept.push(r)
    }
  }
  save_registry(kept)
}

///|
/// 找一条登记：按 pid 或按 profile。
pub fn find_record(entries : Array[InstanceRecord], pid : Int?, profile : String?) -> InstanceRecord? {
  for r in entries {
    match pid {
      Some(p) =>
        if r.pid == p {
          return Some(r)
        }
      None => ()
    }
  }
  for r in entries {
    match profile {
      Some(name) =>
        if r.profile == name {
          return Some(r)
        }
      None => ()
    }
  }
  None
}

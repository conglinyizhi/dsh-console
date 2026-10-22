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
  pid : Int32
  port : Int32
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
          Some(v) =>
            match as_string(v) {
              Some(s) => s
              None => ""
            }
          None => ""
        },
        profile: name,
        started_at: match field_of(json, "startedAt") {
          Some(v) =>
            match as_string(v) {
              Some(s) => s
              None => ""
            }
          None => ""
        },
        log_path: match field_of(json, "logPath") {
          Some(v) =>
            match as_string(v) {
              Some(s) => s
              None => ""
            }
          None => ""
        },
        detached: match field_of(json, "detached") {
          Some(v) =>
            match as_bool(v) {
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
            note = Some(
              "runtime.json 里有 " +
              dropped.to_string() +
              " 条读不出来的登记，已跳过",
            )
          }
        }
        _ =>
          note = Some(
            "runtime.json 顶层不是数组，按空表处理：" +
            paths.runtime,
          )
      }
  }
  { entries, note, }
}

///|
/// 整表落盘（原子写）。
pub async fn save_registry(
  entries : Array[InstanceRecord],
) -> Result[Unit, String] noraise {
  let paths = state_paths()
  let items : Array[@json.JsonVal] = []
  for r in entries {
    items.push(record_json(r))
  }
  match @fsx.write_text_atomic_fs(paths.runtime, @json.encode(@json.JArr(items)) + "\n") {
    Ok(_) => Ok(())
    Err(e) => {
      note_raw(e.raw)
      Err("写文件失败")
    }
  }
}

///|
/// 归一化一个 home 字符串：去首尾空白、去掉末尾多余的斜杠。
/// 空串 / 只有斜杠 / 相对路径一律给空串 —— 空串的语义是「认不出」，不是「根目录」。
pub fn trim_home(raw : String) -> String {
  let text = @json.trim_both(raw)
  let mut end = text.length()
  while end > 1 && @json.slice(text, end - 1, end) == "/" {
    end = end - 1
  }
  if !text.has_prefix("/") || end <= 1 {
    ""
  } else {
    @json.slice(text, 0, end)
  }
}

///|
/// 两处 home 是不是同一处。先归一化再比。
///
/// 只有两边都拿得到、且归一化后相等才算同一处。一边认不出（None 或空串）时给
/// false，也就是按「不同处」处理 —— 认不出它的 home，就没法说它跟另一处是同一处，
/// 而按「同一处」处理会把别的 home 里的同名实例算成本地实例挡下来（隔离 home 的
/// 那只就会一直起不来）。判据是 (home, 名字)：同名不同 home 是两只。
pub fn same_home(a : String?, b : String?) -> Bool {
  match (a, b) {
    (Some(x), Some(y)) => {
      let left = trim_home(x)
      let right = trim_home(y)
      left != "" && left == right
    }
    _ => false
  }
}

///|
/// 加一条。去重键是 pid 与 (home, profile)：同 pid 的老条目、以及**同一处 home 里
/// 同名 profile** 的老条目先去掉，不留重复。
/// 只看 profile 名是不够的：不同 home 里的同名 profile 是两只，各留各的登记。
pub async fn add_record(entry : InstanceRecord) -> Result[Unit, String] noraise {
  let loaded = load_registry()
  let kept : Array[InstanceRecord] = []
  for r in loaded.entries {
    let same_slot = r.profile == entry.profile &&
      same_home(Some(r.home), Some(entry.home))
    if r.pid != entry.pid && !same_slot {
      kept.push(r)
    }
  }
  kept.push(entry)
  save_registry(kept)
}

///|
/// 按 pid 去掉一条；没这条也算成功。
pub async fn remove_by_pid(pid : Int32) -> Result[Unit, String] noraise {
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
/// 找一条登记：按 pid，或者按 (home, profile) 一起给。
///
/// 按名字那条要求同时给 home：同名不同 home 是两只，只给名字认不出是哪一只，
/// 就不认（返回 None），免得把别的 home 那一只的 logPath / 端口当成它的。
pub fn find_record(
  entries : Array[InstanceRecord],
  pid : Int32?,
  profile : String?,
  home : String?,
) -> InstanceRecord? {
  for r in entries {
    match pid {
      Some(p) => if r.pid == p { return Some(r) }
      None => ()
    }
  }
  match (profile, home) {
    (Some(name), Some(h)) =>
      for r in entries {
        if r.profile == name && same_home(Some(r.home), Some(h)) {
          return Some(r)
        }
      }
    _ => ()
  }
  None
}

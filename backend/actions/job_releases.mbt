// 版本来源：包目录与版本解析（package_marker / package_dir_in / job_real_dir /
// package_version_of / find_version_dir）、运行中的快照与用量（running_*）。
//
// 2026-10-20 从 job.mbt 拆出来：「这一版是从哪来的」与「现在谁在用」是只读读数，
// 与作业状态机不是一件事。只搬位置，函数体一个字没改。

///|
/// 包目录在路径里的那一段（与 runtime.mbt 同一个判据）。
let package_marker : String = "/node_modules/@deepseek-ai/dsh"

///|
/// 一只在跑的实例：进程号 / 端口 / profile / home / 包目录 / 版本。
priv struct RunningSnapshot {
  pid : Int32
  port : Int32?
  profile : String
  home : String
  dir : String
  version : String
}

///|
/// 从 argv 里切出 @deepseek-ai/dsh 包目录（与 runtime 那边同一套判据，这里留一份）。
fn package_dir_in(argv : String) -> String? {
  match @json.index_of(argv, package_marker) {
    Some(at) => {
      let mut start = at
      while start > 0 {
        let ch = argv.unsafe_get(start - 1).unsafe_to_char()
        let stop = ch == ' ' ||
          ch == '\t' ||
          ch == '\n' ||
          ch == '\r' ||
          ch == '"' ||
          ch == '\'' ||
          ch == '=' ||
          ch == '(' ||
          ch == '\\'
        if stop {
          break
        }
        start = start - 1
      }
      let prefix = @json.slice(argv, start, at)
      if prefix.has_prefix("/") {
        Some(prefix + package_marker)
      } else {
        None
      }
    }
    None => None
  }
}

///|
/// 一份包装目录的真实路径（读不出来给原串）。
async fn job_real_dir(path : String) -> String noraise {
  match @json.real_path(path) {
    Some(p) => p
    None => path
  }
}

///|
/// 一个包目录里 package.json 的版本（读不到给 None）。试跑之前拿它核对
/// 「要试的确实是作业里写的那一版」——目录被换过的时候，不核对就会拿另一版去验收。
async fn package_version_of(dir : String) -> String? noraise {
  let file = @json.join_path(dir, "package.json")
  let text = match @json.read_text_file_fs(file) {
    Ok(t) => t
    Err(_) => return None
  }
  let json = match @json.json_parse(text) {
    Some(j) => j
    None => return None
  }
  match @json.json_field(json, "version") {
    Some(v) => @json.json_string(v)
    None => None
  }
}

///|
/// 候选里版本等于 version 的那一份的目录（没有给 None）。
async fn find_version_dir(version : String) -> String? noraise {
  let candidates = @runtime.installed_dsh_candidates()
  for c in candidates {
    if c.version == version {
      return Some(c.dir)
    }
  }
  None
}

///|
/// 在跑的实例快照（只认 argv 里解得出包目录的那些 —— 版本 / 包目录都从读数来，不猜）。
async fn running_snapshots() -> Array[RunningSnapshot] noraise {
  let candidates = @runtime.installed_dsh_candidates()
  let out : Array[RunningSnapshot] = []
  let report = @processes.read_processes()
  for item in report.instances {
    match package_dir_in(item.exe_path) {
      Some(dir) => {
        let real = job_real_dir(dir)
        let mut version = ""
        for c in candidates {
          if job_real_dir(c.dir) == real {
            version = c.version
          }
        }
        out.push({
          pid: item.pid,
          port: item.port,
          profile: match item.profile {
            Some(p) => p
            None => ""
          },
          home: match item.dsh_home {
            Some(h) => h
            None => ""
          },
          dir,
          version,
        })
      }
      None => ()
    }
  }
  out
}

///|
/// 有没有在跑的实例用的是这个包目录（真实路径比）。
async fn running_users_of(dir : String) -> Array[RunningSnapshot] noraise {
  let real = job_real_dir(dir)
  let mine : Array[RunningSnapshot] = []
  for item in running_snapshots() {
    if job_real_dir(item.dir) == real {
      mine.push(item)
    }
  }
  mine
}

///|
/// 在跑实例在悬停里的形状。
fn running_json(list : Array[RunningSnapshot]) -> @json.JsonVal {
  let items : Array[@json.JsonVal] = []
  for item in list {
    items.push(
      @json.JObj([
        ("pid", @json.jint(item.pid)),
        ("port", @json.int_or_null(item.port)),
        ("profile", @json.JStr(item.profile)),
        ("home", @json.JStr(item.home)),
        ("dir", @json.JStr(item.dir)),
        ("version", @json.JStr(item.version)),
      ]),
    )
  }
  @json.JArr(items)
}

// ── 进程：跑命令、拼输出尾部 ──────────────────────────────────

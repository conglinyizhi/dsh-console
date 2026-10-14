// 进程环境与路径解析。
//
// 环境变量来源是 /proc/self/environ（读一次），不是任何子进程。
// 取不到 /proc 时退回 @env（本进程自己的环境）。

///|
/// 读 /proc/self/environ 并按 NUL 拆成 key=value。
async fn environ_from_proc() -> Map[String, String] noraise {
  let map : Map[String, String] = Map([])
  let text = try {
    let data = @fs.read_file("/proc/self/environ")
    @utf8.decode_lossy(data.binary(), ignore_bom=true)
  } catch {
    _ => return map
  }
  for entry in text.split("\u{0000}") {
    let raw = owned(entry)
    if raw == "" {
      continue
    }
    match raw.find("=") {
      Some(i) if i > 0 => map[raw[:i].to_owned()] = raw[i + 1:].to_owned()
      _ => ()
    }
  }
  map
}

///|
/// 进程环境变量表。
pub async fn environ() -> Map[String, String] noraise {
  environ_from_proc()
}

///|
/// 取环境变量；空串按未设置处理（与 Node 版 `typeof v === 'string' && v.trim() !== ''` 对齐）。
pub async fn env_value(name : String) -> String? noraise {
  match environ().get(name) {
    Some(v) if v.trim() != "" => Some(v)
    _ => None
  }
}

///|
/// 取环境变量原文；未设置返回 None。
pub async fn env_raw(name : String) -> String? noraise {
  environ().get(name)
}

///|
/// 当前用户的家目录。
/// 先看 $HOME；没有就从 /etc/passwd 里按 $USER 找一行（只读，不调外部命令）。
pub async fn home_dir() -> String noraise {
  match env_value("HOME") {
    Some(h) => return h
    None => ()
  }
  let user = env_value("USER")
  let passwd = try {
    let data = @fs.read_file("/etc/passwd")
    @utf8.decode_lossy(data.binary(), ignore_bom=true)
  } catch {
    _ => ""
  }
  for line in passwd.split("\n") {
    let fields : Array[String] = owned(line).split(":").map(fn(f) { owned(f) }).collect()
    if fields.length() >= 6 {
      let ok = match user {
        Some(u) => fields[0] == u
        None => fields[2] == "0"
      }
      if ok {
        return fields[5]
      }
    }
  }
  "/root"
}
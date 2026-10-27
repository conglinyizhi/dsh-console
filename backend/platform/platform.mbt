// 平台差异的收口处：哪些能力靠 Linux 的 /proc，macOS 上怎么降级，都写在这里。
//
// 判据用「/proc 里那张表读不读得到」而不是编译期常量：同一个二进制在
// Linux 上走 /proc，在 macOS 上走 lsof/ps，不需要两套构建。
//
// macOS 上不做的：
//   · 按 socket inode 把端口对到进程（/proc/<pid>/fd 那条路）—— lsof 能替代，
//     但实例识别那块还依赖 cmdline/environ，先按「不支持」降级，只靠 HTTP 探。
//   · environ 读取——macOS 上没有等价物。

///|
/// 这台机器有没有 /proc（Linux 判据）。macOS 上 /proc 不存在。
pub async fn has_proc() -> Bool noraise {
  @json.is_dir("/proc/net")
}

///|
/// 能不能从进程侧补充扫描（cmdline / environ / fd 那套）。macOS 上不行。
pub async fn supports_proc_scan() -> Bool noraise {
  has_proc()
}

///|
/// 内核版本串（/proc/sys/kernel/osrelease）。拿不到给空串。
pub async fn kernel_release() -> String noraise {
  if !has_proc() {
    return ""
  }
  match @json.read_text_file_fs("/proc/sys/kernel/osrelease") {
    Ok(t) => @json.trim_both(t)
    Err(_) => ""
  }
}

///|
/// 某个端口上有没有人在**听**（只认 LISTEN，TIME-WAIT 那些残留不算）。
pub async fn is_listening(port : Int32) -> Bool noraise {
  let ports = listening_ports()
  ports.contains(port)
}

///|
/// 正在听的本地端口（去重）。
///
/// Linux：读 /proc/net/tcp(6) 的状态列，只认 0A（LISTEN）。
/// macOS：跑 `lsof -nP -iTCP -sTCP:LISTEN`，取 LOCAL 地址那一列。
pub async fn listening_ports() -> Array[Int32] noraise {
  if has_proc() {
    listening_ports_proc()
  } else {
    listening_ports_lsof()
  }
}

///|
/// 进程还活着吗。僵尸进程按死处理（kill(pid, 0) 对它也成功，但端口早放了）。
pub async fn process_alive(pid : Int32) -> Bool noraise {
  if !@fsx.pid_alive(pid) {
    return false
  }
  if has_proc() {
    process_alive_proc(pid)
  } else {
    process_alive_ps(pid)
  }
}

///|
/// 本进程可执行文件的真实路径。Linux 读 /proc/self/exe；macOS 用 argv[0] 绝对化。
pub async fn self_exe() -> String noraise {
  if has_proc() {
    @fs.realpath("/proc/self/exe") catch {
      _ => ""
    }
  } else {
    let args = @env.args()
    match args.get(0) {
      Some(a) => a
      None => ""
    }
  }
}

// ── Linux 实现 ────────────────────────────────────────────────────────

///|
/// /proc/net/tcp(6) 状态列里 LISTEN 的码。
let listen_state : String = "0A"

///|
/// 只认十进制数字，别的字符一律返回 None（lsof 那列偶尔带 `[::1]:5390` 之类）。
fn parse_dec(text : String) -> Int32? {
  if text == "" {
    return None
  }
  let mut value = 0
  for ch in text {
    match ch {
      '0'..<='9' => value = value * 10 + (ch.to_int() - 48)
      _ => return None
    }
  }
  Some(value)
}

///|
fn parse_hex(text : String) -> Int32 {
  let mut value = 0
  for ch in text {
    let d = match ch {
      '0'..<='9' => ch.to_int() - 48
      'a'..<='f' => ch.to_int() - 87
      'A'..<='F' => ch.to_int() - 55
      _ => return value
    }
    value = value * 16 + d
  }
  value
}

///|
async fn listening_ports_proc() -> Array[Int32] noraise {
  let out : Array[Int32] = []
  for file in ["/proc/net/tcp", "/proc/net/tcp6"] {
    let text = match @json.read_text_file_fs(file) {
      Ok(t) => t
      Err(_) => continue
    }
    for line in text.split("\n") {
      let cols = @json.split_ws(@json.owned(line))
      // 列序：0 sl、1 local_address、2 rem_address、3 st —— 表头行只有两列，在这里被筛掉
      if cols.length() < 4 || cols[3] != listen_state {
        continue
      }
      let parts = @json.split_ws(cols[1].replace_all(old=":", new=" "))
      if parts.length() != 2 {
        continue
      }
      let port = parse_hex(parts[1])
      if port > 0 && !out.contains(port) {
        out.push(port)
      }
    }
  }
  out
}

///|
async fn process_alive_proc(pid : Int32) -> Bool noraise {
  match @json.read_text_file_fs("/proc/" + pid.to_string() + "/stat") {
    Ok(text) => {
      let cut = match text.rev_find(")") {
        Some(i) => i
        None => return true
      }
      let fields = @json.split_ws(@json.slice_from(text, cut + 1))
      match fields.get(0) {
        Some(state) => state != "Z" && state != "X"
        None => true
      }
    }
    Err(_) => true
  }
}

// ── macOS 实现 ────────────────────────────────────────────────────────

///|
/// 跑一条命令拿 stdout；起不来或非零都回空串。
async fn sh(cmd : String, args : Array[String]) -> String noraise {
  let input = @process.redirect_from_file("/dev/null") catch { _ => return "" }
  let (code, out, _) = @process.collect_output(
    cmd,
    args,
    inherit_env=true,
    stdin=input,
  ) catch {
    _ => return ""
  }
  if code != 0 {
    return ""
  }
  out.text() catch {
    _ => ""
  }
}

///|
/// lsof 的一行长这样：
///   dsh-console 64610 clyzhi 7u IPv4 0x… 0t0 TCP 127.0.0.1:5390 (LISTEN)
/// 取最后一列之前的 `地址:端口`，只留端口。
async fn listening_ports_lsof() -> Array[Int32] noraise {
  let out : Array[Int32] = []
  let text = sh("lsof", ["-nP", "-iTCP", "-sTCP:LISTEN"])
  for line in text.split("\n") {
    let cols = @json.split_ws(@json.owned(line))
    let last = match cols.length() {
      0 => continue
      n => cols[n - 1]
    }
    if !last.contains(":") {
      continue
    }
    let parts = @json.split_ws(last.replace_all(old=":", new=" "))
    let tail = match parts.get(parts.length() - 1) {
      Some(t) => t
      None => continue
    }
    let port = match parse_dec(tail) {
      Some(p) => p
      None => continue
    }
    if port > 0 && !out.contains(port) {
      out.push(port)
    }
  }
  out
}

///|
/// ps 的状态列里有 Z（僵尸）就算死。
async fn process_alive_ps(pid : Int32) -> Bool noraise {
  let text = sh("ps", ["-p", pid.to_string(), "-o", "stat="])
  let s = @json.trim_both(text)
  if s == "" {
    return false
  }
  !s.contains("Z")
}

///|
/// 一个文件的 md5（取前 8 位）。只用来判断「这份文件变没变」，不用于安全。
///
/// Linux 有 `md5sum`，macOS 只有 `md5 -q`；两边输出格式不同，这里统一成
/// 「十六进制串」再取前 8 位。都拿不到就给 None，调用方回落别的标识。
pub async fn file_hash(path : String) -> String? noraise {
  let raw = if has_proc() {
    sh("md5sum", [path])
  } else {
    sh("md5", ["-q", path])
  }
  let text = @json.trim_both(raw)
  if text == "" {
    return None
  }
  // md5sum 的输出是 `<hex>  <路径>`；md5 -q 只有 hex。取第一段。
  let first = match @json.split_ws(text).get(0) {
    Some(f) => f
    None => return None
  }
  if first.length() >= 8 {
    Some(first[:8].to_owned())
  } else {
    Some(first)
  }
}

///|
/// 某个 PID 的 argv。Linux 读 /proc/<pid>/cmdline（NUL 分隔）；macOS 用
/// `ps -p PID -o command=`（空格分隔，参数里带空格的路径会拆坏，够用）。
pub async fn process_argv(pid : Int32) -> Array[String]? noraise {
  if has_proc() {
    let file = "/proc/" + @json.int_to_dec(pid) + "/cmdline"
    let raw = match @json.read_text_file_fs(file) {
      Ok(t) => t
      Err(_) => return None
    }
    let argv : Array[String] = []
    for part in raw.split("\u{0000}") {
      let item = @json.owned(part)
      if item != "" {
        argv.push(item)
      }
    }
    if argv.length() == 0 {
      None
    } else {
      Some(argv)
    }
  } else {
    let text = sh("ps", ["-p", pid.to_string(), "-o", "command="])
    let argv : Array[String] = []
    for token in @json.split_ws(@json.trim_both(text)) {
      if token != "" {
        argv.push(token)
      }
    }
    if argv.length() == 0 {
      None
    } else {
      Some(argv)
    }
  }
}

///|
/// 进程表里的一行：pid + 命令行（连在一起的整串）。
pub(all) struct ProcessRow {
  pid : Int32
  command : String
}

///|
/// 列出本机进程（pid + 命令行）。Linux 扫 /proc/<pid>/cmdline；macOS 用
/// `ps -eo pid=,command=`。只给能被当前用户看见的进程。
pub async fn process_table() -> Array[ProcessRow] noraise {
  let out : Array[ProcessRow] = []
  if has_proc() {
    let names = match @json.list_dir_result_fs("/proc") {
      Ok(l) => l
      Err(_) => return out
    }
    for name in names {
      if !@json.is_all_digits(name) {
        continue
      }
      let pid = @json.parse_dec(name)
      match process_argv(pid) {
        Some(argv) => out.push({ pid, command: argv.join(" ") })
        None => ()
      }
    }
  } else {
    let text = sh("ps", ["-eo", "pid=,command="])
    for line in text.split("\n") {
      let trimmed = @json.trim_both(@json.owned(line))
      if trimmed == "" {
        continue
      }
      let cols = @json.split_ws(trimmed)
      let pid_text = match cols.get(0) {
        Some(p) => p
        None => continue
      }
      let pid = match parse_dec(pid_text) {
        Some(p) => p
        None => continue
      }
      let cmd = if trimmed.length() > pid_text.length() {
        @json.trim_both(@json.slice_from(trimmed, pid_text.length()))
      } else {
        ""
      }
      out.push({ pid, command: cmd })
    }
  }
  out
}

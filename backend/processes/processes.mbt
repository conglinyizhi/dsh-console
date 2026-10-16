// GET /api/local/processes 的数据体。
//
// 纯读 /proc 找正在运行的 dsh 进程：不 spawn ps / ss / lsof，只 readdir + read_file。
// 字段与 Node 版 server/readProcesses.mjs 的返回值逐字段一致：
//   { procRoot, scanned, matcher, instances: [{ pid, port, profile, dshHome,
//     exePath, startedAt, uptimeSeconds }] }
//
// 两条口径要点：
//   1. --port 不再是必需条件。默认端口的实例命令行里不带 --port，读不到就记 null，
//      不因为读不到就把进程整个丢掉。
//   2. 读不到的字段一律 null，不编。

///|
/// 扫描根（与 Node 版同常量）。
pub let proc_root : String = "/proc"

///|
/// /proc/<pid>/stat 的 starttime 单位：Linux 默认时钟频率 sysconf(_SC_CLK_TCK)。
let clk_tck : Double = 100.0

///|
/// 一个 dsh 进程的摘要。
pub struct ProcSummary {
  pid : Int
  port : Int?
  profile : String?
  dsh_home : String?
  exe_path : String
  started_at : String?
  uptime_seconds : Int?
}

///|
/// readProcesses 的整体结果（instances 接口拿它做进程补充）。
pub struct ProcReport {
  scanned : Int
  instances : Array[ProcSummary]
}

///|
/// 一个 argv 片段是不是 dsh 的可执行入口。
/// 只认两处：最后一段可执行名就叫 dsh（可带 .js/.mjs/.cjs 后缀），
/// 或者路径里有 @deepseek-ai/dsh/ 这一段。
/// 这样 node_modules/.bin/vite 这种「名字里恰好含 dsh」的进程不会被误判成实例。
pub fn is_dsh_entry(token : String) -> Bool {
  let segments = token.split("/")
  for seg in segments {
    let s = seg.to_owned()
    if s == "dsh" || s == "dsh.js" || s == "dsh.mjs" || s == "dsh.cjs" {
      return true
    }
  }
  @json.index_of(token, "@deepseek-ai/dsh/") is Some(_)
}

///|
/// 读 /proc/<pid>/cmdline 按 NUL 拆成 argv；读不到或空给 None。
pub async fn read_argv(pid : Int) -> Array[String]? noraise {
  let file = proc_root + "/" + @json.int_to_dec(pid) + "/cmdline"
  let raw = match @json.read_text_file(file) {
    Ok(t) => t
    Err(_) => return None
  }
  let argv : Array[String] = []
  for part in raw.split("\u{0000}") {
    let item = part.to_owned()
    if item != "" {
      argv.push(item)
    }
  }
  if argv.length() == 0 {
    None
  } else {
    Some(argv)
  }
}

///|
/// 某个 PID 的 cmdline 看起来是不是 dsh（与 read_processes 用同一把尺子：is_dsh_entry）。
/// 读不到 cmdline 给 false —— 读不到就不认，不猜。
/// 第七轮契约拿它判「签名探测不通过的端口要不要列出来」。
pub async fn cmdline_looks_like_dsh(pid : Int) -> Bool noraise {
  match read_argv(pid) {
    Some(argv) => argv.any(fn(token) { is_dsh_entry(token) })
    None => false
  }
}

///|
/// --port 8080 / --port=8080 都认；没有 --port 就是 null（不再是过滤条件）。
pub fn read_port(argv : Array[String]) -> Int? {
  let mut i = 0
  while i < argv.length() {
    let token = argv[i]
    if token == "--port" {
      if i + 1 < argv.length() && @json.is_all_digits(argv[i + 1]) {
        return Some(@json.parse_dec(argv[i + 1]))
      }
      return None
    }
    if @json.starts_with(token, "--port=") {
      let value = @json.slice_from(token, 7)
      if @json.is_all_digits(value) {
        return Some(@json.parse_dec(value))
      }
    }
    i = i + 1
  }
  None
}

///|
/// --profile web / --profile=web。
pub fn read_option(argv : Array[String], name : String) -> String? {
  let eq = @json.slice_from(name, 1) + "="
  let mut i = 0
  while i < argv.length() {
    if argv[i] == name {
      return if i + 1 < argv.length() { Some(argv[i + 1]) } else { None }
    }
    let tail = @json.slice_from(argv[i], 2)
    if @json.starts_with(argv[i], "--") && @json.starts_with(tail, eq) {
      return Some(@json.slice_from(tail, eq.length()))
    }
    i = i + 1
  }
  None
}

///|
/// /proc/<pid>/environ 里的某个 key；读不到（别的用户的进程）给 null。
pub async fn read_env_of(pid : Int, key : String) -> String? noraise {
  let file = proc_root + "/" + @json.int_to_dec(pid) + "/environ"
  let raw = match @json.read_text_file(file) {
    Ok(t) => t
    Err(_) => return None
  }
  let prefix = key + "="
  for entry in raw.split("\u{0000}") {
    let item = entry.to_owned()
    if @json.starts_with(item, prefix) {
      return Some(@json.slice_from(item, prefix.length()))
    }
  }
  None
}

///|
/// /proc/<pid>/stat 第 22 个字段：进程启动时的系统时钟滴答数。
/// comm 里可能有空格和括号，从最后一个 ')' 之后切。
pub async fn read_start_ticks(pid : Int) -> Int64? noraise {
  let file = proc_root + "/" + @json.int_to_dec(pid) + "/stat"
  let raw = match @json.read_text_file(file) {
    Ok(t) => t
    Err(_) => return None
  }
  let cut = match raw.rev_find(")") {
    Some(i) => i
    None => return None
  }
  let fields = @json.split_ws(@json.slice_from(raw, cut + 1))
  if fields.length() <= 19 {
    return None
  }
  let ticks = @json.parse_dec64(fields[19])
  if ticks < 0L { None } else { Some(ticks) }
}

///|
/// /proc/uptime 第一段（秒）。
pub async fn read_uptime_seconds() -> Double? noraise {
  let raw = match @json.read_text_file(proc_root + "/uptime") {
    Ok(t) => t
    Err(_) => return None
  }
  let fields = @json.split_ws(raw)
  if fields.length() == 0 {
    return None
  }
  Some(parse_double(fields[0]))
}

///|
/// 非负十进制（可带小数）。与 Number() 的宽容度不同：这里只认数字与单个小数点，
/// 拿不准就给 -1，让上层判成「读不到」。
fn parse_double(s : String) -> Double {
  if s == "" {
    return -1.0
  }
  if s.length() > 1 && s.unsafe_get(0).unsafe_to_char() == '-' {
    return -1.0
  }
  let mut int_part = 0.0
  let mut frac_part = 0.0
  let mut scale = 1.0
  let mut seen_dot = false
  for ch in s {
    let code = ch.to_int()
    if code >= 48 && code <= 57 {
      if seen_dot {
        scale = scale * 10.0
        frac_part = frac_part + (code - 48).to_double() / scale
      } else {
        int_part = int_part * 10.0 + (code - 48).to_double()
      }
    } else if ch == '.' && !seen_dot {
      seen_dot = true
    } else {
      return -1.0
    }
  }
  int_part + frac_part
}

///|
/// JS 的 Math.round：.5 向上。
fn round_half_up(value : Double) -> Int {
  let floored = value.to_int()
  let frac = value - floored.to_double()
  if frac >= 0.5 { floored + 1 } else { floored }
}

///|
/// 进程已运行秒数：/proc/<pid>/stat 第 22 字段（时钟滴答）与 /proc/uptime 换算。
/// 任一项读不到就给 None —— 「读不到」与「刚启动」必须能分开。
pub async fn uptime_seconds_of(pid : Int, sys_uptime : Double?) -> Int? noraise {
  let ticks = match read_start_ticks(pid) {
    Some(t) => t
    None => return None
  }
  let uptime = match sys_uptime {
    Some(u) => u
    None => return None
  }
  if uptime < 0.0 {
    return None
  }
  let started_ago = uptime - ticks.to_double() / clk_tck
  Some(if started_ago < 0.0 { 0 } else { round_half_up(started_ago) })
}

///|
/// 扫描 /proc，列出 dsh 进程，按 pid 升序。
pub async fn read_processes() -> ProcReport noraise {
  let sys_uptime = read_uptime_seconds()
  let now = @async.now()
  let instances : Array[ProcSummary] = []
  let names = @json.list_dir(proc_root)
  let pids : Array[Int] = []
  for name in names {
    if @json.is_all_digits(name) {
      pids.push(@json.parse_dec(name))
    }
  }
  pids.sort()
  for pid in pids {
    let argv = match read_argv(pid) {
      Some(a) => a
      None => continue
    }
    let mut entry : String? = None
    for token in argv {
      if is_dsh_entry(token) {
        entry = Some(token)
        break
      }
    }
    let exe_path = match entry {
      None => continue
      Some(e) => e
    }
    let port = read_port(argv)
    let uptime_seconds = uptime_seconds_of(pid, sys_uptime)
    let started_at = match uptime_seconds {
      Some(seconds) => Some(@json.iso_from_epoch_ms(now - seconds.to_int64() * 1000L))
      None => None
    }
    instances.push({
      pid,
      port,
      profile: read_option(argv, "--profile"),
      dsh_home: read_env_of(pid, "DSH_HOME"),
      exe_path,
      started_at,
      uptime_seconds,
    })
  }
  { scanned: pids.length(), instances }
}

///|
/// 组装 /api/local/processes 的 data 对象。
pub async fn read_processes_data() -> @json.JsonVal raise @localapi.ReadError {
  let report = read_processes()
  let instances : Array[@json.JsonVal] = []
  for item in report.instances {
    instances.push(@json.JObj([
      ("pid", @json.jint(item.pid)),
      ("port", @json.int_or_null(item.port)),
      ("profile", @json.str_or_null(item.profile)),
      ("dshHome", @json.str_or_null(item.dsh_home)),
      ("exePath", @json.JStr(item.exe_path)),
      ("startedAt", @json.str_or_null(item.started_at)),
      ("uptimeSeconds", @json.int_or_null(item.uptime_seconds)),
    ]))
  }
  @json.JObj([
    ("procRoot", @json.JStr(proc_root)),
    ("scanned", @json.jint(report.scanned)),
    (
      "matcher",
      @json.JStr(
        "argv 里有 dsh 入口（可执行名 dsh 或路径段 @deepseek-ai/dsh）；--port 有就读出来，没有记 null，不再当过滤条件",
      ),
    ),
    ("instances", @json.JArr(instances)),
  ])
}

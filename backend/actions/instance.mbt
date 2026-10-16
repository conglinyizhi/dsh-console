// 实例的起 / 停 / 重启。
//
// 起法照抄宿主上真实实例的形状（去 /proc/<pid>/cmdline 看过）：
//   node <包目录>/lib/bin.js --profile <名> --no-open [--port <端口>]
// 包目录走 runtime 包里那条安装目录规则（与 /api/local/runtime 的 dshPackageDir 同源）。
//
// 那条 argv 里有一件必须说清的事：**dsh 启动器只认 --profile，其余参数原样转给该 profile 的 app**
// （dsh --help：Usage: dsh [--profile] <name> [options] [app-args...]）。
// 所以 --no-open / --port 是 **app 的参数**，不是启动器的（dsh web --help 里才列着它们）。
// 一只 profile 能不能起成常驻实例，取决于它的 app 认不认这两个参数：
//   · 服务型 app（bundles 里有 @deepseek-ai/dsh-web-app，如 web / review-dev）→ 认，起得来；
//   · 非服务型 app（如 headless：答一个任务就打印结果然后退出）→ 不认，立刻回
//     error: unknown option '--no-open' 并退出。
// 判断**不看 profile 名字，只看事实**：这次启动新写出来的日志里有没有「不认识的选项」这类行。
// 命中就把事实翻译成人话（见 detect_arg_rejection / arg_rejection_message），不把日志尾巴丢出去。
//
// 端口、进程、信号的口径：
//   · 端口从 instance.basePort 起找第一个空闲（空闲 = /proc/net/tcp(6) 里任何状态都没占）；
//   · 起完要等到真的 LISTEN 才算成功，超时或子进程提前退出都算失败，并把子进程收掉；
//   · 停止是 SIGTERM -> 等 process.stopGraceMs -> SIGKILL；
//   · 全程只写三个地方：实例日志、runtime.json、audit.jsonl。

///|
/// 启动后等 LISTEN 的上限。dsh web 冷启动在本机是秒级，30s 是给足余量后的兜底值。
pub let boot_timeout_ms : Int = 30000

///|
/// 轮询间隔。
let poll_interval_ms : Int = 100

///|
/// SIGKILL 之后等进程真的消失的上限。
let kill_wait_ms : Int = 3000

///|
/// 从 basePort 起最多试多少个端口。
let port_scan_limit : Int = 200

///|
/// 传下去的 argv 里，属于「服务型 app 才认」的那几个参数。
/// --profile 不在此列：那是 dsh 启动器自己的，启动器一定认。
pub let service_args : Array[String] = ["--no-open", "--port"]

///|
/// 「这个 app 不认识我们的参数」在日志里的特征词（比对前先小写）。
/// 认的是事实，不是 profile 名字。
let arg_reject_markers : Array[String] = [
  "unknown option",
  "unknown argument",
  "unrecognized option",
  "unrecognized argument",
  "unknown flag",
  "unexpected argument",
  "invalid option",
]

///|
/// 一次「参数被拒」的归因证据。
pub struct ArgRejection {
  /// 被点名的服务参数（--no-open / --port 里命中的那几个；一个都没点名就是空数组）
  flags : Array[String]
  /// 日志里那一行的原文，贴进诊断里供核对
  evidence : String
}

///|
/// 起实例用的入口。
pub struct DshCommand {
  node : String
  script : String
  package_dir : String
}

///|
/// 一次启动的结果。
pub struct SpawnOutcome {
  pid : Int
  port : Int
  profile : String
  home : String
  log_path : String
  detached : Bool
  boot_ms : Int
  command : String
  url : String
}

///|
/// 一次停止的结果。
pub struct StopOutcome {
  pid : Int
  port : Int?
  profile : String?
  /// 发出 SIGTERM 到进程消失（或宽限期耗尽）的毫秒数
  sigterm_ms : Int
  /// 是否走到了 SIGKILL
  sigkill : Bool
  exited : Bool
  waited_ms : Int
  signal : String
}

///|
/// 目标实例：停止 / 重启靠它认人。
pub struct Target {
  pid : Int
  port : Int?
  profile : String?
  home : String?
  log_path : String?
}

///|
/// 在 PATH 里找一个可执行文件（只做存在性判断，不执行任何东西）。
/// 实现在 @json.find_in_path：找 dsh 入口（runtime 那条兜底链）也要用同一个 PATH 口径。
pub async fn find_in_path(name : String) -> String? noraise {
  @json.find_in_path(name)
}

///|
/// 解析 dsh 入口：包目录 -> lib/bin.js。包目录不存在 / 入口缺失给 None。
/// 包目录来自 @runtime.installed_dsh_dir 那条兜底链（顺 dsh shim / 全局根下按深度找 /
/// 多份取与在跑实例一致的），与 /api/local/runtime 的 dshPackageDir 同一份结论 ——
/// 起实例不会和读数指向两个不同的 dsh。
pub async fn resolve_dsh_command() -> DshCommand? noraise {
  let dir = match @runtime.installed_dsh_dir() {
    Some(d) => d
    None => return None
  }
  let script = @json.join_all([dir, "lib", "bin.js"])
  if !@json.exists(script) {
    return None
  }
  let node = match find_in_path("node") {
    Some(p) => p
    None => "node"
  }
  Some({ node, script, package_dir: dir })
}

///|
/// 端口是不是有人在听（连一次 127.0.0.1，连上就算）。
pub async fn port_listening(port : Int) -> Bool noraise {
  let attempt : async () -> Bool raise = async fn () {
    let addr = @async_socket.Addr::parse("127.0.0.1:\{port}")
    let sock = @async_socket.Tcp::connect(addr)
    sock.close()
    true
  }
  let result = try {
    @async.with_timeout_opt(300, attempt)
  } catch {
    _ => None
  }
  match result {
    Some(ok) => ok
    None => false
  }
}

///|
/// 十六进制端口。
fn parse_hex(s : String) -> Int {
  if s == "" {
    return -1
  }
  let mut value = 0
  for ch in s {
    let code = ch.to_int()
    let digit = if code >= 48 && code <= 57 {
      code - 48
    } else if code >= 65 && code <= 70 {
      code - 55
    } else if code >= 97 && code <= 102 {
      code - 87
    } else {
      return -1
    }
    value = value * 16 + digit
  }
  value
}

///|
/// /proc/net/tcp(6) 里出现过的本地端口 —— 不筛状态：
/// 一条 TIME_WAIT 或半开的连接也意味着这个端口不该拿来起新实例。
pub async fn busy_ports() -> Array[Int] noraise {
  let out : Array[Int] = []
  for file in ["/proc/net/tcp", "/proc/net/tcp6"] {
    let text = match @json.read_text_file(file) {
      Ok(t) => t
      Err(_) => continue
    }
    for line in text.split("\n") {
      let cols = @json.split_ws(@json.owned(line))
      if cols.length() < 4 {
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
/// 从 base 起找第一个空闲端口。找不到给 None（不瞎扩大范围）。
pub async fn pick_free_port(base : Int) -> Int? noraise {
  let used = busy_ports()
  let registry = @store.load_registry()
  let mut candidate = base
  let mut tried = 0
  while candidate <= 65535 && tried < port_scan_limit {
    let taken = used.contains(candidate) ||
      registry.entries.any(fn(r) { r.port == candidate })
    if !taken {
      return Some(candidate)
    }
    candidate = candidate + 1
    tried = tried + 1
  }
  None
}

///|
/// 进程还活着吗。比 kill(pid, 0) 多一层：僵尸进程的 kill(pid, 0) 也成功，
/// 但它已经死了（端口早就放了，只是父进程还没 wait 它）。
/// 判据取 /proc/<pid>/stat 第三列的状态位，Z（僵尸）按死处理。
pub async fn process_alive(pid : Int) -> Bool noraise {
  if !@fsx.pid_alive(pid) {
    return false
  }
  match @json.read_text_file("/proc/" + pid.to_string() + "/stat") {
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

///|
/// 收掉一个「已经不在」的子进程：waitpid 一次，把它从僵尸状态里摘掉。
///
/// 为什么必须 wait：僵尸进程在 kill(pid, 0) 眼里还活着，process_alive 靠 /proc 的
/// 状态位把 Z 判成死 —— 判死之后如果就此返回，这个子进程既死了又没被 wait，
/// 就一直挂在控制台名下（PPID 是控制台）。长跑的控制台每失败一次攒一个。
/// 只对已经死掉的 pid 调（调用点都先过了 process_alive），不会阻塞；
/// 不是我们的子进程时 waitpid 直接报 ECHILD，吞掉即可。
async fn reap_dead_child(pid : Int) -> Unit noraise {
  try {
    let _ = @process.wait_pid(pid)
  } catch {
    _ => ()
  }
}

///|
/// 尽力回收我们起的僵尸子进程（不是我们的子进程时 wait 会直接报错，吞掉即可）。
async fn reap_ours(pid : Int) -> Unit noraise {
  let registry = @store.load_registry()
  match @store.find_record(registry.entries, Some(pid), None, None) {
    Some(_) =>
      try {
        let _ = @process.wait_pid(pid)
      } catch {
        _ => ()
      }
    None => ()
  }
}

///|
/// 等实例真的答得出 dsh web 签名。子进程中途退出就立刻返回 false，不白等满超时。
pub async fn wait_ready(pid : Int, port : Int, timeout_ms : Int) -> Bool noraise {
  let began = @async.now()
  while (@async.now() - began).to_int() < timeout_ms {
    if dsh_signature_ready(port) {
      return true
    }
    if !process_alive(pid) {
      return false
    }
    @async.sleep(poll_interval_ms)
  }
  dsh_signature_ready(port)
}

///|
/// 端口在听，且答出来的是 dsh web 的签名（401 + 认证文案，或页里有 __DSH_BOOT__）。
/// 只判端口会踩一个真实的坑：服务先 bind、路由后挂载，中间那几百毫秒 GET / 是 404，
/// 只读的 instances 接口这一刻扫过去就认不出这只实例。
pub async fn dsh_signature_ready(port : Int) -> Bool noraise {
  let probe = @localapi.probe_port(port, 2000)
  if !probe.reached {
    return false
  }
  match probe.status {
    Some(401) => @json.index_of(probe.body, "dsh web authentication required") is Some(_)
    Some(_) => @json.index_of(probe.body, "__DSH_BOOT__") is Some(_)
    None => false
  }
}

///|
/// 本次启动新写进日志的那一段（最多 64KB）。
/// from 是 spawn 之前记下的文件大小：同一个日志文件是追加写的，
/// 上一次尝试留下的行不该算进这一次的归因。读不到就给空串（拿不到证据就不归因）。
async fn fresh_log_text(path : String, from : Int64) -> String noraise {
  let size = match @json.file_size(path) {
    Some(s) => s
    None => return ""
  }
  if size <= from {
    return ""
  }
  let span = size - from
  let cap : Int64 = 65536L
  let len = (if span > cap { cap } else { span }).to_int()
  match @json.read_text_at(path, from, len) {
    Ok(t) => t
    Err(_) => ""
  }
}

///|
/// 文本末尾 n 个非空行，用 " / " 连起来（贴进失败信息用）。
fn tail_text_lines(text : String, lines : Int) -> String {
  let kept : Array[String] = []
  for line in text.split("\n") {
    let trimmed = @json.trim_both(@json.owned(line))
    if trimmed != "" {
      kept.push(trimmed)
    }
  }
  let start = if kept.length() > lines { kept.length() - lines } else { 0 }
  let tail = kept[start:].to_owned()
  tail.join(" / ")
}

///|
/// 一行里出现的长选项（-- 开头，到非 [A-Za-z0-9_-] 为止）。
/// 用来判断被拒的那个选项是不是我们传下去的：别人报别人的名字，不该算在我们头上。
fn long_options_in(line : String) -> Array[String] {
  let out : Array[String] = []
  let n = line.length()
  let mut i = 0
  while i + 1 < n {
    if line.unsafe_get(i).unsafe_to_char() == '-' &&
      line.unsafe_get(i + 1).unsafe_to_char() == '-' {
      let buf = StringBuilder()
      buf.write_string("--")
      let mut j = i + 2
      while j < n {
        let ch = line.unsafe_get(j).unsafe_to_char()
        let code = ch.to_int()
        let is_word = (code >= 48 && code <= 57) || (code >= 65 && code <= 90) ||
          (code >= 97 && code <= 122) || ch == '-' || ch == '_'
        if !is_word {
          break
        }
        buf.write_char(ch)
        j = j + 1
      }
      let token = buf.to_string()
      if token.length() > 2 && !out.contains(token) {
        out.push(token)
      }
      i = j
    } else {
      i = i + 1
    }
  }
  out
}

///|
/// 从「本次启动新写出来的日志」里找参数被拒的证据。
///
/// 判据是事实，不是 profile 名字：有一行在说不认识某个选项，且被点名的那个选项
/// 不是别人的（我们只往下传 --no-open / --port，--profile 是启动器自己的）。
/// 认不出来就返回 None —— 那时按「日志尾部」如实交代，不硬套服务参数的结论。
pub fn detect_arg_rejection(text : String) -> ArgRejection? {
  for line in text.split("\n") {
    let raw = @json.owned(line)
    let probe = @json.to_lower(raw)
    let rejected = arg_reject_markers.any(fn(m) { @json.index_of(probe, m) is Some(_) })
    if !rejected {
      continue
    }
    let named : Array[String] = []
    for flag in service_args {
      if @json.index_of(probe, flag) is Some(_) {
        named.push(flag)
      }
    }
    let mut foreign = false
    for opt in long_options_in(probe) {
      if opt != "--profile" && !service_args.contains(opt) {
        foreign = true
      }
    }
    if foreign {
      continue
    }
    return Some({ flags: named, evidence: @json.trim_both(raw) })
  }
  None
}

///|
/// 参数被拒时的人话诊断：说清「这只 profile 不是服务型」，带上证据与 pid / 日志路径，
/// 不把日志尾巴当正文丢出去。
pub fn arg_rejection_message(
  profile : String,
  pid : Int,
  log_path : String,
  rejection : ArgRejection,
  detail : String,
) -> String {
  let flags = if rejection.flags.length() > 0 {
    rejection.flags.join("、")
  } else {
    "--no-open/--port"
  }
  "profile " + profile + " 的 app 不接受服务参数（" + flags +
  "），它不是服务型 profile，起不成常驻实例。" + detail + "（pid " + pid.to_string() + "，日志 " +
  log_path + "）。日志里写着：" + rejection.evidence + "。要跑这种 profile，按它自己的用法跑一次" +
  "（dsh --profile " + profile + " …），别拿它起常驻实例"
}

///|
/// 起一个实例。任何一步失败都把已经起的子进程收掉，不留僵尸。
pub async fn start_instance(
  profile : String,
  home : String?,
  port : Int?
) -> SpawnOutcome raise ActionError {
  let name = @json.trim_both(profile)
  validate_profile_name(name)
  let settings = @store.load_settings().values
  let (default_home, _) = @runtime.resolve_dsh_home()
  let target_home = match home {
    Some(h) =>
      if @json.trim_both(h) == "" {
        default_home
      } else {
        @json.trim_both(h)
      }
    None => default_home
  }
  let profile_dir = @json.join_all([target_home, "profiles", name])
  if !@json.is_dir(profile_dir) {
    fail("not-found", "profile 目录不存在：" + profile_dir)
  }
  // 冲突只看这个 (home, 名字)：别的 home 里同名的那只是另一只，不该挡住这一只
  match running_for_profile_in(name, Some(target_home)) {
    Some(hit) => {
      let port_text = match hit.port {
        Some(p) => "端口 " + p.to_string()
        None => "端口未识别"
      }
      let home_text = match hit.home {
        Some(h) => "，home " + h
        None => ""
      }
      fail(
        "conflict",
        "profile " + name + " 已经在跑（PID " + hit.pid.to_string() + "，" + port_text +
        home_text + "）；同一个 home 里同一个 profile 只允许一只实例",
      )
    }
    None => ()
  }
  let chosen = match port {
    Some(p) => {
      if p < 1 || p > 65535 {
        fail("bad-params", "port 超出范围 1..65535：" + p.to_string())
      }
      let used = busy_ports()
      if used.contains(p) {
        fail("conflict", "端口 " + p.to_string() + " 已被占用（/proc/net/tcp 里有这条记录）")
      }
      p
    }
    None =>
      match pick_free_port(settings.instance_base_port) {
        Some(p) => p
        None => {
          fail(
            "conflict",
            "从 instance.basePort=" + settings.instance_base_port.to_string() +
            " 起连续 " + port_scan_limit.to_string() + " 个端口都被占用，起不了新实例",
          )
          abort("unreachable: fail 一定抛错")
        }
      }
  }
  let command = match resolve_dsh_command() {
    Some(c) => c
    None => {
      fail(
        "spawn-failed",
        "找不到 dsh 入口：PATH 上的 dsh 命令解不出包目录，pnpm 全局根下也没有 @deepseek-ai/dsh/lib/bin.js",
      )
      abort("unreachable: fail 一定抛错")
    }
  }
  let log_dir = @json.join_path(target_home, "logs")
  match @fsx.ensure_dir(log_dir) {
    Ok(_) => ()
    Err(e) => fail("io-error", e)
  }
  let log_path = @json.join_path(
    log_dir,
    "console-" + name + "-" + chosen.to_string() + ".log",
  )
  let args : Array[String] = [
    command.script,
    "--profile",
    name,
    // 下面两个是 app 的参数（dsh 启动器只认 --profile，其余原样转给 app）：
    // 服务型 app 认，非服务型 app 会回 unknown option 然后退出。事实由日志给出，不靠 profile 名字猜。
    "--no-open",
    "--port",
    chosen.to_string(),
  ]
  let log_offset = match @json.file_size(log_path) {
    Some(s) => s
    None => 0L
  }
  let pid = match spawn_child(
    command,
    args,
    target_home,
    profile_dir,
    log_path,
    settings.process_detach,
    settings.process_stop_grace_ms,
  ) {
    Ok(p) => p
    Err(e) => {
      fail("spawn-failed", e)
      abort("unreachable: fail 一定抛错")
    }
  }
  let record : @store.InstanceRecord = {
    pid,
    port: chosen,
    home: target_home,
    profile: name,
    started_at: @json.iso_from_epoch_ms(@async.now()),
    log_path,
    detached: settings.process_detach,
  }
  match @store.add_record(record) {
    Ok(_) => ()
    Err(e) => {
      // 登记写不下去也得把实例收掉：留着它就成了没人认领的进程
      let _ = @fsx.send_signal(pid, @fsx.sigterm)
      fail("io-error", "运行登记写不下去：" + e)
    }
  }
  let began = @async.now()
  let listening = wait_ready(pid, chosen, boot_timeout_ms)
  if !listening {
    let detail = reap_after_failure(pid)
    let _ = @store.remove_by_pid(pid)
    // 只归因这一次启动新写出来的日志（同一个日志文件是追加写的，旧行不算证据）
    let fresh = fresh_log_text(log_path, log_offset)
    match detect_arg_rejection(fresh) {
      Some(rejection) =>
        // 参数被这个 app 拒了：它不是服务型 profile。这条事实比「日志尾巴」有用得多
        fail(
          "spawn-failed",
          arg_rejection_message(name, pid, log_path, rejection, detail),
        )
      None => {
        let tail = tail_text_lines(fresh, 5)
        fail(
          "spawn-failed",
          "实例没起来（pid " + pid.to_string() + "，日志 " + log_path + "）：" + detail +
          (if tail == "" { "" } else { "；日志尾部：" + tail }),
        )
      }
    }
  }
  let boot_ms = (@async.now() - began).to_int()
  {
    pid,
    port: chosen,
    profile: name,
    home: target_home,
    log_path,
    detached: settings.process_detach,
    boot_ms,
    command: command.node + " " + args.join(" "),
    url: "http://127.0.0.1:" + chosen.to_string() + "/",
  }
}

///|
/// 起不来时收子进程：SIGTERM 短等，仍在就 SIGKILL。返回一句人话说明。
async fn reap_after_failure(pid : Int) -> String noraise {
  if !process_alive(pid) {
    // 子进程自己退出了（app 不认参数、入口不存在等都是这一支）——正是要 wait 的那一支：
    // process_alive 把 Z 判成死，但没 wait 的话它就是一只挂在控制台名下的僵尸。
    reap_dead_child(pid)
    return "子进程已经退出"
  }
  let _ = @fsx.send_signal(pid, @fsx.sigterm)
  let began = @async.now()
  while (@async.now() - began).to_int() < 2000 {
    if !process_alive(pid) {
      reap_dead_child(pid)
      return "子进程没监听端口，已 SIGTERM 收掉"
    }
    @async.sleep(50)
  }
  let _ = @fsx.send_signal(pid, @fsx.sigkill)
  let kill_began = @async.now()
  while (@async.now() - kill_began).to_int() < kill_wait_ms {
    if !process_alive(pid) {
      reap_dead_child(pid)
      return "子进程没监听端口，SIGTERM 无效后 SIGKILL 收掉"
    }
    @async.sleep(50)
  }
  "子进程既没监听端口，也没能被收掉（仍在 " + pid.to_string() + "）"
}

///|
/// 控制台主任务组。detach=false 的实例挂在这上面：
/// 控制台退出（正常结束、SIGTERM/SIGINT 取消、甚至随后被信号带走）时，
/// 运行时的结构化并发会取消组里的子任务，按 cancel_handler（SIGTERM -> stopGraceMs -> SIGKILL）收掉它。
///
/// 为什么不能用「main 里 serve 之后的收尾代码」：moonbitlang/async 在全局取消信号之后会
/// 把信号重新抬起来交给默认处理（实测退出码 143），main 里 serve 之后的语句一句都跑不到。
let console_group : Ref[@async.TaskGroup[Unit]?] = { val: None }

///|
/// 登记主任务组（main 起服务前调用一次）。
pub fn set_console_group(group : @async.TaskGroup[Unit]) -> Unit {
  console_group.val = Some(group)
}

///|
/// 挂一只不挡路的收尾任务（open-path 用它等 xdg-open 退出，见 open_path.mbt）。
/// no_wait：控制台退出时不必等它 —— 那条路上的子进程本来也随控制台一起走。
/// 没有任务组（比如被当库调用）就什么也不做，调用方按「没人收尸」的风险自负。
pub fn spawn_reaper(task : async () -> Unit) -> Unit {
  match console_group.val {
    Some(group) => group.spawn_bg(task, no_wait=true)
    None => ()
  }
}

///|
/// 真正 spawn。
/// detach=true：spawn_orphan，完全脱离控制台（控制台怎么死都不影响它）。
/// detach=false：挂到控制台主任务组上（no_wait），控制台退出时被组收掉。
/// 两种都把 stdout/stderr 追加到实例日志，stdin 接 /dev/null（不让实例攥着控制台的标准输入）。
async fn spawn_child(
  command : DshCommand,
  args : Array[String],
  home : String,
  cwd : String,
  log_path : String,
  detach : Bool,
  grace_ms : Int,
) -> Result[Int, String] noraise {
  let env : Map[String, String] = Map([("DSH_HOME", home)])
  let out = try {
    @process.redirect_to_file(
      log_path,
      append=true,
      create_mode=OpenOrCreate,
      permission=0o600,
    )
  } catch {
    err => return Err("打不开实例日志 " + log_path + "：" + err.to_string())
  }
  let input = try {
    @process.redirect_from_file("/dev/null")
  } catch {
    err => return Err("打不开 /dev/null：" + err.to_string())
  }
  if !detach {
    match console_group.val {
      Some(group) =>
        try {
          let child = @process.spawn(
            group,
            command.node,
            args,
            extra_env=env,
            inherit_env=true,
            stdin=input,
            stdout=out,
            stderr=out,
            cwd~,
            cancel_handler=@process.graceful_cancel(timeout=grace_ms),
            no_wait=true,
          )
          return Ok(child.pid)
        } catch {
          err => return Err("spawn 失败（挂控制台任务组）：" + err.to_string())
        }
      None => () // 没有任务组就退回 orphan，语义降级成 detach=true
    }
  }
  let pid = try {
    @process.spawn_orphan(
      command.node,
      args,
      extra_env=env,
      inherit_env=true,
      stdin=input,
      stdout=out,
      stderr=out,
      cwd~,
    )
  } catch {
    err => return Err("spawn 失败：" + err.to_string())
  }
  Ok(pid)
}

///|
/// 这只进程的 home：environ 里的 DSH_HOME 优先，没有再看 fd 表里有没有 …/.dsh/… 这一段。
/// 两条都拿不到给 None（认不出）—— 不拿默认值 $HOME/.dsh 顶替，理由与探测那一侧一致。
async fn home_of_process(item : @processes.ProcSummary) -> String? noraise {
  match item.dsh_home {
    Some(h) =>
      if @json.trim_both(h) == "" {
        @processes.fd_home_hint(item.pid)
      } else {
        Some(h)
      }
    None => @processes.fd_home_hint(item.pid)
  }
}

///|
/// 同一个 (home, 名字) 是不是已经在跑。先看进程表（--profile + home），
/// 端口未知时查登记表与实例读数。
///
/// 判据是 (home, 名字) 而不是只有名字：**同名不同 home 是两只**，别的 home 里的同名
/// 实例不该把这一只挡下来（隔离 home 的 web 被主线的 web 挡住，就是这一条）。
/// home 两边都拿得到且相等才算同一只；实例那边 home 认不出时按不同处处理，
/// 见 store 的 same_home。
pub async fn running_for_profile_in(name : String, home : String?) -> Target? noraise {
  let report = @processes.read_processes()
  let mut hit : Target? = None
  for item in report.instances {
    match item.profile {
      Some(p) =>
        if p == name && process_alive(item.pid) {
          let item_home = home_of_process(item)
          if @store.same_home(item_home, home) {
            hit = Some({
              pid: item.pid,
              port: item.port,
              profile: Some(name),
              home: item_home,
              log_path: None,
            })
          }
        }
      None => ()
    }
  }
  match hit {
    Some(found) =>
      match found.port {
        Some(_) => Some(found)
        None =>
          match port_of_pid(found.pid) {
            Some(p) => Some({ ..found, port: Some(p) })
            None => Some(found)
          }
      }
    None => {
      // 进程表里没有（argv 读不到等）：登记表里活着的那条也算在跑 —— 同样按 (home, 名字) 认
      let registry = @store.load_registry()
      for r in registry.entries {
        if r.profile == name &&
          process_alive(r.pid) &&
          @store.same_home(Some(r.home), home) {
          return Some({
            pid: r.pid,
            port: Some(r.port),
            profile: Some(name),
            home: Some(r.home),
            log_path: Some(r.log_path),
          })
        }
      }
      None
    }
  }
}

///|
/// 某 PID 在听哪个端口：先查登记表，再走实例读数（重，只在需要时走）。
pub async fn port_of_pid(pid : Int) -> Int? noraise {
  let registry = @store.load_registry()
  match @store.find_record(registry.entries, Some(pid), None, None) {
    Some(r) => Some(r.port)
    None => {
      let report = @instances.instances_report_with_settings()
      let mut found : Int? = None
      for item in report.instances {
        match item.pid {
          Some(p) =>
            if p == pid {
              found = Some(item.port)
            }
          None => ()
        }
      }
      found
    }
  }
}

///|
/// 认目标实例：params 里给 pid 或 port 之二选一。
pub async fn resolve_target(pid_in : Int?, port_in : Int?) -> Target raise ActionError {
  match (pid_in, port_in) {
    (Some(_), Some(_)) => fail("bad-params", "pid 与 port 只能给一个")
    (None, None) => fail("bad-params", "要给 pid 或 port")
    _ => ()
  }
  let registry = @store.load_registry()
  let by_pid = match pid_in {
    Some(p) => @store.find_record(registry.entries, Some(p), None, None)
    None => None
  }
  match by_pid {
    Some(r) =>
      return {
        pid: r.pid,
        port: Some(r.port),
        profile: Some(r.profile),
        home: Some(r.home),
        log_path: Some(r.log_path),
      }
    None => ()
  }
  match port_in {
    Some(p) => {
      for r in registry.entries {
        if r.port == p {
          return {
            pid: r.pid,
            port: Some(p),
            profile: Some(r.profile),
            home: Some(r.home),
            log_path: Some(r.log_path),
          }
        }
      }
    }
    None => ()
  }
  let report = @processes.read_processes()
  for item in report.instances {
    let matched = match pid_in {
      Some(want) => item.pid == want
      None => item.port == port_in
    }
    if matched {
      return {
        pid: item.pid,
        port: item.port,
        profile: item.profile,
        home: item.dsh_home,
        log_path: None,
      }
    }
  }
  match port_in {
    Some(p) => {
      let instances = @instances.instances_report_with_settings()
      for item in instances.instances {
        if item.port == p {
          match item.pid {
            Some(found_pid) =>
              return {
                pid: found_pid,
                port: Some(p),
                profile: item.profile,
                home: item.dsh_home,
                log_path: None,
              }
            None => ()
          }
        }
      }
    }
    None => ()
  }
  match pid_in {
    Some(p) => {
      fail("not-found", "PID " + p.to_string() + " 不是已知的 dsh 实例（不在运行登记里，进程表里也没有 dsh 入口）")
      abort("unreachable: fail 一定抛错")
    }
    None =>
      match port_in {
        Some(p) => {
          fail("not-found", "端口 " + p.to_string() + " 上没有认得出的 dsh 实例")
          abort("unreachable: fail 一定抛错")
        }
        None => {
          fail("bad-params", "要给 pid 或 port")
          abort("unreachable: fail 一定抛错")
        }
      }
  }
}

///|
/// 停一个实例：SIGTERM -> 等宽限 -> SIGKILL。
pub async fn stop_pid(pid : Int, grace_ms : Int) -> StopOutcome raise ActionError {
  if !process_alive(pid) {
    fail("not-found", "PID " + pid.to_string() + " 已经不在（可能是上一次已经停掉了）")
  }
  let began = @async.now()
  match @fsx.send_signal(pid, @fsx.sigterm) {
    Ok(_) => ()
    Err(e) => fail("stop-failed", e)
  }
  let mut sigterm_ms = grace_ms
  let mut exited = false
  while (@async.now() - began).to_int() < grace_ms {
    if !process_alive(pid) {
      sigterm_ms = (@async.now() - began).to_int()
      exited = true
      break
    }
    @async.sleep(50)
  }
  let mut sigkill = false
  if !exited {
    sigterm_ms = (@async.now() - began).to_int()
    match @fsx.send_signal(pid, @fsx.sigkill) {
      Ok(_) => sigkill = true
      Err(e) => fail("stop-failed", e)
    }
    let kill_began = @async.now()
    while (@async.now() - kill_began).to_int() < kill_wait_ms {
      if !process_alive(pid) {
        break
      }
      @async.sleep(50)
    }
    exited = !process_alive(pid)
  }
  let waited_ms = (@async.now() - began).to_int()
  if !exited {
    fail(
      "stop-failed",
      "SIGTERM（宽限 " + grace_ms.to_string() + "ms）与 SIGKILL 之后 PID " + pid.to_string() +
      " 仍然在；可能是僵尸进程或没有权限",
    )
  }
  reap_ours(pid)
  {
    pid,
    port: None,
    profile: None,
    sigterm_ms,
    sigkill,
    exited,
    waited_ms,
    signal: if sigkill { "SIGKILL" } else { "SIGTERM" },
  }
}

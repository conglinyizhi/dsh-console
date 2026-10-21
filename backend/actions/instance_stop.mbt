// 实例的另一半：进程存活与收尸、端口探测与挑空闲口、按 profile 找回正在跑的那一只、
// 以及停止（stop_pid：SIGTERM → 宽限 → SIGKILL）。
//
// 2026-10-20 从 instance.mbt 拆出来：那个文件 1199 行，起（spawn）与停（stop）两条链
// 各自完整、只在共用的小工具上相接；拆开之后排查「起不来 / 停不掉」各看一份。
// 只搬位置，函数体一个字没改。


///|
/// SIGKILL 之后等进程真的消失的上限。
let kill_wait_ms : Int = 3000

///|
/// 从 basePort 起最多试多少个端口。
let port_scan_limit : Int = 200

///|
/// 一次「参数被拒」的归因证据。
pub struct ArgRejection {
  /// 被点名的服务参数（--no-open / --port 里命中的那几个；一个都没点名就是空数组）
  flags : Array[String]
  /// 日志里那一行的原文，贴进诊断里供核对
  evidence : String
}

///|
/// 一次启动的结果。
pub struct SpawnOutcome {
  pid : Int
  port : Int
  profile : String
  home : String
  /// 这一只用的 home 归属：trial（homes root 下的 trial- 一次性 home）/ isolated（这只 profile
  /// 自己的隔离 home）/ shared（控制台的 DSH_HOME）。判据是实际用的那条路径，不靠名字猜。
  home_kind : String
  log_path : String
  detached : Bool
  boot_ms : Int
  command : String
  url : String
  /// 这一只实例跑的 dsh 版本与包目录（起的那一刻生效的那一份）
  dsh_version : String
  dsh_package_dir : String
  /// auto / pinned / pin-missing（见 runtime 的 pin_state_*）
  dsh_pin_state : String
  /// 指定失效时那句人话（其余空串）
  dsh_pin_note : String
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
/// /proc/net/tcp(6) 状态列里 LISTEN 的码。
pub let listen_state : String = "0A"

///|
/// /proc/net/tcp(6) 里**正在听**的本地端口 —— 只认状态列 0A（LISTEN），别的状态一律不算。
///
/// 为什么不看别的状态：TIME-WAIT（06）、FIN-WAIT、CLOSE-WAIT、CLOSE 这些都是连接关掉之后的
/// 残留，那段时间端口上**没有任何东西在听**，内核允许重新 bind（监听侧带 SO_REUSEADDR 即可，
/// node 的 server.listen 默认就带）。把它们算成「被占用」会挑掉其实空着的口 ——
/// 实测过的那一次：实例被停掉时自己留下一条 local=<原端口> 的 TIME-WAIT，重启就被它挡回来，
/// 而端口上明明什么都没在听。
///
/// 两张表都读：IPv4 在 /proc/net/tcp，IPv6 在 /proc/net/tcp6（`::1` 上的监听只出现在后者，
/// 只听 v6 的服务也不会在 v4 那张表里留行）。
pub async fn listening_ports() -> Array[Int] noraise {
  let out : Array[Int] = []
  for file in ["/proc/net/tcp", "/proc/net/tcp6"] {
    let text = match @json.read_text_file(file) {
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
/// 从 base 起找第一个空闲端口。空闲 = /proc/net/tcp(6) 里没有 LISTEN，且运行登记里没有 ——
/// 只有真的有人在听的口才跳过（改前连 TIME-WAIT 这类残留也一起跳，白扔掉空着的口）。
/// 找不到给 None（不瞎扩大范围）。
pub async fn pick_free_port(base : Int) -> Int? noraise {
  let used = listening_ports()
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
  profile : String,
  cwd : String,
  log_path : String,
  detach : Bool,
  grace_ms : Int,
) -> Result[Int, String] noraise {
  // 子进程环境 = 继承当前进程 → global → 该 profile（§61.2）。
  // 保留键（DSH_HOME / PATH / HOME …）由这里先摆好，env_for_spawn 不会再覆盖它们。
  let env : Map[String, String] = Map([("DSH_HOME", home)])
  let (inherit, extra) = @store.env_plan(home, profile)
  for pair in extra.iter() {
    env[pair.0] = pair.1
  }
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
            inherit_env=inherit,
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
      inherit_env=inherit,
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
        // 主端口与 alsoPorts 都算：列表按 pid 归并之后，另一个端口不再有自己那一行，
        // 但按端口点「停止 / 重启」的老路径还得认得出它属于哪只实例。
        let mut hit = item.port == p
        for extra in item.also_ports {
          if extra.port == p {
            hit = true
          }
        }
        if hit {
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
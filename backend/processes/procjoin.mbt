// 端口 → 进程：把 /proc/net/tcp(6) 里那条 LISTEN 的 socket inode，对到真正持有它的进程。
//
// 为什么必须走这条路：宿主上真实的 dsh 实例命令行是
//   node …/node_modules/@deepseek-ai/dsh/lib/bin.js --profile web --no-open
// 里面没有 --port，environment 里也没有任何 DSH_* —— 靠命令行认不出它监听哪个端口。
// 唯一可靠的 join 是内核自己给的那一条：
//   /proc/net/tcp 第 9 列 inode  ←→  /proc/<pid>/fd/* 里某个链接目标 socket:[<inode>]
//
// 全程只读：/proc/net/tcp(6)、/proc/<pid>/cmdline、environ、stat、uptime，
// 以及 readlink(/proc/<pid>/fd/*)（唯一的 FFI，见 ../json/fd_link.c）。不 spawn、不写盘。
//
// 读不到就是读不到：每一种失败都对应一个结构化原因码，交给前端显示，不编值。

///|
/// 一个 inode 的持有者。
pub struct Holder {
  inode : Int64
  pid : Int32
  /// 该进程 fd 表里出现过的 …/.dsh/… 路径前缀（DSH_HOME 的候选线索，没有给 None）
  home_hint : String?
}

///|
/// 一次「谁持有这些 inode」扫描的结论与统计。
pub struct HolderScan {
  holders : Array[Holder]
  scanned_pids : Int32
  fd_denied : Int32
  note : String
}

///|
/// 进程事实 + 每一项的来源/原因。拿不到的值是 None，同时 source 里写清为什么。
pub struct ProcFacts {
  pid : Int32?
  inode : Int64?
  profile : String?
  profile_source : String
  dsh_home : String?
  dsh_home_source : String
  entry_path : String?
  version : String?
  version_source : String
  started_at : String?
  uptime_seconds : Int32?
  /// 进程级原因码：port-join / port-arg / process-gone / fd-unreadable / cmdline-unreadable / unscanned
  reason_code : String
  reason : String
}

///|
/// socket:[164633] → 164633；其他链接目标（管道、文件、anon_inode）给 None。
pub fn parse_socket_inode(target : String) -> Int64? {
  if !@json.starts_with(target, "socket:[") || !@json.ends_with(target, "]") {
    return None
  }
  let body = @json.slice(target, 8, target.length() - 1)
  if !@json.is_all_digits(body) {
    return None
  }
  Some(@json.parse_dec64(body))
}

///|
/// 从 fd 链接目标里取 DSH_HOME 前缀：…/.dsh/sessions/… → …/.dsh。
/// 只认绝对路径，且只认 /.dsh/ 这一段；路径里没有就给 None（不猜）。
///
/// 这是**线索**不是结论：~/.dsh-homes/<profile>/ 这类布局在这一段里认不出来，
/// 会照样给 None。给 None 的语义是「认不出」，调用方必须如实写「未知」，
/// 不许拿 $HOME/.dsh 之类的默认值顶替 —— 顶替一次，健康读数、日志目录、卡片 home
/// 会一起指向别人的那一份，而且看不出错在哪。
pub fn dsh_home_prefix(target : String) -> String? {
  if !@json.starts_with(target, "/") {
    return None
  }
  match @json.index_of(target, "/.dsh/") {
    Some(i) => Some(@json.slice(target, 0, i) + "/.dsh")
    None => None
  }
}

///|
/// 目录读失败是不是「权限不足」这一类（EACCES/EPERM，hidepid 或别的用户）。
fn is_denied(message : String) -> Bool {
  @json.index_of_ci(message, "eacces") is Some(_) ||
  @json.index_of_ci(message, "eperm") is Some(_) ||
  @json.index_of_ci(message, "permission") is Some(_) ||
  @json.index_of_ci(message, "denied") is Some(_)
}

///|
/// /proc 下所有数字目录，按 pid 升序。
async fn all_pids() -> Array[Int32] noraise {
  let names = @json.list_dir(proc_root)
  let pids : Array[Int32] = []
  for name in names {
    if @json.is_all_digits(name) {
      pids.push(@json.parse_dec(name))
    }
  }
  pids.sort()
  pids
}

///|
/// 谁持有这些 inode：一遍扫 /proc/<pid>/fd，读链接目标比对。
///
/// 只做一遍：目标 inode 全都对上就提前收工；顺带记下每个持有者 fd 表里的 …/.dsh/… 前缀，
/// 后面判 DSH_HOME 时不用再扫一遍。
pub async fn holders_for_inodes(inodes : Array[Int64]) -> HolderScan noraise {
  let wanted : Array[Int64] = []
  for inode in inodes {
    if !wanted.contains(inode) {
      wanted.push(inode)
    }
  }
  let holders : Array[Holder] = []
  let found : Array[Int64] = []
  let mut scanned = 0
  let mut fd_denied = 0
  let pids = all_pids()
  for pid in pids {
    if found.length() >= wanted.length() {
      break
    }
    let fd_dir = proc_root + "/" + @json.int_to_dec(pid) + "/fd"
    let names = match @json.list_dir_result(fd_dir) {
      Ok(list) => list
      Err(message) => {
        if is_denied(message) {
          fd_denied = fd_denied + 1
        }
        continue
      }
    }
    scanned = scanned + 1
    let mut home_hint : String? = None
    let matched : Array[Int64] = []
    for name in names {
      match @json.read_link(fd_dir + "/" + name) {
        Ok(target) => {
          match dsh_home_prefix(target) {
            Some(prefix) =>
              match home_hint {
                None => home_hint = Some(prefix)
                Some(_) => ()
              }
            None => ()
          }
          match parse_socket_inode(target) {
            Some(inode) =>
              if wanted.contains(inode) && !found.contains(inode) {
                found.push(inode)
                matched.push(inode)
              }
            None => ()
          }
        }
        Err(_) => ()
      }
    }
    for inode in matched {
      holders.push({ inode, pid, home_hint, })
    }
  }
  let note = if wanted.length() == 0 {
    "没有待查的 socket inode（/proc/net/tcp 读不到或没有 loopback LISTEN）"
  } else if found.length() >= wanted.length() {
    "在 /proc/<pid>/fd 里对上了全部 " +
    wanted.length().to_string() +
    " 个 socket inode"
  } else if fd_denied > 0 {
    "有 " +
    fd_denied.to_string() +
    " 个进程的 /proc/<pid>/fd 读不了（权限不足），这些进程的 inode 无法对上"
  } else {
    "扫了 " +
    scanned.to_string() +
    " 个进程的 fd 表，有 " +
    (wanted.length() - found.length()).to_string() +
    " 个 socket inode 没有任何可见进程持有（进程已退出，或它不在本 PID 命名空间里）"
  }
  { holders, scanned_pids: scanned, fd_denied, note, }
}

///|
/// 按 inode 找持有者；找不到给 None。
pub fn holder_for(scan : HolderScan, inode : Int64) -> Holder? {
  for holder in scan.holders {
    if holder.inode == inode {
      return Some(holder)
    }
  }
  None
}

///|
/// 进程级原因码对应的人话。前后端共用同一套口径：前端按码给短标签，长说明照抄这里。
pub fn reason_text(code : String) -> String {
  match code {
    "port-join" =>
      "端口对应的 socket inode 在 /proc/<pid>/fd 里对到了持有进程"
    "port-arg" =>
      "inode 对不上，退回按 cmdline 的 --port 匹配到的进程（证据比 inode 弱）"
    "process-gone" =>
      "端口仍在 LISTEN，但没有可见进程持有该 socket：进程已退出，或它运行在别的 PID 命名空间、属于别的用户"
    "fd-unreadable" =>
      "/proc/<pid>/fd 读不到（权限不足或 hidepid），无法从 inode 找到进程"
    "cmdline-unreadable" =>
      "进程在，但 /proc/<pid>/cmdline 读不到（权限不足，或读的瞬间进程已退出）"
    "unscanned" =>
      "没有拿到该端口的 socket inode（/proc/net/tcp(6) 读不到或该端口不在其中）"
    _ => "原因未分类"
  }
}

///|
/// 构造一条「进程侧什么都没有」的事实。
pub fn absent_facts(
  inode : Int64?,
  code : String,
  detail : String,
) -> ProcFacts {
  let why = if detail == "" { reason_text(code) } else { detail }
  let unknown = "未知：" + why
  {
    pid: None,
    inode,
    profile: None,
    profile_source: unknown,
    dsh_home: None,
    dsh_home_source: unknown,
    entry_path: None,
    version: None,
    version_source: unknown,
    started_at: None,
    uptime_seconds: None,
    reason_code: code,
    reason: why,
  }
}

///|
/// 入口路径 → 所在包的目录 …/node_modules/@deepseek-ai/dsh；不是这条路给 None。
fn dsh_package_dir(entry : String) -> String? {
  match @json.index_of(entry, "node_modules/@deepseek-ai/dsh/") {
    Some(i) => Some(@json.slice(entry, 0, i) + "node_modules/@deepseek-ai/dsh")
    None => None
  }
}

///|
/// 读某个入口包的版本：包目录里的 package.json 的 version 字段。
/// 返回 (版本, 来源说明)。通过 .bin 软链进来的入口先 realpath 一次再找。
pub async fn read_entry_version(entry : String) -> (String?, String) noraise {
  let mut path = entry
  let mut via = ""
  if dsh_package_dir(path) is None {
    match @json.real_path(path) {
      Some(real) =>
        if real != path && dsh_package_dir(real) is Some(_) {
          path = real
          via = "（入口是软链，realpath 后为 " + real + "）"
        }
      None => ()
    }
  }
  let dir = match dsh_package_dir(path) {
    Some(d) => d
    None =>
      return (
        None,
        "入口路径里没有 node_modules/@deepseek-ai/dsh 这一段，认不出包目录：" +
        entry,
      )
  }
  let file = @json.join_path(dir, "package.json")
  let text = match @json.read_text_file(file) {
    Ok(t) => t
    Err(e) =>
      return (
        None,
        "入口包的 package.json 读不到：" + file + "（" + e + "）",
      )
  }
  let parsed = match @json.json_parse(text) {
    Some(j) => j
    None => return (None, "入口包的 package.json 解析失败：" + file)
  }
  match @json.json_field(parsed, "version") {
    Some(v) =>
      match @json.json_string(v) {
        Some(version) =>
          (
            Some(version),
            "入口包 package.json 的 version 字段：" + file + via,
          )
        None =>
          (None, "入口包 package.json 的 version 不是字符串：" + file)
      }
    None => (None, "入口包 package.json 里没有 version 字段：" + file)
  }
}

///|
/// 进程的四项事实：Profile / DSH_HOME / DSH 版本 / 运行时长，逐项带来源。
/// profile 来自 cmdline，home 先看 environ 再看 fd 表，版本来自入口包，时长来自 stat + uptime。
pub async fn facts_for_pid(
  pid : Int32,
  inode : Int64?,
  home_hint : String?,
  code : String,
  detail : String,
) -> ProcFacts noraise {
  let pid_text = @json.int_to_dec(pid)
  let argv = match read_argv(pid) {
    Some(a) => a
    None =>
      return absent_facts(
        inode,
        "cmdline-unreadable",
        "找不到 PID " +
        pid_text +
        " 的 cmdline（读不到，或读的瞬间进程已退出）",
      )
  }
  let profile = read_option(argv, "--profile")
  let profile_source = match profile {
    Some(name) => "PID " + pid_text + " 的 cmdline：--profile " + name
    None => "未知：PID " + pid_text + " 的 cmdline 里没有 --profile"
  }
  let mut entry : String? = None
  for token in argv {
    if is_dsh_entry(token) {
      entry = Some(token)
      break
    }
  }
  let (version, version_source) = match entry {
    Some(e) => read_entry_version(e)
    None =>
      (
        None,
        "未知：PID " +
        pid_text +
        " 的 cmdline 里没有 dsh 入口，认不出是哪个包",
      )
  }
  let (dsh_home, dsh_home_source) = match read_env_of(pid, "DSH_HOME") {
    Some(v) =>
      (Some(v), "$DSH_HOME 环境变量（PID " + pid_text + " 的 environ）")
    None =>
      match home_hint {
        Some(prefix) =>
          (
            Some(prefix),
            "environ 里没有 DSH_HOME；取 fd 表里 …/.dsh/… 路径的前缀（PID " +
            pid_text +
            "）",
          )
        // 认不出就是认不出：不给 dsh_home，也不拿 $HOME/.dsh 顶替。
        // 自定义 home（比如 ~/.dsh-homes/<profile>/）在这一层本来就读不出来，
        // 顶替成默认值等于把这只实例算到主线头上 —— 它的 profileHealth、日志目录、
        // 卡片 home、复制出去的开发指令会一起错，而且看不出错在哪。
        None =>
          (
            None,
            "未知：PID " +
            pid_text +
            " 的 environ 里没有 DSH_HOME，fd 表里也没有 …/.dsh/… 这一段；认不出它的 home，" +
            "不按默认值 $HOME/.dsh 顶替",
          )
      }
  }
  let sys_uptime = read_uptime_seconds()
  let uptime_seconds = uptime_seconds_of(pid, sys_uptime)
  let started_at = match uptime_seconds {
    Some(seconds) =>
      Some(@json.iso_from_epoch_ms(@async.now() - seconds.to_int64() * 1000L))
    None => None
  }
  {
    pid: Some(pid),
    inode,
    profile,
    profile_source,
    dsh_home,
    dsh_home_source,
    entry_path: entry,
    version,
    version_source,
    started_at,
    uptime_seconds,
    reason_code: code,
    reason: if detail == "" {
      reason_text(code)
    } else {
      detail
    },
  }
}

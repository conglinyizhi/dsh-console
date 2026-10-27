// GET /api/local/instances 的数据体。
//
// 口径是「loopback LISTEN 端口 + HTTP 签名」，不是「进程名里含 dsh」：
// 不 spawn、不写盘，只读 /proc/net/tcp(6) 与 /proc/<pid>/*，再对 127.0.0.1 的候选端口发一次 GET。
//
// 字段与 Node 版 server/readInstances.mjs 的返回值逐字段一致：
//   { sources, probeResults, perFile, scope, listenState, candidateLimit, truncated,
//     truncatedNote, candidates, candidateCount, probe, signatures, processSupplement,
//     instances }
//
// 探测口径与 Node 版 readInstances.mjs 对齐：GET、不跟随重定向、单口 500ms 超时、
// 只读前 8KB、候选上限 40、8 路并发；顺序按端口升序，与并发无关。
//
// 判据只认两条 DSH 独有的长字符串：
//   dsh-auth-401    HTTP 401 且体含 "dsh web authentication required"
//   dsh-boot-global 体含 "__DSH_BOOT__"
// 「含 DSH 字样」绝不作判据——本控制台自己的页面标题就带 DSH，那样会把自己列成实例。
//
// 列表的粒度是**进程**，不是端口：探是按端口探的（probeResults 一份不少），
// 但列出来的条目按 pid 归并成一行，同一只进程的其余端口收进 alsoPorts（见 merge_same_pid）。
// 从前一个 pid 听着两个端口就出两行，其中必然有一行是「故障」—— 那是把「正常」说成了「坏」。

///|
/// 监听套接字的来源文件；0A = LISTEN。
priv struct SocketFile {
  file : String
  family : String
}

///|
/// 见上。
let socket_files : Array[SocketFile] = [
  { file: "/proc/net/tcp", family: "ipv4", },
  { file: "/proc/net/tcp6", family: "ipv6", },
]

///|
/// /proc/net/tcp(6) 里一行 LISTEN：端口 + 第 9 列的 socket inode。
/// inode 是「端口 → 进程」那条 join 的唯一钥匙（见 ../processes/procjoin.mbt）。
priv struct ListenSocket {
  port : Int32
  inode : Int64
}

///|
/// 只认 loopback（/proc/net 里按小端十六进制写）。
let loopback_ipv4 : String = "0100007F"

///|
/// ::1
let loopback_ipv6 : String = "00000000000000000000000001000000"

///|
/// ::ffff:127.0.0.1
let loopback_ipv6_mapped : String = "0000000000000000FFFF00000100007F"

///|
/// 候选端口上限的缺省值：超了就截断，并在响应里说明。
/// 真正生效的值来自设置 probe.maxCandidates，这里只是缺省与回退。
pub let max_candidates : Int32 = 40

///|
/// 逐个候选的探测结论（不含响应体），口径可核对。
pub struct ProbeResult {
  port : Int32
  reached : Bool
  http_status : Int32?
  content_type : String?
  signature_id : String?
  error : String?
}

///|
/// 同一只进程的另一个监听端口。
///
/// 为什么收进主端口那一行而不是单独成行：一个 pid 同时听着几个端口时，那几个端口说的都是
/// 「这同一只实例」。各占一行会让一只实例在界面上出现两次，而且其中一行注定是「故障」——
/// dsh 的网页入口只有一个端口，另一个端口探 GET / 自然是 404，那是**正常的**。
/// 界面在说假话比少列一个端口更糟，所以收进主端口那一行，只当一条附注。
pub struct AlsoPort {
  port : Int32
  http_status : Int32?
  /// 这个端口命中的判据（没命中给空串）
  signature_id : String
  /// 一句人话：这个端口是什么、这一次探测拿到了什么
  note : String
}

///|
/// 命中的实例。
pub struct InstanceSummary {
  id : String
  port : Int32
  url : String
  title : String?
  http_status : Int32?
  content_type : String?
  signature_id : String
  signature_describe : String
  signature_evidence : String
  profile : String?
  pid : Int32?
  dsh_home : String?
  exe_path : String?
  started_at : String?
  uptime_seconds : Int32?
  probe_ms : Int32
  /// 该端口在 /proc/net/tcp(6) 里那行的 socket inode（读不到给 None）
  inode : Int64?
  /// 实例入口包的版本（…/node_modules/@deepseek-ai/dsh/package.json）
  version : String?
  version_source : String
  profile_source : String
  dsh_home_source : String
  /// 这只实例用的 home 的归属：trial / isolated / shared。
  /// 空串 = DSH_HOME 读不到，归属不判（§11.1：第三档 trial 是 homes root 下的 trial- 目录）。
  home_kind : String
  /// 上面那一档凭什么判的（一句人话，进悬停）
  home_kind_source : String
  /// 进程级原因码：port-join / port-arg / process-gone / fd-unreadable / cmdline-unreadable / unscanned
  process_reason_code : String
  process_reason : String
  /// 状态灯（第七轮契约第一节）：running / fault / starting，判据见 judge_state
  state : String
  /// 为什么是这个状态：黄要能分开说是 b 还是 c；红不在这个接口里（没在跑的端口不进列表）
  state_reason : String
  /// 解析出的 profile 体检（缺包数 + 有没有 cordis.patch.yml）；解析不出来给 None
  health : @profiles.ProfileHealth?
  /// 同一个 pid 名下的其余监听端口（主端口之外的）。空数组 = 这只进程只听着这一个端口。
  also_ports : Array[AlsoPort]
}

///|
/// 判据表里的一条。
priv struct Signature {
  id : String
  describe : String
}

///|
/// 两条判据，与 Node 版 SIGNATURES 一一对应。
let signature_auth : Signature = {
  id: "dsh-auth-401",
  describe: "HTTP 401 且响应体含 \"dsh web authentication required\"（dsh-client-connection 的未授权应答）",
}

///|
/// 见上。
let signature_boot : Signature = {
  id: "dsh-boot-global",
  describe: "响应体含 \"__DSH_BOOT__\"（dsh web 注入 index.html 的引导全局名）",
}

///|
/// 命中的判据；都没命中给 None。
fn classify(probe : @localapi.Probe) -> Signature? {
  match probe.status {
    Some(401) =>
      if @json.index_of(probe.body, "dsh web authentication required")
        is Some(_) {
        return Some(signature_auth)
      }
    _ => ()
  }
  if @json.index_of(probe.body, "__DSH_BOOT__") is Some(_) {
    return Some(signature_boot)
  }
  None
}

///|
/// 一行一个套接字，按列切：0 序号 1 本地地址 2 远端地址 3 状态 … 9 inode。
/// 只收 st=0A（LISTEN）且本地地址是 loopback 的行；inode 一并带回，
/// 它是后面「端口 → 进程」那条 join 的钥匙。
fn parse_listen_sockets(text : String?, family : String) -> Array[ListenSocket] {
  let out : Array[ListenSocket] = []
  let body = match text {
    Some(t) => t
    None => return out
  }
  for line in body.split("\n") {
    let cols = @json.split_ws(line.to_owned())
    if cols.length() < 4 {
      continue
    }
    if !@json.is_all_digits(@json.slice(cols[0], 0, cols[0].length() - 1)) ||
      !@json.ends_with(cols[0], ":") {
      continue
    }
    if cols[3] != "0A" {
      continue
    }
    let addr_parts = @json.split_ws(cols[1].replace_all(old=":", new=" "))
    if addr_parts.length() != 2 {
      continue
    }
    let hex = @json.to_lower(addr_parts[0])
    let is_loopback = if family == "ipv4" {
      hex == @json.to_lower(loopback_ipv4)
    } else {
      hex == @json.to_lower(loopback_ipv6) ||
      hex == @json.to_lower(loopback_ipv6_mapped)
    }
    if !is_loopback {
      continue
    }
    let port = parse_hex(addr_parts[1])
    if port <= 0 {
      continue
    }
    // 第 9 列是 inode。列数不够或不是数字时按「读不到 inode」处理（给 0），
    // 端口照收 —— 端口本身仍是有效候选，只是这条 join 走不通。
    let inode = if cols.length() > 9 && @json.is_all_digits(cols[9]) {
      @json.parse_dec64(cols[9])
    } else {
      0L
    }
    out.push({ port, inode, })
  }
  out
}

///|
/// 十六进制串转 Int；非法给 -1。
fn parse_hex(s : String) -> Int32 {
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
/// 去重并按端口升序。
fn dedup_sorted(ports : Array[Int32]) -> Array[Int32] {
  let sorted = ports.copy()
  sorted.sort()
  let out : Array[Int32] = []
  for p in sorted {
    let last = out.length() - 1
    if last < 0 || out[last] != p {
      out.push(p)
    }
  }
  out
}

///|
/// 取 <title>…</title> 的内容（大小写不敏感，最多 120 字符）。
fn extract_title(body : String) -> String? {
  let open_at = match @json.index_of_ci(body, "<title") {
    Some(i) => i
    None => return None
  }
  let gt = match @json.index_of(@json.slice_from(body, open_at), ">") {
    Some(i) => open_at + i + 1
    None => return None
  }
  let rest = @json.slice_from(body, gt)
  let close_at = match @json.index_of_ci(rest, "</title>") {
    Some(i) => i
    None => return None
  }
  if close_at < 1 || close_at > 120 {
    return None
  }
  Some(@json.trim_both(@json.slice(rest, 0, close_at)))
}

///|
/// 命中的证据片段：压平空白后截断，回显在响应里供人核对。
fn evidence(probe : @localapi.Probe, signature : Signature) -> String {
  if signature.id == "dsh-auth-401" {
    for line in probe.body.split("\n") {
      let trimmed = @json.trim_both(line.to_owned())
      if @json.index_of(trimmed, "dsh web authentication required") is Some(_) {
        return trimmed
      }
    }
    return ""
  }
  let at = match @json.index_of(probe.body, "__DSH_BOOT__") {
    Some(i) => i
    None => return ""
  }
  let from = if at > 20 { at - 20 } else { 0 }
  @json.collapse_ws(@json.slice(probe.body, from, at + 40))
}

///|
/// 一个端口对应的 socket inode；没有就 None（列里读不到 inode 时记 0，按读不到处理）。
fn socket_inode_of(sockets : Array[ListenSocket], port : Int32) -> Int64? {
  for row in sockets {
    if row.port == port && row.inode != 0L {
      return Some(row.inode)
    }
  }
  None
}

///|
/// 收一行 LISTEN，同端口只留一条；先来的 inode 为空时用后来的补上。
fn push_socket(sockets : Array[ListenSocket], row : ListenSocket) -> Unit {
  let mut i = 0
  while i < sockets.length() {
    if sockets[i].port == row.port {
      if sockets[i].inode == 0L && row.inode != 0L {
        sockets[i] = row
      }
      return
    }
    i = i + 1
  }
  sockets.push(row)
}

///|
/// 进程侧的补充扫描：按 cmdline 的 --port 找 dsh 进程。
/// 这是弱证据，只在 inode join 走不通时兜底（真实实例命令行里根本不带 --port）。
///|
/// macOS 版的进程侧补充：命令行从 `ps` 拿，DSH_HOME / fd 反查拿不到。
/// 解析规则与 Linux 那条路共用（is_dsh_entry / read_port / read_option）。
async fn supplement_processes_ps(
  socket_inodes : Int32,
) -> (ProcessSupplement, Array[@processes.ProcSummary]) noraise {
  let rows = @platform.process_table()
  let found : Array[@processes.ProcSummary] = []
  let mut scanned = 0
  for row in rows {
    scanned = scanned + 1
    let argv = @json.split_ws(row.command)
    if argv.length() == 0 {
      continue
    }
    if !argv.any(fn(t) { @processes.is_dsh_entry(t) }) {
      continue
    }
    let exe = match argv.get(0) {
      Some(e) => e
      None => ""
    }
    found.push(
      @processes.make_proc_summary(
        row.pid,
        @processes.read_port(argv),
        @processes.read_option(argv, "--profile"),
        None,
        exe,
        None,
        None,
      ),
    )
  }
  let with_port = found.filter(fn(p) { p.port is Some(_) })
  let note = if found.length() == 0 {
    "这台机器没有 /proc：只扫了 ps，没找到 dsh 进程"
  } else {
    "这台机器没有 /proc：命令行取自 ps，DSH_HOME 与 fd 反查不可用"
  }
  (
    {
      proc_root: "ps",
      scanned,
      dsh_processes: found.length(),
      with_port: with_port.length(),
      note,
      socket_inodes,
      inode_holders: 0,
      fd_denied: 0,
      join_note: "",
    },
    found,
  )
}

async fn supplement_processes(
  holders : @processes.HolderScan,
  socket_inodes : Int32,
) -> (ProcessSupplement, Array[@processes.ProcSummary]) noraise {
  // macOS 上没有 /proc 的 environ / fd，走 ps 那一路：cmdline 还能用
  // （`ps -eo pid=,command=`），只是 DSH_HOME 和 fd 反查拿不到。
  if !@platform.supports_proc_scan() {
    return supplement_processes_ps(socket_inodes)
  }
  let report = @processes.read_processes()
  let with_port : Array[@processes.ProcSummary] = []
  for item in report.instances {
    match item.port {
      Some(_) => with_port.push(item)
      None => ()
    }
  }
  let note = if with_port.length() > 0 {
    "按 cmdline 的 --port 匹配到 " +
    with_port.length().to_string() +
    " 个宿主 dsh 进程；这只在 socket inode 的 join 走不通时兜底用"
  } else {
    "没有带 --port 的 dsh 进程可兜底（宿主实例的命令行本来就不带 --port），进程侧只认 socket inode 的 join"
  }
  (
    {
      proc_root: @processes.proc_root,
      scanned: report.scanned,
      dsh_processes: report.instances.length(),
      with_port: with_port.length(),
      note,
      socket_inodes,
      inode_holders: holders.holders.length(),
      fd_denied: holders.fd_denied,
      join_note: holders.note,
    },
    with_port,
  )
}

///|
/// 按端口找补充进程；找不到给 None。
fn find_supplement(
  with_port : Array[@processes.ProcSummary],
  port : Int32,
) -> @processes.ProcSummary? {
  for item in with_port {
    if item.port == Some(port) {
      return Some(item)
    }
  }
  None
}

///|
/// 「刚起」的宽限窗口（秒）：控制台起的实例在这段时间内、端口已在听但签名还没通，
/// 按 starting 算；超过就按故障（b）。判据见 judge_state。
pub let start_grace_seconds : Int32 = 20

///|
/// 单个端口签名探测不通过时的一句话结论（用探测事实拼，不编）。
fn probe_verdict(probe : @localapi.Probe) -> String {
  if probe.reached {
    match probe.status {
      Some(code) =>
        "HTTP " + @json.int_to_dec(code) + "，响应体不含任何 dsh 判据"
      None => "拿到了响应，但读不出 HTTP 状态码"
    }
  } else {
    match probe.error {
      Some(e) => "探测没打通：" + e
      None => "探测没打通"
    }
  }
}

///|
/// 缺包名预览：最多三个，多了写「等 N 个」。
fn names_preview(names : Array[String]) -> String {
  let mut text = ""
  let mut i = 0
  while i < names.length() && i < 3 {
    if text != "" {
      text = text + "、"
    }
    text = text + names[i]
    i = i + 1
  }
  if names.length() > 3 {
    text = text + " 等 " + @json.int_to_dec(names.length()) + " 个"
  }
  text
}

///|
/// profile 体检不通过的原因（成因 c）；体检正常给 None。
/// 「缺包」与「没有 cordis.patch.yml」是两条独立判据，都命中就都写出来。
fn profile_fault_text(h : @profiles.ProfileHealth) -> String? {
  let parts : Array[String] = []
  if h.missing_bundles > 0 {
    parts.push(
      "缺 " +
      @json.int_to_dec(h.missing_bundles) +
      " 个包（" +
      names_preview(h.missing_names) +
      "）",
    )
  }
  if !h.has_patch {
    parts.push("没有 cordis.patch.yml")
  }
  let mut text = ""
  for p in parts {
    if text != "" {
      text = text + "；"
    }
    text = text + p
  }
  if text == "" {
    None
  } else {
    Some(text)
  }
}

///|
/// 拿这条实例的 profile 体检：profile 名来自 cmdline 的 --profile，
/// 目录按 <这只实例的 DSH_HOME>/profiles/<name> 解析。
/// 读不到给 None + 原因（不编）；profileHealth 为 null 时全靠这句话解释。
async fn lookup_profile_health(
  profile : String?,
  dsh_home : String?,
) -> (@profiles.ProfileHealth?, String) noraise {
  let name = match profile {
    Some(n) => n
    None =>
      return (None, "进程 cmdline 里没有 --profile，解析不出 profile")
  }
  let home = match dsh_home {
    Some(h) => h
    None =>
      return (
        None,
        "这只实例的 DSH_HOME 认不出来（environ 里没有，fd 表里也没有 …/.dsh/… 这一段），" +
        "所以它的 profile 体检读不了；这里不拿默认值 $HOME/.dsh 或控制台自己的 home 顶替",
      )
  }
  let dir = match @profiles.profile_dir_of(home, name) {
    Some(d) => d
    None =>
      return (None, "profile 名不是单段目录名，不解析：" + name)
  }
  match @profiles.profile_health(home, name) {
    Some(h) => (Some(h), dir)
    None => (None, "profile 目录不存在：" + dir)
  }
}

///|
/// 这条实例是不是本控制台起的（runtime.json 里有 pid 或端口对得上的登记）。
/// runtime.json 只记控制台起过的实例，外部起的一律不在里面 —— 所以它只用来判 starting。
fn registered_instance(
  entries : Array[@store.InstanceRecord],
  pid : Int32?,
  port : Int32,
) -> Bool {
  for r in entries {
    if r.port == port {
      return true
    }
    match pid {
      Some(p) => if r.pid == p { return true }
      None => ()
    }
  }
  false
}

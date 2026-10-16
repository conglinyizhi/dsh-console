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

///|
/// 监听套接字的来源文件；0A = LISTEN。
priv struct SocketFile {
  file : String
  family : String
}

///|
/// 见上。
let socket_files : Array[SocketFile] = [
  { file: "/proc/net/tcp", family: "ipv4" },
  { file: "/proc/net/tcp6", family: "ipv6" },
]

///|
/// /proc/net/tcp(6) 里一行 LISTEN：端口 + 第 9 列的 socket inode。
/// inode 是「端口 → 进程」那条 join 的唯一钥匙（见 ../processes/procjoin.mbt）。
priv struct ListenSocket {
  port : Int
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
pub let max_candidates : Int = 40

///|
/// 逐个候选的探测结论（不含响应体），口径可核对。
pub struct ProbeResult {
  port : Int
  reached : Bool
  http_status : Int?
  content_type : String?
  signature_id : String?
  error : String?
}

///|
/// 命中的实例。
pub struct InstanceSummary {
  id : String
  port : Int
  url : String
  title : String?
  http_status : Int?
  content_type : String?
  signature_id : String
  signature_describe : String
  signature_evidence : String
  profile : String?
  pid : Int?
  dsh_home : String?
  exe_path : String?
  started_at : String?
  uptime_seconds : Int?
  probe_ms : Int
  /// 该端口在 /proc/net/tcp(6) 里那行的 socket inode（读不到给 None）
  inode : Int64?
  /// 实例入口包的版本（…/node_modules/@deepseek-ai/dsh/package.json）
  version : String?
  version_source : String
  profile_source : String
  dsh_home_source : String
  /// 进程级原因码：port-join / port-arg / process-gone / fd-unreadable / cmdline-unreadable / unscanned
  process_reason_code : String
  process_reason : String
  /// 状态灯（第七轮契约第一节）：running / fault / starting，判据见 judge_state
  state : String
  /// 为什么是这个状态：黄要能分开说是 b 还是 c；红不在这个接口里（没在跑的端口不进列表）
  state_reason : String
  /// 解析出的 profile 体检（缺包数 + 有没有 cordis.patch.yml）；解析不出来给 None
  health : @profiles.ProfileHealth?
}

///|
/// 一个来源文件的统计。
pub struct PerFile {
  file : String
  family : String
  readable : Bool
  listen_ports : Int
}

///|
/// 进程补充的统计。
pub struct ProcessSupplement {
  proc_root : String
  scanned : Int
  dsh_processes : Int
  with_port : Int
  note : String
  /// 待 join 的 loopback LISTEN socket inode 数
  socket_inodes : Int
  /// 在 /proc/<pid>/fd 里对上持有者的 inode 数
  inode_holders : Int
  /// /proc/<pid>/fd 读不了（权限）而被跳过的进程数
  fd_denied : Int
  /// join 这一遍的结论说明
  join_note : String
}

///|
/// 一次扫描的完整快照。logs 接口用 instances 字段找 instance:<id>。
pub struct InstancesReport {
  per_file : Array[PerFile]
  /// 这一遍实际用的候选上限 / 单口超时 / 并发（来自设置，回显用）
  candidate_limit : Int
  probe_timeout_ms : Int
  probe_concurrency : Int
  candidates : Array[Int]
  truncated : Bool
  truncated_note : String?
  probe_results : Array[ProbeResult]
  probed : Int
  reached : Int
  /// 签名命中的实例数：fault 条目不计入（条目总数看 instances 长度）
  hits : Int
  instances : Array[InstanceSummary]
  supplement : ProcessSupplement
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
      if @json.index_of(probe.body, "dsh web authentication required") is Some(_) {
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
      hex == @json.to_lower(loopback_ipv6) || hex == @json.to_lower(loopback_ipv6_mapped)
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
    out.push({ port, inode })
  }
  out
}

///|
/// 十六进制串转 Int；非法给 -1。
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
/// 去重并按端口升序。
fn dedup_sorted(ports : Array[Int]) -> Array[Int] {
  let sorted = ports.copy()
  sorted.sort()
  let out : Array[Int] = []
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
fn socket_inode_of(sockets : Array[ListenSocket], port : Int) -> Int64? {
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
async fn supplement_processes(
  holders : @processes.HolderScan,
  socket_inodes : Int,
) -> (ProcessSupplement, Array[@processes.ProcSummary]) noraise {
  let report = @processes.read_processes()
  let with_port : Array[@processes.ProcSummary] = []
  for item in report.instances {
    match item.port {
      Some(_) => with_port.push(item)
      None => ()
    }
  }
  let note = if with_port.length() > 0 {
    "按 cmdline 的 --port 匹配到 " + with_port.length().to_string() +
    " 个宿主 dsh 进程；这只在 socket inode 的 join 走不通时兜底用"
  } else {
    "没有带 --port 的 dsh 进程可兜底（宿主实例的命令行本来就不带 --port），进程侧只认 socket inode 的 join"
  }
  ({
    proc_root: @processes.proc_root,
    scanned: report.scanned,
    dsh_processes: report.instances.length(),
    with_port: with_port.length(),
    note,
    socket_inodes,
    inode_holders: holders.holders.length(),
    fd_denied: holders.fd_denied,
    join_note: holders.note,
  }, with_port)
}

///|
/// 按端口找补充进程；找不到给 None。
fn find_supplement(
  with_port : Array[@processes.ProcSummary],
  port : Int,
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
pub let start_grace_seconds : Int = 20

///|
/// 单个端口签名探测不通过时的一句话结论（用探测事实拼，不编）。
fn probe_verdict(probe : @localapi.Probe) -> String {
  if probe.reached {
    match probe.status {
      Some(code) => "HTTP " + @json.int_to_dec(code) + "，响应体不含任何 dsh 判据"
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
      "缺 " + @json.int_to_dec(h.missing_bundles) + " 个包（" + names_preview(h.missing_names) + "）",
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
  if text == "" { None } else { Some(text) }
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
    None => return (None, "进程 cmdline 里没有 --profile，解析不出 profile")
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
    None => return (None, "profile 名不是单段目录名，不解析：" + name)
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
  pid : Int?,
  port : Int,
) -> Bool {
  for r in entries {
    if r.port == port {
      return true
    }
    match pid {
      Some(p) =>
        if r.pid == p {
          return true
        }
      None => ()
    }
  }
  false
}

///|
/// 状态判据（第七轮契约第一节，写死）：
///   running  签名探测通过（绿由签名给，profile 有毛病也不把「在跑」说成「故障」；
///            成因 c 的事实照写进 stateReason，并落在 profileHealth 字段上）
///   fault    b：端口在听，但签名探测不通过（前提：持有它的进程 cmdline 看起来是 dsh）
///            c：签名没通、且解析出的 profile 缺包 > 0 或没有 cordis.patch.yml
///            b 与 c 同时成立时以 c 起头（那是根因），b 的事实一并写进同一句
///   starting 本控制台刚起（runtime.json 有登记、进程起不到 start_grace_seconds 秒），
///            端口已在听但签名还没通：可能还在启动，不是坏
///
/// 为什么签名优先：使用者主力的 web profile 现成读数就是 bundles.missing = 3
/// （那三个 @deepseek-ai/dsh-experimental-* 不在 profile / hoisted 的 node_modules，
/// 但 dsh 从自己的全局安装里解析得到，实例跑得好好的）。让 c 覆盖签名会把这种
/// 「在跑、签名也过」的实例一律点成黄，与「绿＝签名探测通过」的判据打架。
/// 反过来，b 那一路本来就只能靠 c 说清根因，所以 c 在那里仍然起头。
///
/// 红（停用）不在这里：没在跑的端口根本不进这个列表；没在跑的 profile 由前端按
/// GET /api/local/profiles 的 bundles / patch 自己判（黄 c / 红都落在那一侧）。
fn judge_state(
  has_signature : Bool,
  signature_id : String,
  probe : @localapi.Probe,
  facts : @processes.ProcFacts,
  health : @profiles.ProfileHealth?,
  health_source : String,
  registered : Bool,
) -> (String, String) {
  let port_fault = "端口在听，但签名探测不通过（成因 b）：" + probe_verdict(probe)
  let profile_fault = match health {
    Some(h) => profile_fault_text(h)
    None => None
  }
  if has_signature {
    let health_note = match profile_fault {
      Some(text) =>
        "；profile 检查不过（成因 c）：" + text + "（" + health_source +
        "）—— 这只实例在跑、签名也过，绿由签名给，缺包这一条记在 profileHealth 里"
      None =>
        match health {
          Some(_) =>
            "；profile 体检正常（缺包 0，有 cordis.patch.yml）：" + health_source
          None => "；profile 体检读不到：" + health_source
        }
    }
    return ("running", "签名探测通过（" + signature_id + "）" + health_note)
  }
  match profile_fault {
    Some(text) =>
      ("fault", "profile 检查不通过（成因 c）：" + text + "（" + health_source + "）；" + port_fault)
    None =>
      if registered && is_fresh(facts.uptime_seconds) {
        (
          "starting",
          "本控制台刚起的实例（runtime.json 有登记，进程起于 " +
          uptime_text(facts.uptime_seconds) + "）：" + port_fault + "；可能还在启动，进程起满 " +
          @json.int_to_dec(start_grace_seconds) + " 秒仍不通就按故障（b）算",
        )
      } else {
        ("fault", port_fault + pid_note(facts))
      }
  }
}

///|
/// 进程起没起满宽限窗口？读不到运行时长（/proc/<pid>/stat 读不到）不算「刚起」，
/// 按故障算 —— 拿不准时不往好里说。
fn is_fresh(uptime_seconds : Int?) -> Bool {
  match uptime_seconds {
    Some(u) => u < start_grace_seconds
    None => false
  }
}

///|
/// 运行时长的人话；读不到给「时长读不到」。
fn uptime_text(uptime_seconds : Int?) -> String {
  match uptime_seconds {
    Some(u) => @json.int_to_dec(u) + " 秒前"
    None => "时长读不到"
  }
}

///|
/// fault-b 条目补一句进程侧的凭据（PID 来自 /proc 的 join，不是猜的）。
fn pid_note(facts : @processes.ProcFacts) -> String {
  match facts.pid {
    Some(p) => "；持有它的进程 PID " + @json.int_to_dec(p) + " 的 cmdline 里是 dsh 入口"
    None => ""
  }
}

///|
/// 把一条探测结论 + 进程事实收成实例条目，顺手定状态（第七轮契约第一节）。
/// signature 为 None 表示这条是「签名探测不通过、但进程看起来是 dsh」的 fault 条目：
/// 那三个签名字段没有判据可填，id 给空串、describe 写明为什么、evidence 给空串。
async fn summarize(
  probe : @localapi.Probe,
  facts : @processes.ProcFacts,
  inode : Int64?,
  signature : Signature?,
  registry : Array[@store.InstanceRecord],
) -> InstanceSummary noraise {
  let (sig_id, sig_describe, sig_evidence) = match signature {
    Some(s) => (s.id, s.describe, evidence(probe, s))
    None => ("", "签名探测不通过：" + probe_verdict(probe), "")
  }
  let (health, health_source) = lookup_profile_health(facts.profile, facts.dsh_home)
  let has_signature = signature is Some(_)
  let (state, state_reason) = judge_state(
    has_signature,
    sig_id,
    probe,
    facts,
    health,
    health_source,
    registered_instance(registry, facts.pid, probe.port),
  )
  {
    id: "proc-\{probe.port}",
    port: probe.port,
    url: probe.url,
    title: extract_title(probe.body),
    http_status: probe.status,
    content_type: probe.content_type,
    signature_id: sig_id,
    signature_describe: sig_describe,
    signature_evidence: sig_evidence,
    profile: facts.profile,
    pid: facts.pid,
    dsh_home: facts.dsh_home,
    exe_path: facts.entry_path,
    started_at: facts.started_at,
    uptime_seconds: facts.uptime_seconds,
    probe_ms: probe.ms,
    inode,
    version: facts.version,
    version_source: facts.version_source,
    profile_source: facts.profile_source,
    dsh_home_source: facts.dsh_home_source,
    process_reason_code: facts.reason_code,
    process_reason: facts.reason,
    state,
    state_reason,
    health,
  }
}

///|
/// 按当前设置跑一次扫描（读接口用）：probe.timeoutMs / probe.concurrency / probe.maxCandidates。
pub async fn instances_report_with_settings() -> InstancesReport noraise {
  let settings = @store.load_settings().values
  instances_report(
    settings.probe_timeout_ms,
    settings.probe_concurrency,
    settings.probe_max_candidates,
  )
}

///|
/// 一次完整扫描：读 /proc/net/tcp(6)、探测候选端口、补进程信息。
/// 三个探测参数由调用方给（设置里的 probe.*），不再写死。
pub async fn instances_report(
  timeout_ms : Int,
  concurrency : Int,
  candidate_limit : Int,
) -> InstancesReport noraise {
  let per_file : Array[PerFile] = []
  let sockets : Array[ListenSocket] = []
  for src in socket_files {
    let text = match @json.read_text_file(src.file) {
      Ok(t) => Some(t)
      Err(_) => None
    }
    let rows = parse_listen_sockets(text, src.family)
    per_file.push({
      file: src.file,
      family: src.family,
      readable: text is Some(_),
      listen_ports: rows.length(),
    })
    for row in rows {
      push_socket(sockets, row)
    }
  }
  let unique = dedup_sorted(sockets.map(fn(row) { row.port }))
  let truncated = unique.length() > candidate_limit
  let candidates = if truncated {
    unique[:candidate_limit].to_owned()
  } else {
    unique
  }

  // 端口 → 进程：先拿候选端口的 socket inode，再一遍扫 /proc/<pid>/fd 找持有者。
  // 这一遍只看候选端口（≤40 个），不按进程名猜；扫完就被下面的实例拼装复用。
  let wanted_inodes : Array[Int64] = []
  for port in candidates {
    match socket_inode_of(sockets, port) {
      Some(inode) => wanted_inodes.push(inode)
      None => ()
    }
  }
  let holders = @processes.holders_for_inodes(wanted_inodes)

  // 探测：只打 loopback，单个 500ms 超时，8 路并发（与 Node 版 PROBE_CONCURRENCY 同数）。
  // 顺序仍是端口升序：probe_ports 按下标返回，谁先回来不影响排序。
  // 候选上限 40、单口 500ms 的口径没动，最坏耗时因此是 ceil(40/8)×500ms = 2.5s（改前 20s）。
  let settled = @localapi.probe_ports(candidates, timeout_ms, concurrency)

  let (supplement, with_port) = supplement_processes(holders, wanted_inodes.length())
  // 状态判据要用「这条是不是本控制台起的」：runtime.json 只记控制台起过的实例。
  let registry = @store.load_registry().entries
  let instances : Array[InstanceSummary] = []
  let probe_results : Array[ProbeResult] = []
  let mut reached = 0
  let mut hits = 0
  for probe in settled {
    let signature = classify(probe)
    probe_results.push({
      port: probe.port,
      reached: probe.reached,
      http_status: probe.status,
      content_type: probe.content_type,
      signature_id: match signature {
        Some(s) => Some(s.id)
        None => None
      },
      error: probe.error,
    })
    if probe.reached {
      reached = reached + 1
    }
    if signature is Some(_) {
      hits = hits + 1
    }
    // 端口 → 进程：优先 socket inode 的 join（内核给的对应关系），
    // 对不上才退回按 --port 匹配的弱证据，两条都不通就带结构化原因留空。
    let inode = socket_inode_of(sockets, probe.port)
    let facts = match inode {
      Some(i) =>
        match @processes.holder_for(holders, i) {
          Some(h) => @processes.facts_for_pid(h.pid, inode, h.home_hint, "port-join", "")
          None =>
            match find_supplement(with_port, probe.port) {
              Some(p) => @processes.facts_for_pid(p.pid, inode, None, "port-arg", "")
              None => {
                let code = if holders.fd_denied > 0 {
                  "fd-unreadable"
                } else {
                  "process-gone"
                }
                @processes.absent_facts(
                  inode,
                  code,
                  @processes.reason_text(code) + "（扫了 " +
                  holders.scanned_pids.to_string() + " 个可见进程的 fd 表，其中 " +
                  holders.fd_denied.to_string() + " 个读不了）",
                )
              }
            }
        }
      None =>
        @processes.absent_facts(
          None,
          "unscanned",
          @processes.reason_text("unscanned") + "（端口 " + probe.port.to_string() +
          " 的 LISTEN 行里没有可用的 inode）",
        )
    }
    // 第七轮契约的新口径：签名没通的端口，只要持有它的进程 cmdline 看起来是 dsh，
    // 就列出来并标 fault（b）；进程 join 不上、或 cmdline 不像 dsh 的，仍然不进列表。
    if signature is None {
      let pid = match facts.pid {
        Some(p) => p
        None => continue
      }
      if !@processes.cmdline_looks_like_dsh(pid) {
        continue
      }
    }
    instances.push(summarize(probe, facts, inode, signature, registry))
  }

  {
    per_file,
    candidate_limit,
    probe_timeout_ms: timeout_ms,
    probe_concurrency: concurrency,
    candidates,
    truncated,
    truncated_note: if truncated {
      Some(
        "loopback LISTEN 端口共 \{unique.length()} 个，超过上限 \{candidate_limit}，只探测了前 \{candidate_limit} 个",
      )
    } else {
      None
    },
    probe_results,
    probed: settled.length(),
    reached,
    hits,
    instances,
    supplement,
  }
}

///|
/// profileHealth 字段：{ missingBundles, hasPatch }；profile 解析不出来给 null。
fn profile_health_json(health : @profiles.ProfileHealth?) -> @json.JsonVal {
  match health {
    Some(h) =>
      @json.JObj([
        ("missingBundles", @json.jint(h.missing_bundles)),
        ("hasPatch", @json.JBool(h.has_patch)),
      ])
    None => @json.JNull
  }
}

///|
/// 组装 /api/local/instances 的 data 对象。
pub async fn read_instances() -> @json.JsonVal raise @localapi.ReadError {
  let report = instances_report_with_settings()
  let sources : Array[String] = []
  let per_file : Array[@json.JsonVal] = []
  for item in report.per_file {
    sources.push(item.file)
    per_file.push(@json.JObj([
      ("file", @json.JStr(item.file)),
      ("family", @json.JStr(item.family)),
      ("readable", @json.JBool(item.readable)),
      ("listenPorts", @json.jint(item.listen_ports)),
    ]))
  }
  let probe_results : Array[@json.JsonVal] = []
  for item in report.probe_results {
    probe_results.push(@json.JObj([
      ("port", @json.jint(item.port)),
      ("reached", @json.JBool(item.reached)),
      ("httpStatus", @json.int_or_null(item.http_status)),
      ("contentType", @json.str_or_null(item.content_type)),
      ("signatureId", @json.str_or_null(item.signature_id)),
      ("error", @json.str_or_null(item.error)),
    ]))
  }
  let instances : Array[@json.JsonVal] = []
  for item in report.instances {
    // 带令牌的访问地址（契约第四轮）：每次现算，不缓存 —— token 每次启动都可能变。
    // 读不到就是 null，原因写在 webUrlSource 里（见 weburl.mbt）。
    let web = lookup_web_url(item)
    instances.push(@json.JObj([
      ("id", @json.JStr(item.id)),
      ("port", @json.jint(item.port)),
      ("url", @json.JStr(item.url)),
      ("title", @json.str_or_null(item.title)),
      ("httpStatus", @json.int_or_null(item.http_status)),
      ("contentType", @json.str_or_null(item.content_type)),
      ("signature", @json.JObj([
        ("id", @json.JStr(item.signature_id)),
        ("describe", @json.JStr(item.signature_describe)),
        ("evidence", @json.JStr(item.signature_evidence)),
      ])),
      ("profile", @json.str_or_null(item.profile)),
      ("pid", @json.int_or_null(item.pid)),
      ("dshHome", @json.str_or_null(item.dsh_home)),
      ("exePath", @json.str_or_null(item.exe_path)),
      ("startedAt", @json.str_or_null(item.started_at)),
      ("uptimeSeconds", @json.int_or_null(item.uptime_seconds)),
      ("probeMs", @json.jint(item.probe_ms)),
      ("inode", @json.int64_or_null(item.inode)),
      ("version", @json.str_or_null(item.version)),
      ("versionSource", @json.JStr(item.version_source)),
      ("profileSource", @json.JStr(item.profile_source)),
      ("dshHomeSource", @json.JStr(item.dsh_home_source)),
      ("processReason", @json.JObj([
        ("code", @json.JStr(item.process_reason_code)),
        ("message", @json.JStr(item.process_reason)),
      ])),
      ("webUrl", @json.str_or_null(web.url)),
      ("webUrlSource", @json.JStr(web.source)),
      // 第七轮契约：状态灯三件套（加字段，其余字段一个没动）
      ("state", @json.JStr(item.state)),
      ("stateReason", @json.JStr(item.state_reason)),
      ("profileHealth", profile_health_json(item.health)),
    ]))
  }
  @json.JObj([
    ("sources", @json.jstr_array(sources)),
    ("probeResults", @json.JArr(probe_results)),
    ("perFile", @json.JArr(per_file)),
    ("scope", @json.JStr("loopback（127.0.0.1 / ::1 / ::ffff:127.0.0.1）")),
    ("listenState", @json.JStr("0A（LISTEN）")),
    ("candidateLimit", @json.jint(report.candidate_limit)),
    ("truncated", @json.JBool(report.truncated)),
    ("truncatedNote", @json.str_or_null(report.truncated_note)),
    ("candidates", @json.JArr(report.candidates.map(fn(p) { @json.jint(p) }))),
    ("candidateCount", @json.jint(report.candidates.length())),
    ("probe", @json.JObj([
      ("method", @json.JStr("GET")),
      ("redirect", @json.JStr("manual")),
      ("timeoutMs", @json.jint(report.probe_timeout_ms)),
      ("concurrency", @json.jint(report.probe_concurrency)),
      ("probed", @json.jint(report.probed)),
      ("reached", @json.jint(report.reached)),
      ("hits", @json.jint(report.hits)),
    ])),
    ("signatures", @json.JArr([
      @json.JObj([
        ("id", @json.JStr(signature_auth.id)),
        ("describe", @json.JStr(signature_auth.describe)),
      ]),
      @json.JObj([
        ("id", @json.JStr(signature_boot.id)),
        ("describe", @json.JStr(signature_boot.describe)),
      ]),
    ])),
    ("processSupplement", @json.JObj([
      ("procRoot", @json.JStr(report.supplement.proc_root)),
      ("scanned", @json.jint(report.supplement.scanned)),
      ("dshProcesses", @json.jint(report.supplement.dsh_processes)),
      ("withPort", @json.jint(report.supplement.with_port)),
      ("note", @json.JStr(report.supplement.note)),
      ("socketInodes", @json.jint(report.supplement.socket_inodes)),
      ("inodeHolders", @json.jint(report.supplement.inode_holders)),
      ("fdDenied", @json.jint(report.supplement.fd_denied)),
      ("joinNote", @json.JStr(report.supplement.join_note)),
    ])),
    ("instances", @json.JArr(instances)),
  ])
}

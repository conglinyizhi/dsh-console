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
/// 候选端口上限：超了就截断，并在响应里说明。
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
  candidates : Array[Int]
  truncated : Bool
  truncated_note : String?
  probe_results : Array[ProbeResult]
  probed : Int
  reached : Int
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
/// 一次完整扫描：读 /proc/net/tcp(6)、探测候选端口、补进程信息。
pub async fn instances_report() -> InstancesReport noraise {
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
  let truncated = unique.length() > max_candidates
  let candidates = if truncated {
    unique[:max_candidates].to_owned()
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
  let settled = @localapi.probe_ports(candidates)

  let (supplement, with_port) = supplement_processes(holders, wanted_inodes.length())
  let instances : Array[InstanceSummary] = []
  let probe_results : Array[ProbeResult] = []
  let mut reached = 0
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
    let sig = match signature {
      None => continue
      Some(s) => s
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
    instances.push({
      id: "proc-\{probe.port}",
      port: probe.port,
      url: probe.url,
      title: extract_title(probe.body),
      http_status: probe.status,
      content_type: probe.content_type,
      signature_id: sig.id,
      signature_describe: sig.describe,
      signature_evidence: evidence(probe, sig),
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
    })
  }

  {
    per_file,
    candidates,
    truncated,
    truncated_note: if truncated {
      Some(
        "loopback LISTEN 端口共 \{unique.length()} 个，超过上限 \{max_candidates}，只探测了前 \{max_candidates} 个",
      )
    } else {
      None
    },
    probe_results,
    probed: settled.length(),
    reached,
    instances,
    supplement,
  }
}

///|
/// 组装 /api/local/instances 的 data 对象。
pub async fn read_instances() -> @json.JsonVal raise @localapi.ReadError {
  let report = instances_report()
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
    ]))
  }
  @json.JObj([
    ("sources", @json.jstr_array(sources)),
    ("probeResults", @json.JArr(probe_results)),
    ("perFile", @json.JArr(per_file)),
    ("scope", @json.JStr("loopback（127.0.0.1 / ::1 / ::ffff:127.0.0.1）")),
    ("listenState", @json.JStr("0A（LISTEN）")),
    ("candidateLimit", @json.jint(max_candidates)),
    ("truncated", @json.JBool(report.truncated)),
    ("truncatedNote", @json.str_or_null(report.truncated_note)),
    ("candidates", @json.JArr(report.candidates.map(fn(p) { @json.jint(p) }))),
    ("candidateCount", @json.jint(report.candidates.length())),
    ("probe", @json.JObj([
      ("method", @json.JStr("GET")),
      ("redirect", @json.JStr("manual")),
      ("timeoutMs", @json.jint(@localapi.probe_timeout_ms)),
      ("concurrency", @json.jint(@localapi.probe_concurrency)),
      ("probed", @json.jint(report.probed)),
      ("reached", @json.jint(report.reached)),
      ("hits", @json.jint(report.instances.length())),
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

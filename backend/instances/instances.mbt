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
/// 一行一个套接字，按列切：0 序号 1 本地地址 2 远端地址 3 状态。
/// 只收 st=0A（LISTEN）且本地地址是 loopback 的端口。
fn parse_listen_ports(text : String?, family : String) -> Array[Int] {
  let ports : Array[Int] = []
  let body = match text {
    Some(t) => t
    None => return ports
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
    if port > 0 {
      ports.push(port)
    }
  }
  ports
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
/// 进程扫描只做补充：按端口和真实进程对上号才补 pid 与启动时长，对不上就留空。
async fn supplement_processes() -> (ProcessSupplement, Array[@processes.ProcSummary]) noraise {
  let report = @processes.read_processes()
  let with_port : Array[@processes.ProcSummary] = []
  for item in report.instances {
    match item.port {
      Some(_) => with_port.push(item)
      None => ()
    }
  }
  let note = if with_port.length() > 0 {
    "读到了带 --port 的宿主 dsh 进程，按端口补 pid 与启动时长"
  } else {
    "没读到带 --port 的 dsh 进程（PID 命名空间可能被隔离），pid 与启动时长留空，不伪造"
  }
  ({
    proc_root: @processes.proc_root,
    scanned: report.scanned,
    dsh_processes: report.instances.length(),
    with_port: with_port.length(),
    note,
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
  let all_ports : Array[Int] = []
  for src in socket_files {
    let text = match @json.read_text_file(src.file) {
      Ok(t) => Some(t)
      Err(_) => None
    }
    let ports = parse_listen_ports(text, src.family)
    per_file.push({
      file: src.file,
      family: src.family,
      readable: text is Some(_),
      listen_ports: ports.length(),
    })
    for p in ports {
      all_ports.push(p)
    }
  }
  let unique = dedup_sorted(all_ports)
  let truncated = unique.length() > max_candidates
  let candidates = if truncated {
    unique[:max_candidates].to_owned()
  } else {
    unique
  }

  // 探测：只打 loopback，单个 500ms 超时，按端口升序逐个来。
  // 与 Node 版的差异：Node 用 8 路并发，这里是顺序探测。候选端口上限 40，
  // 单个探测最多 500ms，最坏 20 秒，对只读控制台可以接受；
  // 响应里的 probe.concurrency 如实写 1，不冒充 Node 的 8。
  let settled : Array[@localapi.Probe] = []
  for port in candidates {
    settled.push(@localapi.probe_port(port))
  }

  let (supplement, with_port) = supplement_processes()
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
    let proc = find_supplement(with_port, probe.port)
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
      profile: match proc {
        Some(p) => p.profile
        None => None
      },
      pid: match proc {
        Some(p) => Some(p.pid)
        None => None
      },
      dsh_home: match proc {
        Some(p) => p.dsh_home
        None => None
      },
      exe_path: match proc {
        Some(p) => Some(p.exe_path)
        None => None
      },
      started_at: match proc {
        Some(p) => p.started_at
        None => None
      },
      uptime_seconds: match proc {
        Some(p) => p.uptime_seconds
        None => None
      },
      probe_ms: probe.ms,
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
      ("timeoutMs", @json.jint(500)),
      ("concurrency", @json.jint(1)),
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
    ])),
    ("instances", @json.JArr(instances)),
  ])
}

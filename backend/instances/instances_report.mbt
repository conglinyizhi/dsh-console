// 实例报告：把扫描到的监听口与在跑进程合成一只只实例（state / uptime / 备注 / 健康），
// 以及 /api/local/instances 的读入口（read_instances）与 profile 健康那一段。
//
// 2026-10-20 从 instances.mbt 拆出来：那个文件 1128 行，扫（读 /proc 与 socket）与报
// （拼成给界面的读数）两件事混在一起；拆开之后「扫得对不对」与「说得对不对」分开查。
// 只搬位置，函数体一个字没改。


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
/// 状态判据（第七轮契约第一节，写死）：
///   running  签名探测通过（绿由签名给，profile 有毛病也不把「在跑」说成「故障」；
///            成因 c 的事实照写进 stateReason，并落在 profileHealth 字段上）
///   fault    b：端口在听，但签名探测不通过（前提：持有它的进程 cmdline 看起来是 dsh）
///            c：签名没通、且解析出的 profile 缺包 > 0 或没有 cordis.patch.yml
///            b 与 c 同时成立时以 c 起头（那是根因），b 的事实一并写进同一句
///            （界面上这一档落在**黄**「有警告」，不是红：红灯只给「上一次启动失败
///            且之后没成功过」的那一只，判据在 profiles 读数的 lastStart）
///   starting 本控制台刚起（runtime.json 有登记、进程起不到 start_grace_seconds 秒），
///            端口已在听但签名还没通：可能还在启动，不是坏
///
/// 为什么签名优先：使用者主力的 web profile 现成读数就是 bundles.missing = 3
/// （那三个 @deepseek-ai/dsh-experimental-* 不在 profile / hoisted 的 node_modules，
/// 但 dsh 从自己的全局安装里解析得到，实例跑得好好的）。让 c 覆盖签名会把这种
/// 「在跑、签名也过」的实例一律点成黄，与「绿＝签名探测通过」的判据打架。
/// 反过来，b 那一路本来就只能靠 c 说清根因，所以 c 在那里仍然起头。
///
/// 红不在这里：没在跑的端口根本不进这个列表。没在跑的那一侧由前端按
/// GET /api/local/profiles 落四档（design/design-fixes.md §26.1）：
///   黄 = bundles.missing 非空 / 没有 cordis.patch.yml；
///   红 = 那一只的 lastStart.ok == false（审计流水里最近一条启动记录失败了，
///        且失败之后没有成功过 —— 后端在 profiles 读数里给事实，前端不自己翻审计）；
///   无灯 = 没在跑也没有警告。
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
        "）。这只实例在跑、签名也过，绿由签名给，缺包这一条记在 profileHealth 里"
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
  // 这一只跑在哪份 home 里（§11.1）：判据与起实例那一侧同一条（profiles/homes.mbt），
  // 不按 profile 名字猜。DSH_HOME 读不到时两格都空着，界面据此写「读不到」，不编归属。
  let (home_kind, home_kind_source) = match facts.dsh_home {
    Some(h) => {
      let kind = @profiles.home_kind_of(
        h,
        match facts.profile {
          Some(p) => p
          None => ""
        },
      )
      let source = if kind == @profiles.home_kind_trial {
        "home 在 homes root 下且目录名以 " + @profiles.trial_home_prefix + " 开头：" + h
      } else {
        "按这只实例的 DSH_HOME 与它的隔离 home 比出来的：" + h
      }
      (kind, source)
    }
    None => ("", "这只实例的 DSH_HOME 读不到，home 归属不判")
  }
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
    home_kind,
    home_kind_source,
    process_reason_code: facts.reason_code,
    process_reason: facts.reason,
    state,
    state_reason,
    health,
    // 归并那一步才填（见 merge_same_pid）：一条探测结论只看得到一个端口
    also_ports: [],
  }
}

///|
/// 两个同 pid 的端口里，哪一个更适合当这一行的主端口：
///   ① 签名命中 dsh 判据的那个 —— 那才是 dsh 的入口，状态灯与所有读数都该由它来定；
///   ② 都命中（罕见）/ 都没命中时取端口号小的那个。
/// 这一条与「都不命中时取最小端口」是同一个判据的两半，写在一处免得两边不一致。
fn main_better(a : InstanceSummary, b : InstanceSummary) -> Bool {
  let a_sig = a.signature_id != ""
  let b_sig = b.signature_id != ""
  if a_sig != b_sig {
    return a_sig
  }
  a.port < b.port
}

///|
/// 另一个端口那一句人话：探到什么就说什么，不一律说成「不是 dsh」。
///
/// 命中判据的那一种（同一只进程在两个端口上各答一次 dsh 的应答）也要照实说，
/// 不然那句话就成了「明明命中了，界面上写着不是入口」。
fn also_port_note(item : InstanceSummary) -> String {
  if item.signature_id != "" {
    return "同一个进程的另一个监听端口，它也答出了 dsh 的应答"
  }
  match item.http_status {
    Some(code) =>
      "同一个进程的另一个监听端口，不是 dsh 的网页入口：这一次探测回的是 HTTP " +
      @json.int_to_dec(code)
    None => "同一个进程的另一个监听端口，不是 dsh 的网页入口：这一次探测没打通"
  }
}

///|
/// 按 pid 归并：一个 pid 一行。
///
/// 主端口按 main_better 定（签名命中的优先，都没有取端口最小的），
/// 该 pid 名下的其余端口收进这一行的 also_ports；state / stateReason 只按主端口算。
/// **没有 pid 的条目不参与归并**：进程没 join 上时「这两个端口是不是同一只进程」本来就没证据，
/// 硬凑成一行就是把猜的东西当事实写出来。
///
/// 输出顺序仍是端口升序（按主端口），与这一轮之前「顺序按端口升序」的口径一致。
fn merge_same_pid(items : Array[InstanceSummary]) -> Array[InstanceSummary] {
  // ① 先按 pid 分组（没有 pid 的每一条各自成一组）
  let groups : Array[Array[InstanceSummary]] = []
  let group_pids : Array[Int?] = []
  for item in items {
    let mut at = -1
    match item.pid {
      Some(pid) => {
        let mut i = 0
        while i < group_pids.length() {
          match group_pids[i] {
            Some(p) => if p == pid { at = i }
            None => ()
          }
          i = i + 1
        }
      }
      None => ()
    }
    if at < 0 {
      groups.push([item])
      group_pids.push(item.pid)
    } else {
      groups[at].push(item)
    }
  }
  // ② 每组挑一个主端口，其余挂成 also_ports
  let out : Array[InstanceSummary] = []
  for g in groups {
    let mut main_at = 0
    let mut k = 1
    while k < g.length() {
      if main_better(g[k], g[main_at]) {
        main_at = k
      }
      k = k + 1
    }
    let also : Array[AlsoPort] = []
    let mut j = 0
    while j < g.length() {
      if j != main_at {
        also.push({
          port: g[j].port,
          http_status: g[j].http_status,
          signature_id: g[j].signature_id,
          note: also_port_note(g[j]),
        })
      }
      j = j + 1
    }
    let main_item = g[main_at]
    out.push({ ..main_item, also_ports: also })
  }
  // ③ 按主端口升序（组数很少，选择排序足够，也免得给结构体写一个比较器）
  let mut i = 0
  while i < out.length() {
    let mut min = i
    let mut j = i + 1
    while j < out.length() {
      if out[j].port < out[min].port {
        min = j
      }
      j = j + 1
    }
    if min != i {
      let tmp = out[i]
      out[i] = out[min]
      out[min] = tmp
    }
    i = i + 1
  }
  out
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
  // 逐端口收，收完按 pid 归并（一个 pid 一行，见 merge_same_pid）
  let per_port : Array[InstanceSummary] = []
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
    per_port.push(summarize(probe, facts, inode, signature, registry))
  }
  let instances = merge_same_pid(per_port)

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
    // 同一个进程的其余监听端口：只当附注，不单独成行（见 merge_same_pid）
    let also : Array[@json.JsonVal] = []
    for extra in item.also_ports {
      also.push(@json.JObj([
        ("port", @json.jint(extra.port)),
        ("httpStatus", @json.int_or_null(extra.http_status)),
        ("signatureId", @json.JStr(extra.signature_id)),
        ("note", @json.JStr(extra.note)),
      ]))
    }
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
      // 这一只跑在哪种 home 里（§11.1）：trial / isolated / shared；读不到 DSH_HOME 是空串
      ("homeKind", @json.JStr(item.home_kind)),
      ("homeKindSource", @json.JStr(item.home_kind_source)),
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
      // 同一只进程的其余监听端口（主端口之外的）：空数组 = 只听着这一个
      ("alsoPorts", @json.JArr(also)),
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

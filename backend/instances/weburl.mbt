// 带握手令牌的访问地址（契约「追加契约（第四轮）」）。
//
// dsh web 的首次握手看 URL 里的 ?token=<key>：不带就是 401。控制台起实例时把子进程的
// stdout/stderr 重定向到 <该实例 DSH_HOME>/logs/console-<profile>-<port>.log，
// dsh 的启动横幅「dsh web: http://127.0.0.1:<端口>/?token=<串>」就落在那里。
//
// 外部起的实例（例如使用者手敲 dsh --profile web --no-open）没有这份日志，令牌只打在
// 启动它的那个终端里 —— 那就回 null、把「为什么读不到」写清，绝不编一个地址出来。
//
// 三条取值路径（找到就停，见 lookup_web_url）：
//   1. runtime.json 里那条登记的 logPath
//   2. 按控制台的命名约定拼出来的实例日志（先该实例自己的 DSH_HOME，其次 ~/.dsh）
//   3. ~/.dsh/logs 下有界扫描：最近改动的 20 份 .log，每份只读尾部 200 行
//
// 每次调用现算，不缓存 —— token 每次启动都可能变。
// 读到什么就贴什么：本接口不对令牌做二次握手验证；但「开头 + 尾部盖不住整份文件」时
// 不采信开头那个旧令牌（见 probe_own_log），宁可按读不到回 null，也不给一个点了 401 的链接。

///|
/// 一次「带令牌地址」查找的结论。url 为 None 时 source 写清为什么读不到。
priv struct WebUrlLookup {
  url : String?
  source : String
}

///|
/// 一份日志尾部窗口的读取结果。
priv struct LogWindow {
  ok : Bool
  text : String
  size : Int64
  from_start : Bool
  note : String
}

///|
/// 一份日志里的一次令牌查找。
priv struct TokenFound {
  token : String?
  note : String
}

///|
/// 实例自己那份日志：先读这么多尾部字节。
let own_tail_bytes : Int32 = 262144

///|
/// 尾部没命中时补读的开头字节数。
let own_head_bytes : Int32 = 65536

///|
/// 有界扫描：单份日志的尾部字节上限。
let scan_tail_bytes : Int32 = 65536

///|
/// 有界扫描：单份日志最多看多少行（契约写死 200）。
let scan_tail_lines : Int32 = 200

///|
/// 有界扫描：最多看多少份 .log（契约写死 20）。
let scan_max_files : Int32 = 20

///|
/// 令牌最短长度。dsh 的令牌是 43 个 base64url 字符；短于这个数的按残片丢掉。
let min_token_len : Int32 = 8

///|
/// 验证扫描来的令牌时的单次握手超时（毫秒）。
let verify_timeout_ms : Int32 = 2000

///|
/// 验证握手时最多读多少响应体字节（只看状态码，body 只是为了收尾干净）。
let verify_body_bytes : Int32 = 4096

///|
/// 从实例自己的 url（形如 http://127.0.0.1:8400/）里取 host。
/// 取不到就回 127.0.0.1 —— 实例的 url 本来就是探测时拼的回环地址，这里不编别的主机。
fn host_of(url : String) -> String {
  let after = match url.find("//") {
    Some(i) => @json.slice_from(url, i + 2)
    None => url
  }
  let cut = match (after.find(":"), after.find("/")) {
    (Some(c), Some(s)) => if c < s { c } else { s }
    (Some(c), None) => c
    (None, Some(s)) => s
    (None, None) => after.length()
  }
  let host = @json.slice(after, 0, cut)
  if host == "" {
    "127.0.0.1"
  } else {
    host
  }
}

///|
/// 拼出能直接握手的地址：端口用的是该实例自己的端口，host 用的是该实例自己的 host。
fn build_web_url(host : String, port : Int32, token : String) -> String {
  "http://" + host + ":" + port.to_string() + "/?token=" + token
}

///|
/// 令牌字符集：URL 里安全的那一批（base64url 加几个常见的填充/子分隔符）。
/// 遇到别的字符就收尾 —— 日志里令牌后面跟的是空格、引号或行尾。
fn is_token_char(code : Int32) -> Bool {
  (code >= 48 && code <= 57) ||
  (code >= 65 && code <= 90) ||
  (code >= 97 && code <= 122) ||
  code == 45 ||
  code == 46 ||
  code == 95 ||
  code == 126 ||
  code == 43 ||
  code == 47 ||
  code == 61
}

///|
/// 取一段文本开头的令牌；短于下限（残片）给空串。
fn take_token(text : String) -> String {
  let buf = StringBuilder()
  let n = text.length()
  let mut i = 0
  while i < n {
    let ch = text.unsafe_get(i).unsafe_to_char()
    if !is_token_char(ch.to_int()) {
      break
    }
    buf.write_char(ch)
    i = i + 1
  }
  let token = buf.to_string()
  if token.length() < min_token_len {
    ""
  } else {
    token
  }
}

///|
/// 文本里最后一个「:<端口>/?token=<串>」的令牌；没有给 None。
/// 取最后一个：日志是追加写的，越靠后的横幅越是当前这次启动的。
fn last_token_in(text : String, port : Int32) -> String? {
  let marker = ":" + port.to_string() + "/?token="
  let mut found : String? = None
  let mut from = 0
  while from < text.length() {
    let rest = @json.slice_from(text, from)
    let hit = match rest.find(marker) {
      Some(i) => i
      None => break
    }
    let token = take_token(@json.slice_from(rest, hit + marker.length()))
    if token != "" {
      found = Some(token)
    }
    from = from + hit + marker.length() + token.length()
  }
  found
}

///|
/// 只留末尾 max_lines 行；max_lines <= 0 时原样返回。
fn tail_lines(text : String, max_lines : Int32) -> String {
  if max_lines <= 0 {
    return text
  }
  let all : Array[String] = []
  for line in text.split("\n") {
    all.push(line.to_owned())
  }
  if all.length() <= max_lines {
    return text
  }
  all[all.length() - max_lines:].to_owned().join("\n")
}

///|
/// 读一份日志的尾部窗口：最多 max_bytes 字节，max_lines 大于 0 时再截到末尾这么多行。
/// 读不到不抛错，note 里写清原因。
async fn read_tail_window(
  path : String,
  max_bytes : Int32,
  max_lines : Int32,
) -> LogWindow noraise {
  let size = match @json.file_size(path) {
    Some(s) => s
    None =>
      return {
        ok: false,
        text: "",
        size: 0L,
        from_start: false,
        note: "文件不存在或读不到状态",
      }
  }
  if size == 0L {
    return {
      ok: true,
      text: "",
      size: 0L,
      from_start: true,
      note: "文件是空的（0 字节）",
    }
  }
  let want : Int64 = if size < max_bytes.to_int64() {
    size
  } else {
    max_bytes.to_int64()
  }
  let start = size - want
  let text = match @json.read_text_at_fs(path, start, want.to_int()) {
    Ok(t) => t
    // 读侧说明只给结论：原文该进审计，这条路没有审计行，就不带它
    Err(e) =>
      return {
        ok: false,
        text: "",
        size,
        from_start: false,
        note: "读不动：" + e.summary,
      }
  }
  {
    ok: true,
    text: tail_lines(text, max_lines),
    size,
    from_start: start <= 0L,
    note: if start <= 0L {
      "整份文件 " + size.to_int().to_string() + " 字节都读了"
    } else {
      "读了尾部 " +
      want.to_int().to_string() +
      " 字节（文件共 " +
      size.to_int().to_string() +
      " 字节）"
    },
  }
}

///|
/// 在自己那份实例日志里找令牌。
///   · 先读尾部窗口：横幅是追加写的，最近一次启动的横幅就在末尾这一带
///   · 尾部没命中且窗口没盖到文件开头时，补读开头 64KB；只有「开头 + 尾部」能盖住
///     整份文件才采信开头那一段 —— 中间有缺口的话，开头那个令牌可能已经被后一次启动
///     换掉了，贴出去就是一个点了 401 的链接
async fn probe_own_log(path : String, port : Int32) -> TokenFound noraise {
  let tail = read_tail_window(path, own_tail_bytes, 0)
  if !tail.ok {
    return { token: None, note: tail.note, }
  }
  match last_token_in(tail.text, port) {
    Some(t) =>
      return {
        token: Some(t),
        note: tail.note +
        "，里面有 :" +
        port.to_string() +
        "/?token= 的地址",
      }
    None => ()
  }
  let want : Int64 = if tail.size < own_tail_bytes.to_int64() {
    tail.size
  } else {
    own_tail_bytes.to_int64()
  }
  if tail.from_start {
    return {
      token: None,
      note: tail.note +
      "，整份文件里都没有 :" +
      port.to_string() +
      "/?token= 的地址",
    }
  }
  let head_bytes = if tail.size < own_head_bytes.to_int64() {
    tail.size.to_int()
  } else {
    own_head_bytes
  }
  let covered = head_bytes.to_int64() + want
  if covered < tail.size {
    let gap = tail.size - covered
    return {
      token: None,
      note: "尾部 " +
      want.to_int().to_string() +
      " 字节里没有 :" +
      port.to_string() +
      "/?token=；开头 " +
      head_bytes.to_string() +
      " 字节与尾部之间有 " +
      gap.to_int().to_string() +
      " 字节没读，不拿那一段里的旧令牌冒险（贴出去可能是个 401 的地址）",
    }
  }
  let head = match @json.read_text_at_fs(path, 0, head_bytes) {
    Ok(t) => t
    Err(e) =>
      return {
        token: None,
        note: "尾部没命中，开头也读不动：" + e.summary,
      }
  }
  match last_token_in(head, port) {
    Some(t) =>
      {
        token: Some(t),
        note: "尾部没命中；开头 " +
        head_bytes.to_string() +
        " 字节与尾部合起来盖住了整份文件（" +
        tail.size.to_int().to_string() +
        " 字节），令牌来自开头那一段",
      }
    None =>
      {
        token: None,
        note: "整份文件（" +
        tail.size.to_int().to_string() +
        " 字节）里都没有 :" +
        port.to_string() +
        "/?token= 的地址",
      }
  }
}

///|
/// 一次有界扫描的结论：命中的候选（按文件 mtime 降序排好）与一句人话总结。
/// note 只在没命中时有内容；命中时来源写在每个候选自己的 note 里。
priv struct ScanResult {
  hits : Array[TokenFound]
  note : String
}

///|
/// ~/.dsh/logs 下的有界扫描：最近改动的 20 份 .log，每份只读尾部 200 行。
/// 只看该目录直接子项里的 .log —— 控制台起的实例日志就落在这里。
/// 命中可能不止一处（同一个端口历史上被别的 profile 用过），全带回去让调用方逐个验证。
async fn scan_logs_for_token(dir : String, port : Int32) -> ScanResult noraise {
  let files : Array[(String, Int64)] = []
  for name in @json.list_dir(dir) {
    if !@json.ends_with(@json.to_lower(name), ".log") {
      continue
    }
    let full = @json.join_path(dir, name)
    if @json.is_dir(full) {
      continue
    }
    match @json.mtime_ms(full) {
      Some(ms) => files.push((full, ms))
      None => ()
    }
  }
  if files.length() == 0 {
    return { hits: [], note: dir + " 下没有 .log 文件可扫", }
  }
  files.sort_by(fn(a, b) {
    if a.1 != b.1 {
      if a.1 > b.1 {
        -1
      } else {
        1
      }
    } else {
      @json.compare_code_units(a.0, b.0)
    }
  })
  let limit = if files.length() > scan_max_files {
    scan_max_files
  } else {
    files.length()
  }
  let hits : Array[TokenFound] = []
  for i = 0; i < limit; i = i + 1 {
    let window = read_tail_window(files[i].0, scan_tail_bytes, scan_tail_lines)
    if window.ok {
      match last_token_in(window.text, port) {
        Some(t) =>
          hits.push({
            token: Some(t),
            note: "dsh 日志目录 " +
            dir +
            " 下有界扫描（最近 " +
            limit.to_string() +
            " 份 .log，每份尾部 " +
            scan_tail_lines.to_string() +
            " 行）：" +
            files[i].0 +
            " 命中了 :" +
            port.to_string() +
            "/?token=",
          })
        None => ()
      }
    }
  }
  if hits.length() > 0 {
    return { hits, note: "", }
  }
  {
    hits: [],
    note: dir +
    " 下最近 " +
    limit.to_string() +
    " 份 .log（每份只读尾部 " +
    scan_tail_lines.to_string() +
    " 行）里没有 :" +
    port.to_string() +
    "/?token= 的地址",
  }
}

///|
/// 实测一次握手：GET /?token=<串>，只看状态是不是 401。
/// 扫描来的令牌是跨文件的，可能已经被后一次启动换掉 —— 采信之前先握一次手，
/// 不把点了就 401 的地址交出去。验证不了（探测不到 / 超时）同样不采用，
/// 宁可回 null 让前端把裸地址给人自己拼。
async fn token_handshakes(
  port : Int32,
  token : String,
) -> (Bool, String) noraise {
  let attempt : async () -> @localapi.RawResponse = async fn() {
    @localapi.fetch_path(port, "/?token=" + token, verify_body_bytes)
  }
  let result = @async.with_timeout_opt(verify_timeout_ms, attempt) catch {
    err => {
      let detail = match @json.raw_http_message(err) {
        Some(msg) => msg
        None => err.to_string()
      }
      return (false, "没能验证（" + detail + "）")
    }
  }
  match result {
    None =>
      (
        false,
        "验证握手超时（" +
        verify_timeout_ms.to_string() +
        "ms 内没答）",
      )
    Some(res) =>
      if res.code == 401 {
        (false, "实测握手仍是 401")
      } else {
        (
          true,
          "已实测握手 HTTP " + res.code.to_string() + "（不是 401）",
        )
      }
  }
}

///|
/// dsh home：优先 DSH_HOME 环境变量，其次 ~/.dsh。
/// 与 runtime 包的 resolve_dsh_home 同口径 —— 契约里的扫描目录 ~/.dsh/logs 就落在这上面。
async fn dsh_home_dir() -> String noraise {
  match @json.env_value("DSH_HOME") {
    Some(v) => v
    None => @json.join_path(@json.home_dir(), ".dsh")
  }
}

///|
/// 该实例自己的日志目录：优先它自己的 DSH_HOME，认不出来才落 ~/.dsh。
fn instance_logs_dir(instance : InstanceSummary, home : String) -> String {
  match instance.dsh_home {
    Some(h) =>
      if h != "" {
        @json.join_path(h, "logs")
      } else {
        @json.join_path(home, "logs")
      }
    None => @json.join_path(home, "logs")
  }
}

///|
/// 给一只实例找「能直接握手的地址」。找不到就 url=None，source 里写清是哪一步读不到。
async fn lookup_web_url(instance : InstanceSummary) -> WebUrlLookup noraise {
  let port = instance.port
  let host = host_of(instance.url)
  let home = dsh_home_dir()
  let default_logs_dir = @json.join_path(home, "logs")
  let attempts : Array[String] = []
  // 已经读过的日志路径：登记里的 logPath 与按命名约定拼出来的可能是同一份，
  // 读两遍没意义，原因也不用在 source 里写两遍
  let tried_paths : Array[String] = []
  // 只认这一步自己的登记：先按 pid，再按端口。不按 profile 找 ——
  // 同名 profile 的历史登记可能指着一份别的日志
  let entries = @store.load_registry().entries
  let mut record : @store.InstanceRecord? = None
  match instance.pid {
    Some(pid) =>
      for r in entries {
        if r.pid == pid {
          record = Some(r)
        }
      }
    None => ()
  }
  if record is None {
    for r in entries {
      if r.port == port {
        record = Some(r)
      }
    }
  }
  // 1. runtime.json 里那条登记的 logPath
  match record {
    Some(r) =>
      if r.log_path == "" {
        attempts.push(
          "runtime.json 里这条登记的 logPath 是空的（没有可读的日志路径）",
        )
      } else {
        tried_paths.push(r.log_path)
        let probe = probe_own_log(r.log_path, port)
        match probe.token {
          Some(t) =>
            return {
              url: Some(build_web_url(host, port, t)),
              source: "runtime.json 的 logPath（" +
              r.log_path +
              "）：" +
              probe.note,
            }
          None =>
            attempts.push(
              "runtime.json 的 logPath（" + r.log_path + "）：" + probe.note,
            )
        }
      }
    None => ()
  }
  // 2. 按控制台的命名约定拼实例日志名
  let mut tried_convention = false
  match instance.profile {
    Some(name) =>
      if name != "" {
        tried_convention = true
        let file_name = "console-" + name + "-" + port.to_string() + ".log"
        let own_path = @json.join_path(
          instance_logs_dir(instance, home),
          file_name,
        )
        let paths : Array[String] = [own_path]
        let default_path = @json.join_path(default_logs_dir, file_name)
        if default_path != own_path {
          paths.push(default_path)
        }
        for path in paths {
          if tried_paths.contains(path) {
            continue
          }
          tried_paths.push(path)
          let probe = probe_own_log(path, port)
          match probe.token {
            Some(t) =>
              return {
                url: Some(build_web_url(host, port, t)),
                source: "实例日志（控制台命名约定 console-<profile>-<port>.log）" +
                path +
                "：" +
                probe.note,
              }
            None => attempts.push(path + "：" + probe.note)
          }
        }
      }
    None => ()
  }
  if !tried_convention {
    attempts.push(
      "实例的 profile 认不出来，拼不出 console-<profile>-<port>.log 这个名字",
    )
  }
  let scan = scan_logs_for_token(default_logs_dir, port)
  let mut scan_note = scan.note
  for hit in scan.hits {
    match hit.token {
      Some(t) => {
        let (ok, why) = token_handshakes(port, t)
        if ok {
          return {
            url: Some(build_web_url(host, port, t)),
            source: hit.note + "，" + why,
          }
        }
        scan_note = scan_note +
          (if scan_note == "" { "" } else { "；" }) +
          hit.note +
          "，但那里的令牌" +
          why +
          "，不采用"
      }
      None => ()
    }
  }
  if scan_note != "" {
    attempts.push(scan_note)
  }
  let lead = match record {
    None =>
      "外部实例：令牌在启动它的终端里（runtime.json 里没有这只实例的登记）。控制台可读的文件都没给出带令牌的地址："
    Some(_) => "这只实例的日志里没有带令牌的地址："
  }
  { url: None, source: lead + attempts.join("；"), }
}

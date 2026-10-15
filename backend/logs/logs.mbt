// GET /api/local/logs 的数据体。
//
// 字段与 Node 版 server/readLogs.mjs 的返回值逐字段一致，包括字段顺序与 null 口径：
//   { source, label, kind, instance, [detectedInstances], [homeSource], path, [logsDir],
//     [logFileCount], [pickedBy], requestedTail, effectiveTail, maxTail, settings,
//     readOk, errorCode, readError, fileSize, windowBytes, lines, truncated, truncatedNote }
//
// 来源白名单只有三条：host / audit / instance:<实例 id>。
// 其它一律 unknown-source（400），不猜路径、不接受任意文件名。

///|
/// 固定来源在磁盘上的位置。
pub struct LogSource {
  id : String
  label : String
  file : String
}

///|
/// 动态来源前缀，与 instances 接口的 id 对接。
pub let instance_prefix : String = "instance:"

///|
/// tail 缺省值（与 Node 版一致）。真正生效的缺省来自设置 logs.defaultTail，这里是回退值。
pub let default_tail : Int = 200

///|
/// 见上。超上限不报错，按上限返回。
pub let max_tail : Int = 1000

///|
/// 实例日志目录名。
let instance_logs_dir : String = "logs"

///|
/// 实例日志目录的扫描深度上限。
let instance_scan_depth : Int = 3

///|
/// 只认这些后缀的普通文件；别的文件不猜，也不读。
let log_extensions : Array[String] = [".log", ".jsonl", ".txt"]

///|
/// 一次扫描最多看多少个目录项，有界。
let max_scan_entries : Int = 2000

///|
/// 展示用的单行文本上限；超了截断并加省略号。
let max_text_chars : Int = 400

///|
/// 白名单里两个固定来源。
pub async fn fixed_sources() -> Array[LogSource] noraise {
  let home = @json.home_dir()
  [
    {
      id: "host",
      label: "宿主日志",
      file: @json.join_all([home, ".dsh", "logs", "retry-control", "host.log"]),
    },
    {
      id: "audit",
      label: "审计日志",
      file: @json.join_all([home, ".dsh", "linxi-guard-audit.jsonl"]),
    },
  ]
}

///|
/// 解析出来的来源。
priv struct Resolved {
  id : String
  kind : String
  instance_id : String
  label : String?
  file : String?
}

///|
/// 解析 source 参数；不在白名单里返回 None（调用方回 unknown-source）。
async fn resolve_source(id : String) -> Resolved? noraise {
  if @json.starts_with(id, instance_prefix) {
    let instance_id = @json.slice_from(id, instance_prefix.length())
    if instance_id == "" {
      return None
    }
    return Some({ id, kind: "instance", instance_id, label: None, file: None })
  }
  for source in fixed_sources() {
    if source.id == id {
      return Some({
        id: source.id,
        kind: "fixed",
        instance_id: "",
        label: Some(source.label),
        file: Some(source.file),
      })
    }
  }
  None
}

///|
/// 一行的解析结果。
struct ParsedLine {
  time : String?
  level : String?
  text : String
  verdict : String?
  outcome : String?
}

///|
/// 按非 [a-z0-9] 切词，丢掉空串。
/// 等价 JS 的 text.toLowerCase().split(/[^a-z0-9]+/) 之后再逐项比对。
fn tokenize_alnum(text : String) -> Array[String] {
  let out : Array[String] = []
  let buf = StringBuilder()
  let mut has = false
  for ch in text {
    let code = ch.to_int()
    let is_alnum = (code >= 48 && code <= 57) || (code >= 97 && code <= 122)
    if is_alnum {
      buf.write_char(ch)
      has = true
    } else if has {
      out.push(buf.to_string())
      buf.reset()
      has = false
    }
  }
  if has {
    out.push(buf.to_string())
  }
  out
}

///|
/// 只认明确写得出来的级别标记；没有就 null，界面不上色。
/// 按非字母数字切词后比对：日志里常写成 code=PI_AI_ERROR 这种下划线连写，
/// 用 \b 词边界会被下划线挡住（下划线算词字符），真实错误行会整片漏标。
pub fn level_from_text(text : String) -> String? {
  let tokens = tokenize_alnum(@json.to_lower(text))
  for token in tokens {
    if token == "error" || token == "failed" || token == "failure" || token == "exception" {
      return Some("error")
    }
  }
  for token in tokens {
    if token == "warn" || token == "warning" {
      return Some("warn")
    }
  }
  None
}

///|
/// String? 取值给 String（None 给空串），用于拼接。
fn or_empty(v : String?) -> String {
  match v {
    Some(s) => s
    None => ""
  }
}

///|
/// 审计行的着色判据：先看 outcome，再看 verdict。
pub fn level_from_verdict(verdict : String?, outcome : String?) -> String? {
  let joined = or_empty(verdict) + " " + or_empty(outcome)
  if @json.index_of_ci(joined, "deny") is Some(_) {
    return Some("error")
  }
  if @json.index_of_ci(joined, "block") is Some(_) {
    return Some("error")
  }
  if @json.index_of_ci(joined, "reject") is Some(_) {
    return Some("error")
  }
  if @json.index_of_ci(joined, "flag") is Some(_) {
    return Some("warn")
  }
  if @json.index_of_ci(joined, "review") is Some(_) {
    return Some("warn")
  }
  if @json.index_of_ci(joined, "warn") is Some(_) {
    return Some("warn")
  }
  None
}

///|
/// 命令只带短片段：压平空白、限长 72 字符，超了加省略号。
pub fn short_command(value : String?) -> String {
  match value {
    None => ""
    Some(v) => {
      let flat = @json.trim_both(@json.collapse_ws(v))
      if flat == "" {
        ""
      } else if flat.length() > 72 {
        @json.slice(flat, 0, 72) + "…"
      } else {
        flat
      }
    }
  }
}

///|
/// host.log：ISO 时间 + [插件@版本] + 正文；拆不出的部分保留原始整行，不硬套。
pub fn parse_host_line(raw : String) -> ParsedLine {
  let raw_level = level_from_text(raw)
  let parts = @json.split_ws(raw)
  let fallback : ParsedLine = {
    time: None,
    level: raw_level,
    text: @json.trim_both(raw),
    verdict: None,
    outcome: None,
  }
  // 形如 ^(\S{10,32}?)\s+(.*)$：head 是首段（长度 10..32），rest 是其后全部内容
  if parts.length() == 0 || parts[0].length() < 10 || parts[0].length() > 32 {
    return fallback
  }
  let head = parts[0]
  let rest = @json.trim_both(@json.slice_from(raw, head.length()))
  match @json.iso_time_part(head) {
    None => fallback
    Some(t) => {
      time: Some(t),
      level: level_from_text(rest),
      text: rest,
      verdict: None,
      outcome: None,
    }
  }
}

///|
/// 取对象的字符串字段；不是字符串给 None。
fn field_string(json : Json, key : String) -> String? {
  match @json.json_field(json, key) {
    Some(v) => @json.json_string(v)
    None => None
  }
}

///|
/// audit.jsonl：每行 JSON 压成一行单行文本；命令只带短片段，不倒原始 JSON。
pub fn parse_audit_line(raw : String) -> ParsedLine {
  let obj = match @json.json_parse(raw) {
    Some(j) =>
      match j {
        Object(_) => Some(j)
        _ => None
      }
    None => None
  }
  let json = match obj {
    None =>
      return {
        time: None,
        level: None,
        text: @json.trim_both(raw),
        verdict: None,
        outcome: None,
      }
    Some(j) => j
  }
  let tool = match field_string(json, "tool") {
    Some(t) if t != "" => t
    _ => "未记录工具"
  }
  let verdict = field_string(json, "verdict")
  let outcome = field_string(json, "outcome")
  let parts : Array[String] = [tool, or_empty(verdict) + "/" + or_empty(outcome)]
  match field_string(json, "reviewMode") {
    Some(flag) if flag != "" => parts.push(flag)
    _ => ()
  }
  let cmd = short_command(field_string(json, "command"))
  if cmd != "" {
    parts.push(cmd)
  }
  {
    time: @json.iso_time_part(or_empty(field_string(json, "at"))),
    level: level_from_verdict(verdict, outcome),
    text: join_parts(parts),
    verdict,
    outcome,
  }
}

///|
/// 用 " · " 拼接多段。
fn join_parts(parts : Array[String]) -> String {
  let buf = StringBuilder()
  for i, part in parts {
    if i > 0 {
      buf.write_string(" · ")
    }
    buf.write_string(part)
  }
  buf.to_string()
}

///|
/// 展示用的一行：正文超 400 字符截断。
fn entry(raw : String, parsed : ParsedLine) -> @json.JsonVal {
  let _ = raw
  let text = if parsed.text.length() > max_text_chars {
    @json.slice(parsed.text, 0, max_text_chars) + "…"
  } else {
    parsed.text
  }
  @json.JObj([
    ("time", @json.str_or_null(parsed.time)),
    ("level", @json.str_or_null(parsed.level)),
    ("text", @json.JStr(text)),
    ("verdict", @json.str_or_null(parsed.verdict)),
    ("outcome", @json.str_or_null(parsed.outcome)),
  ])
}

///|
/// 一个候选日志文件。bytes 是文件字节数：0 表示这份日志没内容可看。
priv struct LogCandidate {
  file : String
  mtime_ms : Int64
  bytes : Int64
}

///|
/// 广度优先扫 logs/ 目录，收集看起来像日志的普通文件，带 mtime。
async fn collect_log_files(root : String) -> Array[LogCandidate] noraise {
  let found : Array[LogCandidate] = []
  let queue : Array[(String, Int)] = [(root, 0)]
  let mut cursor = 0
  let mut visited = 0
  while cursor < queue.length() {
    let current = queue[cursor]
    cursor = cursor + 1
    let names = @json.list_dir(current.0)
    if names.length() == 0 {
      continue
    }
    for name in names {
      visited = visited + 1
      if visited > max_scan_entries {
        return found
      }
      let full = @json.join_path(current.0, name)
      if @json.is_dir(full) {
        if current.1 + 1 <= instance_scan_depth {
          queue.push((full, current.1 + 1))
        }
        continue
      }
      let dot = name.rev_find(".")
      let ext = match dot {
        Some(i) => @json.to_lower(@json.slice_from(name, i))
        None => ""
      }
      let known = log_extensions.any(fn(e) { e == ext })
      if !known {
        continue
      }
      match @json.mtime_ms(full) {
        Some(ms) => {
          let bytes = match @json.file_size(full) {
            Some(n) => n
            None => 0L // 拿不到大小按「没内容」算，不会因此把它顶到默认来源上
          }
          found.push({ file: full, mtime_ms: ms, bytes })
        }
        None => () // 读不到状态就不收，不猜
      }
    }
  }
  found
}

///|
/// 这条实例自己的日志文件：运行登记里给它记的 logPath 优先（控制台起的实例都有这条），
/// 其次按控制台的命名约定 console-<profile>-<port>.log 拼一个。
/// 两个都拿不到给 None —— 那是外部起的实例，它名下没有自己的日志，
/// 挑选时落到 host 日志那一档（见 candidate_tier）。
async fn own_log_path(
  instance : @instances.InstanceSummary,
  logs_dir : String,
) -> String? noraise {
  match instance.pid {
    Some(pid) =>
      match @store.find_record(@store.load_registry().entries, Some(pid), None) {
        Some(record) => return Some(record.log_path)
        None => ()
      }
    None => ()
  }
  match instance.profile {
    Some(name) =>
      Some(
        @json.join_path(
          logs_dir,
          "console-" + name + "-" + instance.port.to_string() + ".log",
        ),
      )
    None => None
  }
}

///|
/// host 日志的文件名（固定来源 `host` 落在这个名字上：~/.dsh/logs/retry-control/host.log）。
let host_log_name : String = "host.log"

///|
/// 挑候选时的层级，见 README「实例日志怎么挑」一节的取舍理由：
///   0 这条实例自己的日志，且有内容
///   1 host 日志，且有内容（这条实例没有自己的日志时的落点）
///   2 别的文件，且有内容
///   3 这条实例自己的日志，但空
///   4 host 日志，但空
///   5 别的文件，且空
///
/// 为什么先分「谁的文件」再分「有没有内容」：同一个 logs 目录里，一次**失败的启动**
/// 也会留一份 console-*.log，而且通常比还在跑的实例那份新。只按 mtime 挑，日志页
/// 默认来源显示的就是这份没信息量的失败日志；把它和 host 日志放在同一档里比 mtime，
/// 同样是拿运气当判据。
fn candidate_tier(item : LogCandidate, own : String?) -> Int {
  let mine = match own {
    Some(path) => item.file == path
    None => false
  }
  let is_host = @json.basename(item.file) == host_log_name
  let has_content = item.bytes > 0L
  if mine {
    if has_content { 0 } else { 3 }
  } else if is_host {
    if has_content { 1 } else { 4 }
  } else if has_content {
    2
  } else {
    5
  }
}

///|
/// 从候选里挑这一条：层级 -> mtime 降序 -> 路径升序（同层级同 mtime 时结果稳定可复现）。
fn pick_instance_log(candidates : Array[LogCandidate], own : String?) -> LogCandidate {
  let ranked = candidates.copy()
  ranked.sort_by(fn(a, b) {
    let ta = candidate_tier(a, own)
    let tb = candidate_tier(b, own)
    if ta != tb {
      if ta < tb { -1 } else { 1 }
    } else if a.mtime_ms != b.mtime_ms {
      if a.mtime_ms > b.mtime_ms { -1 } else { 1 }
    } else {
      @json.compare_code_units(a.file, b.file)
    }
  })
  ranked[0]
}

///|
/// settings 字段，与 Node 版同形。
fn settings() -> @json.JsonVal {
  @json.JObj([
    ("strategy", @json.JStr("block-reverse-read")),
    ("initialWindowBytes", @json.jint(65536)),
    ("maxWindowBytes", @json.jint(4194304)),
  ])
}

///|
/// tail 参数的解析结果。note 非空时上层会把它写成 data.tailNote。
pub struct TailSpec {
  tail : Int
  note : String?
}

///|
/// 只认正整数 tail；缺省 200，超过上限不报错但如实说明被截断。
/// 与 Node 版 server/localApi.mjs 的 parseTail 逐条对齐：
///   - 没给 / 空串          -> 缺省 200
///   - 非数字 / 小于等于 0  -> bad-tail（400）
///   - 大于 1000            -> 收敛到 1000，并带 tailNote
pub fn parse_tail(
  raw : String?,
  default_tail_value : Int,
) -> TailSpec raise @localapi.ReadError {
  let text = match raw {
    None => ""
    Some(v) => v
  }
  if text == "" {
    return { tail: default_tail_value, note: None }
  }
  if !@json.is_all_digits(text) {
    raise @localapi.ReadError(code="bad-tail", message="tail 只接受正整数")
  }
  let value = @json.parse_dec(text)
  if value <= 0 {
    raise @localapi.ReadError(code="bad-tail", message="tail 只接受正整数")
  }
  if value > max_tail {
    return {
      tail: max_tail,
      note: Some("tail 超过上限 \{max_tail}，按 \{max_tail} 返回"),
    }
  }
  { tail: value, note: None }
}

///|
/// 按设置里的 logs.defaultTail 解析 tail：没给 tail 参数时就用它。
pub async fn parse_tail_with_settings(raw : String?) -> TailSpec raise @localapi.ReadError {
  let settings = @store.load_settings().values
  parse_tail(raw, settings.logs_default_tail)
}

///|
/// 读一个来源的尾部若干行。读不到就带 errorCode 回来，不抛异常。
pub async fn read_logs(
  source_id : String,
  spec : TailSpec,
) -> @json.JsonVal raise @localapi.ReadError {
  let tail = Some(spec.tail)
  let tail_note = spec.note
  let source = match resolve_source(source_id) {
    Some(s) => s
    None =>
      raise @localapi.ReadError(
        code="unknown-source",
        message="没有这个来源：" + source_id + "，只支持 host / audit / instance:<实例 id>",
      )
  }
  // tail 已经在 parse_tail 里收敛过（缺省 200、超上限按上限并带 tailNote）；
  // 与 Node 版一致：requestedTail 记的是收敛后的值，effectiveTail 与它相同。
  let requested = match tail {
    None => default_tail
    Some(t) => t
  }
  let wanted = requested

  if source.kind == "instance" {
    return read_instance_logs(source, requested, wanted)
  }

  let listed = match source.file {
    Some(f) => f
    None => ""
  }
  // 审计文件会滚动：主文件被滚走（或一时读不到）时退回最近一份归档，
  // 别让「滚动」变成「审计页突然空了」。path 如实体现实读的那份文件。
  let file = if source.id == "audit" {
    @store.audit_read_path(listed)
  } else {
    listed
  }
  let base : Array[(String, @json.JsonVal)] = [
    ("source", @json.JStr(source.id)),
    ("label", @json.str_or_null(source.label)),
    ("kind", @json.JStr("fixed")),
    ("instance", @json.JNull),
    ("path", @json.JStr(file)),
    ("requestedTail", @json.jint(requested)),
    ("effectiveTail", @json.jint(wanted)),
    ("maxTail", @json.jint(max_tail)),
    ("settings", settings()),
  ]
  let read = try {
    @json.read_tail_lines(file, wanted)
  } catch {
    @json.TailError(msg) => {
      let fields = base.copy()
      fields.push(("readOk", @json.JBool(false)))
      fields.push(("errorCode", @json.JStr("read-failed")))
      fields.push(("readError", @json.JStr(msg)))
      fields.push(("fileSize", @json.JNull))
      fields.push(("windowBytes", @json.jint(0)))
      fields.push(("lines", @json.JArr([])))
      fields.push(("truncated", @json.JBool(false)))
      fields.push(("truncatedNote", @json.JNull))
      return @json.JObj(fields)
    }
  }
  let parse = if source.id == "audit" { parse_audit_line } else { parse_host_line }
  let lines : Array[@json.JsonVal] = []
  for raw in read.raw_lines {
    lines.push(entry(raw, parse(raw)))
  }
  let fields = base.copy()
  match tail_note {
    Some(note) => fields.push(("tailNote", @json.JStr(note)))
    None => ()
  }
  fields.push(("readOk", @json.JBool(true)))
  fields.push(("errorCode", @json.JNull))
  fields.push(("readError", @json.JNull))
  fields.push(("fileSize", @json.JNum(read.size.to_double())))
  fields.push(("windowBytes", @json.jint(read.window_bytes)))
  fields.push(("lines", @json.JArr(lines)))
  fields.push(("truncated", @json.JBool(read.truncated)))
  fields.push(("truncatedNote", @json.str_or_null(read.note)))
  @json.JObj(fields)
}

///|
/// 实例来源：先找这条实例，再在它的 DSH_HOME/logs 里挑一份日志 —— 挑法见
/// own_log_path / candidate_tier（先认这条实例自己的那一份，其次 host 日志，
/// 再按有没有内容分层，同级才比 mtime），不是单纯取 mtime 最新的那个文件。
async fn read_instance_logs(
  source : Resolved,
  requested : Int,
  wanted : Int,
) -> @json.JsonVal noraise {
  let report = @instances.instances_report_with_settings()
  let detected = report.instances.length()
  let mut matched : @instances.InstanceSummary? = None
  for item in report.instances {
    if item.id == source.instance_id {
      matched = Some(item)
    }
  }
  // 命中与未命中两条分支各自算好 port / label，两边都用到，不留悬空绑定
  let (port, label) : (@json.JsonVal, @json.JsonVal) = match matched {
    Some(item) => (@json.JNum(item.port.to_double()), @json.JStr("dsh :\{item.port}"))
    None => (@json.JNull, @json.JNull)
  }
  let base : Array[(String, @json.JsonVal)] = [
    ("source", @json.JStr(source.id)),
    ("label", label),
    ("kind", @json.JStr("instance")),
    ("instance", @json.JObj([
      ("id", @json.JStr(source.instance_id)),
      ("port", port),
      ("dshHome", @json.str_or_null(match matched {
        Some(item) => item.dsh_home
        None => None
      })),
    ])),
    ("detectedInstances", @json.jint(detected)),
    ("path", @json.JNull),
    ("requestedTail", @json.jint(requested)),
    ("effectiveTail", @json.jint(wanted)),
    ("maxTail", @json.jint(max_tail)),
    ("settings", settings()),
  ]
  if matched is None {
    let fields = base.copy()
    fields.push(("readOk", @json.JBool(false)))
    fields.push(("errorCode", @json.JStr("unknown-instance")))
    fields.push((
      "readError",
      @json.JStr(
        "没有这个运行中的实例：\{source.instance_id}（当前检测到 \{detected} 个）",
      ),
    ))
    fields.push(("fileSize", @json.JNull))
    fields.push(("windowBytes", @json.jint(0)))
    fields.push(("lines", @json.JArr([])))
    fields.push(("truncated", @json.JBool(false)))
    fields.push(("truncatedNote", @json.JNull))
    return @json.JObj(fields)
  }
  let instance = match matched {
    Some(item) => item
    None => abort("unreachable: matched is Some here")
  }
  // 优先用检测结果里的 DSH_HOME；实例没暴露就回退到 dsh 的默认位置，并写明来源
  let (home, home_source) = match instance.dsh_home {
    Some(h) if h != "" => (h, "实例自身的 DSH_HOME")
    _ => @runtime.resolve_dsh_home()
  }
  let logs_dir = @json.join_path(home, instance_logs_dir)
  let candidates = collect_log_files(logs_dir)
  let own = own_log_path(instance, logs_dir)
  let fields = base.copy()
  // instance.dshHome 用解析后的值，homeSource 写清是哪来的
  for i = 0; i < fields.length(); i = i + 1 {
    if fields[i].0 == "instance" {
      fields[i] = (
        "instance",
        @json.JObj([
          ("id", @json.JStr(source.instance_id)),
          ("port", @json.JNum(instance.port.to_double())),
          ("dshHome", @json.JStr(home)),
        ]),
      )
    }
  }
  fields.push(("homeSource", @json.JStr(home_source)))
  if candidates.length() == 0 {
    fields.push(("readOk", @json.JBool(false)))
    fields.push(("errorCode", @json.JStr("no-log-file")))
    fields.push((
      "readError",
      @json.JStr("这个实例没有可读的日志来源：\{logs_dir} 下没有可读日志文件"),
    ))
    fields.push(("fileSize", @json.JNull))
    fields.push(("windowBytes", @json.jint(0)))
    fields.push(("lines", @json.JArr([])))
    fields.push(("truncated", @json.JBool(false)))
    fields.push(("truncatedNote", @json.JNull))
    return @json.JObj(fields)
  }
  let picked = pick_instance_log(candidates, own)
  let read = try {
    @json.read_tail_lines(picked.file, wanted)
  } catch {
    @json.TailError(msg) => {
      fields.push(("path", @json.JStr(picked.file)))
      fields.push(("readOk", @json.JBool(false)))
      fields.push(("errorCode", @json.JStr("instance-read-failed")))
      fields.push(("readError", @json.JStr(msg)))
      fields.push(("fileSize", @json.JNull))
      fields.push(("windowBytes", @json.jint(0)))
      fields.push(("lines", @json.JArr([])))
      fields.push(("truncated", @json.JBool(false)))
      fields.push(("truncatedNote", @json.JNull))
      return @json.JObj(fields)
    }
  }
  let lines : Array[@json.JsonVal] = []
  for raw in read.raw_lines {
    lines.push(entry(raw, parse_host_line(raw)))
  }
  fields.push(("path", @json.JStr(picked.file)))
  fields.push(("logsDir", @json.JStr(logs_dir)))
  fields.push(("logFileCount", @json.jint(candidates.length())))
  fields.push((
    "pickedBy",
    @json.JStr(
      "logs 目录内先认这条实例自己的日志、其次 host 日志，再按有没有内容分层；同级取 mtime 最新的一个",
    ),
  ))
  fields.push(("readOk", @json.JBool(true)))
  fields.push(("errorCode", @json.JNull))
  fields.push(("readError", @json.JNull))
  fields.push(("fileSize", @json.JNum(read.size.to_double())))
  fields.push(("windowBytes", @json.jint(read.window_bytes)))
  fields.push(("lines", @json.JArr(lines)))
  fields.push(("truncated", @json.JBool(read.truncated)))
  fields.push(("truncatedNote", @json.str_or_null(read.note)))
  @json.JObj(fields)
}

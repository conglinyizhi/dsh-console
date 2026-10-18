// GET /api/local/dsh-releases：能装哪一版 dsh，以及每个来源答没答上来。
//
// 规格：design/dsh-release-sources.md §1。三条口径都照它：
//   1. 三个源**并发**问，每个 6 秒硬超时（curl -m 6，外面再套一层 6 秒的取消）——
//      一个连不上的源不许把页面拖住；
//   2. 采用顺序是 github → npm → 国内镜像：第一个答上来的当准，其余照实列出来但不覆盖它；
//   3. 读不到不是错误：三个源全失败也回 200，每个源为什么没答上来写进 error，
//      **不许把「没问到」写成「没有新版」**。
//
// 为什么走 curl 子进程、不自己在 socket 上发请求：这一条要跟「在命令行里 curl 一下」
// 完全同口径 —— 代理、证书、重定向全交给 curl；环境里有 HTTPS_PROXY / https_proxy
// 就带上它，没有就直连。自己在 socket 上重写一遍 TLS 与代理，迟早与使用者手敲的结果不一致，
// 而这一条接口的全部价值就在于「它说的就是本机真实读到的」。
//
// 网络请求只有下面三个地址（§4），别的一个都不发。

///|
/// 一个源：id 进读数，url 是唯一允许请求的那条地址。
priv struct Source {
  id : String
  url : String
}

///|
/// 三个源。**这个顺序就是采用顺序**（§1.2），别在别处再排一次。
///
/// github 取 release 的 tag（dsh-v 前缀）；npm 与国内镜像是同一副 registry 形状
/// （versions 的键 + dist-tags），所以两者共用一个解析器。
let sources : Array[Source] = [
  {
    id: "github",
    url: "https://api.github.com/repos/deepseek-ai/deepseek-harness/releases?per_page=30",
  },
  { id: "npm", url: "https://registry.npmjs.org/@deepseek-ai/dsh" },
  { id: "mirror", url: "https://registry.npmmirror.com/@deepseek-ai/dsh" },
]

///|
/// 每个源的硬超时（毫秒）。§1.2 写的是 6 秒，curl 的 -m 与外面那层取消用的是同一个数。
let source_timeout_ms : Int = 6000

///|
/// 一个源问下来的结果。
///
/// versions 已经按版本号从新到旧排好；latest / next 只有 registry 形状的源才有
/// （GitHub 的 release 不带 dist-tags），没有就是空串。
priv struct Answer {
  id : String
  ok : Bool
  ms : Int
  error : String
  versions : Array[(String, Bool)]
  latest : String
  next : String
}

///|
/// 没答上来时的那一份：ok=false，versions 空，原因照实写。
fn failed_answer(id : String, error : String, ms : Int) -> Answer {
  { id, ok: false, ms, error, versions: [], latest: "", next: "" }
}

///|
/// 例外渲染成人能读的一行。
/// MoonBit 的 Error::to_string 对带载荷的错误只给类型名，载荷会丢 —— 那对排查没有用，
/// 所以走 Debug 表示（与 localapi/probe.mbt 同一套理由）。
fn describe_error(err : Error) -> String {
  "\{@debug.Debug::to_repr(err)}"
}

///|
/// 问源时带不带代理：环境里有 HTTPS_PROXY 或 https_proxy 就带上它，没有就直连。
///
/// **不写死端口**：代理是这台机器的运行环境，写死一个 127.0.0.1:<端口> 只在这一台机器上对，
/// 换一台就连不上，而「读不到就如实说读不到」最怕的正是这种假。
async fn resolve_proxy() -> String noraise {
  let raw = match @json.env_value("HTTPS_PROXY") {
    Some(v) => v
    None =>
      match @json.env_value("https_proxy") {
        Some(v) => v
        None => ""
      }
  }
  @json.trim_both(raw)
}

///|
/// 取文本的第一行（curl 的报错只有一行有用，别把整段塞进读数）。
fn first_line(text : String) -> String {
  for line in text.split("\n") {
    let trimmed = @json.trim_both(@json.owned(line))
    if trimmed != "" {
      return trimmed
    }
  }
  ""
}

///|
/// 一次 curl：stdout 是响应体，stderr 是 curl 自己那句话。
///
/// 起不来也不抛（没有 curl 的机器上照样要给出读数）：返回 -1，原因在 stderr。
/// 子进程只拿最小环境 —— PATH 用来找 curl 可执行文件，代理按 resolve_proxy 的结果显式传；
/// **不继承**：继承会让「没有 HTTPS_PROXY 就直连」这句话不成立（http_proxy / all_proxy
/// 这些会自己漏进来，而这一条读数说的是「带没带 HTTPS_PROXY」）。
async fn run_curl(url : String, proxy : String) -> (Int, String, String) {
  let env : Map[String, String] = Map([])
  env["PATH"] = match @json.env_value("PATH") {
    Some(p) => p
    None => "/usr/bin:/bin"
  }
  if proxy != "" {
    // 两种写法都摆上：curl 认大写，别的工具认小写
    env["HTTPS_PROXY"] = proxy
    env["https_proxy"] = proxy
  }
  let input = @process.redirect_from_file("/dev/null")
  let (code, stdout, stderr) = @process.collect_output(
    "curl",
    ["-sS", "-m", "6", "--fail", url],
    extra_env=env,
    inherit_env=false,
    stdin=input,
  )
  (code, stdout.text(), stderr.text())
}

///|
/// 一条 curl 失败的人话。分类只按 curl 的退出码，原因照抄它的第一行 stderr：
///   28      超时（-m 6 到点）
///   6/7     DNS 解不出 / 连不上
///   22      --fail：源回了非 2xx
///   35      TLS 握手没成（代理拒了目标、证书不对）
///   3/5     地址写坏了 / 连不上代理
///   52/56   对端把连接断了
/// 认不出的退出码原样带上号码 —— 编一句「连不上」比给号码更糟。
fn curl_failure_text(code : Int, stderr : String) -> String {
  let head = first_line(stderr)
  let detail = if head == "" { "" } else { "：" + @json.utf8_prefix(head, 200) }
  match code {
    28 => "6 秒内没有回话" + detail
    6 | 7 => "连不上" + detail
    22 => "源回了错误状态" + detail
    35 => "连不上（TLS 握手没成）" + detail
    3 => "地址写坏了" + detail
    5 => "连不上代理" + detail
    52 | 56 => "连接被对端断掉" + detail
    -1 => "curl 起不来" + detail
    _ => "curl 退出码 " + code.to_string() + detail
  }
}

///|
/// 版本号切成 (core 数字段, 预发布段)。"0.2.1-rc.2" → ([0, 2, 1], "rc.2")。
fn split_version(version : String) -> (Array[Int], String) {
  match @json.index_of(version, "-") {
    Some(at) =>
      (@json.slice(version, 0, at).split(".").map(fn(s) {
        @json.parse_dec(@json.owned(s))
      }).collect(), @json.slice_from(version, at + 1))
    None =>
      (version.split(".").map(fn(s) { @json.parse_dec(@json.owned(s)) }).collect(), "")
  }
}

///|
/// 预发布段按 semver 的规矩逐段比：两边都是数字就按数字比，否则按字符串比；
/// 前缀相同、段数多的那份更大（rc.2 > rc）。
fn compare_pre(a : String, b : String) -> Int {
  let xs : Array[String] = a.split(".").map(fn(s) { @json.owned(s) }).collect()
  let ys : Array[String] = b.split(".").map(fn(s) { @json.owned(s) }).collect()
  let n = if xs.length() < ys.length() {
    xs.length()
  } else {
    ys.length()
  }
  for i = 0; i < n; i = i + 1 {
    let x = xs[i]
    let y = ys[i]
    if x == y {
      continue
    }
    if @json.is_all_digits(x) && @json.is_all_digits(y) {
      let xi = @json.parse_dec(x)
      let yi = @json.parse_dec(y)
      if xi != yi {
        return if xi < yi { -1 } else { 1 }
      }
      continue
    }
    return if @json.compare_code_units(x, y) < 0 { -1 } else { 1 }
  }
  if xs.length() == ys.length() {
    0
  } else if xs.length() < ys.length() {
    -1
  } else {
    1
  }
}

///|
/// 两个版本号谁大（-1 / 0 / 1）。**专门给这一条接口排序用**：
/// 没有复用 runtime 的 compare_version —— 那一条是 pnpm 挑包时的口径（rc 段当 0、
/// 段数多的算大），"0.2.1-rc.2" 会排到 "0.2.1" 之上，不是版本号的语义。
/// 这里按 semver 走：core 逐段比（缺的段当 0），core 相同则正式版更大，
/// 两个都预发布时比预发布段。
fn compare_version(a : String, b : String) -> Int {
  let (ac, ap) = split_version(a)
  let (bc, bp) = split_version(b)
  let n = if ac.length() < bc.length() {
    bc.length()
  } else {
    ac.length()
  }
  for i = 0; i < n; i = i + 1 {
    let x = if i < ac.length() { ac[i] } else { 0 }
    let y = if i < bc.length() { bc[i] } else { 0 }
    if x != y {
      return if x < y { -1 } else { 1 }
    }
  }
  if ap == "" && bp == "" {
    return 0
  }
  // 同一 core：没有预发布段的是正式版，正式版更大
  if ap == "" {
    return 1
  }
  if bp == "" {
    return -1
  }
  compare_pre(ap, bp)
}

///|
/// 版本列表按版本号从新到旧排。n 最多几十条（GitHub 一次 30 条、registry 37 个键），
/// 每轮挑最大的那条就够，不引排序库也不自己写快排。
fn sorted_desc(items : Array[(String, Bool)]) -> Array[(String, Bool)] {
  let out : Array[(String, Bool)] = []
  let taken : Array[Bool] = []
  for i = 0; i < items.length(); i = i + 1 {
    taken.push(false)
  }
  for i = 0; i < items.length(); i = i + 1 {
    let mut best = -1
    for j, item in items {
      if taken[j] {
        continue
      }
      if best < 0 || compare_version(item.0, items[best].0) > 0 {
        best = j
      }
    }
    if best >= 0 {
      taken[best] = true
      out.push(items[best])
    }
  }
  out
}

///|
/// 一串版本号从新到旧排（installed 那一格用）。
fn sorted_versions_desc(items : Array[String]) -> Array[String] {
  let pairs : Array[(String, Bool)] = []
  for v in items {
    pairs.push((v, false))
  }
  let out : Array[String] = []
  for pair in sorted_desc(pairs) {
    out.push(pair.0)
  }
  out
}

///|
/// 读 GitHub releases：只认 tag_name 以 dsh-v 开头的，去掉前缀当版本号。
///
/// prerelease 标记**用 GitHub 自己给的那个**，不从版本号里的 "-" 推：
/// 两者今天一致，但那是仓库的约定，不是标签的语义。
fn parse_github(body : String) -> Result[Array[(String, Bool)], String] {
  let root = match @json.json_parse(body) {
    Some(j) => j
    None => return Err("回来的不是能认的 JSON")
  }
  let items = match root {
    Array(list) => list
    _ => return Err("回来的不是 release 列表（顶层不是数组）")
  }
  let out : Array[(String, Bool)] = []
  for item in items {
    let tag = match @json.json_field(item, "tag_name") {
      Some(v) =>
        match @json.json_string(v) {
          Some(s) => s
          None => ""
        }
      None => ""
    }
    if !tag.has_prefix("dsh-v") {
      continue
    }
    let version = @json.slice_from(tag, 5)
    if version == "" {
      continue
    }
    let pre = match @json.json_field(item, "prerelease") {
      Some(True) => true
      _ => false
    }
    out.push((version, pre))
  }
  Ok(out)
}

///|
/// 读 registry 形态（npm 与国内镜像同一副形状）：versions 的键就是全部版本号，
/// dist-tags 里的 latest / next 单独记下来（其余 tag 不进返回形状，这一版用不到）。
///
/// 预发布按 semver 口径判：版本号里带 "-" 就是。registry 没有 prerelease 这样的独立字段，
/// 而版本号的形状本身就是它的定义。
fn parse_registry(
  body : String
) -> Result[(Array[(String, Bool)], String, String), String] {
  let root = match @json.json_parse(body) {
    Some(j) => j
    None => return Err("回来的不是能认的 JSON")
  }
  let versions_map = match @json.json_field(root, "versions") {
    Some(Object(map)) => map
    _ => return Err("回来的 JSON 里没有 versions（不像 registry 的包元数据）")
  }
  let out : Array[(String, Bool)] = []
  for key, _ in versions_map {
    let version = @json.owned(key)
    if version == "" {
      continue
    }
    let pre = match @json.index_of(version, "-") {
      Some(_) => true
      None => false
    }
    out.push((version, pre))
  }
  let mut latest = ""
  let mut next = ""
  match @json.json_field(root, "dist-tags") {
    Some(Object(tags)) =>
      for key, value in tags {
        let name = @json.owned(key)
        let text = match @json.json_string(value) {
          Some(s) => s
          None => ""
        }
        if name == "latest" {
          latest = text
        } else if name == "next" {
          next = text
        }
      }
    _ => ()
  }
  Ok((out, latest, next))
}

///|
/// 这一次问走的是哪条路，进失败信息 —— 排查「GitHub 连不上」时第一件事就是它。
fn proxy_note(proxy : String) -> String {
  if proxy == "" {
    "没有配 HTTPS_PROXY，这次是直连"
  } else {
    "走的是环境里的 HTTPS_PROXY（" + proxy + "）"
  }
}

///|
/// 问一个源。任何失败都收敛成「没答上来」+ 原因，绝不向外抛：
/// 一条源坏了不该让整份读数失败（三个源全坏也照样 200，见 §1.3）。
async fn ask_source(source : Source, proxy : String) -> Answer {
  let started_at = @async.now()
  let attempt : async () -> Answer = async fn () {
    let (code, stdout, stderr) = run_curl(source.url, proxy)
    if code != 0 {
      return failed_answer(
        source.id,
        curl_failure_text(code, stderr) + "；" + proxy_note(proxy),
        0,
      )
    }
    match source.id {
      "github" =>
        match parse_github(stdout) {
          Ok(versions) =>
            {
              id: source.id,
              ok: true,
              ms: 0,
              error: "",
              versions: sorted_desc(versions),
              latest: "",
              next: "",
            }
          Err(reason) =>
            failed_answer(
              source.id,
              "回来的格式不对：" + reason + "；" + proxy_note(proxy),
              0,
            )
        }
      _ =>
        match parse_registry(stdout) {
          Ok((versions, latest, next)) =>
            {
              id: source.id,
              ok: true,
              ms: 0,
              error: "",
              versions: sorted_desc(versions),
              latest,
              next,
            }
          Err(reason) =>
            failed_answer(
              source.id,
              "回来的格式不对：" + reason + "；" + proxy_note(proxy),
              0,
            )
        }
    }
  }
  // ms 由这里统一量：包含 curl 起进程、跑网络、解析的全部时间，
  // 也就是「这个源到底花了多久」这一件事。
  let result = try {
    @async.with_timeout_opt(source_timeout_ms, attempt)
  } catch {
    _ => None
  }
  let spent = (@async.now() - started_at).to_int()
  match result {
    Some(answer) => { ..answer, ms: spent }
    None =>
      failed_answer(
        source.id,
        "6 秒内没有回话；" + proxy_note(proxy),
        spent,
      )
  }
}

///|
/// 这台机器上装着哪几版 dsh：与 /api/local/runtime 的 dshCandidates 同一条链
/// （runtime 的 installed_dsh_candidates），版本号相同即算已装。
/// 同一份 dsh 在 pnpm 布局下有两条写法、也可能挂在几个全局根下，按版本号去重。
async fn installed_versions() -> Array[String] noraise {
  let out : Array[String] = []
  for pkg in @runtime.installed_dsh_candidates() {
    if !out.contains(pkg.version) {
      out.push(pkg.version)
    }
  }
  sorted_versions_desc(out)
}

///|
/// 组装 /api/local/dsh-releases 的 data 对象。
///
/// 三个源并发问（@async.all 保序：回来得早晚不影响谁排第几，采用顺序才稳定）。
pub async fn read_releases() -> @json.JsonVal raise @localapi.ReadError {
  let proxy = resolve_proxy()
  let tasks : Array[async () -> Answer] = []
  for source in sources {
    let one = source
    tasks.push(async fn () { ask_source(one, proxy) })
  }
  let answers = try {
    @async.all(tasks[:], max_concurrent=sources.length())
  } catch {
    err => {
      // 单个 ask_source 是 noraise：批量本身只会在被取消（请求方断开）时走到这里。
      // 那就如实标成「没问到」，三个源各一条，不编造任何结论。
      let reason = "整批询问被中断：" + describe_error(err)
      let fallback : Array[Answer] = []
      for source in sources {
        fallback.push(failed_answer(source.id, reason, 0))
      }
      fallback
    }
  }
  let installed = installed_versions()
  // 采用顺序：第一个 ok 的当准，其余照实列出来但不覆盖它
  let mut chosen = ""
  let mut chosen_versions : Array[(String, Bool)] = []
  for answer in answers {
    if answer.ok && chosen == "" {
      chosen = answer.id
      chosen_versions = answer.versions
    }
  }
  // latest / next 只有 registry 形状的源给（GitHub 的 release 没有 dist-tags）：
  // 按同样的优先级取第一个给了的那条。这一句说的是「registry 那边标记的 latest 是哪一版」，
  // 与「chosen 是谁」是两件事，别混。
  let mut latest = ""
  let mut next = ""
  for answer in answers {
    if !answer.ok {
      continue
    }
    if latest == "" {
      latest = answer.latest
    }
    if next == "" {
      next = answer.next
    }
  }
  let listed : Array[@json.JsonVal] = []
  for pair in chosen_versions {
    listed.push(
      @json.JObj([
        ("version", @json.JStr(pair.0)),
        ("prerelease", @json.JBool(pair.1)),
        ("latest", @json.JBool(pair.0 == latest)),
        ("next", @json.JBool(pair.0 == next)),
        ("installed", @json.JBool(installed.contains(pair.0))),
      ]),
    )
  }
  let source_rows : Array[@json.JsonVal] = []
  for answer in answers {
    source_rows.push(
      @json.JObj([
        ("id", @json.JStr(answer.id)),
        ("ok", @json.JBool(answer.ok)),
        ("ms", @json.jint(answer.ms)),
        ("error", @json.JStr(answer.error)),
        // count = 这个源这一趟给出几条版本。github 只算 dsh-v 开头的那些（别的 tag 不收），
        // 所以它可能比 per_page 小；registry 就是 versions 的键数。
        ("count", @json.jint(answer.versions.length())),
      ]),
    )
  }
  // 三个源一个都没答上来：把每个源自己那句话拼成一行，交给缓存层的 failed 档当原因。
  // **这不是「没有新版」**，只是「这一趟谁都没答上来」—— 每一条都带着源自己的原话。
  let mut fetch_error = ""
  if chosen == "" {
    let parts : Array[String] = []
    for answer in answers {
      let why = if answer.error == "" { "没答上来，原因没给" } else { answer.error }
      parts.push(answer.id + "：" + why)
    }
    fetch_error = if parts.length() == 0 { "三个来源都没答上来" } else { parts.join("；") }
  }
  @json.JObj([
    ("readAt", @json.JStr(@json.iso_from_epoch_ms(@async.now()))),
    ("chosen", @json.JStr(chosen)),
    ("versions", @json.JArr(listed)),
    ("latest", @json.JStr(latest)),
    ("next", @json.JStr(next)),
    ("installed", @json.jstr_array(installed)),
    ("sources", @json.JArr(source_rows)),
    ("error", @json.JStr(fetch_error)),
  ])
}

// ── 进程内缓存（§10.1） ─────────────────────────────────────
//
// 这一条接口要「秒回」：三个源各自最多 6 秒，同步问下来页面就得等它。
// 所以拉取与读取分开：
//   * 控制台起来时在后台拉一次（start_prewarm），结果存进下面这份缓存；
//   * GET 只读缓存，一个 await 都不做 —— 缓存空也一样，空就回 loading 并确保后台在拉；
//   * 缓存超过 10 分钟算旧（stale），GET 不等它，只在后台再发起一次。
//
// **「没读到」与「没有新版」还是两件事**：缓存里没有数据只是说「这一趟还没回来」。
// 三个源一个都没答上来时 state=failed，原因那是各源自己的原话拼成的一行 ——
// 这句读数说的是「谁都没答上来」，**不是**「没有新版」。

///|
/// 缓存多旧算旧。10 分钟：比三个源的 6 秒超时大得多，又短到「切回来看到的是近况」。
let cache_ttl_ms : Int64 = 600000L

///|
/// 一份缓存。payload 是 read_releases 组装好的那整份 data（JNull = 还没有过成功的一趟）。
priv struct Cache {
  mut payload : @json.JsonVal
  mut fetched_at_ms : Int64
  /// 最近一趟没拿到答案的原因（空串 = 这一趟有答案）。来源是 read_releases 的 error 那格：
  /// 三个源一个都没答上来时，那里是各源自己的原话拼成的一行。
  /// **失败不清空 payload**：上一次读到的版本列表照样能给人选，只是要如实说这趟没拉到。
  mut error : String
  /// 有没有一趟拉取在路上。GET 靠它决定要不要再发起：在路上就不再叠加第二趟。
  mut in_flight : Bool
}

///|
let cache : Ref[Cache] = {
  val: {
    payload: @json.JNull,
    fetched_at_ms: 0L,
    error: "",
    in_flight: false,
  },
}

///|
/// 挂后台拉取用的任务组（main 起服务前登记一次，与 actions 的 console_group 同一套做法）。
/// 没有任务组（被当库调用）时 GET 照旧只读缓存，不会假装在拉。
let bg_group : Ref[@async.TaskGroup[Unit]?] = { val: None }

///|
/// 缓存空的时候回给前端的那一份空壳：形状与真读数逐字段一致，一个字段都不少。
/// 这样前端不必为「还没有数据」另写一套解析。
fn empty_payload() -> @json.JsonVal {
  @json.JObj([
    ("readAt", @json.JStr("")),
    ("chosen", @json.JStr("")),
    ("versions", @json.JArr([])),
    ("latest", @json.JStr("")),
    ("next", @json.JStr("")),
    ("installed", @json.JArr([])),
    ("sources", @json.JArr([])),
    ("error", @json.JStr("")),
  ])
}

///|
/// 从一份读数里取那格 error（拉取层加的「三个源都没答上来」的原因）。
fn payload_error(payload : @json.JsonVal) -> String {
  match payload {
    @json.JObj(fields) =>
      for field in fields {
        if field.0 == "error" {
          match field.1 {
            @json.JStr(text) => return text
            _ => ()
          }
        }
      }
    _ => ()
  }
  ""
}

///|
/// 从一份读数里取那格 chosen（采用的那个源；空串 = 一个源都没答上来）。
fn payload_chosen(payload : @json.JsonVal) -> String {
  match payload {
    @json.JObj(fields) =>
      for field in fields {
        if field.0 == "chosen" {
          match field.1 {
            @json.JStr(text) => return text
            _ => ()
          }
        }
      }
    _ => ()
  }
  ""
}

///|
/// 后台那一趟：拉一次，结果写进缓存。**绝不向外抛** —— 抛出去会连带取消整个任务组，
/// 一条版本列表读不到不该把控制台带走。
async fn run_fetch() -> Unit noraise {
  // read_releases 把三个源的失败都落成读数里的 error（正常路径不会抛）；
  // 这里仍旧包一层：真抛出来（整批被取消那一档）也只记进 error，绝不带崩任务组。
  let outcome : Result[@json.JsonVal, String] = try {
    Ok(read_releases())
  } catch {
    err => Err(describe_error(err))
  }
  let c = cache.val
  match outcome {
    Ok(payload) => {
      c.payload = payload
      c.fetched_at_ms = @async.now()
      // 一个源都没答上来时，read_releases 会把各源的原话拼在 error 里 —— 存下来给 failed 档用
      c.error = payload_error(payload)
    }
    Err(reason) => c.error = reason
  }
  c.in_flight = false
}

///|
/// 确保后台有一趟在拉：已经在路上就不叠加第二趟。
fn ensure_fetch() -> Unit {
  let c = cache.val
  if c.in_flight {
    return
  }
  match bg_group.val {
    None => ()
    Some(group) => {
      // 先落 in_flight 再 spawn：spawn 出来的那一趟第一件事就是 await，
      // 但顺序写反的话「同一拍里两个 GET」会各起一趟
      c.in_flight = true
      group.spawn_bg(no_wait=true, () => run_fetch())
    }
  }
}

///|
/// 起服务前登记任务组，并立刻在后台拉一次（§10.1「控制台一起来就拉」）。
/// **不 await**：启动路径上一个 await 都不加，serve 不被这次拉取拖住。
pub fn start_prewarm(group : @async.TaskGroup[Unit]) -> Unit {
  bg_group.val = Some(group)
  ensure_fetch()
}

///|
/// GET /api/local/dsh-releases 的真正入口：只读缓存，秒回。
///
/// 形状在 read_releases 那七格之外加四格：
///   state      loading（有一趟在路上）/ ready（有答案、现在没在拉）/ failed（拉到了却没有答案，没在拉）
///   fetchedAt  最近一次拉到的时刻（ISO；还一次都没拉到就是空串）
///   stale      这份缓存是否超过 10 分钟（还一次都没拉到也算旧）
///   error      这一趟没拿到答案的原因（空串 = 有答案）
///
/// 注意 state 说的是**这一趟拉取**的状态，不是「有没有版本」：state=loading 而
/// versions 非空是正常的一档 —— 上一次的数据先给人看着，这一趟在后面刷新。
pub fn cached_releases() -> @json.JsonVal {
  let c0 = cache.val
  let has_data = match c0.payload {
    @json.JNull => false
    _ => true
  }
  let now = @async.now()
  let old = c0.fetched_at_ms == 0L || now - c0.fetched_at_ms > cache_ttl_ms
  // 空或旧才再拉一趟（§10.1 就这两条）。「拉到了却没有答案」**不**在这里重试：
  // 那是一份已经落地的读数（state=failed，原因在 error 里），每次 GET 都重启一轮
  // 6 秒询问的话，前端会以为永远拉不完 —— 而这台机器确实连着哪个源都不通。
  let nothing = has_data && payload_chosen(c0.payload) == ""
  if !has_data || old {
    ensure_fetch()
  }
  let c = cache.val
  let state = if c.in_flight {
    // 有一趟在路上（可能是第一次，也可能是刷新）：列表有旧数据就照旧给出去
    "loading"
  } else if !has_data {
    if c.error == "" { "loading" } else { "failed" }
  } else if nothing {
    // 拉到了，但一个源都没答上来。这不是「没有新版」，原因在 error 与各源的 error 里
    "failed"
  } else {
    "ready"
  }
  let fetched_at = if c.fetched_at_ms == 0L {
    ""
  } else {
    @json.iso_from_epoch_ms(c.fetched_at_ms)
  }
  let base = if has_data { c.payload } else { empty_payload() }
  let extras : Array[(String, @json.JsonVal)] = [
    ("state", @json.JStr(state)),
    ("fetchedAt", @json.JStr(fetched_at)),
    ("stale", @json.JBool(old)),
    ("error", @json.JStr(c.error)),
  ]
  match base {
    @json.JObj(fields) => {
      let merged : Array[(String, @json.JsonVal)] = []
      for field in fields {
        // 读数里已经有 error 那一格（拉取层写的）：不重复摆第二遍，
        // 缓存层这份一定是更新的那一份（失败不清空旧列表，原因跟着这一趟走）
        let mut shadowed = false
        for extra in extras {
          if extra.0 == field.0 {
            shadowed = true
          }
        }
        if !shadowed {
          merged.push(field)
        }
      }
      for extra in extras {
        merged.push(extra)
      }
      @json.JObj(merged)
    }
    _ => @json.JObj(extras)
  }
}


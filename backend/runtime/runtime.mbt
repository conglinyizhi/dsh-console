// GET /api/local/runtime 的数据体。
//
// 字段与 Node 版 server/readRuntime.mjs 的返回值对齐：
//   consoleVersion, consolePackageName, dshVersion, dshPackageName, dshPackageDir,
//   dshSourceLabel, backendRuntime, backendVersion, backendPackageName,
//   consoleVersionSource, dshHome, dshHomeSource, dshProfile, platform
//
// 第二批的两处修正：
//   1. 删掉 nodeVersion。后端跑在 MoonBit native 运行时上，没有 Node；
//      硬编码一个 "v26.11.1" 就是编数据。改用 backendRuntime / backendVersion 如实报告后端自己。
//   2. consoleVersion 不再是编译期常量：运行时读前端 package.json 的 version，
//      读不到给 null，并在 consoleVersionSource 里写明原因。
//
// 第三批（这一批）：**找 dsh 包目录改成一条三级兜底链**，不再只按固定路径扫。
// pnpm v11 的全局布局是 <根>/<槽>/<哈希>/node_modules/@deepseek-ai/dsh，比老布局多一层哈希，
// 「<根>/<槽>/node_modules/@deepseek-ai/dsh」这条固定路径会整条落空：runtime 读 500、
// 起实例报「找不到 dsh 入口」。链条与判据写在 find_installed_dsh 上面。
//
// 文件 IO 只有 @json 里那几个只读入口：read_file / readdir / kind / exists / open+read_at。
// 另外这一批用 @processes 的在跑实例读数挑「与在跑实例一致」的那一份（只读 /proc）。

///|
/// 前端包名（Node 版从这里读 package.json；这里只作为常量回显）。
pub let console_package_name : String = "dsh-console"

///|
/// dsh 来源标签前缀，与 Node 版同常量；后面补上「用了哪条策略」。
pub let dsh_source_label : String = "本机已安装"

///|
/// 找到包目录的策略标签（进读数的来源串）。三条各自独立，
/// 一路找下去，第一条命中的算数。
let via_shim : String = "顺 PATH 上的 dsh 命令解开包目录"

///|
/// 兜底那条：在全局根下按深度找。
let via_scan : String = "在 pnpm 全局根下按深度 3 层找到包目录"

///|
/// 多份候选时的取舍标签。
let pick_same_dir : String = "与在跑实例同一份"

///|
/// 多份候选、版本与在跑实例一致时取版本最高的那份。
let pick_same_version : String = "与在跑实例版本一致，其中取版本最高"

///|
/// 多份候选、没有可参照的在跑实例时取版本最高的那份。
let pick_highest : String = "没有可参照的在跑实例，取版本最高"

///|
/// 兜底扫描的深度上限。已知的三种布局都在这三层之内：
/// <根>/node_modules/@deepseek-ai/dsh、<根>/<槽>/node_modules/…、<根>/<槽>/<哈希>/node_modules/…
let scan_max_depth : Int = 3

///|
/// pnpm 全局安装目录候选，逐个扫，不调外部命令（与 Node 版 globalRoots 一致，
/// 外加 PNPM_HOME / XDG_DATA_HOME —— 全局根被挪走时固定三个会一起落空）。
async fn global_roots() -> Array[String] noraise {
  let home = @json.home_dir()
  let candidates : Array[String] = [
    @json.join_all([home, ".local", "share", "pnpm", "global"]),
    @json.join_path(home, ".pnpm-global"),
    @json.join_all([home, "Library", "pnpm", "global"]),
  ]
  match @json.env_value("PNPM_HOME") {
    Some(v) =>
      if v.has_prefix("/") {
        candidates.push(@json.join_all([v, "global"]))
      }
    None => ()
  }
  match @json.env_value("XDG_DATA_HOME") {
    Some(v) =>
      if v.has_prefix("/") {
        candidates.push(@json.join_all([v, "pnpm", "global"]))
      }
    None => ()
  }
  let roots : Array[String] = []
  for c in candidates {
    let text = @json.trim_both(c)
    if text != "" && !roots.contains(text) {
      roots.push(text)
    }
  }
  roots
}

///|
struct DshPackage {
  name : String
  version : String
  dir : String
  /// 这份是怎么找到的（进读数的来源串）
  source : String
}

///|
/// 读一个 package.json 的 name/version；读不动返回 None。
async fn read_package(file : String) -> (String, String)? noraise {
  let text = match @json.read_text_file(file) {
    Ok(t) => t
    Err(_) => return None
  }
  let json = match @json.json_parse(text) {
    Some(j) => j
    None => return None
  }
  let version = match @json.json_field(json, "version") {
    Some(v) =>
      match @json.json_string(v) {
        Some(s) => s
        None => return None
      }
    None => return None
  }
  let name = match @json.json_field(json, "name") {
    Some(v) =>
      match @json.json_string(v) {
        Some(s) => s
        None => "@deepseek-ai/dsh"
      }
    None => "@deepseek-ai/dsh"
  }
  Some((name, version))
}

///|
/// 版本号按数字段比较（对应 Node 的 localeCompare(..., { numeric: true })）。
fn compare_version(a : String, b : String) -> Int {
  let xs : Array[String] = a.split(".").map(fn(s) { s.to_owned() }).collect()
  let ys : Array[String] = b.split(".").map(fn(s) { s.to_owned() }).collect()
  let n = if xs.length() < ys.length() { xs.length() } else { ys.length() }
  for i = 0; i < n; i = i + 1 {
    let x = parse_num_segment(xs[i])
    let y = parse_num_segment(ys[i])
    if x != y {
      return if x < y { -1 } else { 1 }
    }
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
/// 取版本段里的前导数字；没有数字按 0（"0.2.0-rc.2" 的 rc 段即按 0 处理）。
fn parse_num_segment(seg : String) -> Int {
  let mut value = 0
  let mut digits = 0
  for ch in seg {
    let d = ch.to_int() - '0'.to_int()
    if d < 0 || d > 9 {
      break
    }
    value = value * 10 + d
    digits = digits + 1
  }
  let _ = digits
  value
}

///|
/// 包目录在路径里的那一段。找它比找整条路径稳：
/// 前面是 <根>/<槽> 还是 <根>/<槽>/<哈希> 都不影响结论。
let package_marker : String = "/node_modules/@deepseek-ai/dsh"

///|
/// 从一个路径片段里切出 @deepseek-ai/dsh 的包目录：
/// `/x/node_modules/@deepseek-ai/dsh/lib/bin.js` → `/x/node_modules/@deepseek-ai/dsh`。
/// 认不出（不是绝对路径 / 没有那一段）给 None。
fn package_dir_of_path(token : String) -> String? {
  match @json.index_of(token, package_marker) {
    Some(at) => {
      let start = token_start_before(token, at)
      let prefix = @json.slice(token, start, at)
      if prefix.has_prefix("/") {
        Some(prefix + package_marker)
      } else {
        None
      }
    }
    None => None
  }
}

///|
/// 从 at 往前退到这一段路径的开头（空白 / 引号 / 等号 / 左括号 / 反斜杠算分隔）。
/// 用处：cmdline 被整条塞进一个 token 时（"node …/lib/bin.js --profile web"），
/// 路径前面还挂着别的东西，不能从头数。
fn token_start_before(text : String, at : Int) -> Int {
  let mut start = at
  while start > 0 {
    let ch = text.unsafe_get(start - 1).unsafe_to_char()
    let stop = ch == ' ' ||
      ch == '\t' ||
      ch == '\n' ||
      ch == '\r' ||
      ch == '"' ||
      ch == '\'' ||
      ch == '=' ||
      ch == '(' ||
      ch == '\\'
    if stop {
      break
    }
    start = start - 1
  }
  start
}

///|
/// needle 在 haystack 里的全部出现位置（升序）。找不到给空数组。
fn find_all(haystack : String, needle : String) -> Array[Int] {
  let out : Array[Int] = []
  if needle == "" {
    return out
  }
  let mut from = 0
  while from + needle.length() <= haystack.length() {
    match @json.index_of(@json.slice_from(haystack, from), needle) {
      Some(i) => {
        out.push(from + i)
        from = from + i + needle.length()
      }
      None => break
    }
  }
  out
}

///|
/// 把一段文本里的 needle 全换成 repl。
fn replace_all(text : String, needle : String, repl : String) -> String {
  if needle == "" {
    return text
  }
  let buf = StringBuilder()
  let mut rest = text
  while true {
    match @json.index_of(rest, needle) {
      Some(i) => {
        buf.write_string(@json.slice(rest, 0, i))
        buf.write_string(repl)
        rest = @json.slice_from(rest, i + needle.length())
      }
      None => {
        buf.write_string(rest)
        break
      }
    }
  }
  buf.to_string()
}

///|
/// 把 shim 里那段路径表达式解成绝对路径：
/// pnpm 写的 shim 用 $basedir / $basedir_abs 指自己的目录（bin/dsh 在 <PNPM_HOME>/bin 下，
/// 目标写成 $basedir_abs/../global/v11/<哈希>/…），这里按脚本自己的目录还原。
/// 还原不出绝对路径给 None。$basedir_win 那种 Windows 分支在 Linux 上还原不出来，
/// 换成空串让它自然落空（读不到 package.json 就换下一条候选），不编一个假路径。
fn expand_shim_path(expr : String, shim_dir : String) -> String? {
  if expr == "" {
    return None
  }
  let mut text = expr
  match @json.index_of(text, "$") {
    Some(_) => {
      text = replace_all(text, "${basedir_win}", "")
      text = replace_all(text, "$basedir_win", "")
      text = replace_all(text, "${basedir_abs}", shim_dir)
      text = replace_all(text, "${basedir}", shim_dir)
      // 顺序要紧：$basedir 是 $basedir_abs 的前缀，长的先换
      text = replace_all(text, "$basedir_abs", shim_dir)
      text = replace_all(text, "$basedir", shim_dir)
    }
    None => ()
  }
  if text.has_prefix("/") {
    Some(normalize_path(text))
  } else {
    None
  }
}

///|
/// 把绝对路径里的 . 与 .. 就地收掉（纯字符串，不碰文件系统）。
/// 不做 realpath：realpath 会把 <槽>/<哈希>/node_modules/@deepseek-ai/dsh 这条软链
/// 解成 .pnpm 仓库里的真目录 —— 那条路径跟实例 argv 里记的不是同一个字符串，
/// 「与在跑实例同一份」就比不出来了。这里要的是 pnpm 摆出来的那个路径。
fn normalize_path(path : String) -> String {
  let parts : Array[String] = []
  for seg in path.split("/") {
    let part = @json.owned(seg)
    if part == "" || part == "." {
      continue
    }
    if part == ".." {
      if parts.length() > 0 {
        let _ = parts.pop()
      }
      continue
    }
    parts.push(part)
  }
  "/" + parts.join("/")
}

///|
/// 策略 1：顺 PATH 上的 dsh 命令找它的真包目录。
///
/// dsh 是个 shim（POSIX shell 脚本），里面写着真入口
/// <包目录>/lib/bin.js；软链先落成实路径，$basedir 才指的是这段脚本自己所在的目录。
/// 认下来之前先读一次 <包目录>/package.json：读得到才算找到了包。
async fn shim_candidate() -> DshPackage? noraise {
  let shim = match @json.find_in_path("dsh") {
    Some(p) => p
    None => return None
  }
  let real = match @json.real_path(shim) {
    Some(p) => p
    None => shim
  }
  let text = match @json.read_text_file(real) {
    Ok(t) => t
    Err(_) => return None
  }
  let shim_dir = @json.dirname(real)
  // shim 里有好几条 exec 分支（exe / node / node.exe / 兜底），每条都带一遍真入口路径，
  // 逐个试：解不出绝对路径的、指不到真包目录的，读一次 package.json 就落空换下一条。
  for at in find_all(text, package_marker) {
    let start = token_start_before(text, at)
    let expr = @json.slice(text, start, at) + package_marker
    match expand_shim_path(expr, shim_dir) {
      Some(dir) =>
        match read_package(@json.join_path(dir, "package.json")) {
          Some((name, version)) => return Some({ name, version, dir, source: via_shim })
          None => ()
        }
      None => ()
    }
  }
  None
}

///|
/// 策略 2：在已知全局根下按深度 ≤ scan_max_depth 找
/// <目录>/node_modules/@deepseek-ai/dsh/package.json。
///
/// 为什么不能只按固定路径扫：pnpm v11 在「槽」与 node_modules 之间多一层哈希
/// （<根>/<槽>/<哈希>/node_modules/…），而 <根>/<槽>/node_modules/… 那条会静默扫不到 ——
/// 布局是对方定的，不是我们定的，所以按深度找而不是按层数猜。
async fn scan_root_for_dsh(root : String) -> Array[DshPackage] noraise {
  let found : Array[DshPackage] = []
  scan_into(root, 0, found)
  found
}

///|
/// 递归本体：每个目录先看自己下面的 node_modules/@deepseek-ai/dsh，再往下走一层。
/// node_modules 本身不再进去（里面的 .pnpm 是真目录树，进去只会拖慢，
/// 而入口那一份是软链，已经在上一层读到了）。
async fn scan_into(dir : String, depth : Int, found : Array[DshPackage]) -> Unit noraise {
  let pkg_dir = @json.join_all([dir, "node_modules", "@deepseek-ai", "dsh"])
  match read_package(@json.join_path(pkg_dir, "package.json")) {
    Some((name, version)) => found.push({ name, version, dir: pkg_dir, source: via_scan })
    None => ()
  }
  if depth >= scan_max_depth {
    return
  }
  for entry in @json.list_dir(dir) {
    if entry == "node_modules" || entry == ".pnpm" {
      continue
    }
    let child = @json.join_path(dir, entry)
    if @json.is_dir(child) {
      scan_into(child, depth + 1, found)
    }
  }
}

///|
/// 在跑实例自己跑的是哪一份 dsh：读它的 argv（exe_path 就是那个入口片段）。
/// 只认读得出来的，认不出不猜 —— 这一条只用来在多份候选里分个先后，不参与「有没有装」。
async fn live_instance_packages() -> Array[DshPackage] noraise {
  let found : Array[DshPackage] = []
  let report = @processes.read_processes()
  for item in report.instances {
    match package_dir_of_path(item.exe_path) {
      Some(dir) =>
        if !found.any(fn(p) { p.dir == dir }) {
          match read_package(@json.join_path(dir, "package.json")) {
            Some((name, version)) => found.push({ name, version, dir, source: "" })
            None => ()
          }
        }
      None => ()
    }
  }
  found
}

///|
/// 多份候选时的取舍（策略 3）：
///   ① 与在跑实例同一个包目录的那一份 —— 实例跑的就是它，最省事也最一致；
///   ② 没有①时，版本与在跑实例一致的那批里取版本最高；
///   ③ 连版本都无从参照时，直接取版本最高。
/// 平手时保持候选顺序（shim 找到的那份在前），不靠哈希顺序碰运气。
async fn choose_installed(candidates : Array[DshPackage]) -> DshPackage? noraise {
  if candidates.length() == 0 {
    return None
  }
  if candidates.length() == 1 {
    return Some(candidates[0])
  }
  let live = live_instance_packages()
  for c in candidates {
    if live.any(fn(l) { l.dir == c.dir }) {
      return Some({ ..c, source: c.source + "；" + pick_same_dir })
    }
  }
  let matched : Array[DshPackage] = []
  for c in candidates {
    if live.any(fn(l) { l.version == c.version }) {
      matched.push(c)
    }
  }
  let pool = if matched.length() > 0 { matched } else { candidates }
  let note = if matched.length() > 0 { pick_same_version } else { pick_highest }
  let mut best = pool[0]
  for c in pool {
    if compare_version(c.version, best.version) > 0 {
      best = c
    }
  }
  Some({ ..best, source: best.source + "；" + note })
}

///|
/// 找本机的 @deepseek-ai/dsh，按可靠性三级：
///   1. 顺 PATH 上的 dsh 命令（shim）解开 → 真包目录（最可靠：那是 `dsh` 真会跑的那一份）
///   2. 在已知全局根下按深度 ≤3 找 node_modules/@deepseek-ai/dsh（覆盖 root/、root/槽/、
///      root/槽/哈希/ 三种布局；不写死 v11 那一层）
///   3. 多份候选时挑与在跑实例一致的那份，挑不出取版本最高的
/// 用了哪条策略写进返回值的 source，/api/local/runtime 的来源串直接用它。
///
/// 同一文件里的同类风险（都靠固定布局，逐个判过）：
///   · global_roots 的固定三个根 —— 已加 PNPM_HOME / XDG_DATA_HOME，根挪走了也还有得扫；
///   · 兜底扫描只在根下走 3 层 —— pnpm 再加深一层就落空，届时改 scan_max_depth 一处；
///   · resolve_dsh_home 的默认 ~/.dsh —— 那是 dsh 自己的默认值，跟随它才对，不加兜底；
///   · consoleVersion 的 VERSION / package.json 定位 —— 找的是本工程自己的目录，不是别人的布局；
///   · dist_static 的 dist 根 —— 同上，且解析失败已如实报 503 与原因。
pub async fn find_installed_dsh() -> DshPackage? noraise {
  let candidates : Array[DshPackage] = []
  match shim_candidate() {
    Some(pkg) => candidates.push(pkg)
    None => ()
  }
  for root in global_roots() {
    if !@json.is_dir(root) {
      continue
    }
    for found in scan_root_for_dsh(root) {
      if !candidates.any(fn(c) { c.dir == found.dir }) {
        candidates.push(found)
      }
    }
  }
  choose_installed(candidates)
}

///|
/// 已安装 dsh 的包目录，给「起实例」用：与 /api/local/runtime 的 dshPackageDir 同一条链
/// （同一个 find_installed_dsh），起实例时不会和读数指向两份不同的 dsh。
pub async fn installed_dsh_dir() -> String? noraise {
  match find_installed_dsh() {
    Some(d) => Some(d.dir)
    None => None
  }
}

///|
/// dsh home：优先 DSH_HOME 环境变量，其次 ~/.dsh。
///
/// 这是**控制台自己**的 home。实例的 home 要读实例进程的 /proc/<pid>/environ
/// （见 actions/running_for_profile_in 那一侧），两者今天是巧合一致，不能互相顶替。
pub async fn resolve_dsh_home() -> (String, String) noraise {
  match @json.env_value("DSH_HOME") {
    Some(v) => (v, "DSH_HOME 环境变量")
    None => (@json.join_path(@json.home_dir(), ".dsh"), "默认 ~/.dsh")
  }
}

///|
/// 平台串。Node 版是 `${platform()} ${arch()} (${release()})`，值形如
/// "linux x64 (7.2.9-arch1-1)"。MoonBit 侧只认 Linux/MacOS/Windows，
/// 拿不到 kernel release 与真实机器架构，这两段按本机构建时事实固化。
pub async fn platform_string() -> String noraise {
  let os = match @async.platform {
    @types.Linux => "linux"
    @types.MacOS => "darwin"
    @types.Windows => "win32"
  }
  os + " " + target_arch() + " (" + kernel_release() + ")"
}

///|
/// 本机构建架构（编译期事实）。
pub fn target_arch() -> String {
  "x64"
}

///|
/// 内核版本。读 /proc/sys/kernel/osrelease（只读），读不到给 "unknown"。
pub async fn kernel_release() -> String noraise {
  match @json.read_text_file("/proc/sys/kernel/osrelease") {
    Ok(text) => {
      let t = text.trim().to_owned()
      if t == "" { "unknown" } else { t }
    }
    Err(_) => "unknown"
  }
}

///|
/// 组装 /api/local/runtime 的 data 对象。
pub async fn read_runtime() -> @json.JsonVal raise @localapi.ReadError {
  let (dsh_home, dsh_home_source) = resolve_dsh_home()
  if !@json.is_dir(dsh_home) {
    @localapi.fail_read("dsh-home-missing", "DSH_HOME 不是可读目录：\{dsh_home}")
  }
  let dsh = match find_installed_dsh() {
    Some(d) => d
    None => {
      @localapi.fail_read(
        "dsh-package-missing",
        "没找到 @deepseek-ai/dsh：PATH 上的 dsh 命令解不出包目录，pnpm 全局根下（深度 " +
        scan_max_depth.to_string() + " 层内）也没有 node_modules/@deepseek-ai/dsh",
      )
      abort("unreachable: fail_read always raises")
    }
  }
  let dsh_profile = @json.env_raw("DSH_PROFILE")
  // 控制台版本：优先仓库根的 VERSION 文件，没有才退回前端 package.json。
  // 这样前端换栈（删掉 package.json）之后这条读数不会失效。
  let (console_version, version_source) = @json.read_console_version()
  @json.JObj([
    ("consoleVersion", @json.str_or_null(console_version)),
    ("consolePackageName", @json.JStr(console_package_name)),
    ("consoleVersionSource", @json.JStr(version_source)),
    ("dshVersion", @json.JStr(dsh.version)),
    ("dshPackageName", @json.JStr(dsh.name)),
    ("dshPackageDir", @json.JStr(dsh.dir)),
    ("dshSourceLabel", @json.JStr(dsh_source_label + "（" + dsh.source + "）")),
    ("backendRuntime", @json.JStr(@json.backend_runtime)),
    ("backendVersion", @json.JStr(@json.backend_version)),
    ("backendPackageName", @json.JStr(@json.backend_package_name)),
    ("dshHome", @json.JStr(dsh_home)),
    ("dshHomeSource", @json.JStr(dsh_home_source)),
    ("dshProfile", @json.str_or_null(dsh_profile)),
    ("platform", @json.JStr(platform_string())),
  ])
}

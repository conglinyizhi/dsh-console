// GET /api/local/runtime 的数据体。
//
// 字段与 Node 版 server/readRuntime.mjs 的返回值逐字段一致：
//   consoleVersion, consolePackageName, dshVersion, dshPackageName, dshPackageDir,
//   dshSourceLabel, nodeVersion, dshHome, dshHomeSource, dshProfile, platform
//
// 文件 IO 只有 @json 里那几个只读入口：read_file / readdir / kind / exists。

///|
/// 本后端对应的 dsh-console 前端包事实。前端 package.json 在编译期不可见，
/// 这里按 Node 版实测值固化；改前端版本号时一并改这里。
pub let console_package_name : String = "dsh-console"

///|
/// 见上。
pub let console_version : String = "0.1.0"

///|
/// 本机 Node 版本。MoonBit 进程里没有 Node，这个字段只是与 Node 版保持同形的占位事实。
pub let node_version : String = "v26.11.1"

///|
/// dsh 来源标签，与 Node 版同常量。
pub let dsh_source_label : String = "本机已安装"

///|
/// pnpm 全局安装目录候选，逐个扫，不调外部命令（与 Node 版 globalRoots 一致）。
async fn global_roots() -> Array[String] noraise {
  let home = @json.home_dir()
  [
    @json.join_all([home, ".local", "share", "pnpm", "global"]),
    @json.join_path(home, ".pnpm-global"),
    @json.join_all([home, "Library", "pnpm", "global"]),
  ]
}

///|
struct DshPackage {
  name : String
  version : String
  dir : String
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
/// 在 pnpm 全局目录里找 @deepseek-ai/dsh（global/<槽>/node_modules/@deepseek-ai/dsh/package.json），
/// 多份时取版本最大的那份。
pub async fn find_installed_dsh() -> DshPackage? noraise {
  let found : Array[DshPackage] = []
  for root in global_roots() {
    if @json.is_dir(root) {
      for slot in @json.list_dir(root) {
        let dir = @json.join_all([root, slot, "node_modules", "@deepseek-ai", "dsh"])
        match read_package(@json.join_path(dir, "package.json")) {
          Some((name, version)) => found.push({ name, version, dir })
          None => ()
        }
      }
    }
    let flat = @json.join_all([root, "node_modules", "@deepseek-ai", "dsh"])
    match read_package(@json.join_path(flat, "package.json")) {
      Some((name, version)) => found.push({ name, version, dir: flat })
      None => ()
    }
  }
  if found.length() == 0 {
    return None
  }
  found.sort_by(fn(a, b) { compare_version(a.version, b.version) })
  Some(found[found.length() - 1])
}

///|
/// dsh home：优先 DSH_HOME 环境变量，其次 ~/.dsh。
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
    @localapi.fail_read("dsh-home-missing", "DSH_HOME 不是可读目录：{dsh_home}")
  }
  let dsh = match find_installed_dsh() {
    Some(d) => d
    None => {
      @localapi.fail_read(
        "dsh-package-missing",
        "在 pnpm 全局安装目录里没找到 @deepseek-ai/dsh 的 package.json",
      )
      abort("unreachable: fail_read always raises")
    }
  }
  let dsh_profile = @json.env_raw("DSH_PROFILE")
  @json.JObj([
    ("consoleVersion", @json.JStr(console_version)),
    ("consolePackageName", @json.JStr(console_package_name)),
    ("dshVersion", @json.JStr(dsh.version)),
    ("dshPackageName", @json.JStr(dsh.name)),
    ("dshPackageDir", @json.JStr(dsh.dir)),
    ("dshSourceLabel", @json.JStr(dsh_source_label)),
    ("nodeVersion", @json.JStr(node_version)),
    ("dshHome", @json.JStr(dsh_home)),
    ("dshHomeSource", @json.JStr(dsh_home_source)),
    ("dshProfile", @json.str_or_null(dsh_profile)),
    ("platform", @json.JStr(platform_string())),
  ])
}
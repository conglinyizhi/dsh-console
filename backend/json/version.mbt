// 后端自身版本与「本控制台前端包版本」的运行时读取。
//
// 两条硬要求（第二批）：
//   1. 不再对外谎报 Node 版本。后端跑在 MoonBit native 运行时上，如实报 backendRuntime。
//   2. consoleVersion 不再是编译期常量：运行时去读前端 package.json 的 version，
//      读不到就 null，并在 consoleVersionSource 里写明为什么读不到。
//
// 两处都只做只读文件访问（走 @json 的只读入口）。

///|
/// 本后端模块版本。与 ../moon.mod 里的 version 保持一致，改动时两处同改。
pub let backend_version : String = "0.1.0"

///|
/// 本后端运行时标识。
pub let backend_runtime : String = "moonbit/native"

///|
/// 本后端包的模块名，与 ../moon.mod 的 name 一致。
pub let backend_package_name : String = "conglinyizhi/dsh-console-backend"

///|
/// 允许用来定位前端目录的环境变量，按顺序试。
let frontend_env_names : Array[String] = [
  "DSH_CONSOLE_DIR",
  "DSH_CONSOLE_ROOT",
  "DSH_CONSOLE_HOME",
]

///|
/// 从二进制位置往上找前端目录：找同时含 package.json 与 src/ 的那一层。
/// 覆盖 _build/native/debug/build/<exe> 与直接放在 dsh-console/backend/ 下的部署方式，
/// 以及 backend/ 与前端同级的常见布局。找不到返回 None。
pub async fn locate_frontend_dir() -> String? noraise {
  let dir = dirname(exe_path())
  let mut current = dir
  let mut steps = 0
  while steps < 8 {
    steps = steps + 1
    let parent = dirname(current)
    if parent == current {
      break
    }
    current = parent
    let pkg = join_path(current, "package.json")
    if exists(pkg) && is_dir(join_path(current, "src")) {
      return Some(current)
    }
  }
  None
}

///|
/// 解析前端目录：环境变量优先（非空且目录存在），否则按二进制位置往上找。
/// 返回 (目录, 来源说明)；都没找到时目录为 None。
pub async fn resolve_frontend_dir() -> (String?, String) noraise {
  for name in frontend_env_names {
    match env_value(name) {
      Some(v) =>
        if is_dir(v) {
          return (Some(v), name + " 环境变量")
        } else {
          return (None, name + " 环境变量指向的目录不存在：" + v)
        }
      None => ()
    }
  }
  let exe = exe_path()
  let shown = if exe == "" { "（读不到 /proc/self/exe）" } else { exe }
  match locate_frontend_dir() {
    Some(dir) => (Some(dir), "相对二进制位置上溯找到含 package.json + src/ 的目录")
    None => (None, "既没有 DSH_CONSOLE_DIR 等环境变量，也没能从二进制位置 " + shown + " 上溯找到前端目录")
  }
}

///|
/// 运行时读前端 package.json 的 version。读不到给 None（上层给 null，不编）。
pub async fn read_frontend_version(dir : String) -> String? noraise {
  let text = match read_text_file(join_path(dir, "package.json")) {
    Ok(t) => t
    Err(_) => return None
  }
  let json = match json_parse(text) {
    Some(j) => j
    None => return None
  }
  match json_field(json, "version") {
    Some(v) => json_string(v)
    None => None
  }
}

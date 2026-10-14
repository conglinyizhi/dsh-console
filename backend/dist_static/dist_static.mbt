// 前端构建产物（dist/）的静态服务：让后端一个进程一个端口既答 API 也答页面。
//
// 三件事分清楚：
//   1. 解析静态根：$DSH_CONSOLE_DIST 优先；没有就从 /proc/self/exe 的位置上溯，
//      找同时含 index.html 与静态资源的产物目录（assets/ 目录或同层 .js/.css 都算；
//      与 json 包找前端目录同一套思路，不硬编码绝对路径）。
//   2. 有根：用 moonback 的 unstable_static 中间件服务该目录，history_fallback 指向 index.html
//      （SPA 回退；当前前端是状态切页，这里为将来的 URL 路由留好）。
//   3. 没根：不注册静态中间件，改成 503 + text/plain 把原因写在响应体和启动日志里——
//      解析失败要如实报出来，不能静默给一张空白页。
//
// 只读：静态中间件内部只做 kind / open(ReadOnly) / 读；本包不写盘、不起进程。
//
// 与 API 的关系：本中间件必须挂在 /api/local 的闸门里面（见 localapi 包的 api_gate）。
// unstable_static 的 history_fallback 会把下一跳的 404 换成 index.html，
// 未实现的接口一旦落到这里就会从 JSON 错误壳变成 HTML 页面。

///|
/// 静态根的环境变量名：显式指定优先于自动上溯。
pub let dist_env_name : String = "DSH_CONSOLE_DIST"

///|
/// 上溯层数上限。覆盖 _build/native/<profile>/build/<exe> 这种布局绰绰有余，
/// 与 json 包找前端目录时用的 8 层一致。
let max_walk_up : Int = 8

///|
/// SPA 回退的落点。写成 "/index.html" 是必须的：中间件内部的 normalize_relative_path
/// 要求路径以 / 开头，写 "index.html" 会被静默判成 None，回退等于没配。
pub let history_fallback_path : String = "/index.html"

///|
/// 一个目录是不是构建产物目录：有 index.html，且旁边确实带着静态资源。
/// 只 stat 不读内容。
///
/// 资源形式放宽成两种：`assets/` 子目录（打包器常见布局），或同层直接有
/// `.js` / `.css` 文件（rabbita 这类把产物平铺在根上的布局）。
/// 「index.html 之外还得有东西」这条不能松：只有 index.html 的话，仓库根那个
/// Vite 开发入口会被误当成产物目录。
pub async fn is_dist_dir(dir : String) -> Bool noraise {
  if !@json.exists(@json.join_path(dir, "index.html")) {
    return false
  }
  if @json.is_dir(@json.join_path(dir, "assets")) {
    return true
  }
  has_flat_assets(dir)
}

///|
/// 同层有没有 .js / .css 文件。
async fn has_flat_assets(dir : String) -> Bool noraise {
  let mut found = false
  for entry in @json.list_entries(dir) {
    let (name, _) = entry
    if name.has_suffix(".js") || name.has_suffix(".css") {
      found = true
      break
    }
  }
  found
}

///|
/// 从可执行文件位置往上找 dist 目录：每一层先看 <层>/dist，再看这一层本身。
/// 前者覆盖 backend/_build/... 下的二进制，后者覆盖二进制被放进 dist/ 或直接
/// 指向构建产物的部署方式。读不到 /proc/self/exe 时退化为相对当前工作目录，
/// 上溯一层就停（dirname(".") 是 "."）。
pub async fn locate_dist_dir() -> String? noraise {
  let exe = @json.exe_path()
  let mut current = @json.dirname(exe)
  let mut steps = 0
  while steps < max_walk_up {
    steps = steps + 1
    let child = @json.join_path(current, "dist")
    if is_dist_dir(child) {
      return Some(child)
    }
    if is_dist_dir(current) {
      return Some(current)
    }
    let parent = @json.dirname(current)
    if parent == current {
      break
    }
    current = parent
  }
  None
}

///|
/// 日志里回显 exe 位置；读不到就说读不到，不留空。
fn exe_note(exe : String) -> String {
  if exe == "" {
    "（读不到 /proc/self/exe）"
  } else {
    exe
  }
}

///|
/// 解析静态根，返回 (目录, 来源说明)。
/// 环境变量设了但指向的目录不对，就直接算失败并把原因写清楚，不偷偷回退到自动上溯结果：
/// 显式指的路径是错的，就该在启动日志里看见这件事。
pub async fn resolve_dist_root() -> (String?, String) noraise {
  let exe = @json.exe_path()
  match @json.env_value(dist_env_name) {
    Some(v) =>
      if is_dist_dir(v) {
        return (Some(v), dist_env_name + " 环境变量（显式指定）")
      } else if @json.is_dir(v) {
        return (
          None,
          dist_env_name + " 环境变量指向的目录里没有 index.html 与静态资源（assets/ 目录或同层 .js/.css）：" + v,
        )
      } else {
        return (None, dist_env_name + " 环境变量指向的目录不存在：" + v)
      }
    None => ()
  }
  match locate_dist_dir() {
    Some(dir) =>
      (
        Some(dir),
        "相对可执行文件位置 " + exe_note(exe) + " 上溯找到含 index.html 与静态资源的目录",
      )
    None =>
      (
        None,
        "没有设 " +
        dist_env_name +
        "，也没能从可执行文件位置 " +
        exe_note(exe) +
        " 上溯找到含 index.html 与静态资源的目录",
      )
  }
}

///|
/// 静态根不可用时的代打中间件：GET/HEAD 一律 503 + text/plain，把原因写在响应体里。
/// 不返回 200 空白页，也不装作正常；其它方法原样透传（与静态中间件的守卫一致）。
pub fn unavailable_middleware(reason : String) -> @moonback.Middleware {
  let body = "前端静态资源不可用：\{reason}\n" +
    "本地接口不受影响：/api/local/runtime、/profiles、/logs、/processes、/instances 照常。\n" +
    "修法：把前端构建产物（含 index.html 与静态资源）放到可执行文件同级的 dist/，或用 " +
    dist_env_name +
    " 指定该目录。\n"
  @moonback.Middleware(next => {
    (req, res) => {
      if req.meth is @async_http.Get || req.meth is @async_http.Head {
        res.send_text(body, status=503)
      } else {
        next(req, res)
      }
    }
  })
}

///|
/// 建静态中间件。根解析成功就用 unstable_static（目录服务 + 尾斜杠 index + SPA 回退），
/// 失败就交给 unavailable_middleware 如实报错。
pub fn static_middleware(root : String?, source : String) -> @moonback.Middleware {
  match root {
    Some(dir) =>
      @unstable_static.new(
        root=dir,
        rewrite_trailing_slash_index=true,
        history_fallback=Some(history_fallback_path),
      )
    None => unavailable_middleware(source)
  }
}

///|
/// 启动日志里静态服务那几行。解析结果、来源、回退落点、API 优先级一次写清。
pub fn startup_note(root : String?, source : String) -> String {
  match root {
    Some(dir) =>
      "- 静态根：\{dir}\n" +
      "- 静态根来源：\{source}\n" +
      "- SPA 回退：\{history_fallback_path}（history_fallback；实体文件与静态目录都命中不了时回落到它）\n" +
      "- 优先级：/api/local 与 /api/local/* 由最外层闸门先接走，静态文件抢不到\n"
    None =>
      "- 静态根未解析：\{source}\n" +
      "- 静态服务关闭：非 /api/local 的 GET/HEAD 返回 503 + text/plain 说明原因，不返回空白页\n" +
      "- 本地接口不受影响：/api/local/* 照常\n"
  }
}

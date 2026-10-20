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
/// 从可执行文件位置往上找产物目录。每一层的候选按优先级：
///   `<层>/frontend/dist` → `<层>/dist` → 这一层本身
///
/// 前两个分别对应换栈后的 rabbita 产物与旧的 Vue 产物。**新栈优先**是有意的：
/// 旧产物没删之前两者会同时存在，先看新的才不会一直供着过期的页面。
/// 第三项覆盖二进制被直接放进产物目录里的部署方式。
/// 读不到 /proc/self/exe 时退化为相对当前工作目录，上溯一层就停（dirname(".") 是 "."）。
pub async fn locate_dist_dir() -> String? noraise {
  let exe = @json.exe_path()
  let mut current = @json.dirname(exe)
  let mut steps = 0
  while steps < max_walk_up {
    steps = steps + 1
    let new_stack = @json.join_path(@json.join_path(current, "frontend"), "dist")
    if is_dist_dir(new_stack) {
      return Some(new_stack)
    }
    let legacy = @json.join_path(current, "dist")
    if is_dist_dir(legacy) {
      return Some(legacy)
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
/// 预压缩资源的后缀。与前端 build.sh 里那一步（gzip -9 -n -k）约定一致。
let gzip_suffix : String = ".gz"

///|
/// 前端产物所在的那一层。只有这一层的响应自己带缓存指令（见 gzip_middleware），
/// 因为它的文件名每次构建都不变（assets/app.css、assets/app.js）。
let asset_prefix : String = "assets/"

///|
/// 去掉查询串与片段。静态中间件自己也做这一步，这里是它前面的一层，得同样处理。
fn path_without_query(raw : String) -> String {
  let mut end = raw.length()
  match raw.find("?") {
    Some(i) => if i < end { end = i }
    None => ()
  }
  match raw.find("#") {
    Some(i) => if i < end { end = i }
    None => ()
  }
  raw[:end].to_owned()
}

///|
/// 请求路径 -> 静态根下的相对路径；不认就给 None，交给下一层。
///
/// 这条捷径只认「原样就能拼」的路径：带 % 转义、反斜杠、NUL、`..` 段、不以 /
/// 开头的一律放行给 unstable_static，由它那套解码 + 规范化去判。这样不必在这里
/// 再写一份 URL 解码 —— 少一份解码就少一处能绕开穿越防护的地方，而构建产物
/// （/assets/app.js 这类）本来就是不需要转义的路径。
fn relative_path_or_none(raw : String) -> String? {
  let path = path_without_query(raw)
  guard path.has_prefix("/") &&
    !path.contains("\\") &&
    !path.contains("\u{0}") &&
    !path.contains("%") else {
    return None
  }
  let segments : Array[String] = []
  for segment in path.split("/") {
    let seg = @json.owned(segment)
    if seg == "" || seg == "." {
      continue
    }
    if seg == ".." {
      return None
    }
    segments.push(seg)
  }
  if segments.length() == 0 {
    return None
  }
  Some(segments.join("/"))
}

///|
/// q 值是不是 0（"0" / "0.0" / "0.00" 都算，"0.5" 不算）。
fn quality_is_zero(value : String) -> Bool {
  let head = match value.find(".") {
    Some(i) => value[:i].to_owned()
    None => value
  }
  head == "0"
}

///|
/// 请求头要不要 gzip：按逗号切条目，认 token（gzip 或 \*）且 q 值不是 0。
/// "gzip;q=0" 是明确拒绝，不能当成「要」。
fn accepts_gzip(header : StringView?) -> Bool {
  let raw = match header {
    None => return false
    Some(v) => @json.to_lower(v.to_owned())
  }
  for item in raw.split(",") {
    let entry = @json.trim_both(@json.owned(item))
    if entry == "" {
      continue
    }
    let parts = entry.split(";").collect()
    let token = match parts.get(0) {
      Some(t) => @json.trim_both(@json.owned(t))
      None => ""
    }
    if token != "gzip" && token != "*" {
      continue
    }
    let mut refused = false
    for i = 1; i < parts.length(); i = i + 1 {
      let param = @json.trim_both(@json.owned(parts[i]))
      if param.has_prefix("q=") && quality_is_zero(@json.slice_from(param, 2)) {
        refused = true
      }
    }
    if !refused {
      return true
    }
  }
  false
}

///|
/// 静态资源的内容类型；与 unstable_static 的 guess_content_type 同一口径。
/// 预压缩只换了传输编码，Content-Type 必须还是原文件那个。
fn content_type_of(path : String) -> String {
  let lower = @json.to_lower(path)
  if lower.has_suffix(".js") || lower.has_suffix(".mjs") {
    "text/javascript; charset=utf-8"
  } else if lower.has_suffix(".css") {
    "text/css; charset=utf-8"
  } else if lower.has_suffix(".html") {
    "text/html; charset=utf-8"
  } else if lower.has_suffix(".json") || lower.has_suffix(".map") {
    "application/json; charset=utf-8"
  } else if lower.has_suffix(".txt") {
    "text/plain; charset=utf-8"
  } else if lower.has_suffix(".svg") {
    "image/svg+xml"
  } else if lower.has_suffix(".png") {
    "image/png"
  } else if lower.has_suffix(".ico") {
    "image/x-icon"
  } else if lower.has_suffix(".woff2") {
    "font/woff2"
  } else {
    "application/octet-stream"
  }
}

///|
/// 是不是普通文件（目录、设备、读不到的一律不算）。
async fn is_regular_file(path : String) -> Bool noraise {
  try @fs.kind(path) catch {
    _ => false
  } noraise {
    kind =>
      match kind {
        Regular => true
        _ => false
      }
  }
}

///|
/// 预压缩静态资源中间件。三条同时成立才命中：
///   1. GET / HEAD；
///   2. Accept-Encoding 认 gzip；
///   3. 原文件与同名 .gz 都是普通文件。
/// 任何一条不成立（含读不动、路径不认）都原样交给下一层：.gz 缺失绝不变成 404，
/// 没预压缩的资源照旧发原文件。接口请求走不到这里 —— 链的最外层是 localapi.api_gate。
fn gzip_middleware(root : String) -> @moonback.Middleware {
  @moonback.Middleware(next => {
    (req, res) => {
      guard req.meth is @async_http.Get || req.meth is @async_http.Head else {
        next(req, res)
        return
      }
      let relative = match relative_path_or_none(@json.owned(req.path)) {
        Some(r) => r
        None => {
          next(req, res)
          return
        }
      }
      let original = @json.join_path(root, relative)
      // 前端产物是同名文件（assets/app.css、assets/app.js）：重新构建后名字不变，
      // 不给缓存指令时浏览器会自己猜着缓存，出过「新 JS 配旧 CSS」的混合页面。
      // 所以 assets/ 这一层自己发，带 no-cache；其它路径原样交给下一层。
      guard relative.starts_with(asset_prefix) && is_regular_file(original) else {
        next(req, res)
        return
      }
      let packed = original + gzip_suffix
      if accepts_gzip(req.headers.get("Accept-Encoding")) && is_regular_file(packed) {
        let file = try {
          @fs.open(packed, mode=ReadOnly)
        } catch {
          _ => {
            next(req, res)
            return
          }
        }
        defer file.close()
        let headers = @moonback.Headers::from({
          "Content-Type": content_type_of(original),
          "Content-Length": file.size().to_string(),
          "Content-Encoding": "gzip",
          "Cache-Control": "no-cache",
          "Vary": "Accept-Encoding",
        })
        if req.meth is @async_http.Head {
          res.send_void(status=200, headers~)
        } else {
          let writer = res.respond(status=200, headers~)
          writer.write_reader(file)
        }
        return
      }
      let file = try {
        @fs.open(original, mode=ReadOnly)
      } catch {
        _ => {
          next(req, res)
          return
        }
      }
      defer file.close()
      let headers = @moonback.Headers::from({
        "Content-Type": content_type_of(original),
        "Content-Length": file.size().to_string(),
        "Cache-Control": "no-cache",
      })
      if req.meth is @async_http.Head {
        res.send_void(status=200, headers~)
      } else {
        let writer = res.respond(status=200, headers~)
        writer.write_reader(file)
      }
      return
    }
  })
}

///|
/// 建静态中间件。根解析成功就用 unstable_static（目录服务 + 尾斜杠 index + SPA 回退），
/// 失败就交给 unavailable_middleware 如实报错。
/// 预压缩层（gzip_middleware）挂在外层：命中就自己发 .gz，没命中原样放行给下一层。
pub fn static_middleware(root : String?, source : String) -> @moonback.Middleware {
  match root {
    Some(dir) =>
      gzip_middleware(dir).compose(
        @unstable_static.new(
          root=dir,
          rewrite_trailing_slash_index=true,
          history_fallback=Some(history_fallback_path),
        ),
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
      "- 预压缩：Accept-Encoding 含 gzip 且同名 " + gzip_suffix +
      " 在时发 " + gzip_suffix + "（Content-Encoding: gzip + Vary: Accept-Encoding），" +
      "其余照旧发原文件；" + gzip_suffix + " 缺失不是错误，不会变成 404\n" +
      "- 优先级：/api/local 与 /api/local/* 由最外层闸门先接走，静态文件抢不到\n"
    None =>
      "- 静态根未解析：\{source}\n" +
      "- 静态服务关闭：非 /api/local 的 GET/HEAD 返回 503 + text/plain 说明原因，不返回空白页\n" +
      "- 本地接口不受影响：/api/local/* 照常\n"
  }
}

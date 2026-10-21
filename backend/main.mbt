// dsh-console 本地接口后端入口。
//
// 默认只监听 127.0.0.1:5390（可用 DSH_CONSOLE_BACKEND_HOST / _PORT 覆盖，自测隔离用）。
// 接口分两层：
//   只读（GET，纯只读）：runtime / profiles / logs / processes / instances / dsh-releases
//   写（POST /api/local/action + GET/PUT /api/local/settings + GET /api/local/console）
// 写侧的守卫、动作与落盘全在 actions 包里；这里只负责把两条路分开。
//
// 同一个端口既答 API 也服务前端构建产物 dist/（A 形态，终局形态）。
// 中间件顺序只有一条规矩 —— API 在前，静态在后：
//   最外层 localapi.api_gate  →  /api/local* 到此为止，不往下走
//   次外层 dist_static        →  dist 目录服务 + SPA 回退（index.html）
//   最内层 路由               →  兜底 404
// 静态中间件不能放到闸门外层：它的 history_fallback 会把 404 改写成 index.html，
// 未实现接口的错误壳就没了。

///|
let default_listen_host : String = "127.0.0.1"

///|
let default_listen_port : UInt16 = 5390

///|
/// 十进制串转端口号；非数字或超范围给 None。
fn parse_port(text : String) -> UInt16? {
  if !@json.is_all_digits(text) {
    return None
  }
  let value = @json.parse_dec(text)
  if value < 1 || value > 65535 {
    return None
  }
  Some(value.to_uint16())
}

///|
/// 监听地址：$DSH_CONSOLE_BACKEND_HOST 优先，默认 127.0.0.1。
/// 只做本机自测时的端口隔离用；默认值就是文档里写的那一条。
async fn resolve_listen() -> (String, UInt16) noraise {
  let host = match @json.env_value("DSH_CONSOLE_BACKEND_HOST") {
    Some(v) => v
    None => default_listen_host
  }
  let port = match @json.env_value("DSH_CONSOLE_BACKEND_PORT") {
    Some(v) =>
      match parse_port(v) {
        Some(p) => p
        None => default_listen_port
      }
    None => default_listen_port
  }
  (host, port)
}

///|
/// runtime 读取函数，转成路由 handler 需要的签名。
async fn read_runtime() -> @json.JsonVal raise @localapi.ReadError {
  @runtime.read_runtime()
}

///|
/// profiles 读取函数。
async fn read_profiles() -> @json.JsonVal raise @localapi.ReadError {
  @profiles.read_profiles()
}

///|
/// logs 读取函数。tail 从查询串取；缺省取设置里的 logs.defaultTail；
/// 非正整数 / 超上限都在 logs 包里收敛。
async fn read_logs(
  req : @moonback.Request,
) -> @json.JsonVal raise @localapi.ReadError {
  let source = match @localapi.query_param(req, "source") {
    Some(s) => s
    None =>
      raise @localapi.ReadError(
        code="missing-source",
        message="缺少 source 参数，只支持 host / audit / instance:<实例 id>",
      )
  }
  let spec = @logs.parse_tail_with_settings(@localapi.query_param(req, "tail"))
  @logs.read_logs(source, spec)
}

///|
/// processes 读取函数。
async fn read_processes() -> @json.JsonVal raise @localapi.ReadError {
  @processes.read_processes_data()
}

///|
/// instances 读取函数。
async fn read_instances() -> @json.JsonVal raise @localapi.ReadError {
  @instances.read_instances()
}

///|
/// dsh 版本来源读取函数：**只读进程内缓存，秒回**（design/ops-maintenance-jobs.md §10.1）。
/// 真正问三个源（GitHub / npm / 国内镜像，各自 6 秒硬超时）的是启动时那一趟后台拉取，
/// 以及缓存空 / 过期时由这条接口顺手叫起的后台刷新 —— 都不在这条请求里等。
/// 三个源全没答上来也算读到了（读数里 sources 全是 ok=false）——
/// 读不到是一个事实，不是接口错误；这里按路由表的签名套一层。
async fn read_releases() -> @json.JsonVal raise @localapi.ReadError {
  // cached_releases 只读缓存，不 await：这一条请求因此不会被三个源的网络拖住。
  let value = @releases.cached_releases()
  // 这条接口从不失败：读不到也是读数里的一个事实。ReadError 是路由表要求的形状，
  // 这一格是「形状万一被破坏」时唯一能如实报出来的出口（正常路径走不到）。
  if value is @json.JNull {
    raise @localapi.ReadError(
      code="read-failed",
      message="版本来源读数不完整",
    )
  }
  value
}

///|
/// 已实现的路由表（无查询参数的这几条）。
fn routes() -> Array[@localapi.Api] {
  [
    @localapi.api("/api/local/runtime", read_runtime),
    @localapi.api("/api/local/profiles", read_profiles),
    @localapi.api("/api/local/processes", read_processes),
    @localapi.api("/api/local/instances", read_instances),
    // 版本来源这条不会失败：三个源全没答上来也是 200（读不到是读数里的一个事实，
    // 不是接口错误 —— 见 releases.mbt 的头注释）
    @localapi.api("/api/local/dsh-releases", read_releases),
  ]
}

///|
/// 带查询串的路由表（logs 要读 source / tail）。
fn query_routes() -> Array[@localapi.QueryApi] {
  [@localapi.query_api("/api/local/logs", read_logs)]
}

///|
/// 单个请求的分发：写侧三条路径归 actions，其余按只读接口走。
async fn handle(req : @moonback.Request, res : @moonback.Responder) -> Unit {
  let read_at = @json.iso_from_epoch_ms(@async.now())
  if @actions.handles_path(req.path) {
    @actions.dispatch(req, res, read_at)
    return
  }
  @localapi.dispatch(req, res, routes(), query_routes(), read_at)
}

///|
async fn main {
  // 静态根在起服务之前解析一次：解析结果要写进启动日志，不能藏。
  let (dist_root, dist_source) = @dist_static.resolve_dist_root()
  let app = @moonback.App(ctx => {
    // 接口闸门在最外层：/api/local* 不进静态中间件，404/405 的接口语义原样保留。
    // 闸门直接调 handle，与路由表指向同一个 handler；405 仍由 dispatch 发（非 GET）。
    ctx.add_middleware(@localapi.api_gate(handle))
    // 静态中间件在闸门里层：实体文件命中就答，命中不了回落到 index.html（SPA 回退），
    // 再命中不了才落到最内层的路由（404）。根解析失败时给的是 503 + 原因说明。
    ctx.add_middleware(@dist_static.static_middleware(dist_root, dist_source))
  })
  defer app.close()
  let (host, port) = resolve_listen()
  let server = @moonback.listen(host~, port~)
  // 启动日志只留三行（§79）：这是什么、空一行、该访问的地址。
  // 静态根、API 清单、gzip、SPA 回退这些细节都在 backend/README.md，不在这里刷屏。
  @stdio.stdout.write(
    "dsh-console " + @store.build_sha + "\n\nhttp://\{server.addr}\n",
  )
  // serve 跑在控制台主任务组里：detach=false 的实例就挂在这个组上，
  // 控制台退出（含 SIGTERM/SIGINT 的取消）时由运行时的结构化并发按 stopGraceMs 收掉它们。
  // 不能改成「serve 之后写收尾代码」：收到全局取消信号后运行时会重新抬起信号交给默认处理，
  // serve 之后的语句一句都跑不到（实测退出码 143）。
  @async.with_task_group(group => {
    @actions.set_console_group(group)
    // 版本列表在这里就发起第一次后台拉取（§10.1）：spawn 完立刻往下走，
    // serve 不被它拖住 —— 三个源最坏各 6 秒，那是后台的事。
    @releases.start_prewarm(group)
    app.serve(server)
  })
}

// dsh-console 本地只读接口后端入口。
//
// 默认只监听 127.0.0.1:5390（可用 DSH_CONSOLE_BACKEND_HOST / _PORT 覆盖，自测隔离用），
// 只答 GET，只读文件。
// 本轮（第二批）补齐 /api/local/logs、/api/local/processes、/api/local/instances，
// 五个只读接口全部落地：runtime / profiles / logs / processes / instances。

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
/// logs 读取函数。tail 从查询串取；缺省 / 非正整数 / 超上限都在 logs 包里收敛。
async fn read_logs(req : @moonback.Request) -> @json.JsonVal raise @localapi.ReadError {
  let source = match @localapi.query_param(req, "source") {
    Some(s) => s
    None =>
      raise @localapi.ReadError(
        code="missing-source",
        message="缺少 source 参数，只支持 host / audit / instance:<实例 id>",
      )
  }
  let spec = @logs.parse_tail(@localapi.query_param(req, "tail"))
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
/// 已实现的路由表（无查询参数的四个）。
fn routes() -> Array[@localapi.Api] {
  [
    @localapi.api("/api/local/runtime", read_runtime),
    @localapi.api("/api/local/profiles", read_profiles),
    @localapi.api("/api/local/processes", read_processes),
    @localapi.api("/api/local/instances", read_instances),
  ]
}

///|
/// 带查询串的路由表（logs 要读 source / tail）。
fn query_routes() -> Array[@localapi.QueryApi] {
  [@localapi.query_api("/api/local/logs", read_logs)]
}

///|
/// 单个请求的分发。
async fn handle(req : @moonback.Request, res : @moonback.Responder) -> Unit {
  let read_at = @json.iso_from_epoch_ms(@async.now())
  @localapi.dispatch(req, res, routes(), query_routes(), read_at)
}

///|
/// 把 catch-all 路由注册到所有 HTTP 方法上。
/// 只注册 GET 的话，MoonBack 的路由在方法不匹配时根本不进 handler，
/// 405 就发不出来（实测 POST 会掉成 404）。
fn register_local_api(ctx : @moonback.ModuleContext, path : String, handler : @moonback.Handler) -> Unit {
  let methods : Array[@async_http.RequestMethod] = [
    @async_http.Get,
    @async_http.Head,
    @async_http.Post,
    @async_http.Put,
    @async_http.Delete,
    @async_http.Connect,
    @async_http.Options,
    @async_http.Trace,
    @async_http.Patch,
  ]
  for meth in methods {
    ctx.add_route(meth, path, handler) catch {
      _ => ()
    }
  }
}

///|
async fn main {
  let app = @moonback.App(ctx => {
    register_local_api(ctx, "/api/local", handle)
    register_local_api(ctx, "/api/local/*rest", handle)
  })
  defer app.close()
  let (host, port) = resolve_listen()
  let server = @moonback.listen(host~, port~)
  @stdio.stdout.write(
    "dsh-console 只读本地接口后端已起，http://\{server.addr}\n" +
    "GET /api/local/runtime, /profiles, /logs, /processes, /instances\n",
  )
  app.serve(server)
}
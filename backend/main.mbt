// dsh-console 本地只读接口后端入口。
//
// 只监听 127.0.0.1:5390，只答 GET，只读文件。
// 本轮实现 /api/local/runtime 与 /api/local/profiles；
// logs / processes / instances 明确回 501 not-implemented，不假装成功。

///|
let listen_host : String = "127.0.0.1"

///|
let listen_port : UInt16 = 5390

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
/// 已实现的路由表。
fn routes() -> Array[@localapi.Api] {
  [
    @localapi.api("/api/local/runtime", read_runtime),
    @localapi.api("/api/local/profiles", read_profiles),
  ]
}

///|
/// 未实现接口的路径（本轮明确拒答，避免前端误判成空数据）。
let pending_paths : Array[String] = [
  "/api/local/logs", "/api/local/processes", "/api/local/instances",
]

///|
/// 单个请求的分发：先挡未实现接口，再走通用只读分发。
async fn handle(req : @moonback.Request, res : @moonback.Responder) -> Unit {
  let path = req.path.to_owned()
  let read_at = @json.iso_from_epoch_ms(@async.now())
  if req.meth is @async_http.Get && pending_paths.any(fn(p) { p == path }) {
    @localapi.send_error(
      res,
      501,
      "not-implemented",
      "这个只读接口还没实现：" + path,
      read_at=Some(read_at),
    )
    return
  }
  @localapi.dispatch(req, res, routes(), read_at)
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
  let server = @moonback.listen(host=listen_host, port=listen_port)
  @stdio.stdout.write(
    "dsh-console 只读本地接口后端已起，http://\{server.addr}\n" +
    "GET /api/local/runtime, GET /api/local/profiles\n",
  )
  app.serve(server)
}
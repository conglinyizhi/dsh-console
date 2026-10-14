// 只读 HTTP 探测：对 127.0.0.1 上某个端口发一次 GET，最多读前 8KB。
//
// 这不是「对外请求」：目标写死回环地址，方法写死 GET，读完就断。
// 行为对齐 Node 版 readInstances.mjs 的 probePort：
//   - 500ms 超时
//   - redirect: 'manual' —— 不跟随重定向，3xx 按原样读
//   - 只读前 8KB 响应体，不等整页下完
//   - 连不上 / 超时 / 半路断开都算「没命中」，返回结果里带 error，不抛异常
//
// 传输层用 socket 直连（见 rawhttp.mbt 顶部注释：@http.Client 的构造函数在服务进程的
// handler 上下文里会抛 ResolveHostnameError，已实测，故不采用那一条路径）。

///|
/// 单个响应最多读多少字节。
pub let body_limit_bytes : Int = 8192

///|
/// 单个端口的探测超时（毫秒），与 Node 版 PROBE_TIMEOUT_MS 一致。
pub let probe_timeout_ms : Int = 500

///|
/// 一次探测的结论。字段与 Node 版 probePort 的返回一一对应。
/// pub(all) 是必须的：instances 包要能读出字段，也要能构造「未执行」这一条。
pub(all) struct Probe {
  port : Int
  url : String
  reached : Bool
  status : Int?
  content_type : String?
  body : String
  ms : Int
  error : String?
}

///|
/// 一条「没探测」的占位结论。
pub fn empty_probe(reason : String) -> Probe {
  {
    port: 0,
    url: "",
    reached: false,
    status: None,
    content_type: None,
    body: "",
    ms: 0,
    error: Some(reason),
  }
}

///|
/// 把错误渲染成人能读的一行。
/// MoonBit 的 `Error::to_string` 对含载荷的错误只给类型名（例如
/// "…RawHttpError"），载荷会丢——那对排查没有用，所以这里优先走 Debug 表示，
/// 它至少会把类型名和载荷一起打出来（如 RawHttpError("连接被拒绝：…")）。
fn describe_error(err : Error) -> String {
  match @json.raw_http_message(err) {
    Some(msg) => msg
    None => "\{@debug.Debug::to_repr(err)}"
  }
}

///|
/// 探测一个端口。任何异常都收敛成 reached=false + error 文本，不向外抛。
pub async fn probe_port(port : Int) -> Probe noraise {
  let url = "http://127.0.0.1:\{port}/"
  let started_at = @async.now()
  let base : Probe = {
    port,
    url,
    reached: false,
    status: None,
    content_type: None,
    body: "",
    ms: 0,
    error: None,
  }
  let attempt : async () -> Probe raise = async fn () {
    let response = fetch_root(port, body_limit_bytes)
    {
      ..base,
      reached: true,
      status: Some(response.code),
      content_type: header_value(response.headers, "Content-Type"),
      body: response.body,
    }
  }
  let result = try {
    @async.with_timeout_opt(probe_timeout_ms, attempt)
  } catch {
    err => {
      let spent = (@async.now() - started_at).to_int()
      return { ..base, ms: spent, error: Some(describe_error(err)) }
    }
  }
  let spent = (@async.now() - started_at).to_int()
  match result {
    Some(p) => { ..p, ms: spent }
    None => { ..base, ms: spent, error: Some("The operation was aborted due to timeout") }
  }
}

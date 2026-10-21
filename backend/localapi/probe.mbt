// 只读 HTTP 探测：对 127.0.0.1 上某个端口发一次 GET，最多读前 8KB。
//
// 这不是「对外请求」：目标写死回环地址，方法写死 GET，读完就断。
// 行为对齐 Node 版 readInstances.mjs 的 probePort：
//   - 500ms 超时（缺省值，实际由设置 probe.timeoutMs 决定）
//   - redirect: 'manual' —— 不跟随重定向，3xx 按原样读
//   - 只读前 8KB 响应体，不等整页下完
//   - 连不上 / 超时 / 半路断开都算「没命中」，返回结果里带 error，不抛异常
//
// 传输层用 socket 直连（见 rawhttp.mbt 顶部注释：@http.Client 的构造函数在服务进程的
// handler 上下文里会抛 ResolveHostnameError，已实测，故不采用那一条路径）。

///|
/// 单个响应最多读多少字节。
pub let body_limit_bytes : Int32 = 8192

///|
/// 单个端口的探测超时缺省值（毫秒），与 Node 版 PROBE_TIMEOUT_MS 一致。
/// 真正生效的值来自设置 probe.timeoutMs，这里只是缺省与回退。
pub let probe_timeout_ms : Int32 = 500

///|
/// 探测并发缺省值：8 路，与 Node 版 PROBE_CONCURRENCY 取同一个数。
///
/// 为什么是 8：只打回环，8 条并发连接对本机没有压力，而候选上限 40 × 单口 500ms
/// 的最坏耗时从 20s 降到 ceil(40/8)×500ms = 2.5s。取 4 会把最坏值留在 5s，
/// 换不来什么好处——探测目标写死 127.0.0.1，不存在把别人的端口打满的问题。
/// 真实并发 = min(concurrency, 候选端口数)，响应里如实回生效的那个上限。
/// 真正生效的值来自设置 probe.concurrency，这里只是缺省与回退。
pub let probe_concurrency : Int32 = 8

///|
/// 一次探测的结论。字段与 Node 版 probePort 的返回一一对应。
/// pub(all) 是必须的：instances 包要能读出字段，也要能构造「未执行」这一条。
pub(all) struct Probe {
  port : Int32
  url : String
  reached : Bool
  status : Int32?
  content_type : String?
  body : String
  ms : Int32
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
/// 批量探测：结果按下标与传入的端口顺序一一对应（@async.all 保序），
/// 同时在跑的探测不超过 concurrency 个。
/// 顺序稳定是硬要求：响应里的 probeResults / instances 都按端口升序读，
/// 谁先回来不影响谁排第几。
/// timeout_ms / concurrency 由调用方从设置（probe.timeoutMs / probe.concurrency）传进来。
pub async fn probe_ports(
  ports : Array[Int32],
  timeout_ms : Int32,
  concurrency : Int32,
) -> Array[Probe] noraise {
  let tasks : Array[async () -> Probe] = []
  for port in ports {
    let target = port
    tasks.push(async fn() { probe_port(target, timeout_ms) })
  }
  @async.all(tasks[:], max_concurrent=concurrency) catch {
    err => {
      // 单个 probe_port 是 noraise，批量本身只会在被取消（客户端断开）时走到这里。
      // 那就如实标成「没探测」，端口顺序照旧，不编造任何结论。
      let reason = "批量探测中断：" + describe_error(err)
      let out : Array[Probe] = []
      for port in ports {
        out.push({ ..empty_probe(reason), port, })
      }
      out
    }
  }
}

///|
/// 探测一个端口。任何异常都收敛成 reached=false + error 文本，不向外抛。
/// timeout_ms 来自设置 probe.timeoutMs。
pub async fn probe_port(port : Int32, timeout_ms : Int32) -> Probe noraise {
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
  let attempt : async () -> Probe = async fn() {
    let response = fetch_root(port, body_limit_bytes)
    {
      ..base,
      reached: true,
      status: Some(response.code),
      content_type: header_value(response.headers, "Content-Type"),
      body: response.body,
    }
  }
  let result = @async.with_timeout_opt(timeout_ms, attempt) catch {
    err => {
      let spent = (@async.now() - started_at).to_int()
      return { ..base, ms: spent, error: Some(describe_error(err)), }
    }
  }
  let spent = (@async.now() - started_at).to_int()
  match result {
    Some(p) => { ..p, ms: spent, }
    None =>
      {
        ..base,
        ms: spent,
        error: Some("The operation was aborted due to timeout"),
      }
  }
}

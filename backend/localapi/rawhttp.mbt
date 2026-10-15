// 回环探测用的极简 HTTP/1.1 客户端。
//
// 为什么不用 moonbitlang/async/http 的 Client：在服务进程里（moonback handler 的
// 协程上下文）调 `@http.Client(uri, headers~)`，构造函数会抛
// `ResolveHostnameError("Name or service not known")`；同一条调用在 handler 里
// 内联执行是成功的、在独立程序里也是成功的。原因未定位，因此探测改走已验证可用的
// socket 直连：Tcp::connect(Addr::parse("127.0.0.1:<port>"))。
//
// 覆盖面只针对本机回环诊断探测：
//   - 请求写死 "GET / HTTP/1.1" + Host + Accept + Connection: close
//   - 不跟随重定向（等价 Node 的 redirect: 'manual'），3xx 也按原样读
//   - 只读前 limit 字节，读够就断
//   - 支持 Content-Length 定长、chunked 分块、以及读到 EOF 三种收尾

///|
/// 探测接受的头，与 Node 版 probePort 一致。
pub let accept_header : String = "text/html,application/json;q=0.9,*/*;q=0.8"

///|
/// 一次 HTTP 响应。
pub(all) struct RawResponse {
  code : Int
  headers : Array[(String, String)]
  body : String
}

///|
/// 取响应头的值（名字大小写不敏感）；没有给 None。
pub fn header_value(headers : Array[(String, String)], name : String) -> String? {
  let wanted = @json.to_lower(name)
  for pair in headers {
    if @json.to_lower(pair.0) == wanted {
      return Some(pair.1)
    }
  }
  None
}

///|
/// 从 "HTTP/1.1 401 Unauthorized" 里取状态码。
fn parse_status_code(line : String) -> Int {
  let parts = @json.split_ws(line)
  if parts.length() < 2 {
    return 0
  }
  if @json.is_all_digits(parts[1]) {
    @json.parse_dec(parts[1])
  } else {
    0
  }
}

///|
/// 把头部文本（不含结尾空行）拆成 (name, value)。
fn parse_headers(text : String) -> Array[(String, String)] {
  let out : Array[(String, String)] = []
  for line in text.split("\r\n") {
    let raw = line.to_owned()
    if raw == "" {
      continue
    }
    match raw.find(":") {
      Some(i) => out.push((@json.slice(raw, 0, i), @json.trim_both(@json.slice_from(raw, i + 1))))
      None => ()
    }
  }
  out
}

///|
/// 从 "1f\r\n" 里取十六进制块长度。
fn parse_hex_size(line : String) -> Int {
  let parts = @json.split_ws(line)
  if parts.length() == 0 {
    return -1
  }
  let text = parts[0]
  if text == "" {
    return -1
  }
  let mut value = 0
  for ch in text {
    let code = ch.to_int()
    let digit = if code >= 48 && code <= 57 {
      code - 48
    } else if code >= 65 && code <= 70 {
      code - 55
    } else if code >= 97 && code <= 102 {
      code - 87
    } else {
      return -1
    }
    value = value * 16 + digit
  }
  value
}

///|
/// 按字节上限裁剪一个 UTF-8 字符串。
fn truncate_to_bytes(text : String, limit : Int) -> String {
  if @json.utf8_len(text) <= limit {
    return text
  }
  @json.utf8_prefix(text, limit)
}

///|
/// 读响应体，最多 limit 字节，按 Content-Length / chunked / EOF 三种收尾。
async fn read_body(
  sock : @async_socket.Tcp,
  headers : Array[(String, String)],
  limit : Int,
) -> String raise {
  let lowered = match header_value(headers, "Transfer-Encoding") {
    Some(v) => @json.to_lower(v)
    None => ""
  }
  if @json.index_of(lowered, "chunked") is Some(_) {
    return read_chunked(sock, limit)
  }
  let declared = match header_value(headers, "Content-Length") {
    Some(v) => if @json.is_all_digits(v) { @json.parse_dec(v) } else { -1 }
    None => -1
  }
  read_by_length(sock, if declared >= 0 { declared } else { limit }, limit)
}

///|
/// 读到 declared 字节或读到 EOF，最多 limit 字节。
async fn read_by_length(sock : @async_socket.Tcp, declared : Int, limit : Int) -> String raise {
  let chunks : Array[BytesView] = []
  let mut size = 0
  let target = if declared < limit { declared } else { limit }
  while size < target {
    let room = target - size
    let chunk = try {
      sock.read_some(max_len=room)
    } catch {
      _ => break
    }
    match chunk {
      None => break
      Some(data) =>
        if data.length() == 0 {
          break
        } else {
          chunks.push(data[:])
          size = size + data.length()
        }
    }
  }
  @json.read_head(chunks, limit)
}

///|
/// chunked 分块体：按块读，块间换行跳过，遇到 0 长度块收尾。
async fn read_chunked(sock : @async_socket.Tcp, limit : Int) -> String raise {
  let chunks : Array[BytesView] = []
  let mut size = 0
  let mut done = false
  while !done && size < limit {
    let line = match sock.read_until("\r\n") {
      Some(l) => l
      None => break
    }
    let block = parse_hex_size(line)
    if block <= 0 {
      done = true
    } else {
      let want = if block > limit - size { limit - size } else { block }
      let mut got = 0
      while got < block {
        let room = block - got
        let piece = try {
          sock.read_some(max_len=room)
        } catch {
          _ => break
        }
        match piece {
          None => break
          Some(data) =>
            if data.length() == 0 {
              break
            } else {
              if got < want {
                let keep = if data.length() > want - got { want - got } else { data.length() }
                chunks.push(data[:keep])
                size = size + keep
              }
              got = got + data.length()
            }
        }
      }
      // 块末尾的 CRLF
      let _ = sock.read_until("\r\n")
    }
  }
  @json.read_head(chunks, limit)
}

///|
/// 对 127.0.0.1:<port> 发一次 GET /，最多读 limit 字节。
pub async fn fetch_root(port : Int, limit : Int) -> RawResponse raise {
  fetch_path(port, "/", limit)
}

///|
/// 对 127.0.0.1:<port> 发一次 GET <path>，最多读 limit 字节。失败就抛错，由上层收敛成 error 文本。
///
/// path 会被原样写进请求行：调用方只能传自己拼的路径（根路径探测，或 webUrl 的
/// `/?token=<串>`），那个串取自日志、且已经过令牌字符集过滤（见 instances/weburl.mbt），
/// 带不了空格与 CRLF。
pub async fn fetch_path(port : Int, path : String, limit : Int) -> RawResponse raise {
  let addr = try {
    @async_socket.Addr::parse("127.0.0.1:\{port}")
  } catch {
    _ => raise @json.RawHttpError("端口号无法组成回环地址：127.0.0.1:\{port}")
  }
  let sock = try {
    @async_socket.Tcp::connect(addr)
  } catch {
    _ => raise @json.RawHttpError("连接被拒绝：127.0.0.1:\{port}")
  }
  defer sock.close()
  sock.write(
    "GET \{path} HTTP/1.1\r\nHost: 127.0.0.1:\{port}\r\nAccept: \{accept_header}\r\nConnection: close\r\n\r\n",
  )
  let head_raw = match sock.read_until("\r\n\r\n") {
    Some(h) => h
    None => raise @json.RawHttpError("对端没有返回完整的响应头")
  }
  let head = head_raw
  let cut = match head.find("\r\n") {
    Some(i) => i
    None => 0
  }
  let status_line = @json.slice(head, 0, cut)
  let header_text = if head.length() > cut + 2 {
    @json.slice_from(head, cut + 2)
  } else {
    ""
  }
  let headers = parse_headers(header_text)
  let body = read_body(sock, headers, limit)
  { code: parse_status_code(status_line), headers, body: truncate_to_bytes(body, limit) }
}

// 本工程共用的字符串与字节工具。
//
// 这里的函数都是纯计算，不碰文件、不碰网络。

///|
/// 取字符串的副本，避开 String::to_string 的 deprecated 警告。
pub fn owned(view : StringView) -> String {
  view.to_owned()
}

///|
/// JS 正则 \s 认的空白字符（含 \f \v），日志切词时按它对齐。
pub fn is_space(ch : Char) -> Bool {
  ch == ' ' || ch == '\t' || ch == '\n' || ch == '\r' || ch == '\u{000C}' || ch == '\u{000B}'
}

///|
/// 按 JS 的正则空白切词。空串切成空数组。
/// StringBuilder 没有 length()，这里用一个布尔量跟着记有没有内容。
pub fn split_ws(s : String) -> Array[String] {
  let out : Array[String] = []
  let buf = StringBuilder()
  let mut has = false
  for ch in s {
    if is_space(ch) {
      if has {
        out.push(buf.to_string())
        buf.reset()
        has = false
      }
    } else {
      buf.write_char(ch)
      has = true
    }
  }
  if has {
    out.push(buf.to_string())
  }
  out
}

///|
/// 切掉尾部空白，与 JS 的 String#trimEnd 一致。
pub fn trim_end(s : String) -> String {
  let mut end = s.length()
  while end > 0 && is_space(s.unsafe_get(end - 1).unsafe_to_char()) {
    end = end - 1
  }
  s[:end].to_owned()
}

///|
/// 切掉两端空白，与 JS 的 String#trim 一致。
pub fn trim_both(s : String) -> String {
  let mut start = 0
  let mut end = s.length()
  while start < end && is_space(s.unsafe_get(start).unsafe_to_char()) {
    start = start + 1
  }
  while end > start && is_space(s.unsafe_get(end - 1).unsafe_to_char()) {
    end = end - 1
  }
  s[start:end].to_owned()
}

///|
/// 所有空白字符压成一个半角空格，与 JS 的 replace(/\s+/g, ' ') 一致。
pub fn collapse_ws(s : String) -> String {
  let buf = StringBuilder()
  for ch in s {
    buf.write_char(if is_space(ch) { ' ' } else { ch })
  }
  buf.to_string()
}

///|
/// 子串位置，找不到返回 None。
pub fn index_of(haystack : String, needle : String) -> Int? {
  haystack.find(needle)
}

///|
/// 是否以某个前缀开头。空前缀恒为真（与 JS 的 startsWith('') 一致）。
pub fn starts_with(s : String, prefix : String) -> Bool {
  if prefix == "" {
    return true
  }
  s.has_prefix(prefix)
}

///|
/// 是否以某个后缀结尾。空后缀恒为真。
pub fn ends_with(s : String, suffix : String) -> Bool {
  if suffix == "" {
    return true
  }
  s.has_suffix(suffix)
}

///|
/// 全部小写化。bytes 只做 ASCII 小写，用于大小写不敏感的匹配。
pub fn to_lower(s : String) -> String {
  let buf = StringBuilder()
  for ch in s {
    let code = ch.to_int()
    if code >= 65 && code <= 90 {
      buf.write_char((code + 32).unsafe_to_char())
    } else {
      buf.write_char(ch)
    }
  }
  buf.to_string()
}

///|
/// 大小写不敏感的子串查找，返回原串里的下标。
pub fn index_of_ci(haystack : String, needle : String) -> Int? {
  index_of(to_lower(haystack), to_lower(needle))
}

///|
/// 取切片，下标自动收进 [0, length] 区间（比 String::get 安全，不会因为越界 panic）。
pub fn slice(s : String, start : Int, end : Int) -> String {
  let n = s.length()
  let mut a = if start < 0 { 0 } else { start }
  if a > n {
    a = n
  }
  let mut b = if end < 0 { 0 } else { end }
  if b > n {
    b = n
  }
  if b <= a {
    ""
  } else {
    s[a:b].to_owned()
  }
}

///|
/// 从下标处取到末尾。
pub fn slice_from(s : String, start : Int) -> String {
  slice(s, start, s.length())
}

///|
/// UTF-8 字节长度。
pub fn utf8_len(text : String) -> Int {
  @utf8.encode(text).length()
}

///|
/// 按 UTF-8 字节上限截前缀（截断点一定落在字符边界上）。
pub fn utf8_prefix(text : String, limit : Int) -> String {
  let encoded = @utf8.encode(text)
  if encoded.length() <= limit {
    return text
  }
  @utf8.decode_lossy(encoded[:limit], ignore_bom=true)
}

///|
/// 拼接字节块。BytesView 是只读切片，复制进 Bytes 才能继续累积。
pub fn concat_bytes(chunks : Array[BytesView]) -> Bytes {
  let mut total = 0
  for chunk in chunks {
    total = total + chunk.length()
  }
  let buffer : FixedArray[Byte] = FixedArray::make(total, b'\x00')
  let mut at = 0
  for chunk in chunks {
    buffer.blit_from_bytesview(at, chunk)
    at = at + chunk.length()
  }
  Bytes::from_array(buffer)
}

///|
/// 极简 HTTP 客户端抛出的错误。
pub(all) suberror RawHttpError {
  RawHttpError(String)
}

///|
/// 取错误的载荷文本；不是这种错误给 None。
pub fn raw_http_message(err : Error) -> String? {
  match err {
    RawHttpError(msg) => Some(msg)
    _ => None
  }
}

///|
/// 读 /proc 这类纯数字场景：全十进制数字且非空。
pub fn is_all_digits(s : String) -> Bool {
  if s == "" {
    return false
  }
  for ch in s {
    let code = ch.to_int()
    if code < 48 || code > 57 {
      return false
    }
  }
  true
}

///|
/// 十进制字符串转 Int（只喂 is_all_digits 通过的串）。
pub fn parse_dec(s : String) -> Int {
  let mut value = 0
  for ch in s {
    value = value * 10 + (ch.to_int() - 48)
  }
  value
}

///|
/// 十进制字符串转 Int64；非法给 -1。
pub fn parse_dec64(s : String) -> Int64 {
  if !is_all_digits(s) {
    return -1L
  }
  let mut value = 0L
  for ch in s {
    value = value * 10L + (ch.to_int() - 48).to_int64()
  }
  value
}

///|
/// 按 UTF-16 码元逐位比较，等同 JS 的 `a < b` 字符串序。
/// 不能用 String::compare：core 的实现先比长度再比字符，
/// 对 "web" / "headless" 会给出与 JS 相反的顺序。
pub fn compare_code_units(a : String, b : String) -> Int {
  let n = if a.length() < b.length() { a.length() } else { b.length() }
  for i = 0; i < n; i = i + 1 {
    let x = a.unsafe_get(i).to_int()
    let y = b.unsafe_get(i).to_int()
    if x != y {
      return if x < y { -1 } else { 1 }
    }
  }
  if a.length() == b.length() {
    0
  } else if a.length() < b.length() {
    -1
  } else {
    1
  }
}

///|
/// 把若干字节块拼起来解码成 UTF-8 文本（非法字节按替换字符处理），可选截断到 limit 字节。
/// 探测只读前 8KB 靠它；解码在整段上做，多字节字符不会被块边界切断。
pub fn read_head(chunks : Array[BytesView], limit : Int) -> String {
  let kept : Array[BytesView] = []
  let mut size = 0
  for chunk in chunks {
    if size >= limit {
      break
    }
    let room = limit - size
    if chunk.length() <= room {
      kept.push(chunk)
      size = size + chunk.length()
    } else {
      kept.push(chunk[:room])
      size = limit
    }
  }
  if kept.length() == 0 {
    return ""
  }
  @utf8.decode_lossy(concat_bytes(kept), ignore_bom=true)
}

///|
/// 子串出现次数。
pub fn count_occurrences(haystack : String, needle : String) -> Int {
  if needle == "" {
    return 0
  }
  let mut count = 0
  let mut from = 0
  let mut rest = haystack
  while true {
    match rest.find(needle) {
      Some(i) => {
        count = count + 1
        from = i + needle.length()
        rest = slice_from(rest, from)
      }
      None => break
    }
  }
  let _ = from
  count
}

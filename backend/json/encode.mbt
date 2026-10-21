// JSON 编码与时间格式化。
//
// 为什么不用 core 的 Json + stringify：Json 的对象是 Map[String, Json]，
// 序列化后的字段顺序不保证与 Node 版（JSON.stringify 按插入顺序）一致。
// 本包用有序的 JsonVal 自己拼字符串，字段顺序 = 声明顺序，逐字段对齐 Node 版。

///|
/// 有序 JSON 值。字段顺序即构造顺序。
pub(all) enum JsonVal {
  JNull
  JBool(Bool)
  JNum(Double)
  JStr(String)
  JArr(Array[JsonVal])
  JObj(Array[(String, JsonVal)])
}

///|
/// 十进制整数转字符串。
pub fn int_to_dec(n : Int32) -> String {
  if n == 0 {
    return "0"
  }
  let neg = n < 0
  let mut rest = if neg { -n } else { n }
  let digits = StringBuilder()
  while rest > 0 {
    digits.write_char((48 + rest % 10).unsafe_to_char())
    rest = rest / 10
  }
  let out = StringBuilder()
  if neg {
    out.write_char('-')
  }
  let s = digits.to_string()
  for i = s.length() - 1; i >= 0; i = i - 1 {
    out.write_char(s[i].to_int().unsafe_to_char())
  }
  out.to_string()
}

///|
/// Int64 十进制字符串（走 Int 版本；时间戳量级远小于 Int 上限）。
fn int64_to_dec(n : Int64) -> String {
  int_to_dec(n.to_int())
}

///|
/// 转义成 JSON 字符串字面量，转义表与 JS 的 JSON.stringify 一致。
pub fn escape_json_string(s : String) -> String {
  let buf = StringBuilder()
  for ch in s {
    match ch {
      '"' => buf.write_string("\\\"")
      '\\' => buf.write_string("\\\\")
      '\n' => buf.write_string("\\n")
      '\r' => buf.write_string("\\r")
      '\t' => buf.write_string("\\t")
      '\u{0008}' => buf.write_string("\\b")
      '\u{000C}' => buf.write_string("\\f")
      c =>
        if c.to_int() < 0x20 {
          let hex = int_to_hex4(c.to_int())
          buf.write_string("\\u")
          buf.write_string(hex)
        } else {
          buf.write_char(c)
        }
    }
  }
  buf.to_string()
}

///|
/// 4 位小写十六进制。
fn int_to_hex4(n : Int32) -> String {
  let digits = "0123456789abcdef"
  let out = StringBuilder()
  for i = 3; i >= 0; i = i - 1 {
    out.write_char(digits[(n >> (i * 4)) & 0xF].to_int().unsafe_to_char())
  }
  out.to_string()
}

///|
fn render(into : StringBuilder, v : JsonVal) -> Unit {
  match v {
    JNull => into.write_string("null")
    JBool(b) => into.write_string(if b { "true" } else { "false" })
    JNum(d) => into.write_string(d.to_string())
    JStr(s) => {
      into.write_char('"')
      into.write_string(escape_json_string(s))
      into.write_char('"')
    }
    JArr(items) => {
      into.write_char('[')
      for i, item in items {
        if i > 0 {
          into.write_char(',')
        }
        render(into, item)
      }
      into.write_char(']')
    }
    JObj(fields) => {
      into.write_char('{')
      for i, field in fields {
        if i > 0 {
          into.write_char(',')
        }
        into.write_char('"')
        into.write_string(escape_json_string(field.0))
        into.write_string("\":")
        render(into, field.1)
      }
      into.write_char('}')
    }
  }
}

///|
/// 序列化：无空格 minify 风格，字段顺序 = 声明顺序，与 JSON.stringify 一致。
pub fn encode(v : JsonVal) -> String {
  let buf = StringBuilder()
  render(buf, v)
  buf.to_string()
}

///|
/// null 或字符串。
pub fn str_or_null(s : String?) -> JsonVal {
  match s {
    Some(v) => JStr(v)
    None => JNull
  }
}

///|
/// 可空整数字段：None 给 null。
pub fn int_or_null(n : Int32?) -> JsonVal {
  match n {
    Some(v) => JNum(v.to_double())
    None => JNull
  }
}

///|
/// 可空 64 位整数字段（socket inode 用）：None 给 null。
pub fn int64_or_null(n : Int64?) -> JsonVal {
  match n {
    Some(v) => JNum(v.to_double())
    None => JNull
  }
}

///|
/// 整数字段。
pub fn jint(n : Int32) -> JsonVal {
  JNum(n.to_double())
}

///|
/// 布尔数组字段。
pub fn jstr_array(items : Array[String]) -> JsonVal {
  JArr(items.map(fn(s) { JStr(s) }))
}

///|
/// 把 Unix 毫秒时间戳格式化成 JS 的 Date#toISOString 形状：
/// `2026-10-14T10:48:00.680Z`（UTC，毫秒 3 位，年 4 位）。
pub fn iso_from_epoch_ms(ms : Int64) -> String {
  let mut days = ms / 86400000L
  let mut rem = ms % 86400000L
  if rem < 0L {
    rem = rem + 86400000L
    days = days - 1L
  }
  let tod = rem.to_int()
  let hour = tod / 3600000
  let minute = tod % 3600000 / 60000
  let second = tod % 60000 / 1000
  let milli = tod % 1000
  let (year, month, day) = civil_from_days(days)
  let b = StringBuilder()
  pad_num(b, year, 4)
  b.write_char('-')
  pad_num(b, month.to_int64(), 2)
  b.write_char('-')
  pad_num(b, day.to_int64(), 2)
  b.write_char('T')
  pad_num(b, hour.to_int64(), 2)
  b.write_char(':')
  pad_num(b, minute.to_int64(), 2)
  b.write_char(':')
  pad_num(b, second.to_int64(), 2)
  b.write_char('.')
  pad_num(b, milli.to_int64(), 3)
  b.write_char('Z')
  b.to_string()
}

///|
/// localtime_r(3)：某个绝对时刻的本地 UTC 偏移（秒）。取不到给 None。
/// 走 json/local_time.c 的一次 localtime_r —— 核心库与依赖里没有时区换算，
/// 而「本地时间」是使用者看的那块表，不能用 UTC 冒充。
extern "c" fn local_offset_seconds_raw(sec : Int64) -> Int64 = "dsh_console_local_offset_seconds"

///|
/// 本地时区缩写（C 侧写进缓冲区，返回字节数）。取不到返回 0。
#borrow(buf)
extern "c" fn local_zone_name_raw(buf : Bytes, cap : Int32) -> Int32 = "dsh_console_local_zone_name"

///|
/// C 侧取不到偏移时的哨兵值（|真实偏移| 不可能到 86400 秒）。
let local_offset_unknown : Int64 = 1000000000L

///|
/// 把 Unix 毫秒时间戳格式化成**本地时间** `MM-DD HH:MM`（如 `10-15 18:50`）。
/// 取不到本地时区给 None，调用方按「读不到」写原因，不拿 UTC 顶替。
pub fn local_stamp_from_epoch_ms(ms : Int64) -> String? {
  let sec = if ms >= 0L { ms / 1000L } else { (ms - 999L) / 1000L }
  let offset = local_offset_seconds_raw(sec)
  if offset == local_offset_unknown || offset <= -86400L || offset >= 86400L {
    return None
  }
  let local_ms = ms + offset * 1000L
  let mut days = local_ms / 86400000L
  let mut rem = local_ms % 86400000L
  if rem < 0L {
    rem = rem + 86400000L
    days = days - 1L
  }
  let tod = rem.to_int()
  let (_, month, day) = civil_from_days(days)
  let b = StringBuilder()
  pad_num(b, month.to_int64(), 2)
  b.write_char('-')
  pad_num(b, day.to_int64(), 2)
  b.write_char(' ')
  pad_num(b, (tod / 3600000).to_int64(), 2)
  b.write_char(':')
  pad_num(b, (tod % 3600000 / 60000).to_int64(), 2)
  Some(b.to_string())
}

///|
/// 本地时区名（如 `CST`）。取不到给 None —— 只是给人看的补充，
/// 拿不到时调用方照旧写时间，不写时区。
pub fn local_zone_name() -> String? {
  let probe = local_offset_seconds_raw(0L)
  if probe == local_offset_unknown {
    return None
  }
  let buf = Bytes::make(64, b'\x00')
  let n = local_zone_name_raw(buf, 64)
  if n <= 0 {
    None
  } else {
    Some(@utf8.decode_lossy(buf[:n], ignore_bom=true))
  }
}

///|
fn pad_num(b : StringBuilder, value : Int64, width : Int32) -> Unit {
  let s = int64_to_dec(value)
  let mut pad = width - s.length()
  while pad > 0 {
    b.write_char('0')
    pad = pad - 1
  }
  b.write_string(s)
}

///|
/// 把一条完整 ISO8601 时间戳（形如 2026-10-14T11:12:05.680Z）取成时间部分 "11:12:05"。
/// 判据与 Node 版 readLogs.mjs 的 `^(\d{4}-\d{2}-\d{2})T(\d{2}:\d{2}:\d{2}(?:\.\d{1,3})?)` 等价：
/// 日期三段与时间三段必须是纯数字，小数部分 1..3 位。对不上返回 None。
fn code_at(value : String, i : Int32) -> Char {
  value.unsafe_get(i).unsafe_to_char()
}

///|
pub fn iso_time_part(value : String) -> String? {
  // 结构位：0123456789...  YYYY-MM-DDTHH:MM:SS[.fff]
  let n = value.length()
  if n < 19 {
    return None
  }
  if code_at(value, 4) != '-' ||
    code_at(value, 7) != '-' ||
    code_at(value, 10) != 'T' {
    return None
  }
  if code_at(value, 13) != ':' || code_at(value, 16) != ':' {
    return None
  }
  let digit_positions = [0, 1, 2, 3, 5, 6, 8, 9, 11, 12, 14, 15, 17, 18]
  for i in digit_positions {
    let c = value.unsafe_get(i).to_int()
    if c < 48 || c > 57 {
      return None
    }
  }
  let mut end = 19
  if n > 19 && code_at(value, 19) == '.' {
    let mut k = 20
    while k < n && k - 20 < 3 {
      let c = value.unsafe_get(k).to_int()
      if c < 48 || c > 57 {
        break
      }
      k = k + 1
    }
    if k > 20 {
      end = k
    }
  }
  Some(value[11:end].to_owned())
}

///|
/// 天数（自 1970-01-01）转公历。Howard Hinnant 的 civil_from_days 算法。
fn civil_from_days(days : Int64) -> (Int64, Int32, Int32) {
  let z = days + 719468L
  let era = (if z >= 0L { z } else { z - 146096L }) / 146097L
  let doe = z - era * 146097L
  let yoe = (doe - doe / 1460L + doe / 36524L - doe / 146096L) / 365L
  let y = yoe + era * 400L
  let doy = doe - (365L * yoe + yoe / 4L - yoe / 100L)
  let mp = (5L * doy + 2L) / 153L
  let d = doy - (153L * mp + 2L) / 5L + 1L
  let m = if mp < 10L { mp + 3L } else { mp - 9L }
  (if m <= 2L { y + 1L } else { y }, m.to_int(), d.to_int())
}

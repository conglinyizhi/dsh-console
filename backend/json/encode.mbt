// JSON 编码与时间格式化。
//
// 为什么不用 core 的 Json + stringify：@json.Json 的对象是 Map[String, Json]，
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
pub fn int_to_dec(n : Int) -> String {
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
fn int_to_hex4(n : Int) -> String {
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
/// 整数字段。
pub fn jint(n : Int) -> JsonVal {
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
fn pad_num(b : StringBuilder, value : Int64, width : Int) -> Unit {
  let s = int64_to_dec(value)
  let mut pad = width - s.length()
  while pad > 0 {
    b.write_char('0')
    pad = pad - 1
  }
  b.write_string(s)
}

///|
/// 天数（自 1970-01-01）转公历。Howard Hinnant 的 civil_from_days 算法。
fn civil_from_days(days : Int64) -> (Int64, Int, Int) {
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
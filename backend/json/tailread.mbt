// 反向分块读文件尾部。口径逐条对齐 Node 版 server/readLogs.mjs 的 readTailLines：
//
//   - 从文件末尾往回 64KB 起读，行数不够就翻倍，单次窗口封顶 4MB
//   - 文件小于初始窗口时窗口就是整个文件（atStart 为真，首行即文件首行）
//   - 行数多于 tail 时，只保留末尾 tail 行（此时首行可能是被窗口切断的半行，正好被丢掉）
//   - 窗口内只容得下 1 行时不算「拿到了 tail 行」，如实回 truncated + note
//
// 与 Node 的差异只有一条：Node 用 openSync + readSync 就地读，这里用 @fs.open(ReadOnly)
// 加 File::read_at 定点读。两者都不写文件，也不整份读进内存。

///|
/// 一次尾部读取的结果。
pub struct TailRead {
  raw_lines : Array[String]
  truncated : Bool
  note : String?
  window_bytes : Int32
  size : Int64
}

///|
/// 尾部读取失败：带一条人话原因，不抛异常。
pub suberror TailError {
  TailError(String)
}

///|
/// 首次窗口 64KB。
let initial_window_bytes : Int64 = 65536L

///|
/// 单次窗口上限 4MB。
let max_window_bytes : Int64 = 4194304L

///|
/// 按 \n 切分，保留空行（与 JS 的 String#split('\n') 一致）。
fn split_lines(s : String) -> Array[String] {
  let out : Array[String] = []
  let buf = StringBuilder()
  for ch in s {
    if ch == '\n' {
      out.push(buf.to_string())
      buf.reset()
    } else {
      buf.write_char(ch)
    }
  }
  out.push(buf.to_string())
  out
}

///|
/// 反向分块读尾：读够 tail 行，或者读到头、读满窗口。
pub async fn read_tail_lines(
  file : String,
  tail : Int32,
) -> TailRead raise TailError {
  // 读文件状态失败也走两段式入口；json 包够不到 store，原文在这里落不了，只留结论
  let size = match file_size_fs(file) {
    Ok(v) => v
    Err(e) => {
      raise TailError(e.summary)
    }
  }
  if size == 0L {
    return {
      raw_lines: [],
      truncated: false,
      note: None,
      window_bytes: 0,
      size: 0L,
    }
  }
  // 结论只留一句（json 包够不到 store，记不了 raw）：打开失败就是打开失败
  let handle = @fs.open(file, mode=ReadOnly) catch {
    _ => raise TailError("打开文件失败")
  }
  defer handle.close()
  // 文件可能正在被写：以 fd 自己的 size 为准，不用前面那份可能过期的
  let actual = handle.size() catch {
    _ => raise TailError("读文件状态失败")
  }
  if actual == 0L {
    return {
      raw_lines: [],
      truncated: false,
      note: None,
      window_bytes: 0,
      size: 0L,
    }
  }

  let mut window_bytes = 0L
  let mut window_for_note = 0
  let mut chunk = ""
  let mut at_start = false
  let mut done = false
  while !done {
    let next = if window_bytes == 0L {
      initial_window_bytes
    } else {
      window_bytes * 2L
    }
    window_bytes = if next > actual { actual } else { next }
    window_for_note = window_bytes.to_int()
    let start = actual - window_bytes
    at_start = start <= 0L
    let read_len = (actual - start).to_int()
    chunk = match read_text_at_fs(file, start, read_len) {
      Ok(t) => t
      Err(e) => {
      raise TailError(e.summary)
    }
    }
    let parts = split_lines(chunk)
    let head_count = parts.length() - 1
    let enough = at_start ||
      head_count >= tail ||
      window_bytes >= max_window_bytes
    if enough {
      done = true
    }
  }

  // 行数比 tail 多：首行可能是被窗口截断的半行，去掉
  let mut raw_lines = split_lines(chunk)
  if raw_lines.length() > 0 && raw_lines[raw_lines.length() - 1] == "" {
    raw_lines = raw_lines[:raw_lines.length() - 1].to_owned()
  }
  if !at_start && raw_lines.length() > tail {
    raw_lines = raw_lines[raw_lines.length() - tail:].to_owned()
  }
  let thin = !at_start && raw_lines.length() <= 1
  {
    raw_lines,
    truncated: thin,
    note: if thin {
      Some(
        "尾部窗口 \{window_for_note} 字节内只容得下 1 行，这一行可能被截断",
      )
    } else {
      None
    },
    window_bytes: window_for_note,
    size: actual,
  }
}

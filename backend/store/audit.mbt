// 审计：audit.jsonl —— 每个动作追加一行，超过阈值就滚动（契约第五节）。
//
// 一行一个 JSON 对象，字段固定：at / action / params / ok / code / message / outcome。
//
// 滚动口径（README「运行时登记、归档与审计」一节写了同一份）：
//   · 触发：现有文件字节数 > audit_max_bytes（缺省 8 MiB）
//   · 落点：旧文件原样改名到同目录的 .archive/audit-<UTC 时间戳>.jsonl，不覆盖上一份
//     （时间戳撞了就顺延 -1、-2 ……）
//   · 新文件：保留旧文件的最近 audit_retain_lines 条（缺省 2000 条），
//     后面紧跟本次要追加的那行 —— 保留的那些与新行都不丢
//   · 轮转本身留痕：新文件第一条就是 action="audit-rotate" 的说明行
//     （写明原文件多少行 / 多少字节、归档到哪个路径、本次保留了多少条）。
//     审计不能出现无声的断口，所以这条不是可选装饰，是契约的一部分
//   · 归档目录本身也有上限：只留最近 audit_archive_keep 份（缺省 40），更老的删掉。
//     没有这一条，滚动只是把无限增长从主文件挪到归档目录
//   · 写入顺序（顺序很要紧，实测踩过：先写主文件再 rename 主文件，会把新内容搬进归档、
//     旧流水留在主文件位置上）：
//       ① 把「说明条 + 保留的最近若干条」写成归档文件（内容全量、句柄关掉）
//       ② rename(主文件 -> 归档名)：这一步之后完整旧流水在归档里，可读；主文件短暂不存在
//       ③ 再把同样的内容写成主文件（临时文件 + rename 就位）
//     中间态只有「主文件短暂不存在」，读侧遇到就回退读最近的归档（audit_read_path），
//     不会读成「审计空了」
//   · 并发：整个过程持 audit_write_lock（进程内互斥），否则一笔滚动的两次 rename 会把
//     另一笔刚追加的行落到被 rename 走的旧 inode 上（实测阈值 1 字节 + 100 并发时会丢行）
//
// 失败口径与从前一致：滚动失败只说「这次没滚成」，不让动作失败
// （动作已经发生了，谎报失败更糟）：原因交给调用方写进响应 note。
//
// 三个数可以用 DSH_CONSOLE_AUDIT_MAX_BYTES / DSH_CONSOLE_AUDIT_RETAIN_LINES /
// DSH_CONSOLE_AUDIT_ARCHIVE_KEEP 覆盖 —— 只为自己跑一次真实滚动用
// （缺省值就是生产口径，README 写死了这三个数）。

///|
/// 滚动阈值（字节）。缺省 8 MiB。
let audit_max_bytes_default : Int64 = 8388608L

///|
/// 滚动后新文件保留的最近条数。缺省 2000 条。
let audit_retain_lines_default : Int32 = 2000

///|
/// 归档旧文件用的目录名（相对状态目录）。
let audit_archive_dir : String = ".archive"

///|
/// 归档目录里最多留几份（更老的那份删掉）。
///
/// 没有这一条，滚动只是把无限增长从主文件挪到归档目录：阈值 1 字节的极端口径下
/// 实测主文件稳在保留条数上，归档却一份一份地涨。
/// 缺省 40 份：按 8 MiB 阈值估，一份归档最多约 8 MiB，40 份把归档上限压在 320 MiB 上下，
/// 同时留着 40 次滚动窗口之前的历史 —— 要更长历史就调大它，或者自己备份归档目录。
let audit_archive_keep_default : Int32 = 40

///|
/// 归档文件名前缀。
let audit_archive_prefix : String = "audit-"

///|
/// 归档文件名后缀，也是主审计文件的后缀。
let audit_archive_suffix : String = ".jsonl"

///|
/// 组装一行审计。
pub fn audit_line(
  at : String,
  action : String,
  params : @json.JsonVal,
  ok : Bool,
  code : String?,
  message : String?,
  outcome : @json.JsonVal,
) -> @json.JsonVal {
  @json.JObj([
    ("at", @json.JStr(at)),
    ("action", @json.JStr(action)),
    ("params", params),
    ("ok", @json.JBool(ok)),
    ("code", @json.str_or_null(code)),
    ("message", @json.str_or_null(message)),
    ("outcome", outcome),
  ])
}

///|
/// 审计写入的进程内互斥锁。
///
/// 「先读旧文件、再写新文件、再两次 rename」这套滚动在并发下会互相踩：
/// 一笔替换主文件的同时另一笔正在追加，追加的那行就落在被 rename 走的旧 inode 上，
/// 谁都不再读它（实测：阈值 1 字节、100 条并发时丢掉大半）。
/// 加锁之后每笔「滚动 + 追加」是串行的，不再有交错。
///
/// 进程外并发（同时跑两个后端）不在这把锁的射程内，也不在本工程契约里：
/// 控制台后端只有一个（README「运行时登记、归档与审计」一节写明了这个前提）。
let audit_write_lock : @async.Mutex = @async.Mutex::Mutex()

///|
/// 追加时最多试几次：并发的两笔写会撞同一个临时文件名（临时名 = 目标 + pid + 毫秒，
/// 同一毫秒里两个写者算出来是同一个），谁先 rename 走谁成功，另一个 ENOENT。
/// 撞了就等一下重来一次 —— 审计行宁可重试，不该因为并发而丢。
let append_attempts : Int32 = 6

///|
/// 临时文件被并发写者先搬走时 @fsx 回的原文。匹配字符串是脆的，
/// 但比「并发下偶发丢行」好：撞上就重试，重试到上限才如实回失败。
let tmp_race_marker : String = "rename 到目标失败"

///|
/// 追加一行。
///
/// 追加前看一眼文件大小：超了就先把旧文件滚走（保留最近若干条 + 一条滚动说明），
/// 再把这一行写上去。全程 noraise：滚动失败也只回 Err，由调用方决定怎么提。
/// 滚动成功时那一行说明已经落在新文件里了，不往响应 note 里塞（note 只报坏事）。
pub async fn append_audit(line : @json.JsonVal) -> Result[Unit, String] noraise {
  audit_write_lock.acquire()
  let result = append_audit_locked(line)
  audit_write_lock.release()
  result
}

///|
/// 真正的追加 + 滚动。调用方必须已经持有 audit_write_lock。
async fn append_audit_locked(
  line : @json.JsonVal,
) -> Result[Unit, String] noraise {
  let paths = state_paths()
  let text = @json.encode(line) + "\n"
  let rolled = rotate_if_needed(paths.audit)
  let mut attempt = 0
  let mut last = ""
  while attempt < append_attempts {
    match @fsx.append_text(paths.audit, text) {
      Ok(_) => return Ok(())
      Err(e) =>
        if e.contains(tmp_race_marker) && attempt + 1 < append_attempts {
          last = e
          attempt = attempt + 1
          @async.sleep(2 + attempt)
          continue
        } else {
          let why = match rolled {
            Some(note) =>
              e + "；另外这一次审计滚动没做成：" + note
            None => e
          }
          return Err(why)
        }
    }
  }
  Err(
    "追加审计连试 " +
    append_attempts.to_string() +
    " 次都撞上并发：" +
    last,
  )
}

///|
/// 大文件按需滚动。返回 None 表示「没滚 / 不用滚」，Some 是没滚成的原因。
///
/// 顺序固定：先建归档目录、再把新内容写成临时文件、再 rename(旧 -> 归档)、
/// 最后 rename(临时 -> 主文件)。中途失败时旧流水仍在原地（或已在归档里），不丢。
async fn rotate_if_needed(file : String) -> String? noraise {
  let size = match @json.file_size(file) {
    Some(s) => s
    None => return None
  }
  if size <= audit_max_bytes() {
    return None
  }
  let lines = match read_lines(file) {
    Ok(l) => l
    Err(e) => return Some(e)
  }
  let total_lines = lines.length()
  if total_lines == 0 {
    return None
  }
  let archive = match archive_path(file) {
    Ok(p) => p
    Err(e) => return Some(e)
  }
  // 归档目录要先在：rename(2) 不会替我们建父目录，缺目录时它直接 ENOENT。
  let archive_dir = @json.dirname(archive)
  match @fsx.ensure_dir_fs(archive_dir) {
    Ok(_) => ()
    Err(e) => {
      note_raw(e.raw)
      return Some("建目录失败")
    }
  }
  let keep = audit_retain_lines()
  let keep_count = if total_lines < keep { total_lines } else { keep }
  let kept = lines[total_lines - keep_count:]
  // 新主文件 = 一条滚动说明 + 保留的最近若干条；调用方接着追加本次这一行
  let note = rotation_note(
    @json.iso_from_epoch_ms(@async.now()),
    size,
    total_lines,
    archive,
    kept.length(),
  )
  let out = StringBuilder()
  out.write_string(@json.encode(note))
  out.write_char('\n')
  for kept_line in kept {
    out.write_string(kept_line)
    out.write_char('\n')
  }
  // ① 新内容先落到临时文件；write_text_atomic 会把临时文件 rename 到目标路径上，
  //    这里的目标就是归档名 —— 内容是「旧文件的最近若干条 + 说明条」，
  //    完整流水仍然是旧文件本身（下一步改名过去）
  match @fsx.write_text_atomic_fs(archive, out.to_string()) {
    Ok(_) => ()
    Err(e) => {
      note_raw(e.raw)
      return Some("写文件失败")
    }
  }
  // ② 旧文件改名到归档：从这一步起旧流水在归档里，完整可读
  match @fsx.rename_path(file, archive, replace=true) {
    Ok(_) => ()
    Err(e) => return Some("旧审计文件没归档成：" + e)
  }
  // ③ 新主文件就位：同样走临时文件 + rename，写的时候主文件路径上是空的（上一步刚搬走）
  match @fsx.write_text_atomic_fs(file, out.to_string()) {
    Ok(_) => ()
    Err(e) => {
      note_raw(e.raw)
      return Some("写文件失败")
    }
  }
  // ④ 归档目录留最近 audit_archive_keep() 份，更老的删掉（保历史，也保磁盘）
  prune_archives(archive, audit_archive_keep())
  None
}

///|
/// 归档目录修剪：按文件名（时间戳前缀定长）排序，只留最近 keep 份。
/// 刚滚出去的那一份一定在 keep 之内 —— keep 至少 1，且它是最新的一份。
/// 删不动不报错：删不掉只是多占点盘，不该把「审计已经滚好了」这件事说成失败。
async fn prune_archives(newest : String, keep : Int32) -> Unit noraise {
  if keep < 1 {
    return
  }
  let dir = @json.dirname(newest)
  let names = match @json.list_dir_result(dir) {
    Ok(l) => l
    Err(_) => return
  }
  let archives : Array[String] = []
  for name in names {
    if @json.starts_with(name, audit_archive_prefix) &&
      name.has_suffix(audit_archive_suffix) {
      archives.push(name)
    }
  }
  if archives.length() <= keep {
    return
  }
  let sorted = archives.copy()
  sorted.sort()
  for i = 0; i < sorted.length() - keep; i = i + 1 {
    let _ = @fsx.remove_file_fs(@json.join_path(dir, sorted[i]))
  }
}

///|
/// 归档保留份数：环境变量给了合法正整数就用它，否则缺省。
async fn audit_archive_keep() -> Int32 noraise {
  match @json.env_value("DSH_CONSOLE_AUDIT_ARCHIVE_KEEP") {
    Some(raw) =>
      if @json.is_all_digits(raw) && @json.parse_dec(raw) > 0 {
        @json.parse_dec(raw)
      } else {
        audit_archive_keep_default
      }
    None => audit_archive_keep_default
  }
}

///|
/// 轮转说明行。这不是一条动作，是审计自己的留痕：
/// 谁在什么时候因为超限滚了一次、原文件多大、归档在哪、新文件留了多少条。
fn rotation_note(
  at : String,
  bytes : Int64,
  lines : Int32,
  archive : String,
  kept : Int32,
) -> @json.JsonVal {
  let message = "因超限轮转：原文件 " +
    lines.to_string() +
    " 行 / " +
    bytes.to_string() +
    " 字节已归档到 " +
    archive +
    "，本文件保留最近 " +
    kept.to_string() +
    " 条"
  @json.JObj([
    ("at", @json.JStr(at)),
    ("action", @json.JStr("audit-rotate")),
    (
      "params",
      @json.JObj([
        ("reason", @json.JStr("over-limit")),
        ("archivedPath", @json.JStr(archive)),
        ("sourceLines", @json.jint(lines)),
        ("sourceBytes", @json.JNum(bytes.to_double())),
        ("keptLines", @json.jint(kept)),
      ]),
    ),
    ("ok", @json.JBool(true)),
    ("code", @json.JNull),
    ("message", @json.JStr(message)),
    (
      "outcome",
      @json.JObj([
        ("archivedPath", @json.JStr(archive)),
        ("archivedLines", @json.jint(lines)),
        ("archivedBytes", @json.JNum(bytes.to_double())),
        ("keptLines", @json.jint(kept)),
      ]),
    ),
  ])
}

///|
/// 读一行行的文本；末尾那个换行不算空行。
async fn read_lines(file : String) -> Result[Array[String], String] noraise {
  let text = match @json.read_text_file(file) {
    Ok(t) => t
    Err(e) => return Err("读不动审计文件 " + file + "：" + e)
  }
  let n = text.length()
  let body = if n > 0 && text[n - 1] == '\n' {
    @json.slice(text, 0, n - 1)
  } else {
    text
  }
  let out : Array[String] = []
  for part in body.split("\n") {
    out.push(part.to_owned())
  }
  Ok(out)
}

///|
/// 本次归档落点：.archive/audit-<时间戳>.jsonl，同名就顺延 -1、-2 ……
/// 时间戳精确到毫秒还撞名，只可能是同一毫秒里滚了两次，顺延之后仍不会覆盖上一份。
async fn archive_path(file : String) -> Result[String, String] noraise {
  let stamp = archive_stamp(@json.iso_from_epoch_ms(@async.now()))
  let dir = @json.join_path(@json.dirname(file), audit_archive_dir)
  let base = audit_archive_prefix + stamp
  let mut attempt = 0
  while attempt < 1000 {
    let name = if attempt == 0 {
      base + audit_archive_suffix
    } else {
      base + "-" + attempt.to_string() + audit_archive_suffix
    }
    let candidate = @json.join_path(dir, name)
    if !@json.exists(candidate) {
      return Ok(candidate)
    }
    attempt = attempt + 1
  }
  Err("归档文件名连试 1000 个都被占了（目录 " + dir + "）")
}

///|
/// ISO 时间戳转成能当文件名的样子：2026-10-15T09:52:36.883Z -> 2026-10-15T09-52-36-883Z。
/// 只换掉冒号和句点，别的字符原样留着（时间戳是自己造的，不猜别的形状）。
fn archive_stamp(iso : String) -> String {
  let out = StringBuilder()
  for ch in iso {
    if ch == ':' || ch == '.' {
      out.write_char('-')
    } else {
      out.write_char(ch)
    }
  }
  out.to_string()
}

///|
/// 读侧用的审计文件：主文件有内容就用主文件；主文件不存在或为空（刚滚过、或滚动
/// 三步里第二步与第三步之间被打断）就退回最近的一份归档 —— 滚动不该让审计突然读不到。
pub async fn audit_read_path(audit : String) -> String noraise {
  let size = match @json.file_size(audit) {
    Some(s) => s
    None => 0L
  }
  if size > 0L {
    return audit
  }
  match newest_archive(audit) {
    Some(p) => p
    None => audit
  }
}

///|
/// 归档目录里最新的一份（按文件名比，时间戳前缀定长，字典序就是时间序）。
async fn newest_archive(audit : String) -> String? noraise {
  let dir = @json.join_path(@json.dirname(audit), audit_archive_dir)
  let names = match @json.list_dir_result(dir) {
    Ok(l) => l
    Err(_) => return None
  }
  let base = @json.basename(audit)
  let prefix = @json.slice(base, 0, base_prefix_len(base))
  let mut best : String? = None
  for name in names {
    if !@json.starts_with(name, prefix) ||
      !name.has_suffix(audit_archive_suffix) {
      continue
    }
    match best {
      None => best = Some(name)
      Some(current) => if name > current { best = Some(name) }
    }
  }
  match best {
    Some(name) => Some(@json.join_path(dir, name))
    None => None
  }
}

///|
/// 主文件去掉 .jsonl 后缀的那一段：audit.jsonl -> "audit"，归档名拿它当前缀配对。
fn base_prefix_len(base : String) -> Int32 {
  if base.has_suffix(audit_archive_suffix) {
    base.length() - audit_archive_suffix.length()
  } else {
    base.length()
  }
}

///|
/// 滚动阈值：环境变量给了合法正整数就用它，否则缺省 8 MiB。
/// 只是自测（把阈值调小跑一次真滚动）与运维临时收紧用，不作为设置项。
async fn audit_max_bytes() -> Int64 noraise {
  match @json.env_value("DSH_CONSOLE_AUDIT_MAX_BYTES") {
    Some(raw) =>
      if @json.is_all_digits(raw) && @json.parse_dec(raw) > 0 {
        @json.parse_dec(raw).to_int64()
      } else {
        audit_max_bytes_default
      }
    None => audit_max_bytes_default
  }
}

///|
/// 保留条数：同上，非法值按缺省。
async fn audit_retain_lines() -> Int32 noraise {
  match @json.env_value("DSH_CONSOLE_AUDIT_RETAIN_LINES") {
    Some(raw) =>
      if @json.is_all_digits(raw) && @json.parse_dec(raw) > 0 {
        @json.parse_dec(raw)
      } else {
        audit_retain_lines_default
      }
    None => audit_retain_lines_default
  }
}

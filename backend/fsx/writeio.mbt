// 写侧文件 IO 与进程信号 —— 本工程「写能力」的唯一入口。
//
// 与 json/fsio.mbt（只读入口）分开是有意的：只读那套是接口的形状，一个字段都不动；
// 这里只管写，而且写的目标只允许三类（README「读写分层」一节逐条列了）：
//   1. $XDG_STATE_HOME/dsh-console/ 下的 settings.json / runtime.json / archive.json / audit.jsonl
//   2. 动作直接作用的 profile 目录（派生 / 重命名 / 删除进回收站 / 写备注 .dsh-note.txt）
//   3. 被启动实例自己 DSH_HOME 下的 logs/console-<profile>-<port>.log
//
// 失败一律给 Result[_, String]，不抛异常：调用方按错误码映射成人话再回给前端。
// 唯一的 FFI 是 proc_signal.c 的 kill(2) / getpid(2)：给已有 PID 发信号没有别的原语。

///|
/// kill(2)：给 PID 发信号。
extern "c" fn kill_raw(pid : Int32, sig : Int32) -> Int32 = "dsh_console_kill"

///|
/// kill(pid, 0)：只做存在性与权限判断，不真发信号。
extern "c" fn pid_alive_raw(pid : Int32) -> Int32 = "dsh_console_pid_alive"

///|
/// getpid(2)：原子写的临时文件名用它区分不同进程。
extern "c" fn getpid_raw() -> Int32 = "dsh_console_getpid"

///|
/// stat(2) 的 st_dev：移动目录之前判「两边在不在同一个文件系统」。
/// 失败返回负 errno（见 dev_id.c 的边界说明）。
#borrow(path)
extern "c" fn dev_raw(path : Bytes) -> Int64 = "dsh_console_dev"

///|
/// SIGTERM：先礼。
pub let sigterm : Int32 = 15

///|
/// SIGKILL：后兵。
pub let sigkill : Int32 = 9

///|
/// 本进程 PID。
pub fn os_pid() -> Int32 {
  getpid_raw()
}

///|
/// errno 名。只列这条路径上会遇到的几个，其余给数字，不编名字。
fn errno_name(code : Int32) -> String {
  match code {
    1 => "EPERM 不允许的操作"
    2 => "ENOENT 目标不存在"
    3 => "ESRCH 没有这个进程"
    13 => "EACCES 权限不足"
    17 => "EEXIST 已存在"
    18 => "EXDEV 跨文件系统"
    20 => "ENOTDIR 路径中有非目录"
    21 => "EISDIR 目标是目录"
    22 => "EINVAL 参数非法"
    28 => "ENOSPC 空间不足"
    30 => "EROFS 只读文件系统"
    39 => "ENOTEMPTY 目录非空"
    _ => "errno " + code.to_string()
  }
}

///|
/// 给人发信号。成功 Ok，失败带 errno 名。
pub fn send_signal(pid : Int32, sig : Int32) -> Result[Unit, String] {
  if pid <= 0 {
    return Err("PID 非法：" + pid.to_string())
  }
  let code = kill_raw(pid, sig)
  if code == 0 {
    Ok(())
  } else {
    Err(
      "kill(" +
      pid.to_string() +
      ", " +
      sig.to_string() +
      ") 失败：" +
      errno_name(-code),
    )
  }
}

///|
/// 进程还在不在（权限不足按「在」算，不误报成退出）。
pub fn pid_alive(pid : Int32) -> Bool {
  pid > 0 && pid_alive_raw(pid) == 1
}

///|
/// 一条路径所在的文件系统（stat 的 st_dev）。读不到给 Err（带 errno 名）。
///
/// 移动目录之前必须过这一道：rename(2) 跨文件系统会给 EXDEV，退化成「复制再删」之后
/// 体积一大就不是瞬时的，而使用者要的是「移动」这件事本身。
pub fn dev_of(path : String) -> Result[Int64, String] {
  let code = dev_raw(@utf8.encode(path))
  if code < 0 {
    Err(
      "读不到 " +
      path +
      " 所在文件系统的设备号：" +
      errno_name(-code.to_int()),
    )
  } else {
    Ok(code)
  }
}

///|
/// 一次目录复制的统计。
pub struct CopyStats {
  mut files : Int32
  mut dirs : Int32
  /// 被跳过的名字（每个名字只记一次）
  skipped : Array[String]
}

///|
/// 名字是否在表里。
fn name_in(list : Array[String], name : String) -> Bool {
  list.any(fn(s) { s == name })
}

///|
/// 建目录（递归，已存在不算错）。
async fn ensure_dir_impl(path : String) -> Result[Unit, String] noraise {
  if path == "" {
    return Err("目录路径为空")
  }
  try {
    @fs.mkdir(path, recursive=true, allow_exist=true)
    Ok(())
  } catch {
    err => Err("建目录失败：" + path + "（" + err.to_string() + "）")
  }
}

///|
/// 临时文件名里的进程内序号。
///
/// 只用 pid + 毫秒是不够的：同一毫秒里两个并发写者算出来是同一个名字，
/// 一个写、另一个 rename，先 rename 走的那个把名字搬空、另一个 ENOENT，
/// 更坏的情况是两笔内容被追加进同一个临时文件，rename 之后就多出半截行
/// （审计行与设置都实测复现过）。序号在同一进程里同步自增，够用。
///
/// Ref 是模块级可变量的载体（actions/instance.mbt 的 console_group 同款写法）：
/// MoonBit 的顶层 `let mut` 不作为全局可变量，要可变量得用 Ref。
let tmp_seq : Ref[Int32] = { val: 0, }

///|
/// 取下一个序号。调用点在 write_text_atomic 的第一个 await 之前，不存在交错。
fn next_tmp_seq() -> Int32 {
  tmp_seq.val = tmp_seq.val + 1
  tmp_seq.val
}

///|
/// 原子写文本：先写同目录的临时文件，再 rename 覆盖。
/// 临时文件与目标同目录是有意的 —— 跨文件系统的 rename 不是原子的，也会 EXDEV。
async fn write_text_atomic_impl(
  path : String,
  text : String,
) -> Result[Unit, String] noraise {
  let dir = @json.dirname(path)
  match ensure_dir_impl(dir) {
    Ok(_) => ()
    Err(e) => return Err(e)
  }
  let tmp = path +
    ".tmp-" +
    os_pid().to_string() +
    "-" +
    @async.now().to_string() +
    "-" +
    next_tmp_seq().to_string()
  @fs.write_file(tmp, text, create_mode=CreateOrTruncate, permission=0o600) catch {
    err =>
      return Err(
        "写临时文件失败：" + tmp + "（" + err.to_string() + "）",
      )
  }
  try {
    @fs.rename(tmp, path, replace=true)
    Ok(())
  } catch {
    err => {
      // 留着临时文件就是脏数据，先尽力收掉
      let _ = @fs.remove(tmp) catch { _ => () }
      Err("rename 到目标失败：" + path + "（" + err.to_string() + "）")
    }
  }
}

///|
/// 追加一行到文件（audit.jsonl 用）。文件不存在就建。
pub async fn append_text(
  path : String,
  text : String,
) -> Result[Unit, String] noraise {
  let dir = @json.dirname(path)
  match ensure_dir_impl(dir) {
    Ok(_) => ()
    Err(e) => return Err(e)
  }
  try {
    @fs.write_file(
      path,
      text,
      create_mode=OpenOrCreate,
      append=true,
      permission=0o600,
    )
    Ok(())
  } catch {
    err => Err("追加写失败：" + path + "（" + err.to_string() + "）")
  }
}

///|
/// 覆盖写文本（非原子）。给不需要原子性的场景用；settings / runtime / archive 一律走原子版。
pub async fn write_text(
  path : String,
  text : String,
) -> Result[Unit, String] noraise {
  let dir = @json.dirname(path)
  match ensure_dir_impl(dir) {
    Ok(_) => ()
    Err(e) => return Err(e)
  }
  try {
    @fs.write_file(path, text, create_mode=CreateOrTruncate, permission=0o600)
    Ok(())
  } catch {
    err => Err("写文件失败：" + path + "（" + err.to_string() + "）")
  }
}

///|
/// 读原始字节。复制文件用 —— 不经过 UTF-8 解码，二进制不会被改写。
pub async fn read_bytes(path : String) -> Result[Bytes, String] noraise {
  Ok(@fs.read_file(path).binary()) catch {
    err => Err("读不到 " + path + "：" + err.to_string())
  }
}

///|
/// 按字节写文件。
async fn write_bytes_impl(
  path : String,
  data : Bytes,
  permission~ : Int32 = 0o600,
) -> Result[Unit, String] noraise {
  let dir = @json.dirname(path)
  match ensure_dir_impl(dir) {
    Ok(_) => ()
    Err(e) => return Err(e)
  }
  try {
    @fs.write_file(path, data, create_mode=CreateOrTruncate, permission~)
    Ok(())
  } catch {
    err => Err("写文件失败：" + path + "（" + err.to_string() + "）")
  }
}

///|
/// 路径存在与否。
pub async fn path_exists(path : String) -> Bool noraise {
  @json.exists(path)
}

///|
/// 重命名 / 移动（目录也行）。
pub async fn rename_path(
  from : String,
  to : String,
  replace~ : Bool = false,
) -> Result[Unit, String] noraise {
  try {
    @fs.rename(from, to, replace~)
    Ok(())
  } catch {
    err =>
      Err(
        "改名失败：" + from + " -> " + to + "（" + err.to_string() + "）",
      )
  }
}

///|
/// 删一个文件。
async fn remove_file_impl(path : String) -> Result[Unit, String] noraise {
  try {
    @fs.remove(path)
    Ok(())
  } catch {
    err => Err("删文件失败：" + path + "（" + err.to_string() + "）")
  }
}

///|
/// 建一条符号链接：path 是链接自己，target 是它指向的东西。
///
/// 隔离 home 用它摆 node_modules 与 skills（规格第 2 节：软链，不复制）。
/// 已存在同名路径时算失败 —— 覆盖一条别人摆的软链不是这一次要做的事。
async fn make_symlink_impl(
  target : String,
  path : String,
) -> Result[Unit, String] noraise {
  if target == "" || path == "" {
    return Err("建软链失败：目标或链接路径为空")
  }
  try {
    @fs.symlink(target~, path)
    Ok(())
  } catch {
    err =>
      Err(
        "建软链失败：" +
        path +
        " -> " +
        target +
        "（" +
        err.to_string() +
        "）",
      )
  }
}

///|
/// 递归删目录。硬删走这一条。
async fn remove_tree_impl(path : String) -> Result[Unit, String] noraise {
  try {
    @fs.rmdir(path, recursive=true)
    Ok(())
  } catch {
    err =>
      Err("递归删目录失败：" + path + "（" + err.to_string() + "）")
  }
}

///|
/// 递归数一份目录树：普通文件个数 + 总字节数（回收站条目那一行要用的两个数）。
///
/// 只数普通文件，与 copy_tree 同一口径：软链 / socket / 设备文件是链接不是内容，
/// 数进去会让"体积"变成一个没有对应的数。目录本身不算文件。
///
/// 任何一步读不到就给 Err —— 数不全的时候宁可让调用方写「读不到」，
/// 也不给一个偏小的数冒充这一份的真实体积。
pub async fn measure_tree(
  root : String,
) -> Result[(Int32, Int64), String] noraise {
  let mut files = 0
  let mut bytes : Int64 = 0
  let queue : Array[String] = [root]
  let mut cursor = 0
  while cursor < queue.length() {
    let dir = queue[cursor]
    cursor = cursor + 1
    let names = match @json.list_dir_result(dir) {
      Ok(list) => list
      Err(e) => return Err("列目录失败：" + dir + "（" + e + "）")
    }
    for name in names {
      let path = @json.join_path(dir, name)
      let kind = @fs.kind(path, follow_symlink=false) catch { _ => Unknown }
      match kind {
        Directory => queue.push(path)
        Regular =>
          match @json.file_size(path) {
            Some(size) => {
              files = files + 1
              bytes = bytes + size
            }
            None => return Err("读不到文件大小：" + path)
          }
        _ => ()
      }
    }
  }
  Ok((files, bytes))
}

///|
/// 复制一个普通文件（保留原始字节）。
pub async fn copy_file(
  from : String,
  to : String,
) -> Result[Unit, String] noraise {
  match read_bytes(from) {
    Ok(data) => write_bytes_impl(to, data)
    Err(e) => Err(e)
  }
}

///|
/// 递归复制目录树。skip 里的名字整棵跳过（用于 node_modules 这种安装产物）。
/// 只复制普通文件与目录；软链 / socket / 设备文件一律跳过并在 skipped 里记名 ——
/// 把它们按内容复制出来是假数据，报错又会让整次派生卡在一个无关文件上。
pub async fn copy_tree(
  from : String,
  to : String,
  skip : Array[String],
  on_progress~ : (CopyStats) -> Unit = fn(_stats) { () },
) -> Result[CopyStats, String] noraise {
  let stats : CopyStats = { files: 0, dirs: 0, skipped: [], }
  let queue : Array[(String, String)] = [(from, to)]
  let mut cursor = 0
  while cursor < queue.length() {
    let pair = queue[cursor]
    cursor = cursor + 1
    let src = pair.0
    let dst = pair.1
    match ensure_dir_impl(dst) {
      Ok(_) => ()
      Err(e) => return Err(e)
    }
    stats.dirs = stats.dirs + 1
    on_progress(stats)
    let names = match @json.list_dir_result(src) {
      Ok(list) => list
      Err(e) => return Err("列目录失败：" + src + "（" + e + "）")
    }
    for name in names {
      if name_in(skip, name) {
        if !name_in(stats.skipped, name) {
          stats.skipped.push(name)
        }
        continue
      }
      let s = @json.join_path(src, name)
      let d = @json.join_path(dst, name)
      let kind = @fs.kind(s, follow_symlink=false) catch { _ => Unknown }
      match kind {
        Directory => queue.push((s, d))
        Regular =>
          match copy_file(s, d) {
            Ok(_) => {
              stats.files = stats.files + 1
              on_progress(stats)
            }
            Err(e) => return Err(e)
          }
        _ => {
          let label = name + "（非普通文件）"
          if !name_in(stats.skipped, label) {
            stats.skipped.push(label)
          }
        }
      }
    }
  }
  Ok(stats)
}

///|
/// 改文件权限（env.json 要 600：里面可能含密钥）。
pub async fn chmod_path(
  path : String,
  mode : Int32,
) -> Result[Unit, String] noraise {
  try {
    @fs.chmod(path, mode)
    Ok(())
  } catch {
    err => Err(path + " 改权限失败：" + err.to_string())
  }
}

///|
/// 数一遍目录树里有多少普通文件与目录（不跟软链）。派生前的进度分母靠它。
pub async fn count_tree(
  from : String,
  skip : Array[String],
) -> (Int32, Int32) noraise {
  let mut files = 0
  let mut dirs = 0
  let queue : Array[String] = [from]
  let mut cursor = 0
  while cursor < queue.length() {
    let src = queue[cursor]
    cursor = cursor + 1
    dirs = dirs + 1
    let names = match @json.list_dir_result(src) {
      Ok(list) => list
      Err(_) => continue
    }
    for name in names {
      if name_in(skip, name) {
        continue
      }
      let s = @json.join_path(src, name)
      let kind = @fs.kind(s, follow_symlink=false) catch { _ => Unknown }
      match kind {
        Directory => queue.push(s)
        Regular => files = files + 1
        _ => ()
      }
    }
  }
  (files, dirs)
}
///|
/// 失败的两段：summary 是给人看的结论（不带系统文本），raw 是底层原文（排查用）。
pub(all) struct FsError {
  summary : String
  raw : String
}

///|
/// 建目录：结论「建目录失败」，原文进 raw。
pub async fn ensure_dir_fs(path : String) -> Result[Unit, FsError] noraise {
  match ensure_dir_impl(path) {
    Ok(_) => Ok(())
    Err(raw) => Err({ summary: "建目录失败", raw })
  }
}

///|
pub async fn write_text_atomic_fs(
  path : String,
  text : String,
) -> Result[Unit, FsError] noraise {
  match write_text_atomic_impl(path, text) {
    Ok(_) => Ok(())
    Err(raw) => Err({ summary: "写文件失败", raw })
  }
}

///|
pub async fn write_bytes_fs(path : String, data : Bytes) -> Result[Unit, FsError] noraise {
  match write_bytes_impl(path, data) {
    Ok(_) => Ok(())
    Err(raw) => Err({ summary: "写文件失败", raw })
  }
}

///|
pub async fn remove_file_fs(path : String) -> Result[Unit, FsError] noraise {
  match remove_file_impl(path) {
    Ok(_) => Ok(())
    Err(raw) => Err({ summary: "删文件失败", raw })
  }
}

///|
pub async fn remove_tree_fs(path : String) -> Result[Unit, FsError] noraise {
  match remove_tree_impl(path) {
    Ok(_) => Ok(())
    Err(raw) => Err({ summary: "删目录失败", raw })
  }
}

///|
pub async fn make_symlink_fs(target : String, path : String) -> Result[Unit, FsError] noraise {
  match make_symlink_impl(target, path) {
    Ok(_) => Ok(())
    Err(raw) => Err({ summary: "建软链失败", raw })
  }
}
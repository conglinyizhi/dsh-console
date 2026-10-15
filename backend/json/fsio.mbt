// 只读文件访问。本文件是全工程唯一的文件 IO 入口。
//
// 允许：read_file / readdir / kind / mtime / exists / open(ReadOnly) + read_at
//       / realpath / read_link（readlink(2)，只读链接目标）
// 禁止：任何写 / 建 / 删 / 改名的调用，也禁止创建进程。
// open 只以 ReadOnly 模式调用；敏感文件名在此处硬拦：只判断存在，绝不读内容。
// read_link 走 fd_link.c 的一次 readlink(2)：/proc/<pid>/fd/* 的 socket:[<inode>]
// 只有它能读出来（realpath 对非路径目标必然失败）。

///|
/// 永远不读内容的敏感文件（与 Node 版 readProfiles.mjs 的 SENSITIVE_FILES 一致）。
pub let sensitive_files : Array[String] = [
  ".credentials.yaml", ".env", ".npmrc",
]

///|
/// 取路径最后一段。
pub fn basename(path : String) -> String {
  match path.rev_find("/") {
    Some(i) => path[i + 1:].to_owned()
    None => path
  }
}

///|
/// 是否为受保护文件（按 basename 判断）。
pub fn is_sensitive_path(path : String) -> Bool {
  let base = basename(path)
  sensitive_files.any(fn(name) { name == base })
}

///|
/// 读文本文件。敏感文件拒绝读，返回 Err。读不到也返回 Err。
pub async fn read_text_file(path : String) -> Result[String, String] noraise {
  if is_sensitive_path(path) {
    return Err("拒绝读取敏感文件：" + basename(path))
  }
  try {
    let data = @fs.read_file(path)
    Ok(@utf8.decode_lossy(data.binary(), ignore_bom=true))
  } catch {
    err => Err(err.to_string())
  }
}

///|
/// 路径是否存在（stat 一次，不列目录、不读内容）。
pub async fn exists(path : String) -> Bool noraise {
  try {
    @fs.exists(path)
  } catch {
    _ => false
  }
}

///|
/// 是否是目录。
pub async fn is_dir(path : String) -> Bool noraise {
  try {
    @fs.kind(path) is Directory
  } catch {
    _ => false
  }
}

///|
/// 列出目录名；目录不存在或读不到返回空数组。
pub async fn list_dir(path : String) -> Array[String] noraise {
  try {
    @fs.readdir(path)
  } catch {
    _ => []
  }
}

///|
/// 列目录并标出每一项是不是目录（对应 Node 的 readdirSync(withFileTypes)）。
pub async fn list_entries(path : String) -> Array[(String, Bool)] noraise {
  let names = list_dir(path)
  let out : Array[(String, Bool)] = []
  for name in names {
    let child = join_path(path, name)
    out.push((name, is_dir(child)))
  }
  out
}

///|
/// 拼接路径（Node 的 path.join 语义；两段都非空时中间补一个 /）。
pub fn join_path(a : String, b : String) -> String {
  if a == "" {
    return b
  }
  if b == "" {
    return a
  }
  if a.has_suffix("/") {
    return a + b
  }
  a + "/" + b
}

///|
/// 取父目录，对应 Node 的 path.dirname（只做字符串处理，不碰文件系统）。
pub fn dirname(path : String) -> String {
  if path == "" {
    return "."
  }
  let trimmed = if path.length() > 1 && path.has_suffix("/") {
    path[:path.length() - 1].to_owned()
  } else {
    path
  }
  match trimmed.rev_find("/") {
    None => "."
    Some(0) => "/"
    Some(i) => trimmed[:i].to_owned()
  }
}

///|
/// 本进程二进制文件的真实路径：读 /proc/self/exe 的链接目标（只读，不调外部命令）。
/// 取不到给空串，调用方按「不知道」处理。
pub async fn exe_path() -> String noraise {
  try {
    @fs.realpath("/proc/self/exe")
  } catch {
    _ => ""
  }
}

///|
/// 解析路径上的软链，给出真实路径（realpath(2)）。解析不了给 None。
/// 用途：pnpm 的 .bin/dsh 是指向真实包目录的软链，读入口包版本前要先落下实路径。
pub async fn real_path(path : String) -> String? noraise {
  try {
    Some(@fs.realpath(path))
  } catch {
    _ => None
  }
}

///|
/// 多段路径拼接。
pub fn join_all(parts : Array[String]) -> String {
  let mut acc = ""
  for p in parts {
    acc = join_path(acc, p)
  }
  acc
}

///|
/// 从文件的指定偏移读出最多 `len` 字节。读不到（含越界、IO 错误）返回 Err。
/// 这是本工程唯一带偏移的读入口，反向分块读尾靠它。
pub async fn read_some_at(
  path : String,
  position : Int64,
  len : Int,
) -> Result[Bytes, String] noraise {
  if is_sensitive_path(path) {
    return Err("拒绝读取敏感文件：" + basename(path))
  }
  let file = try {
    @fs.open(path, mode=ReadOnly)
  } catch {
    err => return Err("打不开文件：" + err.to_string())
  }
  defer file.close()
  let buf : FixedArray[Byte] = FixedArray::make(len, b'\x00')
  let n = try {
    file.read_at(buf, position~, offset=0, len~)
  } catch {
    err => return Err("读取失败：" + err.to_string())
  }
  let view = buf.unsafe_reinterpret_as_bytes()
  Ok(view[:n].to_owned())
}

///|
/// 按偏移读一段并解码成 UTF-8 文本（非法字节按替换字符处理）。
/// 解码放在整段上做，避免多字节字符被窗口边界切断。
pub async fn read_text_at(
  path : String,
  position : Int64,
  len : Int,
) -> Result[String, String] noraise {
  match read_some_at(path, position, len) {
    Ok(bytes) => Ok(@utf8.decode_lossy(bytes, ignore_bom=true))
    Err(e) => Err(e)
  }
}

///|
/// 文件字节大小（只 stat，不读内容）。取不到返回 None。
/// 用途：起实例失败时只归因「本次启动新写出来的那段日志」，
/// 上一次尝试留在同一个日志文件里的行不算这一次的证据。
pub async fn file_size(path : String) -> Int64? noraise {
  try {
    Some(@fs.file_size(path))
  } catch {
    _ => None
  }
}

///|
/// 文件 mtime，毫秒。取不到返回 None（对应 Node statSync 抛异常的那一支）。
/// @fs.mtime 返回 (秒, 纳秒)，这里按毫秒截断，与 JS 的 Date 精度一致。
pub async fn mtime_ms(path : String) -> Int64? noraise {
  try {
    let (sec, nsec) = @fs.mtime(path)
    Some(sec * 1000L + (nsec / 1000000).to_int64())
  } catch {
    _ => None
  }
}

///|
/// readlink(2)：读符号链接的目标本身，不跟随、不解析、不写。
/// 这是「端口 → PID」那条 join 的唯一原语：/proc/<pid>/fd/* 里的
/// socket:[<inode>] 只以链接目标的形式存在，realpath 追不到它。
/// 失败返回 Err（带 errno 名），调用方按「读不到」处理，不崩。
#borrow(path, buf)
extern "c" fn read_link_raw(path : Bytes, buf : Bytes, bufsiz : Int) -> Int = "dsh_console_readlink"

///|
/// 读链接目标的缓冲区：Linux 的 PATH_MAX。目标更长时 readlink 截断，这里明确报错，
/// 不返回半个路径 —— 半个路径拿去比对 inode 会得出错结论。
let read_link_cap : Int = 4096

///|
/// errno 名。只列本工程会遇到的几个，其余给数字，不编名字。
fn errno_text(code : Int) -> String {
  match code {
    1 => "EPERM 不允许的操作"
    2 => "ENOENT 目标不存在"
    5 => "EIO 读失败"
    12 => "ENOMEM 内存不足"
    13 => "EACCES 权限不足"
    20 => "ENOTDIR 路径中有非目录"
    22 => "EINVAL 不是符号链接或参数非法"
    34 => "ERANGE 缓冲区太小"
    40 => "ELOOP 链接层数过多"
    _ => "errno " + code.to_string()
  }
}

///|
/// 读符号链接目标。只读一次 readlink(2)，失败给 Err（人话 + errno 名）。
/// 同步的：一次系统调用，没有可挂起的点；调用方在 async 上下文里直接调。
pub fn read_link(path : String) -> Result[String, String] {
  let raw_path = @utf8.encode(path)
  let buf = Bytes::make(read_link_cap, b'\x00')
  let n = read_link_raw(raw_path, buf, read_link_cap)
  if n < 0 {
    return Err("readlink 失败：" + errno_text(-n))
  }
  if n >= read_link_cap {
    return Err("readlink 失败：目标超过 " + read_link_cap.to_string() + " 字节，被截断")
  }
  Ok(@utf8.decode_lossy(buf[:n]))
}

///|
/// 列目录并把失败原因带出来（list_dir 把失败吞成空数组，判断「空目录」与
/// 「读不到」时不够用）。
pub async fn list_dir_result(path : String) -> Result[Array[String], String] noraise {
  try {
    Ok(@fs.readdir(path))
  } catch {
    err => Err(err.to_string())
  }
}

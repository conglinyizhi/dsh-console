// 进程与设备文件两类失败的本地两段式包装。
//
// 为什么不放进 fsx / json：这三处 catch 的是 @process.* 与 redirect_* 抛出来的 Error，
// 只有 actions 这一层起子进程、也只有它需要这两句结论；json 在更底层、拿不到进程上下文，
// 所以按「哪里用、哪里包」放在这里，不引新依赖。
//
// 口径与前几批一致：summary 只进提示条，raw 只进 @store.note_raw（写侧回执才记）。

///|
/// 起进程失败（spawn / spawn_orphan / collect_output 的 catch 共用这一句）。
/// raw 是系统给的那一句（ENOENT / EACCES / 资源不够之类）。
pub fn spawn_error(err : Error) -> @json.FsError {
  { summary: "起进程失败", raw: err.to_string() }
}

///|
/// 打开设备文件失败（/dev/null 这类）：拿不到句柄，子进程就没有 stdin/stdout 可用。
pub fn device_error(err : Error) -> @json.FsError {
  { summary: "打开设备文件失败", raw: err.to_string() }
}

///|
/// 打开文件失败：redirect_to_file 打开的其实是普通文件（补包日志、实例日志），
/// 与 /dev/null 分开成两句 —— 一个该去查磁盘，一个该去查设备与权限。
pub fn open_file_error(err : Error) -> @json.FsError {
  { summary: "打开文件失败", raw: err.to_string() }
}

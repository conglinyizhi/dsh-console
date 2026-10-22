// raw 槽：现在住在 rawsink 包里（§108），store 只做转调，
// 让历史调用点（@store.note_raw / take_raw）不用改。

///|
pub fn note_raw(text : String) -> Unit {
  @rawsink.note_raw(text)
}

///|
pub fn take_raw() -> String {
  @rawsink.take_raw()
}

///|
/// 启动时把读路径的错误日志落点配好（与审计同目录，单独一个文件）。
pub async fn configure_read_error_log() -> Unit {
  let paths = state_paths()
  @rawsink.configure_error_log(@json.join_path(@json.dirname(paths.audit), "read-errors.log"))
}

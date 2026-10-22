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

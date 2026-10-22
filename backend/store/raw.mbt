// 原始错误文本的单格寄存（P2 raw）。
//
// 放在 store 而不是 actions：store 层的函数（envfile 等）也会失败，它们够不到 actions 包的
// note_raw —— 反向依赖会成环。这里只放数据与两个操作，任何包都能调。

///|
/// 最近一次失败的原始错误文本（OSError 之类）。只在本次请求里用，取一次就清。
let raw_slot : Ref[String] = { val: "" }

///|
/// 记下这次失败的原始文本（进 envelope 的 raw，不进 message）。空串等于不记。
pub fn note_raw(text : String) -> Unit {
  raw_slot.val = text
}

///|
/// 取走原始文本（取一次就清，避免串到下一次请求）。
pub fn take_raw() -> String {
  let text = raw_slot.val
  raw_slot.val = ""
  text
}

// 原始错误文本（raw）的进程内寄存处（§108）。
//
// 为什么单独一个包：localapi / json / instances 这些层都在 store 的下游，
// 它们拿得到系统原文却没有写审计的能力；把槽放在最底层，谁都能记，由能写审计的那层取走。

///|
let raw_slot : Ref[String] = { val: "", }

///|
/// 记一次原始错误文本。只保留最近一次；取走即清。
pub fn note_raw(text : String) -> Unit {
  raw_slot.val = text
}

///|
/// 取走并清空。空串表示这一次没有原文。
pub fn take_raw() -> String {
  let text = raw_slot.val
  raw_slot.val = ""
  text
}

///|
/// 读路径的原文去处（§109）：这些层不写审计行，也不该往动作槽里写（会串到下一次动作）。
/// 启动时配一个文件，之后一行一条追加；写失败就吞掉——记日志不能把主流程弄挂。
let error_log : Ref[String] = { val: "", }

///|
pub fn configure_error_log(path : String) -> Unit {
  error_log.val = path
}

///|
pub async fn append_error_line(source : String, text : String) -> Unit noraise {
  let path = error_log.val
  if path == "" {
    return
  }
  let stamp = @async.now().to_string()
  @fs.write_file(
    path,
    stamp + "\t" + source + "\t" + text + "\n",
    create_mode=OpenOrCreate,
    append=true,
    permission=0o600,
  ) catch {
    _ => ()
  }
}

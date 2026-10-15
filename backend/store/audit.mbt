// 审计：audit.jsonl —— 每个动作追加一行，只追加、不轮转（契约第五节）。
//
// 一行一个 JSON 对象，字段固定：at / action / params / ok / code / message / outcome。
// 追加失败不让动作失败（动作已经发生了，谎报失败更糟）：把原因交给调用方写进响应 note。

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
/// 追加一行。
pub async fn append_audit(line : @json.JsonVal) -> Result[Unit, String] noraise {
  let paths = state_paths()
  @fsx.append_text(paths.audit, @json.encode(line) + "\n")
}

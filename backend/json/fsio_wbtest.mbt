// json/fsio 的两段式错误（§105）。
// 这一层的约定只有两条：summary 是给人看的结论，raw 是原文；
// 拼回一行时两者用「：」相连，raw 为空就只给结论。

///|
test "两段拼一行：有原文时用冒号相连" {
  let e : FsError = {
    summary: "写文件失败",
    raw: "/x/y：Permission denied",
  }
  assert_eq(two_part_text(e), "写文件失败：/x/y：Permission denied")
}

///|
test "两段拼一行：没有原文时只给结论" {
  let e : FsError = {
    summary: "拒绝读取敏感文件：credentials.yaml",
    raw: "",
  }
  assert_eq(two_part_text(e), "拒绝读取敏感文件：credentials.yaml")
}

///|
test "结论本身不含系统原文" {
  let e : FsError = { summary: "读链接失败", raw: "ENOENT", }
  assert_false(e.summary.contains("ENOENT"))
  assert_true(two_part_text(e).contains("ENOENT"))
}

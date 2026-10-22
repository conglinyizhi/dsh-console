// patch 文本合并（§111）：只搬被点名的包，别的条目原样留着。
// 形状照真实文件：一个条目以 "- id: …" 开头，下一行 "  name: …" 才是包名。

///|
fn source_patch() -> String {
  "- id: a\n  name: alpha\n  config:\n    a: 1\n- id: b\n  name: beta\n  config:\n    b: 2\n"
}

///|
test "合并：只搬被点名的包" {
  let (added, overwritten, out) = merge_patch_text(
    "- id: a\n  name: alpha\n  config:\n    a: 0\n",
    source_patch(),
    ["beta"],
  )
  assert_true(added.contains("beta"))
  assert_true(overwritten.length() == 0)
  assert_true(out.contains("alpha"))
  assert_true(out.contains("beta"))
}

///|
test "合并：目标里已有同名条目时算覆盖，不算新增" {
  let (added, overwritten, out) = merge_patch_text(
    "- id: a\n  name: alpha\n  config:\n    a: 0\n",
    source_patch(),
    ["alpha"],
  )
  assert_true(overwritten.contains("alpha"))
  assert_false(added.contains("alpha"))
  assert_true(out.contains("a: 1"))
  assert_false(out.contains("a: 0"))
}

///|
test "合并：来源里没有的名字不算新增" {
  let (added, overwritten, out) = merge_patch_text("", source_patch(), ["gamma"])
  assert_eq(added.length(), 0)
  assert_eq(overwritten.length(), 0)
  assert_false(out.contains("gamma"))
}

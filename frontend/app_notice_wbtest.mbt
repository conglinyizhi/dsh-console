// 错误提示的两处切分（§105）：正文只留结论，原文退到悬停。
// 这两条以前出过错——整段 OSError 出现在提示条正文里。

///|
test "按句号切开：正文只留第一句" {
  let (head, hint) = split_error_note(
    "显示 beta 功能 没保存：写文件失败。原始错误：/x（OSError）",
  )
  assert_eq(head, "显示 beta 功能 没保存：写文件失败")
  assert_true(hint.contains("OSError"))
}

///|
test "没有原文标记时整句都是正文，悬停为空" {
  let (head, hint) = split_error_note(
    "作业没能写进磁盘：写文件失败",
  )
  assert_eq(head, "作业没能写进磁盘：写文件失败")
  assert_eq(hint, "")
}

///|
test "正文按句号或分号截断" {
  assert_eq(failure_headline("一句。后面还有"), "一句")
  assert_eq(failure_headline("一句；后面还有"), "一句")
}

///|
test "超长且没有标点时截断并加省略号" {
  let long = "a".repeat(failure_text_max + 10)
  let head = failure_headline(long)
  assert_true(head.has_suffix("…"))
  assert_true(head.length() <= failure_text_max + 1)
}

///|
test "开头就是句号这种坏形状仍给原文，不交空正文" {
  assert_eq(failure_headline("。只剩这句"), "。只剩这句")
}

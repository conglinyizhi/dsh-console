// 行 id 的名字段白名单（§113）：冒号与斜杠都不许出现，空的也不行。

///|
test "名字段：正常名字通过" {
  assert_true(order_name_segment_ok("web"))
  assert_true(order_name_segment_ok("review-space-a"))
}

///|
test "名字段：空、含冒号、含斜杠都拒" {
  assert_false(order_name_segment_ok(""))
  assert_false(order_name_segment_ok("a:b"))
  assert_false(order_name_segment_ok("a/b"))
  assert_false(order_name_segment_ok("/a/b@web"))
}

// 目标行名字的两种形态（§105）：卡片名带端口，磁盘目录名不带。
// merge_row_name 依赖整行结构，这里测它背后的纯函数 merge_strip_port。

///|
test "带端口的卡片名去掉端口" {
  assert_eq(merge_strip_port("web :3080"), "web")
  assert_eq(merge_strip_port("review-space-a :18712"), "review-space-a")
}

///|
test "本来没有端口的名字原样返回" {
  assert_eq(merge_strip_port("web"), "web")
  assert_eq(merge_strip_port("web-dev"), "web-dev")
}

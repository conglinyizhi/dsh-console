// store 里两处「同不同、认得出吗」的纯函数（§105）。
// 这两条此前出过多 home 相关的 bug：认不出 home 却被当成同一处，会把隔离 home 的实例挡掉。

///|
test "同一对 home 归一化后相等才算同一处" {
  assert_true(same_home(Some("/a/b"), Some("/a/b")))
  assert_true(same_home(Some("/a/b/"), Some("/a/b")))
}

///|
test "不同 home、或任一边认不出，都不算同一处" {
  assert_false(same_home(Some("/a/b"), Some("/a/c")))
  assert_false(same_home(Some("/a/b"), None))
  assert_false(same_home(None, Some("/a/b")))
  assert_false(same_home(Some(""), Some("/a/b")))
  assert_false(same_home(Some(""), Some("")))
}

///|
test "行 id：带 home 时用分隔符拼，空 home 时退回老形状" {
  let with_home = profile_row_id("web", "/home/u/.dsh")
  let without = profile_row_id("web", "")
  assert_true(with_home.has_suffix("/home/u/.dsh"))
  assert_true(with_home.contains("web"))
  assert_false(without.contains("/"))
  assert_true(with_home != without)
}

///|
test "同名不同 home 得到不同行 id" {
  assert_true(profile_row_id("web", "/a") != profile_row_id("web", "/b"))
}

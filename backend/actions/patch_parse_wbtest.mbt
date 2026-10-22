// patch 文本的解析细节（§113）：条目边界、名字取值、引号剥离。

///|
test "分块：每条以 - 开头，行内缩进保留" {
  let blocks = patch_blocks("- id: a\n  name: alpha\n- id: b\n  name: beta\n")
  assert_eq(blocks.length(), 2)
  assert_true(blocks[0].contains("name: alpha"))
  assert_true(blocks[1].contains("name: beta"))
}

///|
test "分块：没有 - 前缀的孤立行不成条目" {
  let blocks = patch_blocks("garbage\n- id: a\n  name: alpha\n")
  assert_eq(blocks.length(), 1)
}

///|
test "取名字：去掉引号与两侧空白" {
  assert_eq(patch_block_name("- id: a\n  name: \"@local/x\"\n"), "@local/x")
  assert_eq(patch_block_name("- id: a\n  name:   plain  \n"), "plain")
}

///|
test "取名字：没有 name 行时给空串" {
  assert_eq(patch_block_name("- id: a\n  config: {}\n"), "")
}

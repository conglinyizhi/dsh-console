// 受保护文件与路径末段（§114）：这两条决定「哪些文件拒绝读取」，错了不会编译失败。

///|
test "basename：取最后一段，没有斜杠就整串" {
  assert_eq(basename("/a/b/c.txt"), "c.txt")
  assert_eq(basename("c.txt"), "c.txt")
  assert_eq(basename("/a/b/"), "")
}

///|
test "受保护文件：按 basename 命中" {
  assert_true(is_sensitive_path("/home/u/.dsh/.env"))
  assert_true(is_sensitive_path("/home/u/proj/.npmrc"))
  assert_true(is_sensitive_path("/home/u/.credentials.yaml"))
}

///|
test "受保护文件：旁边的正常文件不误伤" {
  assert_false(is_sensitive_path("/home/u/.dsh/env.json"))
  assert_false(is_sensitive_path("/home/u/.envrc"))
  assert_false(is_sensitive_path("/etc/passwd"))
  assert_false(is_sensitive_path("/home/u/notes/.env.md"))
}

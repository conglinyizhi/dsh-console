// 包名合法性（§115）：包名会拼进路径，带分隔符或上级段一律拒。

///|
test "包名：普通名字与 scoped 名字通过" {
  assert_true(package_name_ok("my-plugin"))
  assert_true(package_name_ok("@local/dsh-x"))
}

///|
test "包名：上级段、空段、绝对路径、反斜杠、NUL 都拒" {
  assert_false(package_name_ok(""))
  assert_false(package_name_ok(".."))
  assert_false(package_name_ok("../x"))
  assert_false(package_name_ok("/etc/passwd"))
  assert_false(package_name_ok("a/b/c"))
  assert_false(package_name_ok("@scope"))
  assert_false(package_name_ok("@/x"))
  assert_false(package_name_ok("@scope/"))
}

// 平台层里能跨平台测的纯逻辑：十六进制解析、十进制解析。
// /proc 与 lsof 那两条路要真机器才能测，CI 上靠 macOS/ubuntu 的 job 各自跑。

///|
test "parse_hex 认小写十六进制" {
  assert_eq(parse_hex("50"), 80)
  assert_eq(parse_hex("1F90"), 8080)
}

///|
test "parse_hex 遇到非十六进制字符就停" {
  assert_eq(parse_hex("1F90xyz"), 8080)
}

///|
test "parse_dec 只认数字" {
  assert_eq(parse_dec("5390"), Some(5390))
  assert_eq(parse_dec("[::1]"), None)
  assert_eq(parse_dec(""), None)
}

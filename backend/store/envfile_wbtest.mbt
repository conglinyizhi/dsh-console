// store/envfile 的纯逻辑单测（白盒，§105）。
// 这些函数不碰磁盘，moon test 即可；不要在这里起控制台。

///|
fn expect_value(
  entries : Map[String, String],
  key : String,
  want : String,
) -> Unit raise {
  match entries.get(key) {
    Some(v) => assert_eq(v, want)
    None => fail("缺少键 " + key)
  }
}

///|
fn expect_absent(entries : Map[String, String], key : String) -> Unit raise {
  match entries.get(key) {
    Some(_) => fail("不该存在键 " + key)
    None => ()
  }
}

///|
test "全小写的键补一份全大写" {
  let entries : Map[String, String] = Map([])
  entries["no_proxy"] = "localhost"
  let out = expand_case_variants(entries, [])
  expect_value(out, "no_proxy", "localhost")
  expect_value(out, "NO_PROXY", "localhost")
}

///|
test "全大写的键补一份全小写" {
  let entries : Map[String, String] = Map([])
  entries["HTTP_PROXY"] = "http://127.0.0.1:10738"
  let out = expand_case_variants(entries, [])
  expect_value(out, "HTTP_PROXY", "http://127.0.0.1:10738")
  expect_value(out, "http_proxy", "http://127.0.0.1:10738")
}

///|
test "混合大小写不补对偶" {
  let entries : Map[String, String] = Map([])
  entries["FooBar"] = "keep"
  let out = expand_case_variants(entries, [])
  expect_value(out, "FooBar", "keep")
  expect_absent(out, "foobar")
  expect_absent(out, "FOOBAR")
}

///|
test "被删掉的键进了 suppressed 就不再补回来" {
  let entries : Map[String, String] = Map([])
  entries["no_proxy"] = "a,b"
  let out = expand_case_variants(entries, ["NO_PROXY"])
  expect_value(out, "no_proxy", "a,b")
  expect_absent(out, "NO_PROXY")
}

///|
test "显式写了两个大小写时各自保留自己的值" {
  let entries : Map[String, String] = Map([])
  entries["no_proxy"] = "lower"
  entries["NO_PROXY"] = "upper"
  let out = expand_case_variants(entries, [])
  expect_value(out, "no_proxy", "lower")
  expect_value(out, "NO_PROXY", "upper")
}

///|
test "键名白名单只认字母数字下划线" {
  assert_false(env_key_allowed("DSH_HOME"))
  assert_false(env_key_allowed(""))
  assert_false(env_key_allowed("has space"))
  assert_false(env_key_allowed("has-dash"))
}

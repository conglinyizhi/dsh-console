// 环境变量文件的解析（§112）：坏形状给空表，非字符串值丢弃，合法值原样取。

///|
test "解析：没有内容给空表" {
  assert_eq(parse_env_map(None).length(), 0)
}

///|
test "解析：坏 JSON 与非对象都给空表" {
  assert_eq(parse_env_map(@json.json_parse("not json")).length(), 0)
  assert_eq(parse_env_map(@json.json_parse("1")).length(), 0)
  assert_eq(parse_env_map(@json.json_parse("[1,2]")).length(), 0)
  assert_eq(parse_env_map(@json.json_parse("\"str\"")).length(), 0)
}

///|
test "解析：对象取字符串值，数字与布尔丢弃" {
  let map = parse_env_map(
    @json.json_parse("{\"A\": \"1\", \"B\": 2, \"C\": true}"),
  )
  assert_eq(map.length(), 1)
  match map.get("A") {
    Some(v) => assert_eq(v, "1")
    None => assert_true(false)
  }
  assert_false(map.contains("B"))
  assert_false(map.contains("C"))
}

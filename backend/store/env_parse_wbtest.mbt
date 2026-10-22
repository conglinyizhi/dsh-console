// 环境变量文件的解析（§111）：坏形状给空表，正常形状按原样取。

///|
test "解析：null 与坏形状都给空表" {
  assert_eq(parse_env_map(None).length(), 0)
  assert_eq(parse_env_map(Some(Json::Num(1))).length(), 0)
}

///|
test "解析：对象按原样取键值，非字符串值丢弃" {
  let raw = @json.parse("{\"A\": \"1\", \"B\": 2}") catch { _ => Json::Null }
  let map = parse_env_map(Some(raw))
  assert_eq(map.length(), 1)
  match map.get("A") {
    Some(v) => assert_eq(v, "1")
    None => ()
  }
  assert_false(map.contains("B"))
}

// 读 core 的 Json（profile 的 package.json 用），只做只读取值，不 panic。

///|
/// Json 取字符串；不是字符串就 None。
pub fn json_string(v : Json) -> String? {
  match v {
    String(s) => Some(s)
    _ => None
  }
}

///|
/// Json 取对象字段。
pub fn json_field(v : Json, key : String) -> Json? {
  match v {
    Object(m) => m.get(key)
    _ => None
  }
}

///|
/// Json 取嵌套字段：root -> a -> b。
pub fn json_path2(root : Json, a : String, b : String) -> Json? {
  match json_field(root, a) {
    Some(inner) => json_field(inner, b)
    None => None
  }
}

///|
/// Json 取数组（非数组返回空数组，语义等同 Node 里 Array.isArray 判否后取 []）。
pub fn json_array(v : Json?) -> Array[Json] {
  match v {
    Some(Array(items)) => items
    _ => []
  }
}

///|
/// 一个空的 JSON 对象。core 的 JsonObject 在别的包里造不出来（只读类型），
/// 需要「参数缺省即空对象」的地方统一走这里，省得各处再造一遍。
pub fn empty_object() -> Json noraise {
  match json_parse("{}") {
    Some(j) => j
    None => abort("unreachable: 空对象字面量一定解析得出来")
  }
}

///|
/// Json 解析文本；失败返回 None（等同 Node 的 try/catch JSON.parse）。
pub fn json_parse(text : String) -> Json? noraise {
  Some(@core_json.parse(text)) catch {
    _ => None
  }
}

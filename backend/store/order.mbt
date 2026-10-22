// 手动排序：order.json —— 一份**显式顺序表**，按行 id 存。
//
// 为什么按行 id 而不是位置索引：列表本身会变（实例起停、profile 增删、归档进出），
// 存一个「第 3 个」在列表变一次之后就指向别的东西了。存 id 则「已经排好的那些」永远
// 还是它们自己，新出现的行没有条目 —— 前端把它们按自动规则排在已排好的之后。
//
// 行 id 两种形状，与应用里的 row.id 一字不差：
//   port:<端口号>            运行中 / 故障那一组的行。端口是全机唯一的，不需要 home。
//   profile:<名字>@<home>    已停止那一组的行。一份档案的身份是 (home, 名字)：
//                            多 home 之后同名不同 home 就是两行，各排各的、不互相顶。
//
// 第三种形状 profile:<名字>（没有 @ 的一段）也认，那是本次改动**之前**的写法：
// 旧 order.json 里就是这个，读得出来就不该丢。它只可能对上「没有 home 可比」的记录
// （见 laststarted：登记里没有 home 时才产这种 id），所以留着它是兼容，不是含糊。
//
// 文件形状：顶层就是一个 JSON 字符串数组（与 runtime.json 一样是裸数组，不包对象）。
// 数组顺序就是使用者拖出来的顺序。写是原子写；读不出来就是空表 + note，
// 绝不拿一份半截的顺序去排页面。
//
// 这里只负责「读 / 写 / 校验形状」；「怎么把这份顺序应用到两组行上」在前端。

///|
/// 行 id 的前缀：端口那一组。
pub let order_id_port_prefix : String = "port:"

///|
/// 行 id 的前缀：profile 那一组。
pub let order_id_profile_prefix : String = "profile:"

///|
/// 名字段与 home 段之间的分隔符。
///
/// 为什么用它：profile 名走白名单（只允许字母数字与 . _ -），里面不可能有 @；
/// 而 home 是绝对路径，可能带任何字符。按**第一个** @ 切开，两段都不会切错。
pub let order_id_home_sep : String = "@"

///|
/// 顺序表最多存多少条。
///
/// 上限不是为了省地方：一份几万条的 id 表只可能来自调用方写错了，而这种错
/// 在写盘之后才被发现就晚了（页面加载时每次都要读它）。超了直接拒。
pub let order_max_ids : Int32 = 5000

///|
/// 运行中那一组的行 id：只有端口，不带 home（端口本来就是全机唯一的）。
pub fn port_row_id(port : Int32) -> String {
  order_id_port_prefix + port.to_string()
}

///|
/// 已停止那一组的行 id：名字 + home。
///
/// home 为空串时给老形状（profile:<名字>）—— 那是「这一条没有 home 可比」的如实写法：
/// 登记里读不到 home 的记录只能这么认，硬安一个默认 home 上去就等于猜（那正是要避免的）。
pub fn profile_row_id(name : String, home : String) -> String {
  if home == "" {
    order_id_profile_prefix + name
  } else {
    order_id_profile_prefix + name + order_id_home_sep + home
  }
}

///|
/// 名字段认不认：非空，且不含冒号与斜杠。
///
/// profile 名的白名单本来就不允许这两个字符（profiles 那一侧同样拒），所以这里拒掉的
/// 只可能是拼错的东西 —— 最典型的一种是把 home 与名字写反（profile:/a/b@web 里的名字
/// 带斜杠），那种 id 存下去以后永远对不上任何一行。
fn order_name_segment_ok(name : String) -> Bool {
  if name == "" {
    return false
  }
  match name.find(":") {
    Some(_) => return false
    None => ()
  }
  match name.find("/") {
    Some(_) => false
    None => true
  }
}

///|
/// 一个行 id 认不认。
///
/// 判据与前端 row.id 的拼法一致：
///   port: 后面必须全是十进制数字、且不能为空；
///   profile: 后面是名字，或「名字@home」—— 名字非空且不含冒号与斜杠；
///   home 必须是**已经归一化的绝对路径**（normalize_home 认、且认出来跟原样一样）。
/// 最后那一条要求「跟原样一样」是为了不让 /a/b/ 这种等价写法混进来：id 是拿来逐字比对的键，
/// 同一个 home 有两种写法就等于两把不同的钥匙。
/// 不认的 id 一律拒绝，**不静默跳过** —— 静默跳过会让调用方以为「存下了」，而实际少了一条。
pub fn order_id_valid(id : String) -> Bool {
  if id.has_prefix(order_id_port_prefix) {
    let rest = @json.slice_from(id, order_id_port_prefix.length())
    return rest != "" && @json.is_all_digits(rest)
  }
  if id.has_prefix(order_id_profile_prefix) {
    let rest = @json.slice_from(id, order_id_profile_prefix.length())
    match rest.find(order_id_home_sep) {
      Some(idx) => {
        let name = @json.slice(rest, 0, idx)
        let home = @json.slice(rest, idx + 1, rest.length())
        if !order_name_segment_ok(name) {
          return false
        }
        match normalize_home(home) {
          Some(normalized) => normalized == home
          None => false
        }
      }
      None => order_name_segment_ok(rest)
    }
  } else {
    false
  }
}

///|
/// 读出来的顺序表 + 文件级问题。
///
/// note 与 registry 的口径一致：坏文件不算致命（回退到空表 = 回到自动排序），
/// 但原因要能看见 —— 顺序悄悄变回默认而不说一句，使用者只会觉得「拖了不生效」。
pub struct LoadedOrder {
  ids : Array[String]
  note : String?
}

///|
/// 读顺序表。文件不存在 -> 空表（全新环境不是错误）；坏了 -> 空表 + note。
pub async fn load_order() -> LoadedOrder noraise {
  let paths = state_paths()
  let (file, file_error) = read_state_json(paths.order)
  let ids : Array[String] = []
  let mut note = file_error
  match file {
    None => ()
    Some(json) =>
      match json {
        Array(items) => {
          let mut dropped = 0
          for item in items {
            match as_string(item) {
              Some(id) =>
                if order_id_valid(id) {
                  ids.push(id)
                } else {
                  dropped = dropped + 1
                }
              None => dropped = dropped + 1
            }
          }
          if dropped > 0 {
            note = Some(
              "order.json 里有 " +
              dropped.to_string() +
              " 条认不出的行 id，已跳过：" +
              paths.order,
            )
          }
        }
        _ =>
          note = Some(
            "order.json 顶层不是数组，按空表处理：" + paths.order,
          )
      }
  }
  { ids, note, }
}

///|
/// 顺序表的 JSON 形状（裸数组）。
pub fn order_json(ids : Array[String]) -> @json.JsonVal {
  @json.jstr_array(ids)
}

///|
/// 整表落盘（原子写）。失败原样回原因，由调用方决定怎么报 —— 顺序没写进去
/// 而回一句「已保存」，使用者下一次刷新就会看到列表跳回原样，且不知道为什么。
pub async fn save_order(ids : Array[String]) -> Result[Unit, String] noraise {
  let paths = state_paths()
  match @fsx.write_text_atomic_fs(paths.order, @json.encode(order_json(ids)) + "\n") {
    Ok(_) => Ok(())
    Err(e) => {
      note_raw(e.raw)
      Err("写文件失败")
    }
  }
}

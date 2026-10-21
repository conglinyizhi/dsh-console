// data-uid：语义路径 → 8 位 base36 的稳定标识。
//
// 为什么要有这个（而不是每个元素手写一串常量）：
//   1. 一个角色的元素会有很多个（卡片、菜单项、日志来源项…），手写常量写到第十个必错，
//      而且改名 / 换分组之后没人记得同步。路径写清楚、值算出来，改路径就自动换值。
//   2. data-name 只表达角色，同角色的两个元素分不开 —— 使用者的拾取工具对
//      「运行中分组」与「已停止分组」两个来源徽标给出了同一条路径。data-uid 补这一刀。
//
// 三条硬约束，改这个文件之前先读一遍：
//   * 稳定：同一个语义元素在两次渲染、两次刷新之间必须是同一个值。
//     「每次渲染随机生成」的值是没用的 —— 工具读到它，下一次刷新就指不到了。
//     所以这里**没有**随机数：长得随机、取值确定。
//   * 确定：只由 parts 决定，别的什么都不看（不读时间、不读 Math.random）。
//   * **不许拿位置算**：parts 里不许出现索引 / 序号 / 「第几个」。
//     列表顺序会变（已停止组按最近改动排序），位置算出来的 uid 会跟着顺序变，比没有还糟。
//     parts 里放的是这一项自己的键：profile 名、实例 port、设置键名、动作名…
//
// 取值域：8 位 base36 = 36^8 ≈ 2.82e12，撞串概率对一页几十个元素可以忽略。
// 算法：FNV-1a 64 位（偏移基底 + 质数都是标准值），逐段先写段长再写内容 ——
// 段长前缀让 ["ab","c"] 与 ["a","bc"] 不会撞成同一个值。

///|
let uid_digits : Array[Char] = [
  '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', 'a', 'b', 'c', 'd', 'e', 'f',
  'g', 'h', 'i', 'j', 'k', 'l', 'm', 'n', 'o', 'p', 'q', 'r', 's', 't', 'u', 'v',
  'w', 'x', 'y', 'z',
]

///|
/// base36 的空间大小 36^8：哈希先对它的模，再逐位取。
let uid_space : UInt64 = 2821109907456UL

///|
/// 语义路径 → 8 位 base36。同一路径永远同一串；不同路径几乎不会撞。
///
/// parts 的写法：从粗到细，最后一段是这一项自己的键。
///   ["overview", "card", "profile:web-dev", "menu-trigger"]
///   ["logs", "source-option", "host"]
pub fn uid(parts : Array[String]) -> String {
  let mut hash : UInt64 = 0xcbf29ce484222325UL
  for part in parts {
    // 段长也进哈希：拼接的二义性（["ab","c"] vs ["a","bc"]）在这里被消掉
    hash = hash ^ part.length().to_uint64()
    hash = hash * 0x100000001b3UL
    for c in part {
      hash = hash ^ c.to_int().to_uint64()
      hash = hash * 0x100000001b3UL
    }
  }
  let mut rest = hash % uid_space
  let picked : Array[Char] = []
  for k = 0; k < 8; k = k + 1 {
    picked.push(uid_digits[(rest % 36UL).to_int()])
    rest = rest / 36UL
  }
  // 取位是从低位往高位，写出去要反过来才是可读的定长 8 位（低位补 0，不截断）
  let buf = StringBuilder()
  for i = 7; i >= 0; i = i - 1 {
    buf.write_char(picked[i])
  }
  buf.to_string()
}

///|
/// 一处标注的两个属性：data-name 说角色，data-uid 说这一个。
///
/// 需要再挂 title / aria 的地方接着往后链就行 —— 语义路径只在这一处进 uid()，
/// 调用点不用各自记「路径该从哪一段开始」。
fn mark(name : String, parts : Array[String]) -> @html.Attrs {
  @html.Attrs::build().data_set("name", name).data_set("uid", uid(parts))
}

// 提示与通知历史：Notice / NoticeRecord 两个结构、历史条数上限、toast 自己走掉的时长。
//
// 2026-10-20 从 state.mbt 拆出来：提示是「一条盖一条」的唯一出口，把这些字段单独放一份，
// 改提示条的形状时不必翻 Model 那一大段。只搬位置，函数体一个字没改。


///|
/// 一条通知历史（§36）：提示条与 toast 都是「一条盖一条」，连点几次动作前面那条就没了，
/// 这一份是给它留的回看窗口。**只在内存里**，刷新页面就清空 —— 它不是审计
/// （审计在 /logs/actions），不落盘。
///
/// 正文与悬停在写进历史之前已经被 redact_tokens 洗过一遍：历史里不许出现带令牌的地址。
pub(all) struct NoticeRecord {
  /// 发生的时刻（HH:MM:SS，浏览器本地时钟）
  at : String
  /// 成功（toast）还是失败（常驻提示条）
  ok : Bool
  /// 正文：一句结论
  text : String
  /// 悬停补充（原样来自调用方）
  hint : String
  /// 这一条有审计行可看（§32 那条规则）：侧栏里多一颗「查看日志」
  audit : Bool
} derive(Eq)

pub extend NoticeRecord with Eq::{ not_equal, equal }

///|
/// 一条全局提示（design/ops-maintenance-jobs.md §14.1）。
///
/// 成功与失败同住一条：ok 决定外壳把它画成底部 toast（3.5 秒后自己走）
/// 还是常驻提示条（直到下一条动作替换它）。
struct Notice {
  /// 这是第几条。外壳按它认「到期消息说的还是不是当前这一条」——
  /// 号对不上就作废，不把一条新提示提前收掉。
  seq : Int
  /// 成功（toast，会自己走）还是失败（常驻）
  ok : Bool
  /// 正文：一句话说清这次动作的结果
  text : String
  /// 正文之外的细节（路径 / 格式 / 后端原文），只进悬停
  hint : String
  /// 发出去的时刻（HH:MM:SS，浏览器本地时钟）。只作记录，不上屏
  at : String
  /// 这一条失败**有一条审计线**可看（design/design-fixes.md §32.1）：
  /// 只有走 POST /api/local/action 的那类动作失败才为 true（它们一定写 audit.jsonl）；
  /// 剪贴板、读数、设置校验之类的失败不写审计，也就不摆那颗「查看日志」。
  audit : Bool
} derive(Eq)

pub extend Notice with Eq::{ not_equal, equal }

// 启动变量的「预设」：一组命名好的 KEY=VALUE，供专窗里勾选后一键补进表里。
//
// 开源仓库里**不预置任何机器特定的值**（代理地址、令牌、路径这类一律不写进来）。
// 要加一条就在这里追加：name 是给人看的名字，note 说明它干什么、什么时候用，
// pairs 是要补进表里的键值对（只补缺：目标里已有的同名键不会被覆盖）。
//
// 例子（不要照抄到仓库里，只作格式说明）：
//   { name: "示例：某个代理", note: "说明为什么要设这些键", pairs: [("SOME_KEY", "值")] }

///|
/// 一条预设。
pub struct EnvPreset {
  name : String
  note : String
  pairs : Array[(String, String)]
}

///|
/// 所有可用预设。默认是空数组 —— 预置值不写进仓库。
pub fn env_presets() -> Array[EnvPreset] {
  []
}

// 服务端构建信息（由 scripts/gen-build-info.sh 生成，不要手改）
//
// build_sha：git 短 sha；build_at：构建时刻（本地时间，给人看的）。
///|
pub let build_sha : String = "929bf0a"

///|
pub let build_at : String = "2026-10-27 09:37:50"

///|
/// 构建模式：dev 用内容哈希做版本标识，release 用 git sha。
pub let build_mode : String = "dev"

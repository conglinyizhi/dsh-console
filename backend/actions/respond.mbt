// 写侧响应外壳与错误码到状态码的映射。
//
// 形状照 design/write-api-contract.md：
//   成功 { ok:true, readOnly:false, readAt, data }
//   失败 { ok:false, readOnly:false, error:{ code, message } }
// 错误码只认下面这张表，别的一个都不造。
//
// 表里有一条不在原契约的七码之内：dsh-not-installed（版本切换那一轮加的）。
// 为什么单独一条而不是并进 io-error：那是**调用方点错了目录**，不是读写失败 ——
// 一句话能纠正的事（候选目录是哪几份，message 里都列着），报成 io-error 会把人引去查磁盘。
// 新增这条要同步的只有两处：这张表与 status_for_code（400）。

///|
/// 写响应上带的 X-Local-Api 值：与只读接口的 read-only 区分开，一眼能看出这是写动作的应答。
pub let local_api_read_write : String = "read-write"

///|
/// 契约里的七个错误码。
pub let codes : Array[String] = [
  "not-authorized", "unknown-action", "bad-params", "not-found", "conflict", "spawn-failed",
  "stop-failed", "io-error",
  // 指定的那个目录不是这台机器上装着的一份 dsh（见 dsh_version.mbt 的 pin_dsh）
   "dsh-not-installed",
  // 同一 kind 已经有一条没做完的作业（见 job.mbt 的 job_start）
   "job-exists",
  // 同一只 profile 已经有一个补包在跑（见 repair.mbt 的 repair_packages）
   "busy",
  // 包管理器跑了但退出码不 0（§39.2）
   "install-failed",
  // 装完了，但按 dsh.profile.bundles 重算仍缺包（§39.2）
   "install-incomplete",
]

///|
/// 带码的写动作错误。
pub(all) suberror ActionError {
  ActionError(code~ : String, message~ : String)
}

///|
/// 抛一个写动作错误。code 不在表里时收敛成 io-error（不往外造新码）。
pub fn fail(code : String, message : String) -> Unit raise ActionError {
  let known = codes.any(fn(c) { c == code })
  raise ActionError(code=if known { code } else { "io-error" }, message~)
}

///|
/// 错误码到 HTTP 状态码。除了契约写明的 not-authorized = 403，其余按语义挑：
/// bad-params / unknown-action = 400，not-found = 404，conflict = 409，其余 500。
pub fn status_for_code(code : String) -> Int32 {
  match code {
    "not-authorized" => 403
    "unknown-action" => 400
    "bad-params" => 400
    // 点了一个不是安装的目录 = 请求本身不对，不是服务端读写失败
    "dsh-not-installed" => 400
    "not-found" => 404
    "conflict" => 409
    // 撞上一条没做完的作业：请求本身没问题，是状态不允许再来一条
    "job-exists" => 409
    // 同一只 profile 已经有一个补包在跑：同上，是状态不允许
    "busy" => 409
    _ => 500
  }
}

///|
/// 写成功外壳。
pub async fn send_write_ok(
  res : @moonback.Responder,
  data : @json.JsonVal,
  read_at : String,
) -> Unit {
  @localapi.send_json(
    res,
    200,
    @json.JObj([
      ("ok", @json.JBool(true)),
      ("readOnly", @json.JBool(false)),
      ("readAt", @json.JStr(read_at)),
      ("data", data),
    ]),
    extra_headers=[("X-Local-Api", local_api_read_write)],
  )
}

///|
/// 写失败外壳。
pub async fn send_write_error(
  res : @moonback.Responder,
  code : String,
  message : String,
  read_at : String,
) -> Unit {
  @localapi.send_json(
    res,
    status_for_code(code),
    @json.JObj([
      ("ok", @json.JBool(false)),
      ("readOnly", @json.JBool(false)),
      ("readAt", @json.JStr(read_at)),
      (
        "error",
        @json.JObj([
          ("code", @json.JStr(code)),
          ("message", @json.JStr(message)),
        ]),
      ),
    ]),
    extra_headers=[("X-Local-Api", local_api_read_write)],
  )
}

///|
/// 方法不对（写端点收到非约定方法）：405 + Allow，壳仍是写侧形状。
pub async fn send_method_not_allowed(
  res : @moonback.Responder,
  allow : String,
  got : String,
  read_at : String,
) -> Unit {
  @localapi.send_json(
    res,
    405,
    @json.JObj([
      ("ok", @json.JBool(false)),
      ("readOnly", @json.JBool(false)),
      ("readAt", @json.JStr(read_at)),
      (
        "error",
        @json.JObj([
          ("code", @json.JStr("method-not-allowed")),
          (
            "message",
            @json.JStr("这个端点只接受 " + allow + "，收到 " + got),
          ),
        ]),
      ),
    ]),
    extra_headers=[("Allow", allow), ("X-Local-Api", local_api_read_write)],
  )
}

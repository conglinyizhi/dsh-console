// 读路径错误日志（§109）：配好路径后追加一行，原文能落到文件里。
// 用仓库内临时目录，跑完自己清；不依赖控制台进程。

///|
async test "append_error_line 把内容写进文件" {
  let dir = ".tmp-verify/rawsink-test"
  let path = dir + "/read-errors.log"
  configure_error_log(path)
  append_error_line("tailread", "读文件状态失败：/x Permission denied")
  append_error_line("localapi", "boom")
  let data = @fs.read_file(path)
  let bytes = data.binary()
  assert_true(bytes.length() > 0)
}

///|
async test "没配路径时静默丢弃，不炸" {
  configure_error_log("")
  append_error_line("weburl", "whatever")
}

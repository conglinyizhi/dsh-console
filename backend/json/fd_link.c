// readlink(2) 的 FFI 桥 —— 整个后端唯一一处 C 代码。
//
// 为什么非要有它：MoonBit 的 fs 层给了 realpath（一路跟随到底），没给 readlink
// （只读链接目标本身）。而「端口 → PID」这条 join 只能靠读 /proc/<pid>/fd/* 的
// 链接目标拿到 socket:[<inode>]，realpath 对 socket: 这种非路径目标必然 ENOENT。
//
// 边界：只有一次 readlink 系统调用。不写盘、不建进程、不解析路径、不做 IO。
// 失败一律返回负 errno 交给 MoonBit 侧判，C 这边不打印、不 abort。
#include <errno.h>
#include <stdint.h>
#include <unistd.h>

#include <moonbit.h>

MOONBIT_FFI_EXPORT
int32_t dsh_console_readlink(moonbit_bytes_t path, moonbit_bytes_t buf, int32_t bufsiz) {
  ssize_t n = readlink((const char *)path, (char *)buf, (size_t)bufsiz);
  if (n < 0) {
    return -(int32_t)errno;
  }
  return (int32_t)n;
}

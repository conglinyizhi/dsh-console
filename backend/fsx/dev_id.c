// stat(2) 的 st_dev 桥 —— 移动目录前「两边是不是同一个文件系统」的判据。
//
// 为什么非要有它：隔离改造用的是 rename(2)（同盘只改目录项，O(1)）。两个 home 在不同
// 文件系统上时 rename 会给 EXDEV，退化成「复制再删」就不再是使用者要的「移动」了。
// MoonBit 的 fs 层给的 mtime / size / kind 里没有设备号，所以这一条只能自己接。
//
// 边界：只有一次 stat。不写盘、不建目录、不解析路径、不打印、不 abort。
// 失败返回负 errno 交给 MoonBit 侧判；成功返回 st_dev（非负）。
#include <errno.h>
#include <stdint.h>
#include <sys/stat.h>

#include <moonbit.h>

MOONBIT_FFI_EXPORT
int64_t dsh_console_dev(moonbit_bytes_t path) {
  struct stat st;
  if (stat((const char *)path, &st) != 0) {
    return -(int64_t)errno;
  }
  return (int64_t)st.st_dev;
}

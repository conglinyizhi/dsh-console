// localtime_r(3) 的 FFI 桥。
//
// 为什么非要有它：派生出的 profile 要在备注第一行写下"从哪来、什么时候"，
// 口径是**本地时间**（使用者看到的那块表），而 MoonBit 侧只有 UTC 的能力
// （@async.now / Date 都是绝对时刻，核心库与本工程的依赖里没有时区换算）。
//
// 边界：读一次时区偏移，不写盘、不建进程、不碰文件。
// 拿不到（localtime_r 返回 NULL）时返回一个哨兵值 —— C 这边不打印、不 abort。
#include <stdint.h>
#include <time.h>

#include <moonbit.h>

// 取不到的哨兵：真实偏移的绝对值不可能到 86400 秒。
#define DSH_CONSOLE_OFFSET_UNKNOWN INT64_C(1000000000)

// 把本地时区缩写写进调用方给的缓冲区，返回写进去的字节数（不含结尾的 0）。
// 取不到时区名给 0，缓冲区保持不动。
MOONBIT_FFI_EXPORT
int32_t dsh_console_local_zone_name(moonbit_bytes_t buf, int32_t cap) {
  time_t t = time(NULL);
  struct tm out;
  if (localtime_r(&t, &out) == NULL || out.tm_zone == NULL) {
    return 0;
  }
  int32_t n = 0;
  while (out.tm_zone[n] != '\0' && n < cap) {
    buf[n] = (uint8_t)out.tm_zone[n];
    n++;
  }
  return n;
}

MOONBIT_FFI_EXPORT
int64_t dsh_console_local_offset_seconds(int64_t sec) {
  time_t t = (time_t)sec;
  struct tm out;
  if (localtime_r(&t, &out) == NULL) {
    return DSH_CONSOLE_OFFSET_UNKNOWN;
  }
  return (int64_t)out.tm_gmtoff;
}

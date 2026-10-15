// kill(2) / getpid(2) 的 FFI 桥 —— 写侧唯一的 C 代码。
//
// 为什么需要它：停止实例要「先 SIGTERM、宽限后再 SIGKILL」，判断 PID 还在不在要做
// kill(pid, 0)。moonbitlang/async 的 @process 只能操作自己 spawn 出来的 Process 句柄，
// 对「一个已有的 PID」没有原语；本工程也不打算为此去 spawn /bin/kill。
//
// 边界：只有 kill(2) 与 getpid(2)。不写盘、不建进程、不解析路径、不读文件、
// 不打印、不 abort。失败一律返回负 errno，交 MoonBit 侧判。
#include <errno.h>
#include <signal.h>
#include <stdint.h>
#include <unistd.h>

#include <moonbit.h>

MOONBIT_FFI_EXPORT
int32_t dsh_console_kill(int32_t pid, int32_t sig) {
  if (kill((pid_t)pid, (int)sig) == 0) {
    return 0;
  }
  return -(int32_t)errno;
}

MOONBIT_FFI_EXPORT
int32_t dsh_console_pid_alive(int32_t pid) {
  if (kill((pid_t)pid, 0) == 0) {
    return 1;
  }
  // EPERM 表示进程在，只是不归我们发信号
  return errno == EPERM ? 1 : 0;
}

MOONBIT_FFI_EXPORT
int32_t dsh_console_getpid(void) {
  return (int32_t)getpid();
}

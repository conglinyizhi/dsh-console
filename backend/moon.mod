// dsh-console 本地只读接口后端（MoonBit / native）。
//
// 依赖版本说明：本机 ~/.moon 处于只读文件系统，注册表索引停留在
// 2026-10-08（最新可见：moonbitlang/moonback@0.8.6、moonbitlang/async@0.22.4）。
// 因此这里锁定索引内可见的最新版本，而不是 0.8.7 / 0.22.5。
// 升级命令：MOON_HOME <可写目录> moon add --upgrade moonbitlang/moonback@<版本>

name = "conglinyizhi/dsh-console-backend"

version = "0.1.0"

readme = "README.md"

license = "Apache-2.0"

keywords = [ "dsh-console", "read-only", "local-api" ]

description = "dsh-console 的本地只读接口后端：与 Node 版响应形状逐字段一致"

preferred_target = "native"

import {
  "moonbitlang/moonback@0.8.6",
  "moonbitlang/async@0.22.4",
}

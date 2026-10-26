# DSH 控制台

[English](README.en.md) · [![CI](https://github.com/conglinyizhi/dsh-console/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/conglinyizhi/dsh-console/actions/workflows/ci.yml) · [![License: MIT](https://img.shields.io/badge/license-MIT-2ea44f.svg)](LICENSE)

![dsh-console 界面截图](docs/screenshot.png)

本机 DSH（DeepSeek Harness）的图形控制台：管 profile、起停实例、看日志。

一个 MoonBit 原生后端加一个 rabbita 前端。后端同时提供只读接口、可写动作与静态资源，
前端产物由它直接服务。同一个端口，不用另起服务。

作用范围：读 `~/.dsh` 下的 profile 与日志、探测本机在跑的 dsh 实例、按需起停实例、
管理 profile（派生 / 重命名 / 归档 / 删除 / 备注）与一组控制台设置。

给在本机跑 DSH 的人用。不想在终端里翻日志、拼 dsh 命令、对着 `~/.dsh` 数 profile 的时候，
用它把这几件事放到一页里看和点。它只服务本机，没打算做成远程面板。

> 非官方工具，与 DeepSeek 无隶属关系。

## 环境准备

- MoonBit 工具链（`moon`）：必需，前后端都用它构建。装法见
  [官方下载页](https://www.moonbitlang.com/download/)，装完确认 `moon version` 能跑
- C 编译器（clang 或 gcc）：必需。MoonBit 的 native 后端把生成的代码编成本机可执行文件
- bash：构建前端时用（`frontend/build.sh`）
- gzip：构建前端时用。它把 `app.js` 与 `app.css` 各压一份 `.gz`，后端在浏览器支持时直接发压缩版，
  首屏从约 3.4 MB 降到约 345 KB。没有它也能跑，只是首屏慢
- Node.js：可选。只用于端到端 smoke（`node scripts/smoke.mjs`），不装也能构建和运行

## 快速开始

```bash
# 1) 构建前端（产物落 frontend/dist）
cd frontend && ./build.sh

# 2) 构建后端（产物 backend/_build/native/debug/build/dsh-console-backend.exe）
cd ../backend && moon build --target native

# 3) 起服务（静态根会自动上溯到 frontend/dist，不用设环境变量）
./_build/native/debug/build/dsh-console-backend.exe
# → http://127.0.0.1:5390/
```

如果这台机器上还没装 DSH，页面会显示一张引导卡，并先用演示数据把界面摆出来。
这样可以先看看它长什么样。

想带着真实感的数据看、又不想碰自己的 `~/.dsh`：

```bash
./scripts/demo.sh          # 用三个示例 profile 起一份隔离的实例
```

> 本仓库的开发机上 `~/.moon` 挂的是只读文件系统，moon 写不进 registry 缓存。
> 所以本地构建跑在各目录下的 `.sandbox/moonhome` 里。`frontend/build.sh` 默认就用它，
> 后端要自己加 `MOON_HOME=$PWD/.sandbox/moonhome`。`~/.moon` 可写的机器和 CI 不用管这一条。
>
> 前端 `build.sh` 会自己导出 `MOON_CC=clang MOON_AR=ar MOON_LD=clang`。
> 后端手工构建时如果默认的 C 工具链不对，照抄这三个。

端口与静态根可以用环境变量覆盖（`DSH_CONSOLE_BACKEND_HOST` / `DSH_CONSOLE_BACKEND_PORT` /
`DSH_CONSOLE_DIST`），细节见 [backend/README.md](backend/README.md)。

## 它能做什么

### 看

只读 GET 接口：运行中的实例（端口 / profile / 版本 / DSH_HOME / 运行时长 / 握手地址）、
磁盘上的 profile（patch 行数、lock 时刻、插件声明与安装、缺包、备注）、日志（宿主 / 审计 / 某只实例）、
本机进程、控制台自身读数。

### 管

写动作统一走 `POST /api/local/action`：启动 / 停止 / 重启实例、派生副本、
重命名、编辑备注、归档 / 取消归档、删除、打开工作目录 / 打开配置。

### 回收站

侧栏「回收站」（`/trash`）列出删除进回收站的每一份（profile 名、删除时刻、文件数、体积），
能恢复回 profile 目录，也能彻底删掉。删完的回执只说「进回收站了」或「删掉了」，
路径和 `mode` 收在悬停里。

### 设置

设置页十二项（探测超时、探测并发、候选端口上限、端口起点、进程 detach 与停止宽限、
日志默认行数、归档区默认展开、beta 功能开关、宽屏侧栏是否收起、缺包警告、删除是否进回收站），
每一项都接到真实行为上。

## 安全边界

- 只绑 `127.0.0.1`，没有账号体系
- 写动作必须带 `X-DSH-Console: 1` 头并校验 `Origin`。这挡得住浏览器跨源页面触发，
  挡不住本机其它进程。那一层不在当前范围内
- 删除默认进回收站（`safety.deleteToTrash`）。硬删要在请求里带 `confirm: "DELETE"`，
  彻底删掉回收站里的一份要带 `confirm: "PURGE"`。两条都从 body 顶层读
- 「打开工作目录 / 打开配置」只接受枚举目标（profile 名 + kind），不接受客户端给的路径
- 起实例默认 detach：控制台被杀掉，已起的实例仍然活着（已实测）
- 实例的握手令牌从它的启动日志里读，只用于拼「打开 Web UI」的地址，不写进审计，不写进悬停

## 数据落在哪

```
$XDG_STATE_HOME/dsh-console/     settings.json  设置
                                 runtime.json   控制台起过的实例登记
                                 archive.json   归档记录
                                 audit.jsonl    审计（只追加；超限滚动）
                                 trash/         删除进回收站的去处
~/.dsh/                          使用者自己的 DSH 目录（profile / 日志 / 会话）
~/.dsh/logs/console-<profile>-<port>.log   控制台起实例时它的 stdout/stderr
```

## 仓库结构

```
backend/    MoonBit 原生后端：只读接口 + 可写动作 + 静态服务（含 gzip 与 history 回退）
frontend/   rabbita 前端（js 目标）+ precss 编的 SCSS；图标是内联 SVG
design/     验收装置：一键验收、若干探针、Vue 版基线、接口契约、待办队列、决策留档
VERSION     控制台版本（后端读它，关于页显示的就是这个）
```

## 验收

两层。第一层是端到端 smoke，不需要浏览器：它起一份隔离的后端，跑 23 条断言
（8 个只读接口、派生/改名/备注/归档/删除/恢复、5 条拒绝路径、首页与未知接口），
不碰你自己的 `~/.dsh`。

```bash
node scripts/smoke.mjs
```

第二层是界面验收，需要 Chromium：

```bash
node design/run-acceptance.mjs http://127.0.0.1:5390/
```

一条命令跑完二十多项判定：几何不变量（状态点跨卡对齐、按钮组右缘贴内容右缘、菜单锚点）、
交互（对话框居中且在最上层可点、取消与点遮罩能关、菜单每项都可点到）、
日志（滚动、级别配色、来源下拉含全部在跑实例）、动效、类名契约。
探针本身也验过：拿 Vue 版对旧基线跑，同一套判定同样全过。

装置与决策留档见 `design/`：`write-api-contract.md`（接口契约）、`backlog.md`（待办与悬着的验证）、
`frontend-parity-checklist.md`（与 Vue 版的对齐清单）。

## 持续集成

[.github/workflows/ci.yml](.github/workflows/ci.yml) 在 push 到 `main` 与 pull_request 时跑，
matrix 是 `ubuntu-latest` / `macos-latest` / `windows-latest`，三个平台上都做：
`moon check`、`moon test`（native 目标）、`moon build --target native`（都在 `backend/`）。
前端只在 ubuntu 与 macos 上构建（`frontend/build.sh` 依赖 bash、gzip、find、wc）。
MoonBit 工具链用官方安装脚本装，同分支的旧任务会被 concurrency 取消。

## 已知边界（没验过的、做不到的）

- 外部起的实例读不到握手令牌：令牌打在启动它的那个终端里，控制台无从读取。
  这类实例的「打开 Web UI」会说明原因并给出裸地址，不会给一个点了 401 的链接。
- 权限不足（EACCES）那条分支没有实测：沙箱里所有进程都属于自己，造不出真的权限拒绝。
  代码在，但没验过。
- 多用户 / hidepid 场景没覆盖：`/proc` 读不到别的用户进程时，只填得出端口。
- 路由是路径式（`/settings/safety`）。敲 hash 形式（`#/settings`）会落到首页，没有别名解析。
- 首屏靠 gzip：`app.js` 约 1.5 MB，压后约 170 KB（后端按 `Accept-Encoding` 发 `.gz`）。
  图标已经是内联 SVG，没有字体文件。
- 跑验收时动画探针会点一次「启动」，点到起不来的 profile（如 `headless`）会在
  `~/.dsh/logs/` 留一份一行的失败日志。探针会停掉自己起的实例，但**清不掉失败留下的日志**。
- 只在 Linux 上开发与测试：macOS 与 Windows 上代码可以通过类型检查（CI 三平台都跑），
  但运行时依赖 Linux 的 `/proc`：实例探测、进程归属、停止实例这几块还没有别的平台的实现，
  功能未验证。

## 许可证

本仓库（dsh-console）以 MIT 发布，见 [LICENSE](LICENSE)。Copyright (c) 2026 Clzhi。

用到的依赖（均为 Apache-2.0，与本仓库的 MIT 兼容）：

- [moonbitlang/core](https://github.com/moonbitlang/core)（MoonBit 标准库与运行时），Apache-2.0
- [moonbit-community/rabbita](https://mooncakes.io/docs/#/moonbit-community/rabbita) 0.15.7（前端框架），Apache-2.0
- [conglinyizhi/precss](https://mooncakes.io/docs/#/conglinyizhi/precss) 0.1.4（样式编译），Apache-2.0
- [moonbitlang/moonback](https://mooncakes.io/docs/#/moonbitlang/moonback) 0.8.6（HTTP 服务），Apache-2.0
- [moonbitlang/async](https://mooncakes.io/docs/#/moonbitlang/async) 0.22.4 / 0.21.2（异步 IO），Apache-2.0

第三方材料：

- 图标路径数据取自 @mdi/js 7.4.47（Pictogrammers，Apache-2.0 / Pictogrammers Free License）。
  取数与版权声明见 [frontend/vendor/licenses/mdi-NOTICE.md](frontend/vendor/licenses/mdi-NOTICE.md)；
  仓库只固化 26 条 SVG 路径常量，不分发上游字体与样式表。

> 说明：上述依赖的许可证依据是 MoonBit 包注册表的 `license` 声明（均为 Apache-2.0）。
> 精确版本包的 LICENSE 原文未随仓库分发，取包需联网。

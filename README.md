# DSH 控制台

本机 DSH（DeepSeek Harness）的图形控制台。一个 MoonBit 原生后端 + 一个 rabbita 前端，
后端同时提供只读接口、可写动作与静态资源，前端产物由它直接服务（同一个端口，无需另起服务）。

作用范围：读 `~/.dsh` 下的 profile 与日志、探测本机在跑的 dsh 实例、按需起停实例、
管理 profile（派生 / 重命名 / 归档 / 删除 / 备注）与一组控制台设置。

## 跑起来

```bash
# 1) 构建前端（产物落 frontend/dist）
cd frontend && MOON_HOME=$PWD/.sandbox/moonhome ./build.sh

# 2) 构建后端
cd ../backend && MOON_HOME=$PWD/.sandbox/moonhome \
  MOON_CC=clang MOON_AR=ar MOON_LD=clang moon build --target native

# 3) 起服务（静态根会自动上溯到 frontend/dist，不用设环境变量）
MOON_HOME=$PWD/.sandbox/moonhome ./_build/native/debug/build/dsh-console-backend.exe
# → http://127.0.0.1:5390/
```

`MOON_HOME` 必须是**各自目录下的** `.sandbox/moonhome`（那里才有依赖索引与缓存；
在仓库根下设会报 `Failed to resolve the module dependency graph`）。

端口、静态根、以及是否只读，都可以用环境变量覆盖（见 `backend/README.md`）。

## 它能做什么

**看**（只读，五个 GET 接口）：运行中的实例（端口 / profile / 版本 / DSH_HOME / 运行时长 / 握手地址）、
磁盘上的 profile（patch 行数、lock 时刻、插件声明与安装、缺包、备注）、日志（宿主 / 审计 / 某只实例）、
本机进程、控制台自身读数。

**管**（写动作，统一走 `POST /api/local/action`）：启动 / 停止 / 重启实例、派生副本、
重命名、编辑备注、归档 / 取消归档、删除、打开工作目录 / 打开配置。

**捞**：侧栏「回收站」（`/trash`）列出删除进回收站的每一份（profile 名、删除时刻、文件数、体积），
能恢复回 profile 目录，也能彻底删掉。删完的回执只讲「进回收站了 / 删掉了」，
路径与 `mode` 这些收在悬停里，不摊在正文上。

**配**：设置页十项（探测超时与并发、端口起点、进程 detach 与停止宽限、日志默认行数、
归档区默认展开、宽屏侧栏是否收起、删除是否进回收站），**每一项都接到真实行为上**。

## 安全边界（如实说，别当成登录）

- 只绑 `127.0.0.1`，**没有账号体系**
- 写动作必须带 `X-DSH-Console: 1` 头 + 校验 `Origin` —— 这挡得住浏览器跨源页面触发，
  **挡不住本机其它进程**（那一层不在当前范围内）
- 删除默认进回收站（`safety.deleteToTrash`）；硬删要在请求里带 `confirm: "DELETE"`，
  彻底删掉回收站里的一份要带 `confirm: "PURGE"`（两条都从 body **顶层**读）
- 「打开工作目录 / 打开配置」只接受枚举目标（profile 名 + kind），**不接受客户端给的路径**
- 起实例默认 detach：**控制台被杀掉，已起的实例仍然活着**（已实测）
- 实例的握手令牌从它的启动日志里读，**只用于拼「打开 Web UI」的地址，不写进审计、不写进悬停**

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

```bash
node design/run-acceptance.mjs http://127.0.0.1:5390/
```

一条命令跑完二十多项判定：几何不变量（状态点跨卡对齐、按钮组右缘贴内容右缘、菜单锚点）、
交互（对话框居中且在最上层可点、取消与点遮罩能关、菜单每项都可点到）、
日志（滚动、级别配色、来源下拉含全部在跑实例）、动效、类名契约。
**探针本身也验过**：拿 Vue 版对旧基线跑，同一套判定同样全过。

装置与决策留档见 `design/`：`write-api-contract.md`（接口契约）、`backlog.md`（待办与悬着的验证）、
`frontend-parity-checklist.md`（与 Vue 版的对齐清单）。

## 已知边界（没验过的、做不到的）

- **外部起的实例读不到握手令牌**：令牌打在启动它的那个终端里，控制台无从读取。
  这类实例的「打开 Web UI」会说明原因并给出裸地址，不会给一个点了 401 的链接。
- **权限不足（EACCES）那条分支没有实测**：沙箱里所有进程都属于自己，造不出真的权限拒绝。
  代码在，但没验过。
- **多用户 / hidepid 场景没覆盖**：`/proc` 读不到别的用户进程时，只填得出端口。
- **路由是路径式**（`/settings/safety`）。敲 hash 形式（`#/settings`）会落到首页，没有别名解析。
- **首屏靠 gzip**：`app.js` 约 1.5 MB，压后约 170 KB（后端按 `Accept-Encoding` 发 `.gz`）。
  图标已经是内联 SVG，没有字体文件。
- 跑验收时动画探针会点一次「启动」，点到起不来的 profile（如 `headless`）会在
  `~/.dsh/logs/` 留一份一行的失败日志。探针会停掉自己起的实例，但**清不掉失败留下的日志**。
## 许可证

本仓库（dsh-console）以 **MIT** 发布，见 [LICENSE](LICENSE)。Copyright (c) 2026 Clzhi。

用到的依赖（均为 Apache-2.0，与本仓库的 MIT 兼容）：

- [moonbitlang/core](https://github.com/moonbitlang/core)（MoonBit 标准库与运行时）— Apache-2.0
- [moonbit-community/rabbita](https://mooncakes.io/docs/#/moonbit-community/rabbita) 0.15.7（前端框架）— Apache-2.0
- [conglinyizhi/precss](https://mooncakes.io/docs/#/conglinyizhi/precss) 0.1.4（样式编译）— Apache-2.0
- [moonbitlang/moonback](https://mooncakes.io/docs/#/moonbitlang/moonback) 0.8.6（HTTP 服务）— Apache-2.0
- [moonbitlang/async](https://mooncakes.io/docs/#/moonbitlang/async) 0.22.4 / 0.21.2（异步 IO）— Apache-2.0

第三方材料：

- 图标路径数据取自 **@mdi/js 7.4.47**（Pictogrammers，Apache-2.0 / Pictogrammers Free License）。
  取数与版权声明见 [frontend/vendor/licenses/mdi-NOTICE.md](frontend/vendor/licenses/mdi-NOTICE.md)；
  仓库只固化 26 条 SVG 路径常量，不分发上游字体与样式表。

> 说明：上述依赖的许可证依据是 MoonBit 包注册表的 `license` 声明（均为 Apache-2.0）。
> 精确版本包的 LICENSE 原文未随仓库分发，取包需联网。

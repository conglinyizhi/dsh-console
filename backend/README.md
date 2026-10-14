# dsh-console 本地只读接口后端（MoonBit）

dsh-console 前端的只读本地接口，用 **MoonBit + moonback** 重写的一版后端。

- 只监听 `127.0.0.1:5390`
- 只答 `GET`，其它方法一律 405
- 只读文件系统：不写文件、不建目录、不删改、不创建进程
- JSON 响应形状与现有 Node 版（`../server/`，vite 中间件）**逐字段一致**，接入时只换 base URL

当前是第一批：脚手架 + 两个纯文件系统接口。

## 依赖

| 依赖 | 版本 | 说明 |
| --- | --- | --- |
| `moonbitlang/moonback` | 0.8.6 | HTTP 框架（官方组织，非已弃用的 hackwaly 源） |
| `moonbitlang/async` | 0.22.4 | 异步运行时与文件 IO（`moonbitlang/async/fs`） |

目标平台固定 `native`（`moon.mod` 里 `preferred_target = "native"`）：要读 `/proc`、要发 loopback 请求，wasm/js 做不了。

> **版本为什么不取最新**：本机 `~/.moon` 挂在**只读文件系统**上，`moon update` 无法刷新注册表索引，
> 索引停留在 2026-10-08，其中可见的最新版本是 moonback 0.8.6 / async 0.22.4（0.8.7 与 0.22.5 尚未进索引）。
> 只能在这两个版本上开发。要升级，需要一个可写的 MOON_HOME，见下面「构建」一节的说明。

## 构建

标准命令（依赖已缓存时可用）：

```bash
cd dsh-console/backend
moon check
moon build --target native
```

产物：`_build/native/debug/build/dsh-console-backend.exe`

**本机限制**：`~/.moon` 只读，moon 无法往全局 registry 缓存写东西（依赖未缓存时解析会失败）。
绕开办法是把 MOON_HOME 指到一个可写目录再构建：

```bash
cd dsh-console/backend
MOON_HOME="$PWD/.sandbox/moonhome" moon check
MOON_HOME="$PWD/.sandbox/moonhome" moon build --target native
```

`.sandbox/` 已在 `.gitignore` 里，属于本机权宜目录，不是工程的一部分。

## 运行

```bash
cd dsh-console/backend
./_build/native/debug/build/dsh-console-backend.exe
# 或者：moon run --target native .
```

启动后：

```
GET http://127.0.0.1:5390/api/local/runtime
GET http://127.0.0.1:5390/api/local/profiles
```

## 已实现的接口

### `GET /api/local/runtime`

对应 Node 版 `server/readRuntime.mjs`。字段：

| 字段 | 类型 | 口径 |
| --- | --- | --- |
| `consoleVersion` | string | 前端包版本（见「已知差异」） |
| `consolePackageName` | string | `dsh-console` |
| `dshVersion` | string | pnpm 全局目录里 `@deepseek-ai/dsh` 的 package.json version |
| `dshPackageName` | string | `@deepseek-ai/dsh` |
| `dshPackageDir` | string | 命中的安装目录绝对路径 |
| `dshSourceLabel` | string | `本机已安装` |
| `nodeVersion` | string | 固定值 `v26.11.1`（MoonBit 进程里没有 Node，见「已知差异」） |
| `dshHome` | string | `$DSH_HOME`，无则 `~/.dsh` |
| `dshHomeSource` | string | `DSH_HOME 环境变量` / `默认 ~/.dsh` |
| `dshProfile` | string \| null | `$DSH_PROFILE`，未设置给 null |
| `platform` | string | `linux x64 (7.2.9-arch1-1)` 形状 |

搜索顺序与 Node 版一致：`~/.local/share/pnpm/global/<槽>/node_modules/@deepseek-ai/dsh`、
`~/.pnpm-global/...`、`~/Library/pnpm/global/...`，外加每个 root 下的扁平 `node_modules`；
多份命中时取版本最大的一份（按版本段数字比较）。

### `GET /api/local/profiles`

对应 Node 版 `server/readProfiles.mjs`。扫 `$DSH_HOME/profiles/`（不递归，跳过 `node_modules` / `.git` / `.cache`），
profile 名按 JS 字符串序升序。每个 profile 的字段与取值口径见 `profiles/profiles.mbt`：

- `bundles.declared`：`package.json` 里 `dsh.profile.bundles` 的长度
- `installed / installedInProfile / installedHoisted`：按 bundle 是否落在 profile 自己的 `node_modules`、还是 `profiles/node_modules`（提升）统计
- `missing`：两处都没有的 bundle 名
- `patch.lines`：`cordis.patch.yml` 去掉末尾单个换行后的行数；文件不存在时 `{exists:false, lines:0}`
- `lock`：`pnpm-lock.yaml` 的存在性与 mtime（ISO8601，毫秒 3 位）；不存在给 `{exists:false, mtime:null}`

读不到的字段一律给 `null` / `0` / `[]`，不编。

### 未实现

`/api/local/logs`、`/api/local/processes`、`/api/local/instances` 返回 **501** + `{"code":"not-implemented"}`。
不返回空数组、不假装成功。

## 响应外壳与状态码

成功：

```json
{"ok":true,"readOnly":true,"readAt":"2026-10-14T10:56:27.361Z","data":{...}}
```

失败：

```json
{"ok":false,"readOnly":true,"error":{"code":"...","message":"..."}}
```

读取中途失败时额外带 `readAt`；405 / 404 这两条前置守卫不带（与 Node 版一致）。

| 场景 | 状态码 | code |
| --- | --- | --- |
| 非 GET | 405（带 `Allow: GET`） | `method-not-allowed` |
| 未知路径 | 404 | `not-found` |
| 未实现接口 | 501 | `not-implemented` |
| DSH_HOME 不是目录 | 500 | `dsh-home-missing` |
| 找不到 dsh 安装 | 500 | `dsh-package-missing` |
| profiles 目录不存在 | 500 | `profiles-missing` |
| 其它读取异常 | 500 | `read-failed` |

每个响应都带 `Content-Type: application/json; charset=utf-8`、`Cache-Control: no-store`、`X-Local-Api: read-only`。

## 只读铁律

- 全部文件访问集中在 `json/fsio.mbt` 与 `json/env.mbt`，只有这些调用：
  `@fs.read_file`、`@fs.exists`、`@fs.kind`、`@fs.readdir`、`@fs.mtime`
- 没有任何写 / 建 / 删 / 改名调用，也没有创建进程（不 import `moonbitlang/async/process` 与 `shell`）
- 凭据类文件（`.credentials.yaml` / `.env` / `.npmrc`）在 `read_text_file` 里按 basename 硬拦：只判断存在，绝不读内容
- 环境变量来自 `/proc/self/environ`，是本进程自己的环境，不是子进程

## 已知差异（与 Node 版）

1. **`consoleVersion`**：Node 版读前端 `dsh-console/package.json`；MoonBit 侧编译期读不到前端文件，
   当前固化常量 `"0.1.0"`（即本机前端 package.json 的实测值）。前端版本号变了要同步改 `runtime/runtime.mbt`。
   想彻底消除这一条，可以加一个构建期生成 `build_info.mbt` 的步骤（暂未做）。
2. **`nodeVersion`**：MoonBit 进程里不存在 Node，固定值 `v26.11.1`。这个字段的意义只是与 Node 版保持同形。
3. **`platform` 里的架构与内核版本**：Node 用 `os.arch()` / `os.release()`；
   MoonBit 标准库只给 OS 族（`moonbitlang/async` 的 `Platform`），架构是编译期常量 `x64`，
   内核版本读 `/proc/sys/kernel/osrelease`。本机实测值与 Node 完全一致。
4. **`readAt` 时间戳格式**与 Node 的 `toISOString()` 一致（UTC、毫秒 3 位、`Z` 结尾），
   只有时钟读数本身的差异。
5. **响应头字段名是小写**：线上发出的是 `x-local-api: read-only` / `cache-control: no-store`，
   Node 版是 `X-Local-Api` / `Cache-Control`。这是 moonback 的行为，不是本工程的选择：
   `moonback.MutHeaders::set` 存的名字大小写会保留，但 `Headers::iter`（真正写线的那一步）在小写化，
   用一页临时程序实测确认过（`set("X-Local-Api", ...)` 迭代出来是 `x-local-api`），当前没有任何 API 能绕开。
   HTTP 字段名按 RFC 9110 大小写不敏感，任何标准客户端（含 curl、fetch）取值都一致。
   **如果验收要求线上字节大小写也相同，需要绕开 moonback 的 Responder、直接用 `moonbitlang/async/http` 写响应头**，这是下一步可做的事。

## 目录结构

```
backend/
├── moon.mod                    # 模块定义、依赖、native 目标
├── moon.pkg.json               # 主包（可执行入口）
├── main.mbt                    # 起服务、注册路由、方法守卫接线
├── json/
│   ├── encode.mbt              # 有序 JSON 编码 + ISO8601 时间格式化
│   ├── fsio.mbt                # 全工程唯一的文件 IO 入口（只读）
│   ├── env.mbt                 # /proc/self/environ、HOME 解析
│   └── value.mbt               # core Json 的只读取值
├── localapi/
│   ├── api.mbt                 # 路由分发、错误码、方法名
│   └── respond.mbt             # 响应外壳与响应头
├── runtime/runtime.mbt         # GET /api/local/runtime
└── profiles/profiles.mbt       # GET /api/local/profiles
```
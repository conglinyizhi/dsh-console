# dsh-console 本地只读接口后端（MoonBit）

dsh-console 前端的只读本地接口，用 **MoonBit + moonback** 重写的一版后端。

- 默认只监听 `127.0.0.1:5390`（自测隔离可用 `DSH_CONSOLE_BACKEND_HOST` / `DSH_CONSOLE_BACKEND_PORT` 覆盖）
- **一个进程一个端口**：同一个端口既答 `/api/local/*`，也服务前端构建产物 `dist/`
  （静态根可用 `DSH_CONSOLE_DIST` 指定）
- 接口只答 `GET`，其它方法一律 405
- 只读文件系统：不写文件、不建目录、不删改、不创建进程
- JSON 响应形状与已退役的 Node 版中间件（`../server/`，见 git 0448ba4 可取回）**逐字段一致**。
  前端走的是同源相对路径 `/api/local/...`，所以「接入」不需要改 base URL：开发期由 Vite 代理到本服务，
  生产期由本服务同时供 `dist/` 与接口（一个进程、一个端口、同源）

第二批补齐 `logs` / `processes` / `instances` 三个接口，并修掉两处硬编码
（`nodeVersion` 伪造、`consoleVersion` 编译期固化）。五个只读接口全部落地。
第三批（A 形态，终局形态）让后端**接管前端静态服务**，并把实例探测从串行提到 **8 路并发**。

## 依赖

| 依赖 | 版本 | 说明 |
| --- | --- | --- |
| `moonbitlang/moonback` | 0.8.6 | HTTP 框架（官方组织，非已弃用的 hackwaly 源） |
| `moonbitlang/async` | 0.22.4 | 异步运行时、文件 IO（`async/fs`）、socket（`async/socket`） |

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
# 自测换端口（不占用 5390）：
DSH_CONSOLE_BACKEND_PORT=5391 ./_build/native/debug/build/dsh-console-backend.exe
# 显式指定前端构建产物（默认从可执行文件位置上溯找 dist/）：
DSH_CONSOLE_DIST=/path/to/dsh-console/dist ./_build/native/debug/build/dsh-console-backend.exe
```

启动日志会写清静态根解析结果（解析出来的目录、来源、SPA 回退落点，或失败原因）。

启动后（API 与前端同一端口）：

```
GET http://127.0.0.1:5390/                                   # dist/index.html
GET http://127.0.0.1:5390/assets/index-xxxxxxxx.js           # 构建产物，MIME 按后缀
GET http://127.0.0.1:5390/api/local/runtime
GET http://127.0.0.1:5390/api/local/profiles
GET http://127.0.0.1:5390/api/local/logs?source=host&tail=200
GET http://127.0.0.1:5390/api/local/processes
GET http://127.0.0.1:5390/api/local/instances
```

## 静态服务：一个进程一个端口接管前端

后端自己服务 `dist/`，前面不再需要挂 vite / nginx。

**静态根解析顺序**

1. `DSH_CONSOLE_DIST`：显式指定的目录必须含 `index.html` 与静态资源（`assets/` 目录，或同层有 `.js` / `.css` 文件）；
   **设了但目录不对就直接算失败**，不偷偷回退到第 2 步，原因写进启动日志与响应体（显式指的路径是错的，就该看得见）
2. 否则从 `/proc/self/exe` 的真实路径往上找（最多 8 层）：先看 `<层>/dist`，再看这一层本身，
   命中条件同上（`index.html` 加静态资源）。不硬编码任何绝对路径，覆盖
   `backend/_build/native/<profile>/build/<exe>` 与二进制被放进 `dist/` 两种部署方式

**SPA 回退**：`history_fallback = /index.html`（`unstable_static` 内部要求带前导斜杠，写 `index.html` 会被静默忽略）。
实体文件、静态目录都命中不了、且路径末段不含 `.` 时回落到 `index.html`；
`/assets/nope.js` 这类带后缀的路径不回退，如实 404。当前前端是状态切页、没有 URL 路由，这一条是为将来留的。

**API 优先级**：中间件链最外层是 `localapi.api_gate`，`/api/local` 与 `/api/local/*` 由它直接交给接口 handler，
静态中间件根本看不到这些请求（未实现接口的 404 错误壳、非 GET 的 405 都由 `dispatch` 照旧发出）。
这一层不是装饰：`history_fallback` 会把「下一跳返回 404」改写成 `index.html`，
未实现的接口一旦落进静态中间件就会从 JSON 错误壳变成一张 HTML 页面。

**解析失败不静默**：`DSH_CONSOLE_DIST` 指向不存在的目录时，启动日志写清原因，
非 `/api/local` 的 `GET` / `HEAD` 返回 `503` + `text/plain` 说明（不是 200 空白页），API 照常可用。

静态服务的文件访问走 moonback `unstable_static` 的 `kind` / `open(ReadOnly)`，本工程没有新增写调用点。

## 已实现的接口

### `GET /api/local/runtime`

对应已退役的 Node 版 `server/readRuntime.mjs`（git 0448ba4 可取回）。字段：

| 字段 | 类型 | 口径 |
| --- | --- | --- |
| `consoleVersion` | string / null | **运行时**读仓库根 `VERSION` 的版本（没有才退回前端 `package.json`，见下） |
| `consolePackageName` | string | `dsh-console` |
| `consoleVersionSource` | string | 上面那个版本号是怎么拿到的，或为什么没拿到 |
| `dshVersion` | string | pnpm 全局目录里 `@deepseek-ai/dsh` 的 package.json version |
| `dshPackageName` | string | `@deepseek-ai/dsh` |
| `dshPackageDir` | string | 命中的安装目录绝对路径 |
| `dshSourceLabel` | string | `本机已安装` |
| `backendRuntime` | string | `moonbit/native`：后端自己的运行时（**取代原 `nodeVersion`**） |
| `backendVersion` | string | 后端自身版本，与 `moon.mod` 的 `version` 一致 |
| `backendPackageName` | string | `conglinyizhi/dsh-console-backend` |
| `dshHome` | string | `$DSH_HOME`，无则 `~/.dsh` |
| `dshHomeSource` | string | `DSH_HOME 环境变量` / `默认 ~/.dsh` |
| `dshProfile` | string / null | `$DSH_PROFILE`，未设置给 null |
| `platform` | string | `linux x64 (7.2.9-arch1-1)` 形状 |

搜索顺序与 Node 版一致：`~/.local/share/pnpm/global/<槽>/node_modules/@deepseek-ai/dsh`、
`~/.pnpm-global/...`、`~/Library/pnpm/global/...`，外加每个 root 下的扁平 `node_modules`；
多份命中时取版本最大的一份（按版本段数字比较）。

**两处硬编码的修正（第二批）**：

1. **删掉 `nodeVersion`**。后端不跑 Node，硬编码 `"v26.11.1"` 就是编数据。
   现在如实报告后端自己：`backendRuntime` = `moonbit/native`、`backendVersion`、`backendPackageName`。
2. **`consoleVersion` 不再是编译期常量**，且**不再绑定前端的实现方式**：
   - **优先**：从 `/proc/self/exe` 的真实路径往上找含 **`VERSION`** 的目录（产品根），读那个文件的版本；
   - **兜底（换栈过渡期）**：没有 `VERSION` 时，按 `DSH_CONSOLE_DIR` / `DSH_CONSOLE_ROOT` /
     `DSH_CONSOLE_HOME` 环境变量，或上溯找**同时含 `package.json` 与 `src/`** 的目录，读它 `package.json` 的 `version`；
   - 任何一步失败都给 `null`，并把**用的是哪条路**写进 `consoleVersionSource`，不编。

   > 为什么加 `VERSION`：后端原先靠前端 `package.json` 读版本，而前端已经换栈成 MoonBit
   > （不再是 Vue 那套 `package.json` + `src/`）。绑定前端实现方式的话，删掉旧前端那一刻
   > 这个读数就会静默失效、关于页变成「未知」。

### `GET /api/local/profiles`

对应已退役的 Node 版 `server/readProfiles.mjs`（git 0448ba4 可取回）。扫 `$DSH_HOME/profiles/`（不递归，跳过 `node_modules` / `.git` / `.cache`），
profile 名按 JS 字符串序升序。每个 profile 的字段与取值口径见 `profiles/profiles.mbt`：

- `bundles.declared`：`package.json` 里 `dsh.profile.bundles` 的长度
- `installed / installedInProfile / installedHoisted`：按 bundle 是否落在 profile 自己的 `node_modules`、还是 `profiles/node_modules`（提升）统计
- `missing`：两处都没有的 bundle 名
- `patch.lines`：`cordis.patch.yml` 去掉末尾单个换行后的行数；文件不存在时 `{exists:false, lines:0}`
- `lock`：`pnpm-lock.yaml` 的存在性与 mtime（ISO8601，毫秒 3 位）；不存在给 `{exists:false, mtime:null}`

### `GET /api/local/logs?source=...&tail=...`

对应已退役的 Node 版 `server/readLogs.mjs`（git 0448ba4 可取回）。

**来源白名单**（只此三类，不接受任意路径）：

| source | 文件 |
| --- | --- |
| `host` | `~/.dsh/logs/retry-control/host.log` |
| `audit` | `~/.dsh/linxi-guard-audit.jsonl` |
| `instance:<实例 id>` | 该实例 DSH_HOME 下 `logs/` 里按 mtime 最新的一个可读日志文件 |

`tail` 口径（与 Node 版 `parseTail` 逐条对齐）：

| 输入 | 行为 |
| --- | --- |
| 没给 / 空串 | 缺省 200 |
| 非数字 / 小于等于 0 | **400 `bad-tail`**（`tail 只接受正整数`） |
| 大于 1000 | 收敛到 1000，响应里额外带 `tailNote`（`tail 超过上限 1000，按 1000 返回`） |

**读法**：反向分块读尾，从文件末尾往回 64KB 起、不够翻倍、单次窗口封顶 4MB；
行数多于 `tail` 时只保留末尾 `tail` 行；窗口内只容得下 1 行时如实回 `truncated` + `truncatedNote`。
**不整份读进内存**（`json/tailread.mbt`）。

**行解析**：

- `host`：`ISO 时间 + [插件@版本] + 正文` 拆出 `time`（只留时间部分）与 `text`；拆不出的整行原样保留
- `audit`：JSONL 压成一行文本（`tool · verdict/outcome · [reviewMode] · 命令短片段`），
  命令超 72 字符截断；**不倒原始 JSON**
- 级别判定按**非字母数字切词**后比对（`error`/`failed`/`failure`/`exception` 归 error；
  `warn`/`warning` 归 warn）。**不用词边界**：下划线算词字符，
  `code=PI_AI_ERROR` 这种真实错误行会整片漏标
- 单行正文超 400 字符只做展示裁剪并加省略号

实例来源找不到时回结构化错误：`unknown-instance`；实例日志目录没有可读文件回 `no-log-file`；
实例没暴露 DSH_HOME 时回退 `~/.dsh` 并如实回 `homeSource`。

### `GET /api/local/processes`

对应已退役的 Node 版 `server/readProcesses.mjs`（git 0448ba4 可取回）。纯读 `/proc`，不 spawn `ps` / `ss` / `lsof`。

- 匹配：可执行名精确为 `dsh`（`.js` / `.mjs` / `.cjs`）**或**路径段含 `@deepseek-ai/dsh/`
- `--port` **不再是必需条件**：有就读出来，没有记 `null`，不因此丢掉进程
- `profile` 取 `--profile` / `--profile=x`；`dshHome` 取 `/proc/<pid>/environ` 的 `DSH_HOME`
- `startedAt` 由 `/proc/<pid>/stat` 第 22 字段（starttime）+ `/proc/uptime` 换算
- 读不到的字段一律 `null`，不编

### `GET /api/local/instances`

对应已退役的 Node 版 `server/readInstances.mjs`（git 0448ba4 可取回）。口径是「loopback LISTEN 端口 + HTTP 签名」。

- 读 `/proc/net/tcp` 与 `/proc/net/tcp6`，筛 `st=0A`（LISTEN）且本地地址是 loopback
  （`127.0.0.1` / `::1` / `::ffff:127.0.0.1`，`/proc/net` 里按小端十六进制写）的端口
- 去重、升序、**上限 40**（超了截断并在响应里说明）
- 对每个候选端口发一次 `GET http://127.0.0.1:<端口>/`：超时 500ms、不跟随重定向、
  **只读前 8KB** 响应体
- **8 路并发**（与 Node 版 `PROBE_CONCURRENCY` 同数，`probe.concurrency` 如实回 `8`）：
  结果顺序仍按端口升序——`@async.all` 按下标收集，谁先回来不影响排序。
  真实并发 = `min(8, 候选数)`。40 个黑洞端口实测：串行 17.1s → 8 路 2.52s
- 两条签名判据（命中的 id 回显在响应里）：
  - `dsh-auth-401`：HTTP 401 且体含 `dsh web authentication required`
  - `dsh-boot-global`：体含 `__DSH_BOOT__`
  - **绝不用「含 DSH 字样」当判据**：本控制台自己的页面标题就带 DSH，那样会把自己列成实例
- 响应带元信息：`candidates` / `candidateCount` / `candidateLimit` / `truncated` / `truncatedNote` /
  `probe`（method、redirect、timeoutMs、concurrency、probed、reached、hits）/ `perFile` /
  `signatures` / `processSupplement`

## 响应外壳与状态码

成功：

```json
{"ok":true,"readOnly":true,"readAt":"2026-10-14T10:56:27.361Z","data":{}}
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
| 缺 source 参数 | 400 | `missing-source` |
| source 不在白名单 | 400 | `unknown-source` |
| tail 非正整数 | 400 | `bad-tail` |
| 实例 id 不存在 | 200（data 里 `readOk:false`） | `unknown-instance` |
| 实例没有可读日志 | 200（data 里 `readOk:false`） | `no-log-file` |
| DSH_HOME 不是目录 | 500 | `dsh-home-missing` |
| 找不到 dsh 安装 | 500 | `dsh-package-missing` |
| profiles 目录不存在 | 500 | `profiles-missing` |
| 日志文件读不动 | 200（data 里 `readOk:false`） | `read-failed` / `instance-read-failed` |
| 其它读取异常 | 500 | `read-failed` |

每个响应都带 `Content-Type: application/json; charset=utf-8`、`Cache-Control: no-store`、`X-Local-Api: read-only`。

## 只读铁律

- 全部文件访问集中在 `json/fsio.mbt`、`json/env.mbt`、`json/tailread.mbt`、`json/version.mbt`，只有这些调用：
  `@fs.read_file`、`@fs.exists`、`@fs.kind`、`@fs.readdir`、`@fs.mtime`、`@fs.realpath`、
  `@fs.file_size`、`@fs.open(ReadOnly)` + `File::read_at`（定位读尾部用）
- 没有任何写 / 建 / 删 / 改名调用，也没有创建进程
  （不 import `moonbitlang/async/process` 与 `moonbitlang/async/shell`）
- 凭据类文件（`.credentials.yaml` / `.env` / `.npmrc`）在 `read_text_file` / `read_some_at` 里按 basename 硬拦：
  只判断存在，绝不读内容
- 环境变量来自 `/proc/self/environ`，是本进程自己的环境，不是子进程
- 静态服务（`dist_static/`）只调 `@json.exists` / `@json.is_dir` / `@json.exe_path` / `@json.env_value`，
  真正读文件的是 moonback `unstable_static` 的 `@fs.kind` 与 `@fs.open(ReadOnly)`：新增的只有**读**，
  `grep` 写 / spawn 关键词在 `.mbt` 里 0 命中（只有注释里出现过「不 spawn、不写盘」这句话）
- 唯一的网络动作是**对 127.0.0.1 候选端口发一次 GET**（写死回环地址、写死 GET、读完即断）

## 已知差异（与 Node 版）

1. **探测走 socket 直连，不走 `@http` 客户端**。
   实测：`moonbitlang/async/http` 的 `@http.Client(uri, headers~)` 在服务进程里
   （moonback handler 的协程上下文）构造就抛 `ResolveHostnameError("Name or service not known")`；
   同一条调用在 handler 里内联执行是成功的，在独立程序里也是成功的，原因未定位。
   因此探测改用已验证可用的 `Tcp::connect(Addr::parse("127.0.0.1:<端口>"))` 加一个极简
   HTTP/1.1 客户端（`localapi/rawhttp.mbt`：支持 Content-Length 定长 / chunked 分块 / 读到 EOF）。
   对外行为不变：GET、500ms 超时、不跟随重定向、只读前 8KB。
2. **探测并发已与 Node 对齐**：两边都是 8 路，`probe.concurrency` 如实回 `8`，
   候选上限 40、单个 500ms 的口径没动。40 个「接受连接但不回 HTTP」的黑洞端口实测：
   串行（改前）17.1s，8 路（改后）2.52s。
3. **`processSupplement.scanned` / `processes.scanned` 可能比 Node 小**：两边都读同一个 `/proc`，
   但本后端的沙箱有 PID 命名空间隔离（`/proc` 里只能看到自己那几个进程），Node 版跑在宿主命名空间里。
   口径相同，差异来自运行环境。
4. **`probeMs`** 是每次实测的毫秒数，天然会波动。
5. **`platform` 里的架构与内核版本**：Node 用 `os.arch()` / `os.release()`；
   MoonBit 标准库只给 OS 族（`moonbitlang/async` 的 `Platform`），架构是编译期常量 `x64`，
   内核版本读 `/proc/sys/kernel/osrelease`。本机实测值与 Node 完全一致。
6. **`readAt` 时间戳格式**与 Node 的 `toISOString()` 一致（UTC、毫秒 3 位、`Z` 结尾），
   只有时钟读数本身的差异。
7. **响应头字段名是小写**：线上发出的是 `x-local-api: read-only` / `cache-control: no-store`，
   Node 版是 `X-Local-Api` / `Cache-Control`。这是 moonback 的行为，不是本工程的选择：
   `moonback.MutHeaders::set` 存的名字大小写会保留，但 `Headers::iter`（真正写线的那一步）在小写化，
   用一页临时程序实测确认过（`set("X-Local-Api", ...)` 迭代出来是 `x-local-api`），当前没有任何 API 能绕开。
   HTTP 字段名按 RFC 9110 大小写不敏感，任何标准客户端（含 curl、fetch）取值都一致。

## 接入前端时要注意的一件事（「关于」页）

后端换掉之后，`/api/local/runtime` 的响应里**已经没有 `nodeVersion` 这个字段**，
多了 `backendRuntime` / `backendVersion` / `backendPackageName` / `consoleVersionSource`。
所以「关于」页原来那一行「node 版本：vX.Y.Z」需要相应调整：

- 语义变了：Node 版那一行说的是**跑服务的 Node 运行时**；这个后端不跑 Node，
  同一行的正确含义是**后端自己的运行时与版本**。
- 建议把这一行拆成/改成：
  - 「后端运行时」→ `backendRuntime` + `backendVersion`（例如 `moonbit/native 0.1.0`）；
  - 想保留「Node 版本」这一行，就必须从别处取（前端自己拿不到宿主 Node 版本），
    最省事的做法是直接删掉这一行，或改成显示 `dshVersion` / `consoleVersion`。
- `consoleVersion` 现在可能是 `null`（读不到前端 `package.json` 时），展示上要能兜住；
  `consoleVersionSource` 写明了来源或失败原因，调试时可以直接显示。

## 目录结构

```
backend/
├── moon.mod                    # 模块定义、依赖、native 目标
├── moon.pkg.json               # 主包（可执行入口）
├── main.mbt                    # 起服务、中间件顺序（API 闸门 → 静态 → 路由）、监听地址解析
├── json/                       # 共用基础层（本工程唯一的只读文件 IO 入口）
│   ├── encode.mbt              # 有序 JSON 编码 + ISO8601 格式化 + ISO 时间取时分秒
│   ├── text.mbt                # 字符串/字节工具、级别切词、错误类型
│   ├── fsio.mbt                # 只读文件访问入口（含定向读 read_some_at）
│   ├── tailread.mbt            # 反向分块读文件尾部
│   ├── version.mbt             # 后端自身版本 + 前端 package.json 的运行时读取
│   ├── env.mbt                 # /proc/self/environ、HOME 解析
│   └── value.mbt               # core Json 的只读取值
├── localapi/
│   ├── api.mbt                 # 路由分发、查询参数、错误码、方法名、API 优先闸门
│   ├── respond.mbt             # 响应外壳与响应头
│   ├── probe.mbt               # 单端口只读探测 + 8 路并发批量探测（保序）
│   └── rawhttp.mbt             # 极简 HTTP/1.1 客户端（回环探测专用）
├── dist_static/
│   └── dist_static.mbt         # 静态根解析、dist 静态中间件、SPA 回退、解析失败时的 503
├── runtime/runtime.mbt         # GET /api/local/runtime
├── profiles/profiles.mbt       # GET /api/local/profiles
├── logs/logs.mbt               # GET /api/local/logs
├── processes/processes.mbt     # GET /api/local/processes
└── instances/instances.mbt     # GET /api/local/instances
```

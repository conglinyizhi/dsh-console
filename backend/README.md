# dsh-console 本地接口后端（MoonBit）

dsh-console 前端的本地接口，用 **MoonBit + moonback** 实现的一版后端。接口分两层：

- **只读（GET，纯只读）**：`runtime` / `profiles` / `logs` / `processes` / `instances`
  —— 形状与已退役的 Node 版中间件（`../server/`，见 git 0448ba4 可取回）**逐字段一致**，这一层一个字段都不动
- **写（第三批新增）**：`POST /api/local/action`（八个动作）、`GET/PUT /api/local/settings`、
  `GET /api/local/console`（运行时登记与归档的只读出口）
  —— 契约见 `../design/write-api-contract.md`

- 默认只监听 `127.0.0.1:5390`（自测隔离可用 `DSH_CONSOLE_BACKEND_HOST` / `DSH_CONSOLE_BACKEND_PORT` 覆盖）
- **一个进程一个端口**：同一个端口既答 `/api/local/*`，也服务前端构建产物 `dist/`
  （静态根可用 `DSH_CONSOLE_DIST` 指定）
- 只读接口只答 `GET`（其它方法 405）；写动作只走 `POST /api/local/action`，且必须带 `X-DSH-Console: 1`
- 前端走的是同源相对路径 `/api/local/...`，所以「接入」不需要改 base URL

第一批落地四个只读接口；第二批补齐 `logs` / `processes` / `instances`，并修掉两处硬编码
（`nodeVersion` 伪造、`consoleVersion` 编译期固化）。第三批（A 形态）让后端**接管前端静态服务**，
并把实例探测从串行提到 **8 路并发**。第四批（本轮）加上**可写层**：
八个动作真的起停进程 / 动 profile 目录，四项设置真的接到探测、端口分配、起停与日志缺省上。

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
GET http://127.0.0.1:5390/api/local/settings
GET http://127.0.0.1:5390/api/local/console
```

写动作（本机 curl 直连没有 Origin，只需要那个自定义头）：

```bash
curl -X POST http://127.0.0.1:5390/api/local/action \
  -H 'Content-Type: application/json' -H 'X-DSH-Console: 1' \
  -d '{"action":"start-instance","params":{"profile":"web"}}'

curl -X PUT http://127.0.0.1:5390/api/local/settings \
  -H 'Content-Type: application/json' -H 'X-DSH-Console: 1' \
  -d '{"values":{"instance.basePort":8500,"logs.defaultTail":50}}'
```

## 静态服务：一个进程一个端口接管前端

后端自己服务 `dist/`，前面不再需要挂 vite / nginx。

**静态根解析顺序**

1. `DSH_CONSOLE_DIST`：显式指定的目录必须含 `index.html` 与静态资源（`assets/` 目录，或同层有 `.js` / `.css` 文件）；
   **设了但目录不对就直接算失败**，不偷偷回退到第 2 步，原因写进启动日志与响应体（显式指的路径是错的，就该看得见）
2. 否则从 `/proc/self/exe` 的真实路径往上找（最多 8 层）：先看 `<层>/dist`，再看这一层本身，
   命中条件同上（`index.html` 加静态资源）。**每一层的候选顺序**：`<层>/frontend/dist` → `<层>/dist` → 这一层本身——新栈优先，旧产物没删之前不会一直供着过期页面。不硬编码任何绝对路径，覆盖
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

只读五个（形状与 Node 版逐字段一致）+ 写侧三条（`POST /api/local/action`、`GET/PUT /api/local/settings`、
`GET /api/local/console`，见「可写层」一节）。

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
| 没给 / 空串 | 缺省取设置 `logs.defaultTail`（缺省 200） |
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
- 去重、升序、**候选上限取设置 `probe.maxCandidates`（缺省 40）**（超了截断并在响应里说明）
- 对每个候选端口发一次 `GET http://127.0.0.1:<端口>/`：超时取设置 `probe.timeoutMs`（缺省 500ms）、不跟随重定向、
  **只读前 8KB** 响应体
- **并发取设置 `probe.concurrency`（缺省 8，与 Node 版 `PROBE_CONCURRENCY` 同数）**，响应里回的就是生效值：
  结果顺序仍按端口升序——`@async.all` 按下标收集，谁先回来不影响排序。
  真实并发 = `min(8, 候选数)`。40 个黑洞端口实测：串行 17.1s → 8 路 2.52s
- 两条签名判据（命中的 id 回显在响应里）：
  - `dsh-auth-401`：HTTP 401 且体含 `dsh web authentication required`
  - `dsh-boot-global`：体含 `__DSH_BOOT__`
  - **绝不用「含 DSH 字样」当判据**：本控制台自己的页面标题就带 DSH，那样会把自己列成实例
- 响应带元信息：`candidates` / `candidateCount` / `candidateLimit` / `truncated` / `truncatedNote` /
  `probe`（method、redirect、timeoutMs、concurrency、probed、reached、hits）/ `perFile` /
  `signatures` / `processSupplement`

**端口 → 进程（把卡上的 Profile / DSH_HOME / 版本 / 运行时长填出来）**

HTTP 签名只回答「这个端口是不是 DSH web」，回答不了「它是哪只实例」。宿主上的实例命令行是
`node …/node_modules/@deepseek-ai/dsh/lib/bin.js --profile web --no-open`：**没有 `--port`**，
environ 里也**没有任何 DSH_***，靠命令行认不出它监听哪个端口。所以补一条内核给的对应关系：

1. `/proc/net/tcp(6)` 那行的**第 9 列 socket inode**（解析端口时一并带回，见 `ListenSocket`）
2. 扫 `/proc/<pid>/fd/*` 的**链接目标**，找 `socket:[<inode>]` → 得到 **PID**
   （全工程唯一一处 C 代码 `json/fd_link.c`：一次 `readlink(2)`，MoonBit 的 fs 层有 realpath、没有它）
3. `/proc/<pid>/cmdline` 读 `--profile`；`/proc/<pid>/environ` 读 `DSH_HOME`，
   没有就看 fd 表里 `…/.dsh/…` 路径的前缀，都没有才落默认 `$HOME/.dsh`（来源写进 `dshHomeSource`）
4. 入口路径里 `node_modules/@deepseek-ai/dsh` 这一段的 `package.json` → `version`（软链入口先 realpath）
5. `/proc/<pid>/stat` 第 22 字段 + `/proc/uptime` → `startedAt` / `uptimeSeconds`

实例对象因此多出：`inode` / `version` / `versionSource` / `profileSource` / `dshHomeSource` /
`processReason{code,message}`，`profile` / `pid` / `dshHome` / `exePath` / `startedAt` /
`uptimeSeconds` 也由这条 join 填。`processSupplement` 多出 `socketInodes` / `inodeHolders` /
`fdDenied` / `joinNote`。

进程级原因码（读不到时给前端区分用，不编值）：

| code | 含义 |
|---|---|
| `port-join` | 端口对应的 socket inode 在 `/proc/<pid>/fd` 里对到了持有进程 |
| `port-arg` | inode 对不上，退回按 cmdline 的 `--port` 匹配（证据比 inode 弱） |
| `process-gone` | 端口仍 LISTEN，但没有可见进程持有该 socket：进程已退出，或不在本 PID 命名空间 / 属于别的用户 |
| `fd-unreadable` | `/proc/<pid>/fd` 读不到（权限不足或 hidepid） |
| `cmdline-unreadable` | 进程在，但 `/proc/<pid>/cmdline` 读不到 |
| `unscanned` | 没拿到该端口的 socket inode（`/proc/net/tcp(6)` 读不到） |

**HTTP 签名探测保留**：它既是「这端口真的是 DSH web」的交叉校验，也是 `/proc` 侧读不到时的回退口径。
两边都读不到才是真的读不到。

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

写侧的壳与上面对称，只是 `readOnly` 为 `false`、`X-Local-Api: read-write`：

```json
{"ok":true,"readOnly":false,"readAt":"2026-10-15T07:17:44.588Z","data":{"action":"start-instance","outcome":{}}}
{"ok":false,"readOnly":false,"readAt":"…","error":{"code":"conflict","message":"profile web-dev 已经在跑（PID 278412，端口 8400）…"}}
```

`GET /api/local/settings` 与 `GET /api/local/console` 是只读端点，走只读壳（`readOnly:true`）。

## 可写层（第四批，本轮）

契约是 `../design/write-api-contract.md`，实现全在 `actions/` 与 `fsx/` 两个包里。

### 写动作只有一个入口

```
POST /api/local/action
Headers（必须）: X-DSH-Console: 1 ；Origin 只能缺省或本机回环（http://127.0.0.1 / http://localhost / http://[::1]）
Body: { "action": "<动作名>", "params": { ... } }   delete-profile 硬删时另带 "confirm":"DELETE"
```

守卫顺序：方法 → 解析 body → 守卫 → 执行 → 审计 → 应答。**解析在守卫前是有意的**：解析没有副作用，
先回「body 不对」比先回 403 更好排查。守卫不过回 `403 not-authorized`，其余按码给状态：
`unknown-action`/`bad-params` 400、`not-found` 404、`conflict` 409、`spawn-failed`/`stop-failed`/`io-error` 500。

为什么这样挡得住网页跨源触发：浏览器不允许跨源请求带自定义头，预检会先拦掉；Origin 校验再挡一层。
**对「本机恶意进程」不设防** —— 那一层不在这轮范围（契约第一节写明）。

### 八个动作

| action | 真实做的事 | 关键边界 |
| --- | --- | --- |
| `start-instance` | `node <dsh包目录>/lib/bin.js --profile <名> --no-open --port <端口>`，等它答出 dsh web 签名才算起成功 | 同 profile 已在跑 → `conflict`（message 里有 pid 与端口）；端口占用 → `conflict`；起不来 → 收掉子进程，message 给「参数被拒」的人话诊断（见「哪些 profile 能起成常驻实例」）或日志尾部 |
| `stop-instance` | SIGTERM → 等 `process.stopGraceMs` → 仍在则 SIGKILL | 目标必须在运行登记或进程表里认得出是 dsh，否则 `not-found`（不误杀别的 pid） |
| `restart-instance` | 先停后起，端口与 profile 沿用原来的 | 认不出 profile → `not-found` |
| `fork-profile` | 递归复制 profile 目录（**跳过 node_modules**，那是 pnpm 安装产物，提升目录仍解析得到） | 新名默认 `<原名>-dev`，重名自动加 `-2`/`-3`…；给了 port 就顺手把新 profile 起起来 |
| `rename-profile` | 改磁盘上的目录名 | 空名 / 非法字符 / 重名 / 正在运行 都拒 |
| `archive-profile` | 往 `archive.json` 追加一条（`merged` 表示成果是否已回灌主线） | **不动磁盘上的 profile** |
| `unarchive-profile` | 删掉那条记录 | 没有这条 → `not-found` |
| `delete-profile` | `safety.deleteToTrash=true` 时整目录移进 `<状态目录>/trash/<名>-<毫秒>`；false 时递归硬删 | 硬删必须带 `"confirm":"DELETE"`，否则 `bad-params`；正在运行 → `conflict` |

起实例的两条实测细节（都在代码注释里）：

1. **端口 ≠ 可服务**。服务先 bind、路由后挂载，中间那几百毫秒 `GET /` 回的是 404。
   只等端口会让只读的 `instances` 接口在这一刻认不出刚起的实例。所以等的是
   **dsh web 签名**（401 + `dsh web authentication required`，或页里有 `__DSH_BOOT__`）。
2. **僵尸进程的 kill(pid,0) 也成功**。判活不能只看 `kill(pid,0)`，还要看 `/proc/<pid>/stat` 的状态位，
   `Z` 按死处理；否则停止动作会一直报「SIGKILL 之后仍然在」。

### 哪些 profile 能起成常驻实例

起实例的 argv 是 `node <dsh包目录>/lib/bin.js --profile <名> --no-open --port <端口>`。
这里有一条容易踩的事实：**dsh 启动器只认 `--profile`，其余参数原样转给该 profile 的 app**
（`dsh --help`：`Usage: dsh [--profile] <name> [options] [app-args...]`）。
`--no-open` / `--port` 是 **app 的参数**——`dsh web --help` 里才列着它们，`dsh --help` 里没有。

所以能不能起成常驻实例，取决于这只 profile 的 app 认不认这两个参数：

| profile 的形状 | 例子 | 起实例的结果 |
| --- | --- | --- |
| 服务型 app（bundles 里有 `@deepseek-ai/dsh-web-app`） | `web`、`review-dev` | 认这两个参数，起得来：等它答出 dsh web 签名，返回 pid / 端口 / 日志路径 |
| 非服务型 app | `headless`（`@deepseek-ai/dsh-headless`：答一个任务、打印结果、退出） | 不认：子进程立刻回 `error: unknown option '--no-open'` 并以退出码 1 结束 |

**判断不看 profile 名字，只看事实。** 起失败时只读*本次启动新写出来的那段日志*
（同一个日志文件是追加写的，spawn 前记下文件大小，上一次尝试留下的行不算这一次的证据），
看里面有没有「不认识的选项」这类行（`unknown option` / `unknown argument` /
`unrecognized option` / `unrecognized argument` / `unknown flag` / `unexpected argument` /
`invalid option`）。被点名的选项还得是**我们传下去的那几个**（`--no-open` / `--port`）：
别人报别人的名字，就不往服务参数上归因（`--profile` 是启动器自己的，不算）。

**失败时用户看到什么**（错误码仍是契约里那七个之一 `spawn-failed`，HTTP 500，没有新增错误码）：

- **命中「参数被拒」**：给一句人话 + 证据 + pid / 日志路径 + 后续建议，
  **不把日志尾巴当正文丢出去**：

  ```json
  {"ok":false,"readOnly":false,"readAt":"2026-10-15T07:40:00.000Z","error":{
    "code":"spawn-failed",
    "message":"profile headless 的 app 不接受服务参数（--no-open），它不是服务型 profile，起不成常驻实例。子进程已经退出（pid 4321，日志 /home/u/.dsh/logs/console-headless-8400.log）。日志里写着：error: unknown option '--no-open'。要跑这种 profile，按它自己的用法跑一次（dsh --profile headless …），别拿它起常驻实例"}}
  ```

- **没命中**（启动就崩、bundle 解析不了、profile 自身有毛病等）：维持原来的形状 ——
  `实例没起来（pid …，日志 …）：<收尾说明>；日志尾部：…`，尾部的口径同样是**本次启动新写出来的那几行**。
  那时日志尾巴就是最好的证据，如实贴出来比套一句结论有用。
  实测负例（bundles 里挂一个不存在的包）：message 如实给出
  `dsh: cannot resolve profile bundle …`，没有被误判成「服务参数被拒」。

`restart-instance` 与 `fork-profile` 带 port 时走的是同一条起实例路径，诊断一致。

### `process.detach` 的两种语义

- `true`：`spawn_orphan`，完全脱离控制台。控制台正常退出、被 SIGTERM、被 SIGKILL，它都活着
  （实测：控制台 SIGKILL 之后实例仍在听端口，`GET /` 仍回 401）。
- `false`：实例挂在**控制台主任务组**上（`@process.spawn(group, …, no_wait=true)`，
  `cancel_handler = graceful_cancel(timeout=stopGraceMs)`）。控制台退出时由运行时的结构化并发收掉它
  （实测：控制台 SIGTERM 之后实例消失）。

> 为什么不是「`app.serve` 之后写收尾代码」：moonbitlang/async 在全局取消信号之后会把信号重新抬起来交给
> 默认处理，实测控制台退出码 143，`serve` 之后的语句**一句都跑不到**。因此 detach=false 只能挂在任务组上。

### 设置（每一项都接到真实行为上）

`GET /api/local/settings` → `{ ok, readOnly:true, readAt, data:{ path, values, defaults, sources, note } }`；
`PUT /api/local/settings` body `{ "values": { … } }` → 校验后**原子写**（同目录临时文件 + rename），返回新值。

| key | 缺省 | 接到哪（都实测过） |
| --- | --- | --- |
| `probe.timeoutMs` | 500 | 实例签名探测的单口超时（`instances.probe.timeoutMs` 回显的就是生效值） |
| `probe.concurrency` | 8 | 探测并发（`instances.probe.concurrency` 回显） |
| `probe.maxCandidates` | 40 | 候选端口上限（`instances.candidateLimit` 回显，超了照旧截断并带 `truncatedNote`） |
| `instance.basePort` | 8400 | 起实例 / 派生时找空闲端口的起点（实测改 8500 后新实例就在 8500） |
| `process.detach` | true | 起实例是否脱离控制台（见上一节） |
| `process.stopGraceMs` | 5000 | 停止时 SIGTERM 到 SIGKILL 的宽限（实测 grace=0 → 直接 SIGKILL，`sigkillSent:true`；grace=5000 → 只发 SIGTERM） |
| `logs.defaultTail` | 200 | 日志接口不带 tail 参数时的缺省（实测 50 → 回 50 行，500 → 回 500 行；显式 tail 不受影响） |
| `ui.archiveOpenByDefault` | false | 前端读 `GET /api/local/settings` 决定归档区默认展开（后端负责存取与回显） |
| `safety.deleteToTrash` | true | 删除进回收站还是硬删（见上表） |

取值范围（越界即 `bad-params`，不静默夹取）：`probe.timeoutMs` 50..60000、`probe.concurrency` 1..64、
`probe.maxCandidates` 1..1000、`instance.basePort` 1..65535、`process.stopGraceMs` 0..600000、
`logs.defaultTail` 1..1000（布尔键只认布尔）。

**读不到就用缺省，坏文件不让接口挂掉**：`settings.json` 不存在 → 全部按缺省、`sources` 全是「默认」；
读不动 / 解析失败 / 某一项取值非法 → 那一项按缺省，原因写进 `sources` 的对应键
（形如 `"默认（<路径> 里的值不可用：超出取值范围 …）"`），文件级问题另放在 `data.note`。

### 运行时登记、归档与审计

| 文件 | 内容 | 写时机 |
| --- | --- | --- |
| `runtime.json` | 控制台**自己起过**的实例：`{ pid, port, home, profile, startedAt, logPath, detached }` | 起实例成功 / 停止 / 重启 |
| `archive.json` | 归档记录：`{ profile, merged, archivedAt }` | 归档 / 取消归档 |
| `audit.jsonl` | 每个动作一行：`{ at, action, params, ok, code, message, outcome }`，**只追加、不轮转** | 每个动作（含失败与 403）、以及 settings 的 PUT |

外部已有的实例不写进 `runtime.json`。对账（pid 已消失就清理）发生在**动作里**，不发生在 GET：
`GET /api/local/console` 只读，它给每条登记标一个 `alive`（按 `/proc/<pid>/stat` 判，僵尸算死）。

### 前端怎么拿到登记与归档

只读那五个接口的形状不能动，所以另开了一个只读端点：

```
GET /api/local/console → { ok, readOnly:true, readAt, data:{
  stateDir, settingsPath, runtimePath, archivePath, auditPath, trashDir,
  runtime:[{ pid, port, home, profile, startedAt, logPath, detached, alive }],
  archive:[{ profile, merged, archivedAt }],
  notes:[] } }
```

前端用它标出「由本控制台启动」的实例、渲染归档区；动作成功后重新拉一遍读数即可（`instances` 里
控制台起的实例与手工起的实例一视同仁，签名与 `processReason` 都照旧）。

## 读写分层与写盘边界

接口分两层之后，「只读」这件事换了个说法：**只读接口那一层仍然是纯只读，写能力全部收在两个新包里**。

### 只读层（一个字段都没动）

- 全部读访问集中在 `json/fsio.mbt`、`json/env.mbt`、`json/tailread.mbt`、`json/version.mbt`：
  `@fs.read_file`、`@fs.exists`、`@fs.kind`、`@fs.readdir`、`@fs.mtime`、`@fs.realpath`、
  `@fs.open(ReadOnly)` + `File::read_at`、`@fs.file_size`（只 stat 大小），以及 `read_link`
  （`readlink(2)`，只读链接目标）与 `list_dir_result`。`json/` 里**没有任何写 / 建 / 删 / 改名 / 建进程调用**（自测 grep 0 命中，
  见下面「自测怎么核对」）
- 凭据类文件（`.credentials.yaml` / `.env` / `.npmrc`）在 `read_text_file` / `read_some_at` 里按 basename 硬拦：
  只判断存在，绝不读内容
- 环境变量来自 `/proc/self/environ`，是本进程自己的环境
- 静态服务（`dist_static/`）只调 `@json.exists` / `@json.is_dir` / `@json.exe_path` / `@json.env_value`，
  真正读文件的是 moonback `unstable_static` 的 `@fs.kind` 与 `@fs.open(ReadOnly)`
- 只读接口里的唯一网络动作是**对 127.0.0.1 候选端口发一次 GET**（写死回环地址、写死 GET、读完即断）

### 写层：写盘只落在这些路径

写调用点**全部**在 `fsx/writeio.mbt`（唯一的写入口）与 `actions/instance.mbt`（唯一的建进程处）。
它们只被下面这些路径调用，别处不写：

| 写的东西 | 路径 | 谁在写 |
| --- | --- | --- |
| 设置 | `$XDG_STATE_HOME/dsh-console/settings.json`（缺省 `~/.local/state/dsh-console/`） | `store/settings.mbt` |
| 运行登记 | `$XDG_STATE_HOME/dsh-console/runtime.json` | `store/registry.mbt` |
| 归档记录 | `$XDG_STATE_HOME/dsh-console/archive.json` | `store/archive.mbt` |
| 审计 | `$XDG_STATE_HOME/dsh-console/audit.jsonl`（只追加） | `store/audit.mbt` |
| 回收站 | `$XDG_STATE_HOME/dsh-console/trash/<profile>-<毫秒>/` | `actions/profile_fs.mbt`（`deleteToTrash=true`） |
| profile 目录 | 被动作**直接作用**的那一个：派生（新建）、重命名（改名）、删除（移走或删掉） | `actions/profile_fs.mbt` |
| 实例日志 | `<该实例 DSH_HOME>/logs/console-<profile>-<port>.log` | `actions/instance.mbt`（spawn 时重定向 stdout/stderr） |

三份状态文件都是**原子写**（同目录临时文件 + `rename`）；`audit.jsonl` 只 append。

### FFI

全工程两处 C，各自只有一次系统调用族：

- `json/fd_link.c`：`readlink(2)`（只读，端口 → inode → PID 那条 join 用）
- `fsx/proc_signal.c`：`kill(2)` / `kill(pid,0)` / `getpid(2)`。停止实例要「先 SIGTERM、宽限后 SIGKILL」，
  判活要 `kill(pid,0)`，而 `@process` 只能操作自己 spawn 出来的句柄，**对任意 PID 没有原语**，
  本工程也不想为此去 spawn `/bin/kill`。三个函数都不写盘、不建进程、不读文件。

### 自测怎么核对

```bash
cd dsh-console/backend
# 写调用点只在两个文件里
grep -rn '@fs\.write_file\|@fs\.mkdir\|@fs\.rename\|@fs\.remove\|@fs\.rmdir\|@process\.spawn\|spawn_orphan' --include=*.mbt . | grep -v .mooncakes | grep -v _build
# 只读层干净（无输出）
grep -rn 'write_file\|mkdir\|rename\|remove\|rmdir\|spawn' json/*.mbt json/*.c
```



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
│   ├── fsio.mbt                # 只读文件访问入口（含定向读 read_some_at、read_link）
│   ├── fd_link.c               # 唯一一处 C：readlink(2) 的 FFI 桥（一次系统调用）
│   ├── tailread.mbt            # 反向分块读文件尾部
│   ├── version.mbt             # 后端自身版本 + 前端 package.json 的运行时读取
│   ├── env.mbt                 # /proc/self/environ、HOME 解析
│   └── value.mbt               # core Json 的只读取值
├── localapi/
│   ├── api.mbt                 # 路由分发、查询参数、错误码、方法名、API 优先闸门
│   ├── respond.mbt             # 响应外壳与响应头
│   ├── probe.mbt               # 单端口只读探测 + 批量并发探测（保序；超时与并发由设置给）
│   └── rawhttp.mbt             # 极简 HTTP/1.1 客户端（回环探测专用）
├── fsx/                        # 写侧基础层（全工程唯一的写入口）
│   ├── writeio.mbt             # 原子写 / 追加 / 建目录 / 改名 / 删树 / 复制树 / 发信号
│   └── proc_signal.c           # 唯一另一处 C：kill(2) / kill(pid,0) / getpid(2)
├── store/                      # 状态文件（$XDG_STATE_HOME/dsh-console）
│   ├── state.mbt               # 状态目录与 JSON 文件读取（坏文件给原因）
│   ├── settings.mbt            # 九项设置的键、缺省、取值范围、原子落盘
│   ├── registry.mbt            # runtime.json：控制台起过的实例
│   ├── archive.mbt             # archive.json：归档记录
│   └── audit.mbt               # audit.jsonl：动作审计（只追加）
├── actions/                    # 可写层（唯一入口 POST /api/local/action）
│   ├── guard.mbt               # X-DSH-Console + Origin 守卫
│   ├── respond.mbt             # 写侧响应外壳与错误码 → 状态码
│   ├── action.mbt              # 动作分发、参数解析、审计、GET /api/local/console
│   ├── instance.mbt            # 起 / 停 / 重启、端口分配、签名等就绪、进程判活
│   ├── profile_fs.mbt          # 派生 / 重命名 / 删除（回收站或硬删）
│   ├── settings_api.mbt        # GET / PUT /api/local/settings
│   └── console_api.mbt         # GET /api/local/console
├── dist_static/
│   └── dist_static.mbt         # 静态根解析、dist 静态中间件、SPA 回退、解析失败时的 503
├── runtime/runtime.mbt         # GET /api/local/runtime
├── profiles/profiles.mbt       # GET /api/local/profiles
├── logs/logs.mbt               # GET /api/local/logs
├── processes/processes.mbt     # GET /api/local/processes
├── processes/procjoin.mbt      # 端口 → socket inode → PID → Profile/DSH_HOME/版本/时长
└── instances/instances.mbt     # GET /api/local/instances
```
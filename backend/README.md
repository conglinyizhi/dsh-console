# dsh-console 本地接口后端（MoonBit）

dsh-console 前端的本地接口，用 **MoonBit + moonback** 实现的一版后端。接口分两层：

- **只读（GET，纯只读）**：`runtime` / `profiles` / `logs` / `processes` / `instances` / `dsh-releases`
  —— 形状与已退役的 Node 版中间件（`../server/`，见 git 0448ba4 可取回）**逐字段一致**，这一层一个字段都不动
  （`dsh-releases` 是这一轮新加的：并发问 GitHub / npm / 国内镜像三个源，规格见
  `../design/dsh-release-sources.md`；三个源全没答上来也回 200，每个源各自的原因写在读数的 `sources` 里）
- **写（第三批新增）**：`POST /api/local/action`（十个动作）、`GET/PUT /api/local/settings`、
  `GET /api/local/console`（运行时登记与归档的只读出口）
  —— 契约见 `../design/write-api-contract.md`

- 默认只监听 `127.0.0.1:5390`（自测隔离可用 `DSH_CONSOLE_BACKEND_HOST` / `DSH_CONSOLE_BACKEND_PORT` 覆盖）
- **一个进程一个端口**：同一个端口既答 `/api/local/*`，也服务前端构建产物 `dist/`
  （静态根可用 `DSH_CONSOLE_DIST` 指定）
- 只读接口只答 `GET`（其它方法 405）；写动作只走 `POST /api/local/action`，且必须带 `X-DSH-Console: 1`
- 前端走的是同源相对路径 `/api/local/...`，所以「接入」不需要改 base URL

第一批落地四个只读接口；第二批补齐 `logs` / `processes` / `instances`，并修掉两处硬编码
（`nodeVersion` 伪造、`consoleVersion` 编译期固化）。第三批（A 形态）让后端**接管前端静态服务**，
并把实例探测从串行提到 **8 路并发**。第四批加上**可写层**：
动作真的起停进程 / 动 profile 目录，各项设置真的接到探测、端口分配、起停与日志缺省上。
第四批第二轮改三处：**归档去掉 `merged`**（旧文件仍能读）、
**每个 profile 的备注**（`/api/local/profiles` 新增 `note` / `noteSource`，新动作 `set-profile-note`，
落点 `<profile 目录>/.dsh-note.txt`）、**派生结果写明拷贝口径**（已拷 N 个文件、未拷 node_modules）。
第四批第三轮补上三个空壳菜单项里的后端能力：
新动作 **`open-path`**（打开目录 / 打开配置）——参数只有 profile 名与一个枚举 `kind`，
目标路径由后端自己拼（**没有路径参数这回事**），交给 `xdg-open` 直接 exec。
第四批第四轮加**带握手令牌的访问地址**（`instances` 的 `webUrl` / `webUrlSource`，每次现算、不缓存、不进审计）。
第四批第五轮（本轮，契约「追加契约（第五轮）」那一节）让**派生出来的新 profile 一眼认得出**：
`profiles` 每个 profile 加 **`dirMtimeMs`** / `dirMtimeSource`（目录 mtime，卡片第六格与列表排序都用它），
`fork-profile` 给新 profile 写一条备注当"出生证明"（**写失败不让派生失败**），并把"结果落在哪"写进提示。

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

先生成构建信息（短 sha + 构建时刻，写进 `backend/store/build_info.mbt` 与
`frontend/build_info.mbt`；页脚与 `/api/local/console` 的 `buildSha`/`buildAt` 都读它）：

```bash
./scripts/gen-build-info.sh          # 前端 build.sh 也会自己调一次
```

再编译（依赖已缓存时可用）：

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

**预压缩（gzip）**：前端构建链的最后一步用系统 `gzip -9 -n -k` 给 `app.js` / `app.css`
各压一份同名 `.gz`（见 `frontend/build.sh`；压缩链不引入 Node，也不为它写一套 MoonBit 压缩实现）。
静态中间件外层挂了一层 `gzip_middleware`：**GET / HEAD**、请求头 `Accept-Encoding` 认 gzip
（认 `gzip` 与 `*`，`gzip;q=0` 算明确拒绝）、且原文件与同名 `.gz` 都是普通文件 —— 三条同时成立才发 `.gz`，
带上 `Content-Encoding: gzip` 与 `Vary: Accept-Encoding`，`Content-Type` 仍是原文件那个。
其余情形（含 `.gz` 不存在、路径带 `%` 转义、读不动）原样交给下一层：**`.gz` 缺失不是错误，不会变成 404**，
没预压缩的资源照旧发原文件。只走静态资源这条路 —— 中间件链最外层还是 `api_gate`，`/api/local` 的响应（JSON，不预压缩）碰不到它。
本机实测：`app.js` 1529782 字节 → `app.js.gz` 174243 字节。

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
| `dshSourceLabel` | string | `本机已安装` + 找到它的那条策略，形如 `本机已安装（顺 PATH 上的 dsh 命令解开包目录；与在跑实例同一份）`；按你指定的那一份时是 `本机已安装（按你指定的版本）` |
| `dshCandidates` | array | 这台机器上装着的 dsh（版本切换那一轮新增）：`[{ version, name, dir, source, active, running }]`。`active` = 起实例会用的那一份；`running` = 有在跑实例的入口包就是它 |
| `dshPinState` | string | `auto`（没指定）/ `pinned`（按你指定的那一版）/ `pin-missing`（指定过，但那份已经不在这台机器上或版本对不上，已回落自动挑） |
| `dshPinNote` | string | 指定失效时那句人话（「你指定过 X，现在找不到了，这一版按自动挑的 Y 算」）；其余空串 |
| `backendRuntime` | string | `moonbit/native`：后端自己的运行时（**取代原 `nodeVersion`**） |
| `backendVersion` | string | 后端自身版本，与 `moon.mod` 的 `version` 一致 |
| `backendPackageName` | string | `conglinyizhi/dsh-console-backend` |
| `dshHome` | string | `$DSH_HOME`，无则 `~/.dsh` |
| `dshHomeSource` | string | `DSH_HOME 环境变量` / `默认 ~/.dsh` |
| `dshProfile` | string / null | `$DSH_PROFILE`，未设置给 null |
| `platform` | string | `linux x64 (7.2.9-arch1-1)` 形状 |

找包目录是一条三级兜底链（`backend/runtime/runtime.mbt` 的 `find_installed_dsh`），
按可靠性排：**① 顺 PATH 上的 `dsh` 命令**（它是 pnpm 写的 shim，脚本里写着真入口
`<包目录>/lib/bin.js`，连 `$basedir` 的写法一起还原）→ **② 在已知全局根下按深度 ≤3 找**
`<目录>/node_modules/@deepseek-ai/dsh` → **③ 多份候选时挑与在跑实例一致的那份**
（先看同一个包目录，再看版本一致的那批里版本最高的），挑不出参照就取版本最高。

为什么不能只按固定路径扫：pnpm v11 的全局布局是 `<根>/<槽>/<哈希>/node_modules/@deepseek-ai/dsh`，
比老布局多一层哈希，`<根>/<槽>/node_modules/…` 那条会整条落空 —— 读数报 `dsh-package-missing`、
起实例报找不到入口，而 `dsh --version` 一切正常。全局根除了 `~/.local/share/pnpm/global`、
`~/.pnpm-global`、`~/Library/pnpm/global` 三个固定候选，还认 `PNPM_HOME` 与 `XDG_DATA_HOME`。

用了哪条策略写进 `dshSourceLabel`，不猜也不吞。同一份结论同时喂给起实例那条路
（`installed_dsh_dir`），读数与起实例不会指向两个不同的 dsh。

**版本切换（回退）那一轮把这条链拆成两层**：

- `installed_dsh_candidates()` —— 这台机器上装了哪几份：shim 解开的那份 + 各全局根下扫到的全部，
  **按真实路径去重**。同一个真目录在 pnpm 的布局里有两种写法（`<槽>/<哈希>/node_modules/@deepseek-ai/dsh`
  是软链，真身在 `<槽>/<哈希>/node_modules/.pnpm/@deepseek-ai+dsh@<版本>_<哈希>/…`），
  字符串比会把同一份数成两份，所以按 `realpath` 判。
  老布局（`global/5/node_modules/.pnpm/…`）不靠走 `.pnpm` 覆盖：pnpm 会在
  `<槽>/node_modules/@deepseek-ai/dsh` 摆软链过去，读 `package.json` 顺着软链就读到了。
  **不按条目名去 `.pnpm` 里扫 `dsh`**：那里还有别的全局包顺便装进来的依赖副本（本机就有一份
  0.2.1-rc.2 只存在于某个槽的 `.pnpm` 里，pnpm 从没把它摆在 `node_modules/@deepseek-ai` 下）——
  那种副本算不算「装了一份」可疑，而且版本更高时会被自动挑挑中，等于拿用户没装过的版本起实例。
- `resolve_dsh_selection()` —— 生效的是哪一份：有指定（`dsh-pin.json`）且那一份还在就用它，
  否则走原来的自动挑（与在跑实例同一份 → 同版本里最高 → 最高）。
  指定的目录没了 / `package.json` 版本与记录对不上 → **回落自动挑并如实标 `pin-missing`**，
  `dshPinNote` 里写清「你指定过哪一版、现在按哪一版」，不报错、也不偷偷改记录。

指定只影响**以后起的实例**（`start-instance` / `restart-instance` 的 argv 里那个包目录）；
控制台自己不换 dsh，系统上的 `dsh` 命令与 pnpm 全局安装一个字节都不动。

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
- `note` / `noteSource`（第二轮新增的**加字段**，旧消费者忽略即可）：备注正文与来源。
  备注放在 `<profile 目录>/.dsh-note.txt`，读到给原文 + `"文件"`；没有这个文件给 `""` + `"默认"`；
  有文件读不动给 `""` + `"默认（<路径> 读取失败：…）"`（与设置的 `sources` 同一套口径，读不到就说读不到）
- `lastStart` / `lastStartSource`（第十六轮新增的**加字段**，旧消费者忽略即可）：
  这只 profile **最近一次启动**的结局，读自审计流水 `audit.jsonl` 里最近一条启动记录
  （`action` 为 `start-instance` 或 `restart-instance`，后者见 design-fixes §27.1），
  形状是 `{ action, ok, at, code, message, home }`。
  `ok:false` 表示最近一次是失败的：它就是「失败之后没有成功过」的判据
  （真有过一次成功，那一次就是最近那一条）。一条记录都没有时给 `null` + 一句来源说明；
  `lastStartSource` 写明取的是哪一条（含 `action` 名）、按什么对上的（`params.home` 等于
  这只 profile 的 home / 控制台的 home / 那一笔没带 home 时按 profile 名）。
  「最近」的判据是这些行里 `at` 最大的那一条，不按 home 槽先筛一遍：
  同一只 profile 的记录会落在「带 home」与「不带 home」两个槽里。
  归属在 `profiles/profiles.mbt` 的 `last_start_of`：别的 home 里的同名记录不算这一只的。
  `restart-instance` 的审计行由 `actions/action.mbt` 的 `audit_params_for` 补上
  `params.profile` / `params.home`（请求体里只有 pid 或 port），失败那一笔才认得出是谁。
- `dirMtimeMs` / `dirMtimeSource`（第五轮新增的**加字段**，旧消费者忽略即可）：profile **目录**的 mtime
  （Unix 毫秒，数字；读不到给 `null` + 原因）。卡片第六格「最近改动」与列表排序都用它。
  **口径是「最近改动」，不是「创建时间」**：多数文件系统上可靠的创建时间拿不到
  （`ctime` 会在 chmod / 改名时变，`birth time` 不通用），目录 mtime 是能拿到且不会骗人的那个值；
  派生会写进新目录，所以刚派生出来的 profile 一定是 mtime 最新、排在最前面的那一个。
  这一层**不动** `profiles` 数组的顺序：数组仍按 profile 名升序，降序排序是消费者按 `dirMtimeMs` 做的事

### `GET /api/local/logs?source=...&tail=...`

对应已退役的 Node 版 `server/readLogs.mjs`（git 0448ba4 可取回）。

**来源白名单**（不接受任意路径）：

| source | 文件 |
| --- | --- |
| `host` | `~/.dsh/logs/retry-control/host.log` |
| `audit` | `~/.dsh/linxi-guard-audit.jsonl`（linxi-guard 的守卫审计） |
| `actions` | `$XDG_STATE_HOME/dsh-console/audit.jsonl`（控制台自己的动作审计；主文件读不到时退回最近一份归档）。与 `audit` 是两个文件：失败提示条那颗「查看日志」落在这里，失败那行的 `message` 是完整原文 |
| `instance:<实例 id>` | 该实例 DSH_HOME 下 `logs/` 里挑出来的一个可读日志文件（挑法见下） |

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

**实例日志怎么挑**（挑错会让日志页默认显示一份没用的日志，所以口径写在这里）：

1. 候选 = 该实例 DSH_HOME 的 `logs/` 目录下（含至多 3 层子目录）`.log` / `.jsonl` / `.txt` 普通文件
2. 排序层级（数字小的在前）：

   | 层级 | 是什么 |
   | --- | --- |
   | 0 | 这条实例自己的日志，且有内容 |
   | 1 | `host.log`，且有内容 |
   | 2 | 别的文件，且有内容 |
   | 3 | 这条实例自己的日志，但空 |
   | 4 | `host.log`，但空 |
   | 5 | 别的文件，且空 |

3. 同层级按 mtime 降序，mtime 相同按路径升序（结果稳定可复现）
4. 「这条实例自己的日志」= 运行登记里这条实例的 `logPath`；登记里没有就按控制台的命名约定
   `console-<profile>-<port>.log` 拼一个。两个都拿不到（外部起的实例）就没有这一档

**为什么不是「mtime 最新的那个」**：一次**失败的启动**也会在同一个 `logs/` 目录里留下
`console-<profile>-<port>.log`，而且它通常比还在跑的实例那份新。只按 mtime 一刀切，日志页默认来源
（前端取 `instance:<第一个实例>`）显示的就是这份失败日志 —— 它对使用者没有信息量，
「日志能不能滚」这类判定也无从谈起。

**为什么 host 日志单独占一档**：只有本控制台起的实例才会把输出重定向到 `console-<profile>-<port>.log`。
外部起的（比如手敲 `dsh --profile web --no-open`）没有这一份，它名下的 `logs/` 里能读到的就只剩
别人的失败残留与 host 日志；这时 host 日志是这台机器上唯一持续在写、能反映真实活动的记录，
比一份死掉的失败残留有用得多 —— 这也正是「没有能用的实例日志就回退 host 日志」这条口径。
分档之后空文件仍然排在有内容的后面而不是被丢掉：全空时如实回 0 行；选中的理由写在响应字段 `pickedBy` 里。

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

**一个 pid 多个监听端口：归并成一行（版本切换那一轮）**

一只 dsh 进程常同时听着几个端口（本机的 web 实例就同时听着 3080 与 9230）。以前按端口列，
一个 pid 出两行，而第二行必然是 `fault` —— dsh 的网页入口只在一个端口上，另一个端口探 `GET /`
当然是 404。**界面在说假话**，比少列一个端口糟得多。

现在列表的粒度是**进程**：

1. 探测仍按端口做，`probeResults` 一个都不少（那是全局事实，不是实例行）；
2. 成行前按 pid 归并：**主端口 = 该 pid 名下签名命中 dsh 判据的那个**；一个都没命中时取端口号最小的；
3. 同 pid 的其余端口收进该行的 `alsoPorts`：`[{ port, httpStatus, signatureId, note }]`
   （`note` 是一句人话，例如「同一个进程的另一个监听端口，不是 dsh 的网页入口：这一次探测回的是 HTTP 404」）；
4. `state` / `stateReason` **只按主端口算**；
5. 没有 pid 的条目（进程 join 不上）**不参与归并**：那时「这两个端口是不是同一只进程」没有证据，
   硬凑成一行就是把猜的当事实。按端口点停止 / 重启的老路径仍然认 `alsoPorts` 里的端口。

界面上：卡片不显示、也不因此变色；详情抽屉里主端口那一行下面多一行「还听着 9230」（原因在悬停里）。

**带令牌的访问地址（第四轮加字段）**

dsh web 的首次握手看 URL 里的 `?token=<key>`，不带就是 401。控制台把实例的 stdout/stderr
重定向到 `<该实例 DSH_HOME>/logs/console-<profile>-<port>.log`，启动横幅
`dsh web: http://127.0.0.1:<端口>/?token=<串>` 就落在那里。所以 `instances[]` 每个实例
**新增两个字段**（其余字段一个都没动，旧消费者忽略即可）：

| 字段 | 类型 | 口径 |
| --- | --- | --- |
| `webUrl` | string / null | 能直接握手的完整地址；读不到就是 `null`，**绝不编** |
| `webUrlSource` | string | 令牌来自哪份文件的哪一段，或为什么读不到 |

取值顺序（找到就停，实现见 `instances/weburl.mbt`）：

1. `runtime.json` 里这条实例登记的 `logPath`（先按 pid 对，再按端口对；**不按 profile 找**，
   同名 profile 的历史登记可能指着一份别的日志）
2. 按控制台命名约定拼出来的实例日志 `console-<profile>-<port>.log`（先该实例自己的 `DSH_HOME`，
   再 dsh 默认的 `~/.dsh`）
3. dsh 日志目录下的有界扫描：最近改动的 **20 份 .log**，每份**只读尾部 200 行**，找提到
   `:<端口>/?token=` 的行

几条硬口径：

- **端口必须与该实例一致**：匹配串就是 `:<该实例的端口>/?token=`，所以不会把别的实例的令牌
  贴上来；host 取该实例自己的 `url`（`http://127.0.0.1:<端口>/`）
- **令牌原值不进审计**：`audit.jsonl` 里只有动作与 profile（实测 grep 令牌 → 0 命中），
  `webUrlSource` 里也只写文件与段落，不带令牌
- **每次现算、不缓存**：token 每次启动都会变，同一个 `instances` 请求里现读现拼；
  同一个日志文件里有多条横幅时取**最后**那条（追加写，越靠后越是当前这次启动的）
- **读不到就说读不到**：外部实例（手动起的，例如 3080）没有这份日志，令牌打在启动它的终端里 ——
  回 `null` + 「外部实例：令牌在启动它的终端里……」，不给一个点了 401 的链接
- **有界读，够不着也不猜**：自己那份日志先读尾部 256KB；没命中且窗口没盖到文件开头时补读开头
  64KB，**只有「开头 + 尾部」能盖住整份文件才采信开头那一段** —— 中间有缺口时开头那个令牌可能
  已经被后一次启动换掉了，宁可回 `null` 并写明「中间 N 字节没读」
- **第 3 步扫来的令牌先实测一次握手**：跨文件扫到的横幅可能是同一个端口更早那次运行的，早被换掉了。
  采信之前对 `127.0.0.1:<端口>` 发一次 `GET /?token=<串>`（2s 超时，只看状态码）：401、探测不到、
  超时都不采用，回 `null` 并写明「实测握手仍是 401，不采用」；不是 401 才采用，`webUrlSource` 里
  带上实测到的状态码。第 1、2 步读的是该实例自己那份追加写的日志、取的是最后一条横幅，不做这一步
- 这一层仍然是**纯只读**：只做 `file_size` / `read_at` / `readdir` / `mtime` 与注册表读取，
  不写盘、不建进程

**状态灯三件套（第七轮加字段）**

卡片图标右上角那个实心圆要判据，所以 `instances[]` 每个实例**再加三个字段**
（其余字段一个都没动，旧消费者忽略即可）：

| 字段 | 类型 | 口径 |
| --- | --- | --- |
| `state` | string | `running` / `fault` / `starting` |
| `stateReason` | string | 为什么是这个状态；黄能分开说是 b 还是 c |
| `profileHealth` | object / null | `{ missingBundles, hasPatch }`；解析不出 profile 给 `null` |

**关键行为改动**：改前「签名探测不通过」的端口**根本不进列表**。现在只要**持有它的进程
cmdline 看起来是 dsh**（与 `/api/local/processes` 同一把尺子：可执行名 `dsh`，
或路径段里有 `@deepseek-ai/dsh/`），就**列出来并标 `fault`**，`stateReason` 里写着
「端口在听，但签名探测不通过（成因 b）：…」。join 拿不到 PID 的端口仍然不列 ——
无从判断它是不是 dsh，不猜。

判据（写死，实现见 `instances/judge_state`）：

| state | 判据 |
| --- | --- |
| `running` | 签名探测通过。绿由签名给：profile 有毛病也**不**把「在跑」说成「故障」，c 的事实照写进 `stateReason` 与 `profileHealth` |
| `fault` | **b**：端口在听、持有它的进程 cmdline 看起来是 dsh，但签名探测不通过（含探测没打通 / 超时）；**c**：签名没通，且解析出的 profile 缺包 > 0 或没有 `cordis.patch.yml`。b 与 c 同时成立时以 c 起头（那是根因），b 的事实同句写出 |
| `starting` | 本控制台刚起（`runtime.json` 里有 pid 或端口对得上的登记，且进程起不到 `start_grace_seconds` = 20 秒），端口已在听但签名还没通：可能还在启动，不是坏 |

**红（停用）不在这个接口里**：没在跑的端口不可能是 LISTEN 候选，所以它不进 `instances` ——
红由「列表里没有它」表达。没在跑的 profile 那一档（黄 c / 红）由前端拿
`GET /api/local/profiles` 现成的 `bundles.missing` 与 `patch.exists` 自己判，后端不重复给。

**为什么签名优先于 c**：使用者主力的 `web` profile 现成读数就是 `bundles.missing = 3`
（`@deepseek-ai/dsh-experimental-agent-team-profile` / `-auto-review` / `-schedule-bundle`
不在 profile 与 hoisted 的 `node_modules` 里，但 dsh 从自己的全局安装解析得到，实例跑得好好的）。
让 c 覆盖签名会把这种「在跑、签名也过」的实例一律点成黄，与「绿＝签名探测通过」的判据打架；
反过来，b 那一路本来就只能靠 c 说清根因，所以 c 在那里仍然起头。

`profileHealth` 与 `GET /api/local/profiles` 的 `bundles.missing` / `patch.exists` 同源
（同一个 profile 目录、同一套「profile 自己的 `node_modules` → `profiles/node_modules` 共享」查找，
实现见 `profiles/profile_health`）。给 `null` 的三种原因都写在 `stateReason` 里：
进程 cmdline 里没有 `--profile` / 实例的 DSH_HOME 读不到 / profile 目录不存在或名字不是单段。

**fault 条目对写侧的影响**（有意为之，写在这里免得被当成回归）：

- `archive-profile` 的「正在跑的不许归档」把 fault 条目也算在跑（它确实占着那个端口）；
  判据与起实例同一条：**(home, 名字)** —— 别的 home 里同名的那只是另一只，不挡这一份
  （改前只比名字：W1 归档被 W2 在 $W2_PORT 上跑的同名实例挡回，实测过）
- `stop-instance` / `restart-instance` 按 `port` 找目标时，fault 条目也能找到 pid（改前是 `not-found`）
- `probe.hits` **仍是签名命中数**：fault 条目不计入，条目总数看 `instances` 长度

fault 条目的 `signature` 给 `{ id: "", describe: "签名探测不通过：…", evidence: "" }` ——
没有判据可填，不编一个 id。

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
`unknown-action`/`bad-params`/`dsh-not-installed` 400、`not-found` 404、`conflict`/`job-exists`/`busy` 409、
`spawn-failed`/`stop-failed`/`install-failed`/`install-incomplete`/`io-error` 500。

> `busy` / `install-failed` / `install-incomplete` 是补包那一轮（第九轮）加的三个码：
> 同一只 profile 已经有一个补包在跑（`busy`，409）、包管理器退出码非 0 或超时（`install-failed`）、
> 装完了按 `dsh.profile.bundles` 重算仍缺（`install-incomplete`）。后两条的 message 都带日志路径。
>
> 后来又拆/加了三个（都在补包这一族，message 都带日志路径或直接说清原因）：
> - `packages-not-found`（500）：跑完仍缺包，且 install 日志里有 registry 说「没这个包」的证据
>   （`ERR_PNPM_FETCH_404` / `404 Not Found` / `E404`）。message 列出缺的包名并说「得改 package.json」——
>   这一档重试多少次都没用，下一步是改声明，不是再点一次。
> - `no-package-manager`（500）：开跑**之前**就拦下——这只 profile 选中的包管理器不在 `PATH` 上。
>   不拦的话要等满 120 秒超时，而等下去也不会有转机。
> - `unsupported-manager`（500）：这只 profile 是 Yarn PnP（目录里有 `.pnp.cjs`），包不在 `node_modules` 里，
>   控制台不代跑，说明里让用它自己的 yarn。
>
> 补包用哪个包管理器：先认 `package.json` 的 `packageManager` 字段（`pnpm@9.1.0` → `pnpm`），
> 再按 lock 文件（`pnpm-lock.yaml` → pnpm、`package-lock.json` → npm），都没有按 pnpm。

> `dsh-not-installed` 是版本切换那一轮加的第八个码（原契约七码之外）。为什么单开一条：
> 那是**调用方点了一个不是安装的目录**，不是读写失败 —— message 里把「这台机器上装着哪几份」都列出来了，
> 归进 `io-error` 会把人引去查磁盘。

**失败也要带结构化细节**（`actions/action.mbt` 的 `failure_outcome`）：`ActionError` 只装得下
code 与 message，装不下 `{ command, exitCode, durationMs, logPath, missingBefore, missingAfter }`
这些字段。动作在 `fail` 之前把这一笔的 outcome 放进那个 Ref，`handle_action` 的 catch 取走
（取走即清）写进审计 —— 所以**失败那笔审计与成功那笔形状一致**，`/logs/actions` 里能直接
看到日志路径。写入点与抛出点之间没有 await，两笔并发失败不会互串。

**原始错误原文（`raw`）只落审计，不进提示条**：`message` 说的是结论（「写文件失败」），
原文（`OSError("@fs.mkdir()… Permission denied")` 这类）跟在那行的 `raw` 上，回执里也带一份
`error.raw` 给排查用。store 的那个格子（`store/raw.mbt`）**取一次就清**，所以 `handle_action`
的失败分支必须**先取一次**再构造回执：从前是 `error_json` 自己去取，于是审计那一侧永远是空串。

**结论固定这几句（两段式 helper 的 `summary`，别在调用点另造）**：

| 结论 | 出处（helper） | 底层原文 `raw` 里放什么 |
| --- | --- | --- |
| 建目录失败 | `@fsx.ensure_dir_fs` | `OSError("@fs.mkdir()…")` 之类 |
| 写文件失败 | `@fsx.write_text_atomic_fs` / `write_text_fs` / `write_bytes_fs` | `OSError("@fs.write()…")` 之类 |
| 删文件失败 | `@fsx.remove_file_fs` | 同上 |
| 删目录失败 | `@fsx.remove_tree_fs` | 同上 |
| 建软链失败 | `@fsx.make_symlink_fs` | 同上 |
| **重命名失败** | `@fsx.rename_path_fs` | `<from> -> <to>（OSError(… EXDEV / EACCES …)）` |
| **改权限失败** | `@fsx.chmod_path_fs` | `<路径>（OSError(…)` |
| **统计失败** | `@fsx.measure_tree_fs` | 坏在哪一步、哪个目录：`列目录失败：<目录>（…）` / `读不到文件大小：<文件>` |
| **列目录失败** | `@json.list_dir_result_fs` | `<目录>（OSError(…)）`；EACCES / EPERM 那几个词在原文里（`/proc` 的 hidepid 靠它们认） |
| **读文件状态失败** | `@json.file_size_fs` | `<路径>（OSError(…)）`（stat 不动）；tailread 里 `fd.size()` 那一处只给结论 |
| **复制失败** | `@fsx.copy_tree_fs` | 坏在哪一步、哪个文件：`列目录失败：<目录>（…）` / `读不到 <文件>：（…）` / `写文件失败：<文件>（…）` |
| **追加失败** | `@fsx.append_text_fs` | `追加写失败：<路径>（OSError(…)）` |
| **读文件失败** | `@json.read_text_file_fs` | `OSError("@fs.read()…")` 之类；敏感文件是「拒绝读取敏感文件：<名字>」，`raw` 留空 |
| **读文件失败（字节）** | `@fsx.read_bytes_fs` / `@json.read_some_at_fs` | `<路径>（OSError(…)）`（读 fd 那一步失败）；文本读不动与字节读不动常不是同一件事，所以分开一句 |
| **打开文件失败** | `@json.read_some_at_fs`（open 那一步） | `<路径>（OSError(…)）`（不存在 / 权限 / 是目录） |
| **读链接失败** | `@json.read_link_fs` | errno 名（`ENOENT 目标不存在`…）或「目标超过 4096 字节，被截断」 |

两段式是 `{ summary, raw }`：`summary` 只进提示文案，`raw` 只进 `@store.note_raw`。
调用点**只在失败会变成本次请求的回执 / 审计行时**才 `note_raw`；读侧说明（进 `sources`、
返回 `None`、纯探测）**一律不记 raw** —— 那个格子是进程内单格，读侧写进去会串到下一次无关失败。

调用点保留自己更具体的说法也允许（例如「读不动审计文件 <路径>」「package.json 读不出来」）：
把原来的系统文本摘掉、只留结论即可；原来那句纯是系统文本时才用 helper 的 `summary`。

`FsError` 全工程只有一处定义：`@json.FsError`（`json/fsio.mbt`，`{ summary, raw }`）。
放 json 是因为 json 不依赖本工程的其它包、fsx 依赖 json —— 反过来定义会成环；写侧那几个
`@fsx.*_fs` 的签名直接写着 `Result[Unit, @json.FsError]`，读写两侧共用这一个类型。

旧的 `read_text_file` / `read_link` / `rename_path` / `chmod_path` /
`copy_tree` / `read_bytes` / `append_text` / `read_some_at` / `read_text_at` /
`write_text` / `measure_tree` / `list_dir_result` 仍在（转调壳，
内部把 `summary` 与 `raw` 拼回一行给还没切的老调用方），新代码一律走 `_fs` 入口。

为什么这样挡得住网页跨源触发：浏览器不允许跨源请求带自定义头，预检会先拦掉；Origin 校验再挡一层。
**对「本机恶意进程」不设防** —— 那一层不在这轮范围（契约第一节写明）。

### 十四个动作

| action | 真实做的事 | 关键边界 |
| --- | --- | --- |
| `start-instance` | `node <dsh包目录>/lib/bin.js --profile <名> --no-open --port <端口>`，等它答出 dsh web 签名才算起成功 | 同 profile 已在跑 → `conflict`（message 里有 pid 与端口）；端口**真**被占 → `conflict`，message 贴的是这次 bind 报的原话（见下面「端口占用的裁判是 bind」）；起不来 → 收掉子进程，message 给「参数被拒」的人话诊断（见「哪些 profile 能起成常驻实例」）或日志尾部 |
| `stop-instance` | SIGTERM → 等 `process.stopGraceMs` → 仍在则 SIGKILL | 目标必须在运行登记或进程表里认得出是 dsh，否则 `not-found`（不误杀别的 pid） |
| `restart-instance` | 先停后起，端口与 profile 沿用原来的 | 认不出 profile → `not-found`；老端口上只剩 TIME-WAIT 这类残留时**照常起得来**（残留不是占用，见下面「端口占用的裁判是 bind」） |
| `fork-profile` | 递归复制 profile 目录（**跳过 node_modules**，那是 pnpm 安装产物，提升目录仍解析得到），**再给新 profile 写一条"出生证明"备注** | 新名默认 `<原名>-dev`，重名自动加 `-2`/`-3`…；给了 port 就顺手把新 profile 起起来。拷贝口径写明：**「已拷 N 个文件，未拷 node_modules；新 profile 会显示缺包，装一次即可」**（`outcome.filesCopied` 是真实拷过去的文件数）。备注见下面「派生出的新 profile 怎么认得出」 |
| `rename-profile` | 改磁盘上的目录名 | 空名 / 非法字符 / 重名 / 正在运行 都拒 |
| `set-profile-note` | 写备注：非空 `text` 原子写进 `<profile 目录>/.dsh-note.txt`（覆盖旧的）；**空串 = 删掉那个文件** | 名字先过白名单、再确认解析到 `profilesRoot` 之内（**目录穿越拒 `bad-params`**）；目录不存在 `not-found`；超过 2000 字符 `bad-params`；写不动 `io-error`。`text` 不 trim（前后空格是用户写的），**缺 `text` 键 ≠ 空串**：缺键 `bad-params` |
| `open-path` | `xdg-open <目标>` 打开一个**枚举目标**：`kind:"dir"`（缺省）= profile 目录，`kind:"config"` = 它的 `cordis.patch.yml`。**直接 exec**（不经 shell、不做任何字符串插值），spawn 完不等它干活 | **params 只认 `profile` 与 `kind`**，多一个键（比如 `path`）就 `bad-params`——客户端给不了路径。名字过白名单 + 解析结果必须落在 profilesRoot 之内（两道，与 `set-profile-note` 同款）；目标不存在 `not-found`；PATH 里没有 `xdg-open` / 没有图形环境（`DISPLAY` 与 `WAYLAND_DISPLAY` 都没设）/ `xdg-open` 起来就非零退出 → `io-error`，message 写清是哪一种 |
| `archive-profile` | 往 `archive.json` 追加一条 `{ profile, home, archivedAt }`。`home` 可选（不给 = 控制台自己的 `DSH_HOME`） | **不动磁盘上的 profile**；一份档案的身份是 **(home, 名字)**：同一个 home 的同名 profile 已在归档区 → `conflict`，同名另一 home 各归各的。**同一个 home 里同名的那只正在跑 → `conflict`**（message 里给 pid、端口与 home），别的 home 里同名实例在跑不挡这一份 |
| `unarchive-profile` | 撤掉那一份（`profile` + 可选 `home`）的记录 | 没有这一份 → `not-found`；同名另一 home 的那条留着不动 |
| `delete-profile` | `safety.deleteToTrash=true` 时整目录移进 `<状态目录>/trash/<名>-<毫秒>`；false 时递归硬删 | 硬删必须带 `"confirm":"DELETE"`，否则 `bad-params`；正在运行 → `conflict` |
| `set-row-order` | 把**整份**手动顺序原子写进 `<状态目录>/order.json`：一个行 id 的字符串数组，元素只认 `port:<端口号>` 与 `profile:<名字>@<home>`（老形状 `profile:<名字>` 仍然认，见下面「状态文件」那一节） | 不是字符串 / id 形状不对 / 有重复 / 超 5000 条 → `bad-params`；写不动 `io-error`。空数组合法（= 清空顺序表，回到自动排序）。**不做增量合并**：调用方给的就是要落盘的那一份 —— 增量式接口要后端先读一份当前顺序再算，两次并发拖动会互相覆盖 |
| `pin-dsh` | **指定用哪一版 dsh 起实例**：把 `{ dir, version, pinnedAt }` 原子写进 `<状态目录>/dsh-pin.json`。只改控制台自己的记录，**不碰系统上的 `dsh` 命令、不碰 pnpm 全局安装** | `params` 只认 `dir`，多一个键 `bad-params`；`dir` 必须在本机候选里（按真实路径比，`.pnpm` 里那个写法也认），不在 → `dsh-not-installed`（message 里列出这台机器上装着哪几份）；写不动 `io-error`。`outcome` 是 `{ dir, version, pinPath }` |
| `unpin-dsh` | 撤掉指定，回到自动挑：删掉 `<状态目录>/dsh-pin.json` | **不收参数**（多一个键 `bad-params`）；文件本来就不在也算成功，`outcome.removed=false` 如实说「不是刚删掉的」。`outcome` 是 `{ removed, previousVersion, pinPath }` |
| `repair-packages` | 在 profile 目录里跑包管理器补 node_modules：有 `pnpm-lock.yaml` → `pnpm install --prefer-offline`，有 `package-lock.json` → `npm install --prefer-offline`，都没有按 pnpm。stdout/stderr 追加进 `<状态目录>/logs/repair-<名>-<毫秒>.log`；跑完重读 bundles 算剩余缺包 | 120 秒上限（到点 SIGTERM，2 秒后 SIGKILL）；**同一只 profile 同时只允许一个**（第二个 `busy`）；目录不在 / 没有 package.json → `not-found`；命令退出码非 0 或超时 → `install-failed`；装完仍缺 → `install-incomplete`。`outcome` 带 `command / exitCode / durationMs / logPath / missingBefore / missingAfter / remaining`（**失败那笔审计也带**，见下面的 failure_outcome） |

### 搬家之后重算软链接（relink，第九轮 §48）

profile 里的软链（典型是 `node_modules/@local/*`）是**相对路径**：`dsh-annotate -> ../../../../../x`。
相对路径按「链接自己所在目录」算 —— profile 从 `<DSH_HOME>/profiles/<名>` 搬到
`<homes root>/<名>/profiles/<名>`（多两层）之后，同一段就指到别处，插件列表于是全报「包不可用」。
所以 isolate / deisolate / fork 三条搬家路径**搬完都跑一遍重算**（`profiles/relink.mbt`）：

- 相对链接：用「旧链接所在目录 + 链接文本」算出它原本指向的绝对目标，再用「新链接所在目录」重算相对
  路径写回；
- 绝对链接原样保留（它们不随目录变）；
- 目标不存在就跳过并记一条（原本就坏的不修、也不弄得更坏）；
- `.pnpm` 整棵不进去（pnpm 自己的链接农场，装一次会重建），遍历有条数上限；
- fork 的复制本身不拷软链（`copy_tree` 只复制普通文件与目录），所以它那一步是「按源目录解析出的绝对
  目标，在副本里重新摆一条」；回执的 `skipped` 里不再出现已经带过来的那些。

配置文件：`cordis.patch.yml` / `package.json` 里以旧 profile 目录开头的绝对路径换成新目录前缀，
只换「后面跟 `/` 或正好等于旧目录」的出现。三个数都进回执与审计的 outcome：
`linksFixed` / `linksBroken` / `refsRewritten`（§48.2 要的 `refsRewritten` 就是第三个）。

**已经断掉的那份不修**：不做「猜目标」的修复动作，也不给 UI 入口 —— 搬家当时才有旧路径可用，
事后没有可靠依据；坏链接在搬家时只会被跳过。

### 派生出的新 profile 怎么认得出（第五轮）

使用者报过一次："刚才从外部配置文件分出来一个，看不出来是我分出来的……它竟然来到了最下面"。
三处一起改，缺一处都还是认不出：

1. **列表排序口径 = 最近改动**。`profiles` 数组本身仍按名字升序（只读层的形状不动），
   已停止那一组由消费者按 `dirMtimeMs` **降序**排，读不到的排最后、按名字升序兜底。
   用"最近改动"而不是"创建时间"：可靠的创建时间在多数文件系统上拿不到（`ctime` 会因 chmod / 改名而变，
   `birth time` 不通用）；而派生一定会写这个目录，所以刚派生出来的**一定是 mtime 最新**的那个。
2. **备注就是它的出生证明**。派生时往 `<新 profile 目录>/.dsh-note.txt` 写：

   ```
   从 <源 profile> 派生 · <本地时间>
   <源 profile 原有的备注，原样接在后面>
   ```

   **为什么覆盖源备注而不是留着不管**：派生是整目录拷贝，源 profile 的备注会跟着拷过来，
   而那条备注讲的是**源**的事（"这个是干啥用的"），留在新 profile 里会误导 —— 所以第一行必须是它的来历，
   源的那段原文退居第二行起、继续留着供参考。总长按备注上限 2000 字符截断
   （第一行短，真正被截掉的只会是尾部）。
   **备注写失败不算派生失败**：目录已经拷好了，为一个备注把整次派生报成失败是假报 ——
   outcome 里 `noteFile.written=false` + `noteFile.error` 写清原因，顶层 `note` 也照实说。
3. **提示要说清结果落在哪**：`outcome` 里有 `newName` / `noteFile{path,text,written,error}` /
   `dirMtimeMs` / `listPosition`，顶层 `note` 一句话讲完"新 profile 叫什么、它在列表最上面、
   备注里写着从哪来、拷了多少文件"。使用者问的"那我点这个按钮呢是否有效"就靠这一句回答。

本地时间由 `json/local_time.c` 的 `localtime_r(3)` 取（见下面「FFI」）；
时区读不到时退回 UTC 并在括号里写明，绝不假装是本地时间。

起实例的两条实测细节（都在代码注释里）：

1. **端口 ≠ 可服务**。服务先 bind、路由后挂载，中间那几百毫秒 `GET /` 回的是 404。
   只等端口会让只读的 `instances` 接口在这一刻认不出刚起的实例。所以等的是
   **dsh web 签名**（401 + `dsh web authentication required`，或页里有 `__DSH_BOOT__`）。
2. **僵尸进程的 kill(pid,0) 也成功**。判活不能只看 `kill(pid,0)`，还要看 `/proc/<pid>/stat` 的状态位，
   `Z` 按死处理；否则停止动作会一直报「SIGKILL 之后仍然在」。
3. **判死之后还得 wait 一次**。`Z` 被判成死，但「死了又没被 wait」的子进程仍然挂在控制台名下
   （`ps -o pid,stat,cmd --ppid <控制台pid>` 里一堆 `Z`），控制台退出才被回收 —— 长跑的控制台每失败一次攒一个。
   收尾的 `reap_after_failure` 因此在每条「子进程已经不在」的分支上都补了一次 `wait_pid`
   （只对已经死掉的 pid 调，不会阻塞；不是自己的子进程时报 `ECHILD`，吞掉）。

### 端口占用的裁判是 bind，不是 /proc/net/tcp

- **找空闲口（从 `instance.basePort` 往后扫）只认 LISTEN**：`/proc/net/tcp(6)` 状态列等于 `0A` 的才算
  「有人在听」。TIME-WAIT(06)、FIN-WAIT、CLOSE-WAIT、CLOSE 都是连接关掉之后的残留，
  那段时间端口上**没有任何东西在听**，监听侧带 `SO_REUSEADDR`（node 的 `server.listen` 默认带）
  就 bind 得上 —— 把它们算成「被占用」，等于白扔掉空着的口。
- **显式指定的端口（起实例带 `port`、重启沿用老端口）在这里不预判**：`/proc` 那张表判不出
  「有没有人在听」（见上一条），预判只会猜错。真正的裁判是这一次 bind：起不来就报
  **进程写下的原话**，形如 `Error: listen EADDRINUSE: address already in use 127.0.0.1:8400`
  （errno 名与端口都在里面），不再由控制台替内核编一句「/proc/net/tcp 里有这条记录」。

`busy_ports()` 这次只有两个调用点，两处都过了一遍：找空闲口那处改成只认 LISTEN（`listening_ports()`，
比改前更准，不再跳过其实空着的口）；显式端口那处不再需要它，预判整段删掉。

**这条规矩是拿一次真事故换来的**：实例被停掉时自己留下一条 `local=<原端口>` 的 TIME-WAIT，
重启沿用老端口时被自己的残留挡回来 —— 页面一瞬间是空的（老实例已经停了，新实例没起来），
换个端口重试就成功。实测复现（远端，独立 home / state / 端口，改前改后两组二进制对照）：

| 场景 | 改前（basePort=8420） | 改后（basePort=8430） |
| --- | --- | --- |
| basePort 上有 TIME-WAIT、没人听 | 跳过，起在 basePort+1 | 直接用 basePort |
| 指定端口上有 TIME-WAIT | `conflict`：「端口 8421 已被占用（/proc/net/tcp 里有这条记录）」 | 起得来，实例就在 8421 上 |
| 指定端口上真有 LISTEN | `conflict`（同上那句猜的） | `conflict`：「这次 bind 没成，进程写下的原话是 Error: listen EADDRINUSE: address already in use 127.0.0.1:8450」 |
| 带着一条活连接重启（事故形状） | `conflict`，实例没起来 | 重启成功，TIME-WAIT 与新监听并存 |

**IPv4 与 IPv6 两张表都读**：`/proc/net/tcp` 与 `/proc/net/tcp6`（`::1` 上的监听只出现在后者）。
改前改后都读两张表，这次动的是「哪一列算数」—— 状态列不是 `0A` 的一律不算。

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

- **命中「这次 bind 没成」**（日志里有 `EADDRINUSE` / `EADDRNOTAVAIL` 这类 errno 名，
  或 `address already in use` 这种原话；`EACCES` 只在跟 `listen` / `bind` 挨着时才算 ——
  单独一句 `permission denied` 可能来自文件操作，不往 bind 上归因）：错误码仍是契约里的
  `conflict`（409），message 把**原话**贴出来，并说清它来自这次 bind、不是我们按 `/proc/net/tcp` 猜的：

  ```json
  {"ok":false,"readOnly":false,"readAt":"2026-10-16T12:16:00.000Z","error":{
    "code":"conflict",
    "message":"端口 8450 起不来：这次 bind 没成，进程写下的原话是「Error: listen EADDRINUSE: address already in use 127.0.0.1:8450」。这句话来自这次 bind（errno 与端口都在里面），不是我们按 /proc/net/tcp 猜的。换一个端口，或先腾出这个端口（profile iso，pid 21034，日志 …/logs/console-iso-8450.log，子进程已经退出）"}}
  ```

- **没命中**（启动就崩、bundle 解析不了、profile 自身有毛病等）：维持原来的形状 ——
  `实例没起来（pid …，日志 …）：<收尾说明>；日志尾部：…`，尾部的口径同样是**本次启动新写出来的那几行**。
  那时日志尾巴就是最好的证据，如实贴出来比套一句结论有用。
  实测负例（bundles 里挂一个不存在的包）：message 如实给出
  `dsh: cannot resolve profile bundle …`，没有被误判成「服务参数被拒」。

`restart-instance` 与 `fork-profile` 带 port 时走的是同一条起实例路径，诊断一致。

### `open-path`：只认枚举目标，不接受路径

行菜单里「打开工作目录 / 编辑配置」两项落到这一个动作上。**客户端给不了路径**：

```json
{"action":"open-path","params":{"profile":"web","kind":"dir"}}
```

- `kind` 缺省 `"dir"`：目标是 `<profilesRoot>/<名>`；`"config"` 则是它下面的 `cordis.patch.yml`。
  别的取值 `bad-params`。
- `params` 里出现 `profile` / `kind` 之外的键一律 `bad-params`。**这是有意的**：塞一个 `path` 进来会被拒，
  而不是被默默忽略——忽略掉的话，「塞了 path 也成功」看起来就像那条路径生效了。
- 白名单 + 落点两道校验与 `set-profile-note` 同款：名字只允许字母数字与 `._-`、不以点开头、不是 `.` / `..`，
  拼出来的路径还得确认带 `profilesRoot/` 前缀。
- 交给桌面的方式是 **`xdg-open` 直接 exec**：目标路径是 argv 里的一项，没有 shell、没有任何字符串插值，
  带空格 / 引号 / `$` 的路径也只是这一项的字面量。spawn 之后**不等它干活**。

**打不开如实报 `io-error`，message 写清是哪一种**（不假装成功）：

| 情形 | message 里写什么 |
| --- | --- |
| PATH 里没有 `xdg-open` | `PATH 里找不到 xdg-open（这台机器上没装 xdg-utils），打不开 <路径>` |
| 没有图形环境 | `没有图形环境：DISPLAY 与 WAYLAND_DISPLAY 都没设置，xdg-open 打不开 <路径>…` |
| `xdg-open` 起来就非零退出 | `xdg-open 起来就退出了（退出码 N），<路径> 没打开；它说：<stderr 尾部>` |

前两种是起进程之前判的。第三种要一条证据：spawn 之后看 600ms，它在这段窗口里退出、且退出码不为 0 才判失败
（窗口不是「等它干活」——`xdg-open` 打不开时是毫秒级退出，打得开时要么把活交给会话再自己退出（0），要么留着跑）。
它这几百毫秒的 stderr 落在一个一次性文件 `<状态目录>/open-path-<毫秒>.log` 里，读完随即删掉；
建不了这个文件就退回 `/dev/null`，记不下它说的话不该让打开动作直接失败。

成功时的 `outcome`：`{ what, path, opener, pid, exitCode, detail }` —— `path` 是**后端算出来的**目标绝对路径，
`opener` 是实际用的那个 `xdg-open` 的绝对路径，`exitCode` 在它已经退出时给出（还在跑给 `null`）。

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
| `instance.basePort` | 8400 | 起实例 / 派生时找空闲端口的起点（实测改 8500 后新实例就在 8500）；空闲 = 该端口在 `/proc/net/tcp(6)` 里**没有 LISTEN**，且运行登记里没有 —— TIME-WAIT 这类残留不算占用 |
| `process.detach` | true | 起实例是否脱离控制台（见上一节） |
| `process.stopGraceMs` | 5000 | 停止时 SIGTERM 到 SIGKILL 的宽限（实测 grace=0 → 直接 SIGKILL，`sigkillSent:true`；grace=5000 → 只发 SIGTERM） |
| `logs.defaultTail` | 200 | 日志接口不带 tail 参数时的缺省（实测 50 → 回 50 行，500 → 回 500 行；显式 tail 不受影响） |
| `ui.archiveOpenByDefault` | false | 前端读 `GET /api/local/settings` 决定归档区默认展开（后端负责存取与回显） |
| `ui.sidebarCollapsed` | false | 前端读它决定宽屏下侧栏的形态：展开成 190px，或收成 56px 的图标栏。窄屏不看这一项，那一档的侧栏从顶部汉堡滑出、不占位（后端负责存取与回显） |
| `safety.deleteToTrash` | true | 删除进回收站还是硬删（见上表） |
| `profile.ignoreMissingBundles` | true | 缺包不参与状态灯（§40）：前端读它决定「缺 N 个包」算不算警告。缺省 true = 不报警；关掉之后缺包重新算作黄灯。后端只负责存取与回显，缺包仍然可以在抽屉里装（`repair-packages` 不受这一项影响） |

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
| `archive.json` | 归档记录：`{ profile, home, archivedAt }`（第二轮删掉了 `merged`；**旧文件里带 `merged` 仍能读**，那个键被忽略。**没有 `home` 的旧记录也照读**：读成空串，按名字参与判重与取消归档） | 归档 / 取消归档 |
| `trash-origins.json` | 回收站条目各自的**来源 home**：`{ "<目录名>": "<home>" }`，恢复按它归位（没有来源的旧条目落回控制台自己的 home，并说出来） | 删除进回收站 / 恢复 / 彻底删除 |
| `audit.jsonl` | 每个动作一行：`{ at, action, params, ok, code, message, outcome }`，**失败那笔另带 `raw`**（原始 OSError 之类；空则整个键都不出现），**超阈值轮转**（口径见下） | 每个动作（含失败与 403）、以及 settings 的 PUT |
| `audit.jsonl` 的归档 | `.archive/audit-<UTC 时间戳>.jsonl`：滚出去的那份原样搬过去（含它自己的说明条），目录里最多留 40 份 | 每次轮转 |

#### `audit.jsonl` 怎么滚动（阈值与保留条数写死在这里）

审计平时只追加，不加轮转跑几个月就是几 MB 的流水，所以超过阈值就滚。三个数都是常数、不是设置项：

| 常数 | 值 | 含义 |
| --- | --- | --- |
| 滚动阈值 | **8 MiB**（8388608 字节） | 文件字节数**超过**它就滚一次（等于不滚） |
| 保留条数 | **2000 条** | 滚完新文件保留旧文件最近 2000 条，本次要追加的那行接在后面 |
| 归档保留份数 | **40 份** | 归档目录里只留最近 40 份，更老的删掉 |

滚动动作（顺序有讲究：先写新主文件再 rename 主文件，会把新内容搬进归档、旧流水留在主文件位置上，实测踩过）：

1. 把「说明条 + 保留的最近 2000 条」写成归档文件 `.archive/audit-<UTC 时间戳>.jsonl`，写完关句柄；**同名不覆盖**，撞名顺延 `-1`、`-2`……
2. `rename` 主文件到同一个归档名：这一步之后**完整旧流水**在归档里，可读
3. 再把同样的内容写成主文件（临时文件 + `rename` 就位）

**轮转本身留痕**：新主文件的第一条永远是 `action="audit-rotate"` 的说明行，写清
「原文件 N 行 / M 字节已归档到 <路径>，本文件保留最近 K 条」（结构化字段在
`params.archivedPath / sourceLines / sourceBytes / keptLines`）。审计不允许出现无声的断口，这条是契约的一部分。

其它几条口径：

- **原子**：三步都是「同目录临时文件 + `rename`」，没有半截文件；模型上唯一可见的中间态是「主文件短暂不存在」（第 2 与第 3 步之间），读侧 `audit_read_path` 遇到就回退读最近的归档 —— 滚动不会让审计突然读不到
- **并发**：整个过程持进程内互斥锁 `audit_write_lock`。不加锁时一笔滚动的两次 `rename` 会把另一笔刚追加的行落到被搬走的旧 inode 上（实测阈值 1 字节 + 100 条并发会丢行）。跨进程（同时跑两个后端）不在射程内，也不在契约里
- **失败不连坐**：滚动失败只把原因回给调用方拼进响应 `note`，**不让动作失败**（`store/audit.mbt` 全链 `noraise`）
- **令牌原值仍然不进审计**（下面「令牌原值不进审计」那条不因滚动而放松）
- 自测/运维可以临时改这三个数：`DSH_CONSOLE_AUDIT_MAX_BYTES` / `DSH_CONSOLE_AUDIT_RETAIN_LINES` / `DSH_CONSOLE_AUDIT_ARCHIVE_KEEP`（非法值一律按上面的缺省）

外部已有的实例不写进 `runtime.json`。对账（pid 已消失就清理）发生在**动作里**，不发生在 GET：
`GET /api/local/console` 只读，它给每条登记标一个 `alive`（按 `/proc/<pid>/stat` 判，僵尸算死）。

### 前端怎么拿到登记与归档

只读那五个接口的形状不能动，所以另开了一个只读端点：

```
GET /api/local/console → { ok, readOnly:true, readAt, data:{
  stateDir, settingsPath, runtimePath, archivePath, auditPath, orderPath, trashDir,
  deleteToTrash, deleteToTrashSource,
  runtime:[{ pid, port, home, profile, startedAt, logPath, detached, alive }],
  archive:[{ profile, archivedAt }],
  order:["port:3080", "profile:web", ...],
  lastStarted:[{ id, at, source }],
  notes:[] } }
```

前端用它标出「由本控制台启动」的实例、渲染归档区；动作成功后重新拉一遍读数即可（`instances` 里
控制台起的实例与手工起的实例一视同仁，签名与 `processReason` 都照旧）。

`order` 是手动排序的**显式顺序表**（`order.json` 的原样）。空数组 = 没拖过 = 列表走自动排序；
表里没有的行（新出现的实例 / 新加的 profile）由前端按自动规则排在已排好的之后，
运行中与已停止**两组各自排**，不合并成一张表（组是语义）。

`lastStarted` 是每只实例 / 每只 profile **最后一次被启动**的时刻，同一个 id 只留 `at` 最大的那一条。
两份控制台自己的记录合起来出：`runtime.json` 的 `startedAt`（每条登记同时产出 `port:` 与 `profile:` 两条 id），
以及 `audit.jsonl` 里 `action="start-instance"` 且 `ok=true` 的行（失败的启动不算启动过）。
审计滚动之后主文件只保留最近若干条，更早的历史在 `.archive/` 里，这一版**不读归档** ——
「上次启动」要的是最近那一次，最近的必然在主文件里。读不动的文件把原因写进 `notes`，不静默。

`deleteToTrash` 是**生效值**（与删除动作在 `store/settings.mbt` 读的是同一处），
`deleteToTrashSource` 说它来自文件还是默认（取值与 `/api/local/settings` 的 `sources` 同一套：
「文件」/「默认」/「默认（…原因…）」）。加这两个字段的理由：设置是懒加载的，而删除确认框
在打开之前就得说清「删了会怎样」—— 让确认框去解释「为什么还不知道」是说给实现者听的话。

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

写调用点**全部**在 `fsx/writeio.mbt`（唯一的写入口）与两处建进程处
（`actions/instance.mbt` 起 dsh 实例、`actions/open_path.mbt` 起 `xdg-open`）。
它们只被下面这些路径调用，别处不写：

| 写的东西 | 路径 | 谁在写 |
| --- | --- | --- |
| 设置 | `$XDG_STATE_HOME/dsh-console/settings.json`（缺省 `~/.local/state/dsh-console/`） | `store/settings.mbt` |
| 运行登记 | `$XDG_STATE_HOME/dsh-console/runtime.json` | `store/registry.mbt` |
| 归档记录 | `$XDG_STATE_HOME/dsh-console/archive.json` | `store/archive.mbt` |
| 审计 | `$XDG_STATE_HOME/dsh-console/audit.jsonl`（追加；超 8 MiB 滚动，归档进同目录 `.archive/`） | `store/audit.mbt` |
| 手动顺序 | `$XDG_STATE_HOME/dsh-console/order.json`（**顶层就是字符串数组**，元素是 `port:<端口号>` / `profile:<名字>@<home>`；老形状 `profile:<名字>` 仍认；空数组 = 没拖过） | `store/order.mbt` |
| dsh 版本指定 | `$XDG_STATE_HOME/dsh-console/dsh-pin.json`（`{ dir, version, pinnedAt }`；文件不在 / 读不动 / 字段不全 = 没指定，不报错也不偷偷写） | `store/dshpin.mbt`（动作在 `actions/dsh_version.mbt`） |
| 回收站 | `$XDG_STATE_HOME/dsh-console/trash/<profile>-<毫秒>/` | `actions/profile_fs.mbt`（`deleteToTrash=true`） |
| 回收站来源 | `$XDG_STATE_HOME/dsh-console/trash-origins.json` | `store/trash_origins.mbt` |
| profile 目录 | 被动作**直接作用**的那一个：派生（新建）、重命名（改名）、删除（移走或删掉） | `actions/profile_fs.mbt` |
| profile 备注 | `<profile 目录>/.dsh-note.txt`（空串语义 = 删掉它；**派生时也写这一个文件**） | `actions/profile_fs.mbt`（`set-profile-note` 与 `fork-profile`） |
| 实例日志 | `<该实例 DSH_HOME>/logs/console-<profile>-<port>.log` | `actions/instance.mbt`（spawn 时重定向 stdout/stderr） |
| 打开窗口 | **控制台自己不写盘**：目标路径交给桌面环境（`xdg-open`），后面开什么窗口是那个会话的事 | `actions/open_path.mbt`（第二处建进程处）。它给 `xdg-open` 的 stderr 落一个一次性捕获文件 `<状态目录>/open-path-<毫秒>.log`，探测窗过了就读出来、**随即删掉**（建不了就退回 `/dev/null`） |

三份状态文件都是**原子写**（同目录临时文件 + `rename`）；`audit.jsonl` 平时只 append，超阈值时按上面「`audit.jsonl` 怎么滚动」一节滚动（同样是原子写）。

### FFI

全工程三处 C，各自只有一次系统调用族：

- `json/fd_link.c`：`readlink(2)`（只读，端口 → inode → PID 那条 join 用）
- `json/local_time.c`：`localtime_r(3)` 两次（一次取本地 UTC 偏移、一次取时区缩写）。派生备注第一行要写
  "本地时间"，而核心库与本工程的依赖里**没有时区换算**，UTC 顶替会写出一个与使用者那块表对不上的时间。
  只读时间，不写盘、不建进程、不碰文件；取不到返回哨兵值，MoonBit 侧按"读不到"处理（写明原因，不拿 UTC 冒充）
- `fsx/proc_signal.c`：`kill(2)` / `kill(pid,0)` / `getpid(2)`。停止实例要「先 SIGTERM、宽限后 SIGKILL」，
  判活要 `kill(pid,0)`，而 `@process` 只能操作自己 spawn 出来的句柄，**对任意 PID 没有原语**，
  本工程也不想为此去 spawn `/bin/kill`。三个函数都不写盘、不建进程、不读文件。
- 本地时间只走上面 `json/local_time.c` 那一次 `localtime_r`，**没有**为它去 spawn `date`。

### 自测怎么核对

```bash
cd dsh-console/backend
# 写调用点与建进程处只在三个文件里：fsx/writeio.mbt、actions/instance.mbt、actions/open_path.mbt
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
│   ├── settings.mbt            # 十项设置的键、缺省、取值范围、原子落盘
│   ├── registry.mbt            # runtime.json：控制台起过的实例
│   ├── archive.mbt             # archive.json：归档记录（(home, 名字) 为身份）
│   ├── trash_origins.mbt       # trash-origins.json：回收站条目各自从哪个 home 删的
│   ├── order.mbt               # order.json：手动顺序（行 id 带 home）
│   ├── dshpin.mbt              # dsh-pin.json：用哪一版 dsh 起实例的指定记录
│   ├── laststarted.mbt         # 「上次启动」表（行 id 同一套）
│   └── audit.mbt               # audit.jsonl：动作审计（超阈值滚动 + 归档 + 读侧回退）
├── actions/                    # 可写层（唯一入口 POST /api/local/action）
│   ├── guard.mbt               # X-DSH-Console + Origin 守卫
│   ├── respond.mbt             # 写侧响应外壳与错误码 → 状态码
│   ├── action.mbt              # 动作分发、参数解析、审计、GET /api/local/console
│   ├── instance.mbt            # 起 / 停 / 重启、端口分配、签名等就绪、进程判活
│   ├── dsh_version.mbt         # pin-dsh / unpin-dsh：指定用哪一版 dsh 起实例
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
├── instances/instances.mbt     # GET /api/local/instances
└── instances/weburl.mbt        # 带令牌的访问地址（webUrl / webUrlSource）
```
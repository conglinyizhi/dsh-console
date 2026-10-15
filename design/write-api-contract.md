# 可写层接口契约（前后端并行开发的依据）

## 一、写动作只有一个入口

```
POST /api/local/action
Headers（必须，二者缺一即拒）:
  X-DSH-Console: 1          ← 自定义头；跨源请求带不了它（浏览器预检会挡）
  Origin: http://127.0.0.1:<本机端口>   ← 或完全缺失（curl 直连时没有 Origin）
Body:
  { "action": "<动作名>", "params": { ... } }
```

**为什么这样**：后端只绑 127.0.0.1，但本机其它程序与浏览器页面都能发请求。自定义头 + Origin 校验能挡住网页跨源触发（浏览器不允许跨源带自定义头且预检会拦），对"本机恶意进程"不设防——那一层不在这轮范围。

拒绝时返回 `403` + `{ ok:false, readOnly:false, error:{ code:"not-authorized", message } }`。

## 二、动作清单（`action` 取值与 params）

| action | params | 语义与约束 |
| --- | --- | --- |
| `start-instance` | `{ profile, home?, port? }` | 起一只 dsh 实例。**已在跑的同一 profile 要拒绝**（`conflict`，并在 message 里指出已在哪个端口）。port 缺省时按 `instance.basePort` 起找第一个空闲 |
| `stop-instance` | `{ pid }` 或 `{ port }` | 先 SIGTERM，等 `process.stopGraceMs`，仍在则 SIGKILL |
| `restart-instance` | `{ pid }` 或 `{ port }` | 先停后起（端口与 profile 沿用原来的） |
| `fork-profile` | `{ profile, newName?, port? }` | 派生一份新 profile；新名字默认 `<原名>-dev`，重名自动加序号 |
| `rename-profile` | `{ profile, newName }` | 改磁盘上的 profile 目录名；空名、非法字符、重名都要拒 |
| `archive-profile` | `{ profile, merged? : bool }` | 记一条归档（**不动磁盘上的 profile**），`merged` 表示成果是否已回灌主线 |
| `unarchive-profile` | `{ profile }` | 删掉那条归档记录 |
| `delete-profile` | `{ profile }` | 按 `safety.deleteToTrash` 决定移入回收站还是硬删；**硬删要有明确二次参数**（见下） |

**destructive 的两条额外要求**：
- `delete-profile` 当 `safety.deleteToTrash=false` 时，body 里还必须带 `"confirm":"DELETE"`，否则 `bad-params`
- 所有动作成功后返回 `{ ok:true, data:{ action, outcome:{...}, note? } }`；outcome 里放这次真实发生的事（pid/端口/路径/前后名字），**不要只回一个 ok**

## 三、设置（真能配置，且每项都要真的生效）

```
GET /api/local/settings   → { ok, data:{ values:{...}, defaults:{...}, sources:{ key: "文件" | "默认" } } }
PUT /api/local/settings   body { values:{...} }  → 校验后落盘并返回新值
```

**存储位置** `$XDG_STATE_HOME/dsh-console/settings.json`（`XDG_STATE_HOME` 缺省 `~/.local/state`）；原子写（临时文件 + rename）。**同一目录还放两份运行时数据**：`runtime.json`（控制台起过的实例登记）与 `archive.json`（归档记录）。

**键与缺省值（每一项都必须接到真实行为上，没接上的不许出现）**

| key | 缺省 | 接到哪 |
| --- | --- | --- |
| `probe.timeoutMs` | 500 | 实例签名探测超时 |
| `probe.concurrency` | 8 | 探测并发（现在写死 8） |
| `probe.maxCandidates` | 40 | 候选端口上限（现在写死 40） |
| `instance.basePort` | 8400 | 启动/派生时找空闲端口的起点 |
| `process.detach` | true | 起实例时是否脱离控制台存活 |
| `process.stopGraceMs` | 5000 | 停止时 SIGTERM 到 SIGKILL 的宽限 |
| `logs.defaultTail` | 200 | 日志页默认尾部行数 |
| `ui.archiveOpenByDefault` | false | 归档区默认是否展开 |
| `safety.deleteToTrash` | true | 删除是进回收站还是硬删 |

**新键一律「读不到就用缺省」**，文件坏了不能让接口挂掉（回退 + 在 sources 里写明原因）。

## 四、运行时登记（`runtime.json`）

控制台自己起过的实例记一条：`{ pid, port, home, profile, startedAt, logPath, detached }`。
用途：① 停止/重启要知道它是不是我们起的；② 页面可以标出「由本控制台启动」；③ 进程已消失时能对账清理。
**只记我们起的**；外部已有的实例不写进这个文件。

## 五、审计与错误形状

- 所有动作都往 `$XDG_STATE_HOME/dsh-console/audit.jsonl` 追加一行（时间 / 动作 / 参数 / 结果 / 错误码）——**只追加，不轮转**
- 错误码固定这几个：`not-authorized` / `unknown-action` / `bad-params` / `not-found` / `conflict` / `spawn-failed` / `stop-failed` / `io-error`
- GET 仍然是纯只读；**只读那套接口的形状一个字段都不许动**（前端与验收都按它写的）

## 六、前端要做的对应部分

- 侧栏加「设置」一项，**顶栏那个设置按钮去掉**；设置页 = 左索引 + 右条目两栏
- 索引分组： 实例与端口 / 进程 / 日志 / 界面 / 危险动作（每项显示当前值，改动即保存并提示结果）
- 下拉菜单各按钮接 `POST /api/local/action`：启动 / 停止 / 重启 / 派生 / 归档 / 取消归档 / 重命名 / 删除；**动作成功后要刷新读数**（不是只弹个提示）
- 失败要显示后端给的具体原因（conflict / not-authorized / spawn-failed…），**不许吞掉**
- 「由本控制台启动」的实例在卡上标出来（读 runtime.json 的登记）

---

# 追加契约（第二轮：备注 / 归档去标记 / 派生口径）

## 一、归档不再有「已合并」标记（使用者的决定）
- `archive-profile` 的参数里**去掉 `merged`**；归档记录只剩 `{ profile, archivedAt }`
- `GET /api/local/console` 的 `archive[]` **去掉 `merged` 字段**
- 已经存在、带着 `merged` 的旧 archive.json **要能读**（忽略该字段，不许因此报错）

## 二、每个 profile 的备注（新功能）
使用者原话：「每个 profile 允许用户额外编辑备注来记录这个是干啥用的」。

- **存放**：`<profile 目录>/.dsh-note.txt`（纯文本 UTF-8，上限 2000 字符）。放**目录里**的理由：派生是整目录拷贝，备注跟着走；改名、搬走都不丢。
- **读**：`GET /api/local/profiles` 的每个 profile **新增 `note` 字段**（无备注给空串；读不到给空串并在 `noteSource` 里写原因）。这是**加字段**，旧消费者忽略即可。
- **写**：`POST /api/local/action` 新增动作 `set-profile-note`，params `{ profile, text }`；`text` 为空串表示**删掉那个文件**。
- **校验**：profile 必须解析到 `<profilesRoot>/<name>` 之内（防目录穿越）；超长拒绝（`bad-params`）；写失败给 `io-error`。
- **必做的实测**：写完备注之后**用这只 profile 起一次实例，确认 dsh 照常起来**（profile 目录里多一个文件不能把 dsh 弄坏）。这一条验不过就换存放位置，并在报告里说明。

## 三、派生的口径
- 现状：整目录拷贝，**排除 `node_modules`**。使用者说「整个 profile 目录」，但全拷一次是几百 MB/几万文件 ✗
- **本轮保持排除 `node_modules`**，但要在派生结果里**写明**「已拷 N 个文件，未拷 node_modules；新 profile 会显示缺包，装一次即可」
- **备注文件必须跟着拷过去**（它在目录里，天然会跟着 ✓ 但要实测证明）
---

# 追加契约（第三轮：补齐三个空壳菜单项）

现状（已核实）：行菜单里 `查看日志` / `打开工作目录` / `编辑配置` **没有后端能力、前端也没有处理分支**，点了落到兜底什么也不做。使用者点名了这三项。
其余九个动作（start/stop/restart/fork/rename/set-profile-note/archive/unarchive/delete）都已经是真的，**本轮不许动它们的语义**。

## 一、后端新增动作 `open-path`（打开目录 / 打开配置）

```
POST /api/local/action
{ "action": "open-path", "params": { "profile": "<名>", "kind": "dir" | "config" } }
kind 缺省 "dir"（profile 目录）；"config" 指向该 profile 的 cordis.patch.yml
→ { ok:true, data:{ action, outcome:{ what, path, opener, pid? }, note } }
```

**安全要求（这条是硬要求）**：
- **只接受枚举目标，绝不接受客户端给的路径** —— 没有 `path` 参数这回事 ✗
- profile 名走既有白名单校验；解析出的路径必须落在 profilesRoot 之内（两道，与 set-profile-note 同款）
- 用 `xdg-open` 直接 exec（**不经 shell**，不做任何字符串插值 ✗），detached、不等它退出
- 目标不存在 → `not-found`；打不开（没有 xdg-open / 无 DISPLAY）→ `io-error`，message 里写清是哪种（**别假装成功**）
- 只读层不动；这仍走 `POST /api/local/action` 与既有守卫（`X-DSH-Console` + Origin）

## 二、前端三个菜单项接上

| 菜单项 | 行为 |
| --- | --- |
| 查看日志 | **切到日志页，并把来源设成这只实例**（`instance:<id>` 这套已有），打开即滚到底。**不要新开页面** |
| 打开工作目录 | `open-path` + `kind:"dir"`；成功/失败都要有反馈（失败显示后端给的原因） |
| 编辑配置 | `open-path` + `kind:"config"`；profile 没有 `cordis.patch.yml` 时显示后端给的 `not-found` 原因 |

三项都要**真跑一遍贴证据**；`打开工作目录`/`编辑配置` 在无图形环境下会失败，那就**如实贴出失败提示**并在报告里说明环境限制，不许写成成功。
---

# 追加契约（第四轮：带握手令牌的访问地址）

使用者原话：「启动某个实验 profile 的时候，我们能通过 webui 来启动新的标签页吗？因为首次握手需要控制台打印的 key」

## 事实（已核实）
- dsh web 的首次握手是 URL 里的 `?token=<key>`；不带就是 **401**（实测 `GET http://127.0.0.1:3080/` → 401）
- 控制台起实例时把它的 stdout/stderr 重定向到 `~/.dsh/logs/console-<profile>-<port>.log`，**dsh 启动横幅里有带 token 的完整地址**（worker 证据：`dsh web: http://127.0.0.1:8462/?token=…`）
- **外部起的实例**（例如使用者手动起的 3080）：token 打在启动它的那个终端里，控制台可读的文件里**没有** ✗

## 一、后端：每个实例补一个「能直接握手的地址」

`GET /api/local/instances` 的每个实例**加两个字段**（加字段，旧消费者忽略即可）：

```
webUrl:       string | null   // 带 token 的完整地址；读不到就是 null
webUrlSource: string          // 令牌从哪来，或为什么读不到（见下）
```

**取值顺序（找到就停）**：
1. 运行时登记里那条记录（`runtime.json` 的 `logPath`）指向的日志文件里找 `http://<host>:<port>/?token=<串>`
2. `~/.dsh/logs/console-<profile>-<port>.log`
3. `~/.dsh/logs/` 下有界扫描（**只扫最近改动的前 20 个 .log**，每份**只读尾部 200 行**）里提到 `:<port>/?token=` 的行

**硬要求**：
- **读不到就给 null，不许编** ✗；`webUrlSource` 写清是哪种来源或哪种读不到（`外部实例：令牌在启动它的终端里` / `日志里没有带令牌的地址` / `日志文件不存在` …）
- 端口必须与实例端口一致（别把别的实例的令牌贴上来 ✗）
- host 用该实例自己的 host（现在实例的 url 字段里就有）
- **令牌不进审计** ✗：`audit.jsonl` 里不许出现 token 原值（记动作与 profile 就够）
- 每次读都现算（token 可能每次启动都变 ✗ 不许缓存）
- 只读层其余字段一个都不许动

## 二、前端

- 卡片上的「打开 Web UI」与行菜单的「在新标签页打开」**都用 `webUrl`**（有就用带令牌的）
- 「访问地址」那一行显示的仍是裸地址（人读的），但**悬停里给出 webUrl 的来源或为什么读不到**
- `webUrl` 为 null 时：按钮仍可点，但**先提示读不到令牌的原因**，并把裸地址给出来（让人能从启动它的终端里自己拼）——**不许给一个点了 401 的链接还装作能用** ✗
- 「复制访问地址」复制裸地址；**另加一条「复制带令牌的地址」**（有 webUrl 时才出现）

## 三、验收

- 起一只实例 → 贴出 instances 响应里该实例的 `webUrl` 与 `webUrlSource`，并**用 curl 证明这个地址能过握手**（`GET <webUrl>` 不再是 401，贴状态码）
- 停掉再起 → token 变了的话，贴出两次 webUrl 不同（证明是现算的）
- 外部实例（使用者那只 3080）→ `webUrl: null` + 原因写明「令牌在启动它的终端里」
- 审计文件里 grep token 原值 → **0 命中**
- 读不到的分支：把实例日志删掉再读 → null + 对应原因（不许崩）
- `node design/run-acceptance.mjs <baseUrl>`：判定项全过
- **显式路径提交**（并行期间），中文描述 ≤30 字
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
| `archive-profile` | `{ profile, home? }` | 记一条归档（**不动磁盘上的 profile**）。一份档案的身份是 **(home, 名字)**：同名不同 home 各一条，重复归档同一份才 `conflict`；`home` 缺省 = 控制台自己的 `DSH_HOME` |
| `unarchive-profile` | `{ profile, home? }` | 撤掉那一份的归档记录（只撤这一条，同名另一 home 的留着） |
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
| `ui.sidebarCollapsed` | false | 宽屏下侧栏是展开还是收成 56px 的图标栏（窄屏不看这一项，侧栏从汉堡滑出、不占位） |
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
---

# 追加契约（第五轮：派生出的新 profile 要认得出来 + 补上第六格）

使用者原话：
> 「展示数据的时候，不是一共有六个格子，但它实际展示了五个数据嘛。另外一个你就直接展示它的时间好了」
> 「我刚才试图创建了一个分支，是从外部配置文件里面分出来的。但是它的那个分出来的，我看不出来是我分出来的。首先它和其他的派生没有任何的区别……它在分出来之后，它竟然来到了最下面……也没有放在我视线范围内的最上面……我都不知道它忽然冒出来这个新的，那我点这个按钮呢是否有效」

## 一、卡片的第六格：时间

卡片字段区是 2 列 × 3 行 = 6 格，现在只填了 5 格 ✗（缺失的那格空着）。
**补一格「最近改动」**，取该 profile 目录的 mtime，按本地时间显示（如 `10-15 18:50`）。

- 后端：`GET /api/local/profiles` 每个 profile 加 `dirMtimeMs`（毫秒时间戳；读不到给 null 并给 `dirMtimeSource` 说明原因）。
  **这是加字段**，其余字段一个不动。
- 前端：这一格显示的标签就用「最近改动」，读不到写「读不到」+ 悬停给原因。
- **为什么用「最近改动」而不是「创建时间」**：多数文件系统上可靠的创建时间拿不到（`ctime` 会在 chmod/改名时变，`birth time` 不通用）。
  用目录 mtime 是能拿到且不会骗人的那个 ✓ 刚派生出来的 profile **一定是最新的**，所以它同时也回答了「哪个是刚弄的」。
- 运行中的卡也补同一格（profile 解析得出就用它的 mtime；解析不出写「—」并说明原因）。

## 二、派生出来的必须一眼认得出

1. **排序：最近改动的在最前**
   - 已停止那一组的顺序改为**按 `dirMtimeMs` 降序**（新的在最上面），读不到的排最后、按名字升序兜底
   - 排序依据要写进 README/注释：不是「创建时间」，是「最近改动」（诚实口径）
2. **派生时给新 profile 写一条备注**（这条备注就是它的出生证明）
   - 内容：`从 <源 profile> 派生 · <本地时间>`，再**换行接上源 profile 原有的备注**（源没有备注就只写第一行）
   - 总长按备注上限 2000 字符截断；写失败不许让派生失败（派生成功 + 备注失败要在 outcome 里说明）
   - **为什么覆盖而不是不管**：派生是整目录拷贝，源 profile 的备注会被一起拷过来 ✗ 那条备注讲的是**源**的事，直接留着会误导 ✓ 所以新 profile 的第一行必须是它的来历
3. **派生成功的提示要说清东西在哪**
   - 提示里带上：新 profile 名、它出现在列表**最上面**（因为最近改动在最前）、以及「它的备注写着从哪来」
   - 使用者原话里有「那我点这个按钮呢是否有效」——所以要让他**一眼看到结果**，而不是只弹一句「已派生」

## 三、验收（要量的，别只说做完了）

- 后端：`moon check` / `moon build --target native` 尾部 0 error；只读接口其余字段一个没动（贴一个响应对照）
- **派生一次真链路**：贴 `fork-profile` 的 outcome（含新备注那条与 `dirMtimeMs`）、新目录里 `.dsh-note.txt` 的实际内容、以及它在 `profiles` 响应里的顺序位置（应为第一个）
- 排序：造两个 mtime 不同的 profile（或 `touch` 现有目录），贴出前后顺序变化；读不到 mtime 的那个排在最后
- 第六格：贴卡片 DOM 里那一格的实际文本与悬停内容（有值 / 读不到两种情况）
- 提示条：贴派生成功后提示条的实际文案
- `node design/run-acceptance.mjs <baseUrl>`：**判定项全过**（现在 28 条判定 + 2 条信息）
- 收尾干净：测试派生的 profile 删掉、`~/.dsh/logs/console-*.log` 清掉、runtime.json 回 `[]`
---

# 追加契约（第六轮：回收站）

使用者原话：「回收站呢？」（配图：删除 `web-dev` 的回执说 `mode=trash`、给了 `trashPath`，但界面上没有任何回收站入口）

## 现状（已核实）
- 删除进回收站是**真的**：`~/.local/state/dsh-console/trash/web-dev-1792070484767/`，108 个文件都在 ✓
- 但**没有任何界面能看到或恢复它** ✗ —— 所以确认框那句「删除后移入回收站，可以捞回来」目前是**一个没有把手的承诺** ✗
- 另外那条删完的回执把 `mode=trash · trashPath=… · hardDeleted=false` 直接摊在界面上 ✗（上一轮刚清过同类泄漏，这处漏了）

## 一、后端

### 读：回收站条目
`GET /api/local/console` 的 data 加 `trash: [{ dir, profile, deletedAtMs, fileCount, bytes }]`
- 目录名形如 `<profile>-<epochMs>`；**profile 名本身可能含 `-`** ✗ 所以按**最后一个** `-` 切分，切不出来就 profile 给原目录名、deletedAtMs 给 null
- `bytes` 递归求和；读不到给 null 并说明（别编 ✗）

### 写：两个动作
1. `restore-from-trash`，params `{ dir }`
   - 把 `trash/<dir>` **移回** `~/.dsh/profiles/<profile>`
   - **目标已存在时必须拒绝** ✗（`conflict`，message 说清「已经有同名的 profile 了，先改名或删掉它」）
   - `dir` 必须解析到 trash 目录之内（防穿越，与既有两道校验同款）
   - 成功后 outcome 给：恢复到的路径、文件数
2. `purge-trash-item`，params `{ dir }`，**必须带 `{ confirm: "PURGE" }`** ✗
   - 真删掉那份；缺 confirm 给 `bad-params`
   - 与 `delete-profile` 的硬删同一风险等级 ✓ 守卫与审计照旧 ✓

## 二、前端

1. **侧栏加「回收站」**（与实例总览 / 日志 / 设置 / 关于 并列），路由 `/trash` ✓
   - 列表：每行 = profile 名 + 删除时间 + 文件数 + 体积 + 两个按钮（**恢复**、**彻底删除**）
   - 真正删之前弹确认框 ✓（走既有那套 `dialog()` 居中/层级/点击口径 ✗ 别另起一套）
   - 空态：「回收站是空的」（**不是加载态** ✗ 两种要分清 ✓）
   - 恢复成功/失败都要有反馈；失败要显示后端给的具体原因（尤其 `conflict` 那条）
2. **删完的回执改成人话**：
   - 回收站：「`web-dev` 已移入回收站，可以从**回收站**里恢复。」（带上入口在哪 ✓）
   - 硬删：「`web-dev` 已删除，无法恢复。」
   - 路径、mode、hardDeleted 这些**收进悬停** ✗ 不许摊在正文
3. 卡片行菜单的「删除」仍在原位不动 ✓

## 三、验收（贴证据）
- 两端构建 0 error（后端 `moon build --target native`；前端 `build.sh` / `check.sh`）
- **真链路**：拿一个**测试 profile**（自己在隔离 DSH_HOME 里造 ✗ **别碰使用者的 profile**）走完整一圈：
  删除 → 出现在回收站列表（贴 DOM 文本）→ 恢复 → 回到 profile 列表（贴两侧状态）→ 再删一次 → 彻底删除 → 列表回到空 + 磁盘上真没了
- **`conflict` 分支**：回收站里留一份、先建一个同名 profile、再点恢复 → 必须拒绝并说明原因（贴原文）
- **穿越负例**：`dir` 塞 `../profiles/web` → 必须 `bad-params`
- 回执文案：回收站与硬删两种各贴实际文本；证明正文里**没有路径/mode 这些**（悬停里有 ✓）
- `node design/run-acceptance.mjs http://127.0.0.1:5390/`：判定项全过（现在 28 条；日志那两条我知道还挂着我自己的一个探针问题，**不用你管** ✓）

## 四、环境与提交
- 5390 上跑着控制台（**别 kill、别重启**）；测试全在隔离的 DSH_HOME / XDG_STATE_HOME 里做 ✓
- **别动使用者的 `~/.dsh/profiles` 与 `~/.local/state/dsh-console`** ✗（他的 `web-dev` 还在回收站里，别碰那一份）
- 机器现在偏慢，长命令留足超时；成规模的代码用 write 落文件
- **显式路径提交**，中文描述 ≤30 字；先读 `~/.agents/skills/git-commit/SKILL.md` 并跑自检脚本
---

# 追加契约（第七轮：卡片变条目 + 详情抽屉 + 三色状态灯）

使用者原话与决定：
> 「改一下吧，图标右上角来标记一个实心的圆，绿色标记为运行，黄色标记为故障，红色标记为停用」
> 「然后隐藏启动等一大堆按钮……侧边栏来展示所有的东西包括面板和控制按钮，这样每个卡片都有详细的空间展示详细内容，首页就只有一点 profile 名称和备注等简单的东西」
> 「1 b+c / 2 A / 3 B」（故障 = b 或 c；详情 = 覆盖式抽屉；卡片不再留 ⋯ 菜单）

## 一、状态灯

卡片图标右上角一个**实心圆**：

| 颜色 | 含义 | 判据（本轮定死） |
| --- | --- | --- |
| 绿 | 运行中 | 签名探测通过 |
| 黄 | 故障 | **b**：端口在 loopback LISTEN、持有它的进程 cmdline 看起来是 dsh，但签名探测不通过；或 **c**：解析出的 profile 缺包大于 0（或没有 cordis.patch.yml） |
| 红 | 停用 | 没有在跑 |

**颜色不能是唯一信息** ✗：抽屉里要写明「为什么是这个颜色」，黄的两种成因要能分开说。

### 后端要补的（本轮唯一的接口改动，加字段）

GET /api/local/instances 每个实例加三个字段：

| 字段 | 取值 |
| --- | --- |
| state | running / fault / starting |
| stateReason | 为什么是这个状态（黄与红必须解释得出来，别只给颜色） |
| profileHealth | { missingBundles, hasPatch } 或 null（来自已解析的 profile） |

**关键行为改动**：现在「签名探测不通过」的端口**根本不进列表** ✗。
新口径下，**只要持有它的进程看起来是 dsh**（端口到 PID 的 join 已经有了，看 cmdline），就要**列出来并标 fault** ✓，
stateReason 写清「端口在听，但签名探测不通过」。

## 二、卡片只留三样
1. 图标 + 右上角状态灯
2. profile 名（在跑的显示 名:端口）
3. 备注（有才显示）

去掉：六格读数、按钮组、⋯ 菜单（点整张卡就是唯一入口）。

## 三、详情抽屉（右侧、覆盖式）
- 点卡片滑出；点外部 / Esc / 关闭按钮收起。
- 抽屉里放**全部**：六格读数 + profile 健康 + 状态灯为什么是这个颜色 + **所有控制按钮**
  （打开 Web UI / 启动 / 停止 / 重启 / 查看日志 / 打开工作目录 / 编辑配置 / 重命名 / 备注 / 派生 /
  复制访问地址 / 复制带令牌的地址 / 复制开发指令 / 归档 / 取消归档 / 删除 —— 今天行菜单里有的一个不少）。
- 焦点：打开时进抽屉、关闭时回触发它的那张卡。
- 窄屏占满宽度、宽屏固定宽度；内容可滚动。

## 四、响应式重算
卡片小了一大截，原来那套断点（2 列 1352 / 3 列 1917）作废 ✗。
按新卡片最小可用宽度重推，目标是在常见宽屏上**排得比现在多** ✓；上限仍要钉死；
**任何宽度下都不许横向溢出** ✓。

## 五、验收
- 两端构建 0 error。
- 三色各自实测：绿（在跑的 3080）；黄 b（造一个「端口在听但签名不对」的进程）；黄 c（一只缺包的 profile）；红（停止的）。
  每种贴：卡片上颜色取计算样式（不是看截图）+ 抽屉里那句「为什么」。
- 抽屉：点卡开、点外部关、Esc 关、焦点进与回、窄屏占满宽；截图。
- 卡片只剩三样：贴 DOM（卡片内文本、有没有按钮或菜单节点）。
- 多档宽度：列数、页面溢出、每卡内部溢出；出三张图。
- 抽屉里每个按钮用 elementFromPoint 反查可达。
- 跑我的验收：**会有若干条红** ✗（我的判定大量依赖卡片字段与 ⋯ 菜单，这两样本轮被搬走/去掉）。
  **别改我的脚本** ✗，在报告里列出哪些条红了、是不是因为控件搬家即可 —— 我这边重做判定。
### 补充：b/c 与「签名通过」冲突时的优先级（2026-10-16 定，走 A）

后端实现时撞到一个真冲突并报了上来：使用者的 `web` profile 一直报**缺 3 个包**
（那三个包不在 profile 的 node_modules 里，但能从 dsh 全局安装的 .pnpm 解析到，所以 3080 跑得好好的），
于是「c 算 fault」与「签名通过 = 绿」在同一个实例上打架。

**定案 A（签名通过优先）**：

1. **签名探测通过 → 该实例 state = running（绿）** ✓ —— 颜色回答的是「它现在在不在服务」这个问题。
   缺包这一条仍然照实记进 `profileHealth`，但不改颜色。
2. **c 仍然算 fault，落在两处**：
   - 端口在听但签名不通过的条目：`stateReason` 以「成因 c」起头，b 的事实同句写出；
   - **没有在跑的 profile**：由前端的 profile 灯从 `profiles` 的 bundles/patch 算（一只停着且缺包的 profile 就是黄 c）。
3. 「黄 c」的验收就用**一只停着的缺包 profile** ✓，不要去把在跑且健康的实例弄成黄的。

**这么定的理由**：颜色要回答一个明确的问题（在不在服务）。
缺包是**档案的健康**，它是另一件事 —— 混进颜色里，会让「在跑但档案有瑕疵」和「真的跑挂了」看起来一样，
而这两件的处置完全不同（前者照用，后者要去救）。给同一个颜色，等于把两个不同的问题合并成一个 ✗

---

# 追加契约（Phase 3 c：归档 / 回收站 / 顺序表的键带上 home）

背景：[`dsh-home-isolation-plan.md`](dsh-home-isolation-plan.md) 决定给开发用 profile 独立 `DSH_HOME`；
一份档案的身份因此从「profile 名」变成 **(home, profile 名)**。归档 / 回收站 / 顺序表这三处按名字做键的地方全要跟着改，
否则同名两份档案互相顶。实测（[`phase3-impact-map.md`](phase3-impact-map.md) 第四节）：`archive.json` 只写得出
`[{"profile":"zz-same"}]`；回收站恢复写死 `profiles_root()`，删了隔离那份、恢复却落回主线。

## 一、后端

### 归档（`archive.json`）
- 记录形状 `{ profile, home, archivedAt }`；`home` 缺失（本次改动之前写的旧记录）读成空串。
- `archive-profile` / `unarchive-profile` 参数多一个可选 `home`（绝对路径，不含 `.` / `..` 段；不给按控制台自己的 `DSH_HOME`）。
- 判据：名字相等 **且**（home 相等，**或**记录与请求里有一方没有 home —— 兼容口径，见第三节）。

### 回收站（`trash/` + `trash-origins.json`）
- 条目目录名仍是 `<profile>-<epochMs>`（不动，旧条目照旧读得出来、排得出时间）。
- 新增 `$XDG_STATE_HOME/dsh-console/trash-origins.json`：`{ "<目录名>": "<home>" }`，
  由 `delete-profile` 在移入回收站之后写；`restore-from-trash` 按它归位、`purge-trash-item` 顺手清掉。
- `GET /api/local/console` 的 `trash[]` 每条加 `home`（空串 = 没记来源）与 `homeSource`（来源或没有它的原因）。
- **恢复目标是记下来的那个 home**，不是控制台自己的 home。没记来源的旧条目落回控制台自己的 home，
  并在回执 note 里说明「这一条没有来源 home 记录，是按本控制台的 home 恢复的」。
- home 这一格**不写进回收站条目目录里**：那个目录就是 profile 本体，多一个标记文件就会跟着恢复回去，
  顺带还会被算进「几个文件 · 多少字节」的读数里。

### 顺序表（`order.json`）
- 行 id 两种形状：`port:<端口号>`（端口全机唯一，不带 home）与 `profile:<名字>@<home>`。
- 老形状 `profile:<名字>` 仍然认：本次改动之前的 order.json 读得出来就不丢（那一条失去名次，回到自动排序）。
- 校验：名字非空且不含冒号与斜杠；home 必须是**已归一化**的绝对路径。`profile:/a/b@web`（把 home 与名字写反）
  与 `profile:web@/a/b/`（带尾斜杠的等价写法）都拒 —— id 是逐字比对的键，等价写法就是两把钥匙。

## 二、前端
- 行 id 与后端一字不差地拼（`state.mbt` 的 `profile_row_id` / `archived_row_id`）；归档与取消归档的 params 带上 `home`。
- 归档区的匹配按 (home, 名字)：同名两份档案在页面上是两条（本家的那一行 + 一条「磁盘上没有这只 profile」的孤行），
  取消归档只撤点中的那一条。
- 其余界面一个像素都不动（只动 id 的拼法与提交给后端的参数）。

## 三、兼容（旧数据一条都不许丢）

| 旧数据 | 新代码怎么读 |
| --- | --- |
| `archive.json` 里没有 `home` 的记录 | 读成 `home: ""`，按名字参与判重与取消归档 —— 读得出来、撤得掉 |
| 回收站里本次改动之前删的条目 | 没有来源记录 → 落回控制台自己的 home，回执里把这件事说明 |
| `order.json` 里 `profile:<名字>` | 仍然认（不报错、不丢），只是这一行排不上名次 |

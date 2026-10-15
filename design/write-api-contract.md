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

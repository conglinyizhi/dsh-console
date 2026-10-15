# data-name / data-uid：元素标注与验收

前端每个「最终元素」现在带两个属性：

| 属性 | 管什么 | 例 | 唯一性 |
| --- | --- | --- | --- |
| `data-name` | **角色** —— 这是什么东西 | `instance-card` / `source-badge` / `menu-item` | 允许重复（同类共用） |
| `data-uid` | **这一个** —— 是哪一个 | `oik6nbmu`（8 位 base36） | 全页唯一，跨刷新稳定 |

起因：使用者的元素拾取工具对「运行中分组」与「已停止分组」两个来源徽标给出了**完全相同的路径**
（`span[data-name=source-badge]` 同时命中两处），那两个元素上原先没有能区分彼此的键。
只靠 `data-name` 加「第 n 个匹配」，工具与人都指不准。

规划见 `design/data-name-plan.md`（其中第五节记着与技能原文的那一处有意改动：
技能原文说不要加 index/id 序号，这一轮按使用者要求给重复项各配一个 `data-uid`）。

## 一、uid 怎么来的

`frontend/uid.mbt`：

- `pub fn uid(parts : Array[String]) -> String`
- 64 位 FNV-1a（`0xcbf29ce484222325` / `0x100000001b3`），逐段**先写段长再写内容**，
  段长前缀消掉拼接的二义性（`["ab","c"]` 与 `["a","bc"]` 不是同一个值）
- 取模 36^8，逐位转 base36，定长 8 位
- 调用点统一走 `mark(name, parts)`（同一个文件里）：一次给出 `data-name` 与 `data-uid`

三条硬约束写在 `uid.mbt` 的文件头：

1. **稳定** —— 同一个语义元素两次刷新必须同值。所以里面**没有随机数**：
   「随机哈希」的正确读法是「长得随机、取值确定」。
2. **确定** —— 只由 `parts` 决定，不读时间、不读 `Math.random`。
3. **不含位置** —— `parts` 里不许出现索引 / 序号 / 「第几个」。放在最后一段的是
   **这一项自己的键**：`row.id`（`port:3080` / `profile:web-dev` / `archived:xxx`）、
   设置键名、动作名、来源值、字段键……已停止组刚改成按最近改动排序，
   用位置算出来的 uid 会跟着顺序变，比没有还糟。

## 二、覆盖面

按 `design/data-name-plan.md` 第三节补齐，**已有的 23 处一处没改名**（`instance-card`、
`row-menu`、`source-badge`、`log-box`、`settings-tab`…… 原样保留）。新增的角色：

- 卡片：`card-name`、`console-mark`、`card-note`、每格 `card-field` + `field-label` / `field-value`
- 卡上按钮：`open-web-ui`、`stop`、`start`、`restart`、`menu-trigger`、`menu-item`、`menu-overlay`
- 副标题行：`sub-line`、`sub-kind`、`status-dot`、`sub-state`、`sub-uptime`、`port-note`
- 归档区：`archived-row`、`archive-name`、`archive-kind`、`archive-stamp`、`unarchive`、`archive-delete`、`archived-toggle`
- 对话框：`dialog-title` / `dialog-message` / `dialog-ok` / `dialog-cancel` / `rename-input` / `note-input` / `note-error` / `confirm-note`
- 日志页：`log-source-label`、`log-source-option`（每一项）、`log-source-divider`、`logs-meta`、`log-empty`
- 设置页：`settings-note`、`setting-name` / `setting-desc` / `setting-meta` / `setting-saving`
- 其他：`section-title`、`workflow-entry`、`kv-label` / `kv-value`

不标的照技能口径：纯布局容器（`.dsh-actions` / `.dsh-case-head` / `.dsh-title-line`）、
装饰（状态点外的图标）、动态文本行（日志的行 —— 它没有自己的键，拿行号算就违反第三条）。

## 三、怎么跑

```bash
# 1. 唯一性 / 稳定性 / 顺序无关 / 六种状态全量枚举
node accept-data-uid.mjs http://127.0.0.1:5390/ pass.json headless

# 2. 语义路径 → uid 对照表
node build-table.mjs pass.json uid-table.md

# 3. 活页面复核：JS 侧独立重写同一套算法，路径手写，与 DOM 上的值三方对齐
node check-paths.mjs http://127.0.0.1:5390/ uid-crosscheck.md

# 4. 出图：一张卡片的 DOM 片段
node dump-card-dom.mjs http://127.0.0.1:5390/ .

# 5. 项目验收（判定项不许变）
node ../../design/run-acceptance.mjs http://127.0.0.1:5390/
```

## 四、实测结论（都在本目录的产物里）

### 1. 唯一性 —— 每个状态零重复（`pass.json`）

| 状态 | 元素数 | 去重后 | 重复 |
| --- | --- | --- | --- |
| 初始页（实例总览） | 132 | 132 | 0 |
| 展开行菜单 | 141 | 141 | 0 |
| 打开对话框（重命名） | 138 | 138 | 0 |
| 设置页 | 35 | 35 | 0 |
| 日志页 | 16 | 16 | 0 |
| 关于页 | 17 | 17 | 0 |
| 展开归档区 | 139 | 139 | 0 |

### 2. 稳定性 —— 每个状态刷新两次，逐元素比对（`pass.json`）

七种状态合计比对 **618** 个元素，**不一致 0**。
比对的身份不含位置也不含文本（卡片上「最近改动」的值会变，那是内容不是身份）：
`data-name` + 所在卡片 `data-instance` + 所在对话框 + 自己的键（`data-action` /
`data-field` / `data-setting` / `data-group` / option 的 `value`）。

两张不同卡上的同名按钮（同名不同 uid，各自稳定）：

| data-name | 卡片 | data-uid |
| --- | --- | --- |
| `restart` | web（运行中，`port:3080`） | `5nmvfpef` |
| `restart` | web-dev（`profile:web-dev`） | `8x8apiai` |
| `restart` | review-dev（`profile:review-dev`） | `1pokuw9z` |
| `restart` | headless（`profile:headless`） | `odjh9zso` |

### 3. 顺序无关（`pass.json` 的 `order`）

- 动的什么：`touch -d '2030-01-01 00:00:00' ~/.dsh/profiles/headless`
  （已停止组按目录 mtime 降序，headless 原先排在最后）
- 卡片顺序：`web :3080, web-dev, review-dev, headless` → `web :3080, headless, web-dev, review-dev`（真的变了）
- 132 个元素逐一对 uid：**变了 0 个**
- 还原：`touch -d "2026-10-15 16:13:38.396605910 +0800" ~/.dsh/profiles/headless`，
  复量 `stat` 与原值一致（`order.restored: true`）

### 4. 对照表

- `uid-table.md`：**618 行**「角色 + 限定 → uid」，按状态分组。
  任取一个 uid 都能查到它是什么，例如 `yoehocfs` = `overview | card | profile:web-dev | menu-trigger`
  = web-dev 那张卡右上角的「⋯」。
- `uid-crosscheck.md`：19 条手写语义路径，**不一致 0**。
  这是三方对齐 —— 路径（照 `uid.mbt` 口径手写）、JS 侧独立重写的算法算出来的 uid、
  页面上元素真带的 `data-uid`。其中就有那一对曾经分不开的徽标：

  | 元素 | 语义路径 | uid |
  | --- | --- | --- |
  | 运行中分组来源徽标 | `overview \| section \| running \| source-badge` | `i478edtj` |
  | 已停止分组来源徽标 | `overview \| section \| stopped \| source-badge` | `hsv3ns45` |

### 5. 出图

- `card-dom.png`：一张已停止卡片的 DOM 片段（缩进过、SVG 内部折叠），
  data-name 与 data-uid 逐处可见；`card-dom.txt` 是同一份纯文本，`card-dom.html` 是渲染它的图页
- `card.png`：这张卡片本身的截图（对照用）

### 6. 项目验收（`run-acceptance.log`）

`node design/run-acceptance.mjs http://127.0.0.1:5390/` → **判定 28 项：通过 28，失败 0**。
新增属性没有改变任何几何与交互（无横向溢出、按钮组右缘、菜单锚点与落焦、
对话框居中与遮罩、日志滚动、动效数量都与基线一致）。

**这一条要说清楚**：光跑 `run-acceptance.mjs` 跑到过三次「通过 27，失败 1」，
失败项固定是「来源下拉含全部在跑实例」（期望 2 只 / 实测 1 项）。
那是验收脚本自己的竞态，不是这次改动：动效探针会点「启动」真拉起一只实例，
它自己的收尾是「点完约 1 秒后轮询一次实例列表，把新出现的停掉」——DSH 实例起来要 1~2 秒，
这个轮询常常来不及；而那条判定比的是「日志页抓取那一刻下拉里几项」与「判定时实时几只在跑」，
日志页探针又跑在动效探针之前。`frontend/evidence-mtime-field/README.md` 第 190-193 行
记过同一次失败，结论一样：**实例集合稳定之后重跑即全过**。

所以最后一跑用 `stable-instances.mjs` 把实例集合按住不动：它只做探针本来就要做的那件事
（把这一轮新起的实例停掉），起跑时在跑的一只都不碰。这一跑的日志在
`stable-instances.log`（停掉本轮新起的 8401 web-dev），判定表 28/28。

## 五、这一轮动过的机器状态（都已还原）

| 动的什么 | 为什么 | 还原 |
| --- | --- | --- |
| `~/.local/state/dsh-console/archive.json` 临时写入一条 `{"profile":"dsh-uid-accept-demo","archivedAt":"2026-10-15T10:00:00.000Z"}` | 没有归档记录时「展开归档区」这个状态根本不存在，量不到 | 量完写回 `[]`，与备份逐字节 `cmp` 一致 |
| `~/.dsh/profiles/headless` 的目录 mtime 推成 2030-01-01 | 顺序无关那一项要真把顺序变一下 | `touch -d` 回原值，`stat` 复量一致 |
| 动效探针在验收过程中起的实例（8400 / 8401） | `run-acceptance.mjs` 自己的行为 | 全部停掉；收工时在跑的只剩原有的 `3080:web` |

控制台（127.0.0.1:5390，pid 565646）全程没有重启、没有 kill。
**没有新建或删除任何 profile**：只动过 `headless` 一个目录的 mtime，没碰过任何内容。

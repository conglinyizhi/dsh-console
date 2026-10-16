# 计划：给开发用的 profile 独立 DSH_HOME

> 状态：**只是计划，未动手**（2026-10-16 使用者提出，明确说「仅计划不行动」）。
>
> **2026-10-16 已按 Phase 0 侦察结论修正三处**（见 `dsh-home-phase0-findings.md`）：
> §3 凭据那条原文写「符号链接」是**错的且危险** ✗✗（会漏明文副本，见下）；
> §7「没有便宜的中间态」**不成立** ✗（有半价方案）；§5.4「插件可能硬编码」**风险不存在** ✓（逐个查过）。
> 起因：现在隔离的是 profile（`cordis.patch.yml` 与它那份 `node_modules`），
> 但 **DSH_HOME 是共用的** —— 会话、插件状态、插件写在 home 根下的数据全都混在一起。

## 一、先看事实（已实测，别凭印象）

`~/.dsh` 顶层实际内容与体量：

| 路径 | 体量 | 性质 | 该不该跟着 profile 隔离 |
| --- | --- | --- | --- |
| `sessions/` | 280M | **按工作目录分组**（11 个目录，形如 `--home-…-airp-probe--`） | 想隔离，但见「代价」一节 |
| `sessions-backup-…/` | 142M | 手工备份 | 不动 |
| `attachments/` | 96M | 会话附件（按哈希存） | 想隔离 |
| `storages/` | 8.1M | **插件状态** | **最该隔离的** |
| `linxi-guard-audit.jsonl`、`linxi-guard-directives/`、`dsh-draw-dream/`、`dsh-canvas/` | 4.1M 起 | **插件直接写在 home 根下的数据** | **最该隔离的** |
| `profiles/` | 5.5M | profile 本体 | 已经在隔离 ✓ |
| `cache/` | 576K | 可重建 | 隔离与否都行 |
| `logs/` | 492K | 控制台起的实例日志落在这儿 | 想隔离（见下） |
| `skills/` | 48K | 技能 | 共享更合理 |
| `.credentials.yaml` | 小 | **凭据** | **绝不复制** ✗✗ 见下 |

**Phase 0 补充的两条事实**（实测）：
- **会话身份 = `(DSH_HOME, cwd, session-id)`**，与 profile 无关 ✓（隔离 home 里跑 headless，落点全在隔离目录；主线 `~/.dsh` 顶层 `-newermt` 为空 ✓）。
- **在役的 `web` 实例，它的 Host 进程环境里没有 `DSH_HOME`** ✗（从 konsole/zsh 起的），而控制台进程有（从 dsh 会话的 bash 里拉起、被注入过）。
  所以「实例进程一定有 DSH_HOME」是错的 ✗ —— 控制台现在去读**实例自己的** `/proc/<pid>/environ` 是对的做法，要保持。

**由此得出两句话**：
1. 现在真正没隔离的是**插件自己的状态**（`storages/` 与挂在 home 根下的插件目录）—— 一个在开发的插件写坏了，会写到主线头上。
2. 会话是按**工作目录**分的、不是按 profile 分的，所以「同一个目录 = 一份历史」这件事本身就是当前的行为。

## 二、目标形态

- **主线 profile 继续共用 home**（会话历史统一，这是它该有的样子）。
- **fork 出来的开发 profile 用独立 home**（例如 `~/.dsh-homes/<profile>/`）。
- 控制台里每只实例/profile **显式标出它属于哪个 home**（卡片上已经有 `DSH_HOME` 那一格，正好用上）。

## 三、独立 home 里放什么（这一节是成败关键）

| 项 | 做法 | 理由 |
| --- | --- | --- |
| `.credentials.yaml` | **在凭据插件那一行配 `config.path` 指向共用那份** ✗✗ **不要用符号链接** | **符号链接是错的**：凭据写入走 `writeFileAtomic`（临时文件 + rename），而 rename 会**替换掉链接本身**而不是写穿 —— 实测过，链接变成普通文件，共用那份没动，**独立 home 里多出一份明文密钥副本** ✗✗ 没有环境变量能指凭据，`config.path` 是唯一的口子 |
| `skills/` | **必须显式链接** | `$DSH_HOME/skills` 与 `~/.agents/skills` 是**两个独立的根**（本机两个都在用），独立 home **不会自动继承**前者 ✗ |
| `sessions/`、`attachments/`、`storages/`、`cache/`、home 根下插件数据 | **全新的一份** | 隔离的正是这些 |
| 体量 | 新 home 起步几乎为零 | 280M 是历史积累，不会跟着复制 |

## 四、控制台要跟着改（真正的工作量在这儿）

现在的读接口都**假定只有一个 home**：`profiles` 的 `dshHome`/`dshHomeSource`、日志的「目录依据」、
实例的 `--profile` 解析、备注与归档的键 —— 全都是单 home 口径。多 home 之后要：

1. `profiles` 改为**跨 home 聚合**，每只标出所属 home；同名不同 home 是两只。
2. 实例识别**按 home 归位**（`--profile` + 该进程的 `DSH_HOME` 一起定身份，不能只看名字）。
3. 备注、归档、回收站的键都要带上 home（否则同名会串）。
4. 设置里的「端口起点」「删除方式」这些是**控制台自己的**，不受影响 ✓。

## 五、代价与风险（如实列，不美化）

1. **会话历史会被拆开** ✗ —— 同一个工作目录在不同 home 下是两份历史；
   想 `--resume` 找昨天那个会话，可能要找对 home 才找得到。
   缓解：卡片上显式显示 `DSH_HOME`（已有）✓；控制台可在会话相关处提示「这只实例用的是另一份 home」✓。
2. **凭据不能复制** ✗✗ —— 只能符号链接；链接对「换了 key」天然有效 ✓。
3. **控制台改造是真工作量**（第四节）—— 比「加个环境变量」大得多 ✗。
4. ~~插件可能硬编码 `~/.dsh`~~ **风险不存在** ✓（Phase 0 逐个查过：全部是「读 `process.env.DSH_HOME`，为空才退回 `~/.dsh`」，逐条带文件:行号；两个无主目录是空的）。
   这是整个计划**能否成立的生死前提**，它成立了 ✓ 但前提是**启动器必须把 `DSH_HOME` 注入实例的进程环境** —— 控制台已经在做 ✓
5. 磁盘：每个 home 起步很小，但长期各自长大。

## 六、建议顺序

1. **Phase 0（便宜）**：摸清 dsh 自己对 home 的语义 —— 哪些路径是 home 相对、有没有官方的多 home 支持、
   会话身份是不是 `(工作目录, home)`；顺带验那几个插件是否 respect `DSH_HOME`。
2. **Phase 1（便宜）**：定「哪种 profile 给独立 home」（倾向：fork 给的，主线不给）。
3. **Phase 2（便宜）**：定 home 里放什么（第三节表）。
4. **Phase 3（大）**：控制台多 home 改造（第四节）。
5. **Phase 4**：迁移 —— 已有 fork 不强制迁 ✓；提供「迁到独立 home / 迁回来」两个动作，失败可回退 ✓。

## 七、便宜的中间态：**有**（原文写「没有」是错的 ✗，Phase 0 实测推翻）

`sessions/` 与 `storages/` 的根**不是硬编码**，是组合层的表达式：

```
dsh-base/cordis.patch.yml:133   root: !!js dshHomePath('sessions')
dsh-base/cordis.patch.yml:171   root: !!js dshHomePath('storages')
```

而 patch 换 config 是整体替换，有两层可用：**home 级** `$DSH_HOME/cordis.patch.yml`（压过 profile 层）与 `--patch <file>`。
**实测**：在隔离 home 里用 `--patch` 把两个根都挪到别处，会话确实落在挪走的位置 ✓

同样机制还能挪：`attachments`（attachment-local 有 `dshHome` 配置）与**凭据**（credentials-local 有 `path`，见 §3）。

**盖不到的**：`profiles/`、`logs/`、以及只读 env 的插件状态 —— 所以是**半价**不是全价 ✓
但「要么做 Phase 3、要么维持现状」这个说法**不成立** ✓
## 八、它跟已有功能的关系

- 「复制开发指令」里那段约束（只改这一份、别动主线）在多 home 之后**会更硬** ✓（连状态都不在一处了）。
- 归档/回收站语义不变 ✓（只多一个 home 维度）。
- 派生时若目标 home 不同，`node_modules` 那份「缺包」提示照旧成立 ✓。
---

## 决定（2026-10-16，使用者拍板）：选 B 层

> 「B，要不然这个软件的隔离功能不可靠」

B 层 = 日志、技能、缓存、home 根下的插件目录都要隔离。
这些东西走 DSH_HOME 相对路径或 dshHomePath 服务，profile 层的 patch 覆盖不到 ✗，
所以：每只开发用 profile 必须有自己的一份 DSH_HOME —— 第三、四节是必做项，砍不掉。

### 口径跟着改

1. Phase 2.5（profile 层 patch 挪 root）在独立 home 方案下大部分不再需要 ——
   给了 profile 自己的 home，sessions、storages、logs、cache、技能、home 根插件目录天然都在里面。
2. 但凭据那一条仍然必做且方式不变：credentials 那一行配 config.path 指向共用那一份，
   绝不能用符号链接（写入走 writeFileAtomic，rename 会替换掉链接本身，每个 home 里会多一份明文密钥副本，Phase 0 已实测）。
3. 技能有两个根要显式处理：$DSH_HOME/skills 与 ~/.agents/skills 是独立的两个，
   独立 home 不会自动继承后者 —— 要么显式链接，要么明确开发 profile 不挂全局技能（这是要定的取舍）。
4. Phase 3 多一条前置：动手前先追清控制台自己是怎么列会话的
   （Phase 0b 只确认后端不直接扫 sessions 目录，没追出真实来源）。
   否则会出现会话挪走了、控制台里看不见了。

### 工作顺序

1. 追清控制台的会话列表来源（Phase 3 前置，小）
2. 定技能那个取舍（挂链接还是各用各的）
3. Phase 3：控制台多 home 改造（跨 home 聚合 profile、实例按 home 归位、备注归档回收站的键带上 home）
4. Phase 4：迁移（已有 fork 不强制迁，提供双向迁移动作，失败可回退）

# dsh-console Phase 0：DSH_HOME 语义侦察结论

> 状态：**只读侦察，未改任何产品代码**（2026-10-16）。
> 对应计划：[`dsh-home-isolation-plan.md`](dsh-home-isolation-plan.md) 第六节 Phase 0。
> 侦察对象：本机安装的 `@deepseek-ai/dsh@0.2.0-rc.2`，装于
> `~/.local/share/pnpm/global/v11/9f523-18dc46948a8c937c-0/node_modules/.pnpm/`。
> 下文所有 `包名/lib/xxx.js:行` 都相对该 `.pnpm` 目录；找不到就按包名搜同名目录。

---

## 结论先行

**独立 DSH_HOME 这条路能真隔离干净 —— 前提只有两条，且都不涉及改 dsh 源码。**

1. **启动器必须把 `DSH_HOME` 注入实例的进程环境**（不是只在 dsh 内核里解析）。
   我们自己那几个插件全是读 `process.env.DSH_HOME`，读到空串/未定义就退回硬编码的 `~/.dsh`。
   控制台现在已经在做这件事（`backend/actions/instance.mbt:690`），所以控制台起的实例是干净的。
2. **`.credentials.yaml` 绝对不能用符号链接** —— 一次写入就会把链接换成一个真文件，
   等于往独立 home 里落一份明文密钥副本。改用 `credentials` 那一行的 `path` 配置（有实测，见 Q4）。

另外有一条**计划文档写错了、需要改口径**：第七节「没有便宜的中间态」不成立。
`sessions` 与 `storages` 的根都是**组合层（patch 层）算出来的**，一个 patch 就能把它们指到任意路径，
不需要第二个 home。详见 Q2 与「计划文档要改的地方」。

**没有一个自研插件硬编码 `~/.dsh` 到不可挽回的地步。** 见 Q5。

---

## Q1. dsh 里哪些路径是 home 相对的

### 中枢：`@deepseek-ai/dsh-home-paths`

整个 dsh 只有一套 home 解析，别的包都从它派生：

```
dsh-home-paths/lib/index.js:73-76
function resolveDshHome(configured, env = process.env) {
	const fromEnv = env[DSH_HOME_ENV];
	return resolve(expandHomePath(configured ?? (fromEnv !== void 0 && fromEnv.trim().length > 0 ? fromEnv : defaultDshHome())));
}
```

优先级：**显式配置 > `$DSH_HOME` > `~/.dsh`**；空串或纯空白的 `DSH_HOME` 当未设置（:66-68 注释）。
派生子路径用 `dshHomePath(...segments)`（:82-84）与 `dshCachePath(...)`（:91-94，固定插一层 `cache`）。

### 逐个列表

| 数据 | 实际落点 | 是不是 home 相对 | 证据 |
| --- | --- | --- | --- |
| 会话日志 | `$DSH_HOME/sessions` | ✓ | `dsh-base/cordis.patch.yml:133` `root: !!js dshHomePath('sessions')` |
| 插件 KV 状态 | `$DSH_HOME/storages` | ✓ | `dsh-base/cordis.patch.yml:171` `root: !!js dshHomePath('storages')` |
| 会话附件 | `$DSH_HOME/attachments/v1` | ✓ | `dsh-attachment-local/lib/index.js:996` `join(dshHome, "attachments", "v1")` |
| 附件缓存 | `$DSH_HOME/cache/attachments` | ✓ | `dsh-attachment-local/lib/index.js:997` `dshCachePath({ dshHome }, "attachments")` |
| 缓存根 | `$DSH_HOME/cache` | ✓ | `dsh-home-paths/lib/index.js:91-93` |
| 凭据 | `$DSH_HOME/.credentials.yaml` | ✓ | `dsh-credentials-local/lib/index.js:58` |
| 匿名用户 id | `$DSH_HOME/.anonymous-user-id` | ✓ | `dsh-anonymous-user-id/lib/index.js:51` |
| profile 本体 | `$DSH_HOME/profiles/<name>` | ✓ | `dsh-app-boot/lib/index.js:485`（`PROFILES_DIR`）+ `:524-526` |
| 启动报告 | `$DSH_HOME/logs` | ✓ | `dsh/lib/bin.js:178` `const logDir = join(context.home, "logs")`（:151 注释） |
| 技能 | `$DSH_HOME/skills` | ✓ | `dsh-skill-filesystem/lib/index.js:172` `join(this.dshHome, "skills")` |
| 设置（新） | `$DSH_HOME/settings.yaml` | ✓ | `dsh-settings/lib/index.js:348` `join(profile.home, "settings.yaml")` |
| 设置（旧，迁移残留） | `$DSH_HOME/settings.yaml.imported` | ✓ | 同上，`:350-351` rename 成 `.imported` |
| llm-deepseek 文件缓存 | `$DSH_HOME/llm-deepseek/files-v3.json` | ✓ | `dsh-llm-deepseek/lib/index.js:804` |
| home 级用户 patch | `$DSH_HOME/cordis.patch.yml` | ✓ | `dsh/lib/profile-boot-BZ2ZjNWi.js:115-117` |
| home 级 `.env` | `$DSH_HOME/.env` | ✓ | `dsh-app-boot/lib/index.js:3433-3437`（`readEnvLayer(binName, home, ...)`） |
| 语音输入模型 | `$DSH_HOME/speech-to-text/sensevoice` | ✓ | `dsh-experimental-voice-input-bundle/cordis.patch.yml:9` |

### 明确**不是** home 相对的（容易踩）

| 数据 | 实际落点 | 证据 |
| --- | --- | --- |
| 用户级技能根 | `~/.agents/skills`（**OS home**，不是 `$DSH_HOME`） | `dsh-skill-filesystem/lib/index.js:78`：`resolve(config.agentsHome ?? process.env.DSH_AGENTS_HOME ?? join(homedir(), ".agents"))`，再 `:177` 拼 `skills` |
| 项目级技能根 | `<project>/.dsh/skills`、`<project>/.agents/skills` | `dsh-skill-filesystem/lib/index.js:155, 160` |
| 打包技能目录 | `$DSH_BUNDLED_SKILL_DIR` | `dsh-skill-filesystem/lib/index.js:84` |
| PreShell 兜底 | `~/.pi/runtime/preshell` | 已归档的 guard `lib/preshell.mjs:97` |

**所以：`$DSH_HOME/skills`（48K，技能）在独立 home 下会**看不到**主线的技能 —— 计划第三节说「链接或共享」是对的，
而且从 Q1 看，**必须显式链接/复制，不会自动跟随 `~/.agents`**。
顺带一提，本机两个技能根都真实在用：`~/.agents/skills` 35 项，`~/.dsh/skills` 16 项。后者会跟着独立 home 走（变空），前者天然共享、不受影响。

---

## Q2. 有没有官方的多 home 支持

**没有。**

- `resolveDshHome` 只返回**一个**根，没有列表、没有 per-profile home、没有「按 profile 分 home」的概念。
- CLI **没有 `--home` 参数**。`dsh/lib/bin.js:105` 的全部选项只有
  `--profile` / `--from-default-profile` / `--patch` / `--dump-config` / `--dump-config-schema` / `--dump-default-config`。
- **`DSH_HOME` 只能来自继承的进程环境**，任何 `.env` 都设不了它：
  `dsh-app-boot/lib/index.js:3358-3364` 把 `DSH_` 列为 `BOOTSTRAP_PREFIXES`，`:3385-3388` 的 `isBootstrapOnly` 命中即拒，
  错误文案在 `:3415`（「…only the launching environment may set…」）。`:3366-3371` 注释写明「`DSH_HOME` 本身是 bootstrap-only，
  所以没有任何 `.env` 能挪动这条豁免」。

### 但有一个真正能覆盖路径的开关（计划第七节没算到）

组合层是**可 patch** 的，而且 **patch 换 `config` 是整体替换、不深合并**：

```
dsh-app-boot/lib/index.js:2760
"An insert appends entries, optionally inside the group identified by id. Other patches replace
 supplied fields; config is replaced wholesale, not deep-merged."
```

而 `sessions` / `storages` 的根正是组合层里的表达式（`!!js dshHomePath('sessions')`），不是硬编码。
可用的 patch 层有两层（`dsh/lib/profile-boot-BZ2ZjNWi.js:193-198` 注释写明顺序）：

1. `$DSH_HOME/cordis.patch.yml` —— home 级用户层，**压过 profile 自己的层**，对每个 profile 都生效；
2. `--patch <file>` —— 每次启动追加的 overlay，排在最上。

**实测（隔离 home 内跑 headless，patch 把两个根都挪走）：**

```yaml
# redirect.patch.yml
- id: session-persistence-jsonl
  config:
    root: /tmp/dsh-home-probe-phase0/redirected-sessions
- id: storage-json
  config:
    root: /tmp/dsh-home-probe-phase0/redirected-storages
```

```
$ DSH_HOME=/tmp/dsh-home-probe-phase0 dsh --profile headless --patch .../redirect.patch.yml "say hi"
# （模型调用因缺 key 失败，但会话已经落盘）
/tmp/dsh-home-probe-phase0/redirected-sessions/--tmp-dsh-home-probe-phase0-some-project--/session-7f41c516-.../
/tmp/dsh-home-probe-phase0/redirected-storages/session_projcache/sessions/
```

同样机制还能挪 `attachments`（`attachment-local` 有 `dshHome` 配置项）与凭据（`credentials-local` 有 `path`），
实测 `--dump-config` 已确认两层 patch 都吃进去了：

```
- id: credentials
  config:
    path: ~/.dsh/.credentials.yaml
- id: attachment-local
  config:
    dshHome: /tmp/dsh-home-probe-phase0/redirected-attachments-home
```

**它盖不到的**：只读 `process.env.DSH_HOME` 的插件（`dock/`、`linxi-modes.json` …）、`profiles/`、`logs/`。
所以 patch 层是「半价」，不是「全价」。但它确实存在，计划第七节的「要么做 Phase 3，要么维持现状」过于绝对。

### 其余与路径有关的环境变量（全部无害）

```
$ grep -rhoE "DSH_[A-Z0-9_]{2,}" <安装树> --include='*.js' | sort | uniq -c | sort -rn
```
结果里与**路径**有关、且不是 `DSH_HOME` 的只有两个：
`DSH_AGENTS_HOME`（改 `~/.agents` 的位置）与 `DSH_BUNDLED_SKILL_DIR`。其余是遥测、传输、DOM 命名空间等。

---

## Q3. 会话的身份到底是什么

### 源码结论：是 `(home, 工作目录, 会话 id)`，**不含 profile**

会话根的来源是组合层（Q1 第一行），根之下再按 cwd 与 id 分层：

```
dsh-session-persistence-jsonl/lib/index.js:884-903   projectKey(cwd)  → "--home-clyzhi-Public-foo--"
dsh-session-persistence-jsonl/lib/index.js:902-904   projectDir(root, cwd) = join(root, projectKey(cwd))
dsh-session-persistence-jsonl/lib/index.js:914-916   sessionDir(root, cwd, id) = join(projectDir(root,cwd), encodeSegment(id))
dsh-session-persistence-jsonl/lib/index.js:926-938   logPath(...) = <sessionDir>/session.v4.jsonl[.zstd]
```

组合层里 `root = dshHomePath('sessions')` ⇒ **身份 = `(DSH_HOME, cwd, session-id)`**。
profile **不在键里** —— 同一个目录在同一 home 下不论用哪个 profile 都是同一份历史。这印证了计划第一节的第 2 条。

### 实测：两边对上

隔离 home `/tmp/dsh-home-probe-phase0`，工作目录 `<probe>/some-project`：

```
$ DSH_HOME=/tmp/dsh-home-probe-phase0 dsh --profile headless "say hi"
dsh: MISSING_CREDENTIAL: llm-deepseek: no API key for provider route "deepseek-official"; ...
```

（模型调用失败不影响结论 —— 会话在调模型之前就已经落盘。）

```
/tmp/dsh-home-probe-phase0/sessions/--tmp-dsh-home-probe-phase0-some-project--/session-bb0966a6-2522-4b35-8300-bae6c3c1be9d/
    session.v4.jsonl.zstd      ← 会话正文（0600）
    session.lock
/tmp/dsh-home-probe-phase0/storages/session_projcache/sessions/session-bb0966a6-....json
/tmp/dsh-home-probe-phase0/.anonymous-user-id
/tmp/dsh-home-probe-phase0/profiles/headless/{cordis.yml,cordis.patch.yml,package.json,pnpm-workspace.yaml}
/tmp/dsh-home-probe-phase0/profiles/web/…（同一次跑里 --dump-config 初始化出来的）
```

**主线 `~/.dsh` 全程未被触碰**：

```
$ find ~/.dsh -maxdepth 1 -newermt '2026-10-16 11:30'
（空）
```

目录键的编码与既有的 `~/.dsh/sessions/--home-clyzhi-Public-…--` 完全同构。
实测完 probe 目录已删除。

### 附带发现（对控制台要紧）：Host 进程其实**没有** `DSH_HOME`

读 `/proc/*/environ` 得到的现场：

```
pid 7734  DSH_HOME=<absent>
  node ~/.local/share/pnpm/global/v11/499c6f07…/node_modules/@deepseek-ai/dsh/lib/bin.js --profile web --no-open
pid 41984 DSH_HOME=~/.dsh
  ./_build/native/debug/build/dsh-console-backend.exe      （ppid = 7734）
```

那个 `dsh --profile web` 是从 konsole/zsh 里起的（`ppid 1988 = /bin/zsh`），**启动环境里就没有 `DSH_HOME`**，
它的 home 是 `resolveDshHome()` 走默认分支算出来的 `~/.dsh`。
而控制台进程是**从 dsh 会话的 bash 工具里**被拉起来的，于是拿到了 `dsh-shell-env` 注入的 `DSH_HOME`
（`dsh-shell-env/lib/index.js:86`：`[DSH_HOME_ENV]: this.dshHome`）。

**两个后果，Phase 3 必须按这个来：**

- 别把「进程环境里有 `DSH_HOME`」当成理所当然。控制台现在读**实例进程自己的** `/proc/<pid>/environ`
  （`backend/processes/processes.mbt:271`、`backend/instances/weburl.mbt:378-388`）是对的做法，要保持；
  而控制台自己的 `resolve_dsh_home`（`backend/runtime/*.mbt:151-156`）反映的是**控制台**的环境，不是实例的 —— 今天两者恰好一致，纯属启动方式巧合。
- 反过来说：**只要启动器注入了 `DSH_HOME`，插件就一定跟得上**。这正是控制台 `instance.mbt:690` 正在做的事。

---

## Q4. `.credentials.yaml` 怎么被读的

### 路径

```
dsh-credentials-local/lib/index.js:56-61
function resolveSpec(config) {
	return {
		filename: resolve(config.path ?? join(resolveDshHome(config.dshHome), ".credentials.yaml")),
		watch: config.watch ?? true,
		debounceMs: config.debounceMs ?? 100
	};
}
```

- 默认 home 相对（`$DSH_HOME/.credentials.yaml`），**没有任何环境变量能指到别处**。
- 想指到别处只有一条路：给 `credentials` 那一行（`dsh-base/cordis.patch.yml:117-118`，id 就是 `credentials`）
  配 `path: <绝对路径>`。**实测可用**，见 Q2 的 dump 片段。
- 另外它还把 `$DSH_HOME/.env` 与 `<cwd>/.env` 当作**只读**回退来源（`dsh-credentials-local/lib/index.js:13-20` 的头注释），
  优先级：继承环境 > `$DSH_HOME/.credentials.yaml` > `<cwd>/.env` > `$DSH_HOME/.env`。
- 监听用 `canonicalizeWatchPath`（`dsh-home-paths/lib/index.js:29-44`），会 `realpath` 到最终真身。

### ✗✗ 计划第三节「符号链接」这条是**错的**

凭据的写入全部走原子替换：

```
dsh-credentials-local/lib/index.js:557, 580, 620, 682   await writeFileAtomic(this.spec.filename, ...)
```

而 `dsh-atomic-write` 自己写明 rename 会**替换掉符号链接本身**，而不是写穿到它指向的文件：

```
dsh-atomic-write/lib/index.js:45-56（JSDoc）
* ... The rename also replaces a symlinked target itself instead of writing
* through to its referent, and the same-directory sibling keeps the rename on
* one filesystem.
（实现见 :66-72，temp 同名目录 + rename）
```

**实测（隔离目录，未碰真凭据）：**

```
BEFORE  linked isSymlink = true
AFTER   linked isSymlink = false | mode = 600
AFTER   shared file content = "DEEPSEEK_API_KEY: shared-original"
AFTER   linked file content = "DEEPSEEK_API_KEY: written-through-isolated-home"
```

也就是说：**在 Models 页存一次 key，符号链接就变成一个真文件，独立 home 里从此躺着一份明文密钥副本**，
而共用那份原地不动 —— 正好是计划第三节标了 ✗✗ 想避免的结果。硬链接同理（rename 换的是目录项，共用 inode 反而更迷惑）。

**替代做法（推荐）**：在 home 级 `$DSH_HOME/cordis.patch.yml`（或 profile 层）里写

```yaml
- id: credentials
  config:
    path: ~/.dsh/.credentials.yaml
```

写入直接落到共用文件上，原子替换、跨进程锁、`0600` 校验全都是原本的语义，没有副本。

---

## Q5. 我们自己那几个挂在 home 根下的数据目录

先把「谁在写」查清楚，再逐个看代码。

### 实际的家底

```
$ ls ~/.dsh
attachments/  cache/  dock/  dsh-canvas/  dsh-draw-dream/  dsh-session-manager/
fragments.toml  linxi-guard-audit.jsonl  linxi-guard-classifier-key  linxi-guard-directives/
linxi-guard.json  linxi-modes.json  linxi-review-pool.toml  linxi-models.toml.bak-*  logs/
profiles/  sessions/  sessions-backup-20261002-122314/  settings.yaml.imported  skills/  storages/
```

### 逐项判定

| home 根下的东西 | 写入方 | 代码位置 | `DSH_HOME` 判定 |
| --- | --- | --- | --- |
| `linxi-modes.json` | `dsh-linxi`（行 id `linxi-modes`，**在役**） | `dsh-linxi/lib/host.mjs:118-127` | **✓ 读 `process.env.DSH_HOME` 优先** |
| `dock/` | `dsh-dock`（**在役**） | `dsh-dock/index.js:105-108` | **✓** |
| `dsh-session-manager/annotations.v1.json` | `dsh-session-manager@0.6.2`（**在役**，npm 包） | `.../dsh-session-manager/lib/index.js:179-182` → `compat/dsh-adapter.js:151` | **✓ 走 Host 服务 `ctx.get("dshHomePath")`** |
| `fragments.toml` | `dsh-linxi-fragments`（**已停用**） | `dsh-linxi-fragments/lib/fragments.mjs:34-39` | **✓** |
| `linxi-guard-audit.jsonl` | `dsh-linxi-guard`（**已退役、源码在 .archive**） | `.archive/dsh-linxi-guard/lib/audit.mjs:36-42, :111, :121` | **✓** |
| `linxi-guard-directives/` | 同上 | `.../lib/directives.mjs:92-96, :103-107` | **✓** |
| `linxi-guard.json`（overlay）、`linxi-guard-rules.txt` | 同上 | `.../lib/index.mjs:1271, 1286-1293` | 走 `ctx.fs.resolve()`（**cwd 相对**）—— 见下方注 |
| `linxi-guard-classifier-key` | 同上 | `.../lib/secret.mjs:18-22, :28-30` | **✓** |
| `linxi-review-pool.toml` | 同上 | `.../lib/memory.mjs:60,69`；`.../lib/pool.mjs:46,176` | **✓** |
| `dsh-draw-dream/` | `dsh-draw-dream`（**已归档**） | `.archive/dsh-draw-dream/index.js:43`、`channels.js:25` | **✓** |
| `dsh-canvas/` | **找不到任何代码**，目录**空的**（pages/assets 都空，mtime 10月2日） | —— | 无主残留 |
| `.agent-presets/` | **找不到任何代码**，目录**空的**，mtime 8月15日 | —— | 无主残留 |
| `linxi-models.toml.bak-*`、`sessions-backup-*` | 手工备份 | —— | 不归代码管 |

典型写法（三个包一模一样，只是变量名不同）：

```
dsh-linxi/lib/host.mjs:118-127
export function statusPath() {
	const fromEnv = process.env.DSH_HOME;
	const candidates = [fromEnv, …, join(homedir(), '.dsh')];
	const home = candidates.find((c) => typeof c === 'string' && c !== '');
	return home === undefined ? undefined : join(home, 'linxi-modes.json');
}

dsh-linxi-guard/lib/audit.mjs:36-42
function harnessHome() {
	const explicit = process.env.DSH_HOME?.trim();
	if (explicit !== undefined && explicit !== '') return explicit;
	…
	return join(homedir(), '.dsh');
}

.archive/dsh-draw-dream/index.js:43
const ROOT = path.join(process.env.DSH_HOME?.trim() || path.join(os.homedir(), '.dsh'), 'dsh-draw-dream')

dsh-dock/index.js:105-108
const home = typeof process.env.DSH_HOME === 'string' && process.env.DSH_HOME.length > 0
  ? process.env.DSH_HOME : join(homedir(), '.dsh');
```

### 判定

**没有一个是「硬编码 `~/.dsh` 且不看环境变量」的。** 全部是
「读 `process.env.DSH_HOME`，为空才退回 `~/.dsh`」。
所以**只要启动器注入 `DSH_HOME`，这五六个包全都会跟着走** —— 隔离不会漏。

要注意的是这个回退**不是死代码**：Q3 那个现场说明里，在役的 web 实例 Host 进程 `DSH_HOME` 就是缺的，
插件此刻正靠 `~/.dsh` 兜底 —— 今天兜对了，但它是兜的，不是算的。

### 扫出来的两个瑕疵（不影响结论，但值得记一笔）

1. `dsh-linxi/lib/host.mjs:122` 的回退链中间一项写成
   `join(process.env.DSH_PROFILE_DIR, '..')` —— `DSH_PROFILE_DIR` 是 `<home>/profiles/<name>`，
   取父目录得到的是 `<home>/profiles`，**不是 home**。
   因为 `DSH_HOME` 永远排第一位，这项实际取不到，属于潜伏错误。
2. `dsh-linxi-guard/lib/audit.mjs:39-41` 两个分支返回同一个值（`===` 判断 `DSH_PROFILE` 后照样返回 `~/.dsh`），
   是写残的分支。该包已退役，改不改都行。

### 关于 guard 的 overlay 路径

`linxi-guard.json` / `linxi-guard-rules.txt` 走的是 `ctx.fs.resolve(settings().overlayFile)`（`lib/index.mjs:1288`），
这是 **cwd 相对**，不是 home 相对 —— 尽管文件实际躺在 home 根下。
该行在 `~/.dsh/profiles/web/cordis.patch.yml:67-81` 已 `disabled: true`（2026-10-07 退役），
所以这是历史遗留口径，不是现役行为。要恢复时顺手改掉。

---

## 「独立 DSH_HOME 能不能真隔离干净」

**能。** 判据：

- dsh 内核的**全部**用户数据都在一个根下，且那个根可以被 `DSH_HOME` 整个挪走（Q1）。实测无残留。
- 所有自研插件都读 `process.env.DSH_HOME`（Q5），控制台已经给实例注入这个变量（`instance.mbt:690`）。
- 会话、storages、attachments、cache、plugins 状态一并跟着走（Q3 实测）。

**卡点只有两个，且都能在不改 dsh、不改插件的条件下解决：**

1. **`.credentials.yaml` 不能用符号链接** —— 改用 `credentials` 行的 `path` 配置。
   （硬性：符号链接这条路会让密钥副本落进独立 home。）
2. **`DSH_HOME` 必须由启动器注入实例进程环境**，不能指望 dsh 自己 export。
   控制台起的实例没问题；非控制台起的实例（桌面上快捷方式、终端里手敲）**不会有**，
   那时内核与插件会一起退到 `~/.dsh` —— 结果是「这个实例压根没隔离」，而不是「状态被拆开」，
   属于同一种失败但方向不同，Phase 3 要在卡片上把 home 显式打出来（计划第二节已有此意）。

**不卡的地方**：没有任何自研插件把 `~/.dsh` 写死到脱离环境变量。计划第五节第 4 条的风险，实测下来不成立。

---

## 计划文档里需要改口径的地方

1. **第三节表格第 1 行「`.credentials.yaml`：符号链接指向共用那份」** ✗ → 改成
   「用 `credentials` 行的 `config.path` 指到共用那份」。理由与实测见 Q4。
   这一条的代价比预想的小（不用发明新机制，现成配置项），但**做法必须换**。

2. **第七节「有没有便宜的中间态（结论：没有）」** ✗ → 结论要改成「有半价，但不完整」。
   `sessions` / `storages` 是组合层的 `!!js` 表达式，不是硬编码；一个 patch 层就能把它们
   （外加 `attachments`、凭据）指到任意路径，主线 home 保持不变。实测见 Q2。
   代价是它盖不到 `profiles/`、`logs/`、以及只读 `process.env.DSH_HOME` 的插件状态，
   所以「要么 Phase 3、要么现状」的说法不成立，但 Phase 3 仍然是**唯一完整**的答案 ——
   建议把第七节改写成「半价方案能覆盖 X，不能覆盖 Y，完整隔离仍需 Phase 3」。

3. **第三节「`skills/`：链接或共享」** → 要写死成**必须显式链接或复制**。
   `$DSH_HOME/skills` 与 `~/.agents/skills` 是两个独立的根（Q1），独立 home 不会自动继承前者；
   后者本来就跟着 OS home，天然共享，不受影响。

4. **第五节第 4 条「插件可能硬编码 `~/.dsh`……要逐个验」** → 已验完，可以消掉风险标记，
   换成一条更实际的风险：「**启动器没注入 `DSH_HOME` 时，插件与内核会一起静默退回 `~/.dsh`**」。

5. **第四节第 2 条「实例识别按 home 归位」可以省一半力气**：
   控制台已经在读实例进程的 `/proc/<pid>/environ`（`processes.mbt:271`）并已有
   「该实例自己的 `DSH_HOME`，认不出来才落 `~/.dsh`」的逻辑（`weburl.mbt:378-388`）。
   多 home 要补的是**聚合与键**（第四节 1、3 条），不是重新发明 home 探测。

6. 汇总成一句：**Phase 0 的结论是「可以干，而且比计划想的便宜」** ——
   唯一一处「必须改做法」的是凭据，唯一一处「必须保证的前置」是启动器注入 `DSH_HOME`。

---

## 侦察方法与边界

- 全程只读：没改 dsh 源码、没改 profile、没改控制台。
- 实测一律在 `/tmp/dsh-home-probe-phase0`（隔离 `DSH_HOME`）下进行，共两次：
  一次纯净跑（验落点），一次带 `--patch`（验覆盖能力）；**用完已 `rm -rf`**。
- `~/.dsh` 只读：用 `find -newermt` 确认探测期间主线未被写入。
- **没有读 `.credentials.yaml` 的内容**：只看了它的路径解析代码，以及 `file` 层面的权限位。
- 5390 上的控制台实例、`frontend/` 均未触碰。

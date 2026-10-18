# 维护：作业台与「升级 dsh」

状态：名字已定（侧栏第二项「维护」）。规格第二版：**验收由用户自己试，程序只负责把新版跑起来、记下结论、按结论迁移或回滚。**

## 0 一句话

侧栏在「实例总览」下面加一项**维护**。里面是一张**作业台**：一项作业 = 一组按顺序做、每步有检查、失败能退回、关掉页面明天还能接着做的步骤。

第一条作业：**升级 dsh** —— 锁定当前版本当回滚锚，装新版本，把新版本起成一只**能真用的实例**给用户试；用户说好用就迁移到新版，说不好用就回滚，旧版本最后才清理。

## 1 为什么是「作业」不是「流程」

作业有状态（现在到第几步）、有检查（每步的结论要留下）、有回滚点、能中断恢复。流程没有这些。
界面用大白话，内部术语不进正文。

## 2 装在哪

- 侧栏第二项：`维护`，路由 `/maintenance`
- 页面：作业列表（一张卡：标题、状态、第几步、开始于、一句话结果）+ 展开后的步骤表
- 空态：`还没有作业。/ 一条作业是按顺序做完的事，中间停止也不会丢进度。`

## 3 状态与落盘

- 目录：`$XDG_STATE_HOME/dsh-console/jobs/`（与 dsh-pin.json 同一套口径，走 `@store.state_paths()` 加一个 `jobs` 字段）
- 一份作业一个文件：`<jobId>.json`，jobId = `<kind>-<epoch秒>`
- 形状（字段名即 JSON 键）：

```json
{
  "id": "upgrade-dsh-1791028571",
  "kind": "upgrade-dsh",
  "title": "升级 dsh",
  "createdAt": "…", "updatedAt": "…",
  "step": "lock|install|trial|verdict|commit|rollback|cleanup|done|aborted",
  "steps": [
    { "key": "lock", "state": "passed|failed|skipped|not-run|running", "at": "…",
      "note": "一句人话", "evidence": {} }
  ],
  "rollbackAnchor": { "dir": "…", "version": "0.2.1-rc.2" },
  "target": { "version": "0.2.2-rc.1", "dir": "…" },
  "trial": { "port": 8500, "pid": 1234, "url": "http://127.0.0.1:8500/", "profile": "web", "startedAt": "…" },
  "verdict": { "value": "good|bad", "at": "…", "note": "" },
  "commands": [ { "at": "…", "argv": ["pnpm","add","-g","@deepseek-ai/dsh@0.2.2-rc.1"], "result": "…" } ]
}
```

三条硬口径：

1. **五档状态**：`running / passed / failed / skipped / not-run`。**「没验到」必须是 skipped 或 not-run，绝不能写成 passed**。
2. 写入一律原子（沿用 `@fsx.write_text_atomic`）。坏文件读不出来 → 列表里那条显示「记录读不出来」+ 原因，不吞。
3. 控制台重启后作业还在，状态从文件恢复，不靠内存。

## 4 动作（都走 POST /api/local/action，守卫照旧）

| 动作 | 参数 | 做什么 | 失败码 |
|---|---|---|---|
| `job-start` | `{"kind":"upgrade-dsh","version":"<目标版本>","profile":"<试跑用哪只 profile>"}` | 建作业，**第 1 步 lock 立刻做**：把当前生效的那份 dsh 记为回滚锚（只记在作业里，不动 dsh-pin.json） | `bad-params` / `job-exists`（同一 kind 已有未结束的） / `not-found`（profile 不存在） |
| `job-install` | `{"id":"…","confirm":false}` | `confirm:false` = **预演**：回出确切命令、它会不会覆盖正在跑的那份，不执行；`confirm:true` = 执行 `pnpm add -g @deepseek-ai/dsh@<版本>`，输出尾部记进 commands，并把新版候选目录记进 target | `not-found` / `conflict`（不在 install 步）/ `spawn-failed` |
| `job-trial` | `{"id":"…"}` | **把新版起成一只真用的实例**：新版目录 + 用户真实 DSH_HOME + 用户选的 profile + 空闲端口，等监听 + 签名通过；记 pid / port / url / token（读得到才记）进 trial。**不判定好坏**。跑完 step=trial→verdict | `conflict`（不在 trial 步，或已有一只试跑实例在跑）/ `spawn-failed` |
| `job-verdict` | `{"id":"…","verdict":"good"|"bad"|"later"}` | good → 停试跑实例、把 dsh-pin.json 指到新版、step=commit；bad → 停试跑实例、把 dsh-pin.json 恢复成开工前的状态（原来没指定就删掉）、step=rollback；later → 只记录，什么都不动，step 留在 verdict | `bad-params` / `conflict`（不在 verdict 步） |
| `job-cleanup-preview` | `{"id":"…"}` | 列出「清理后会删掉什么」：旧版包目录、占多大、有没有在跑的实例用它 | `not-found` |
| `job-cleanup` | `{"id":"…","confirm":"DELETE"}` | 删旧版包目录（硬删，只删这一份）。没带 confirm 一律拒 | `bad-params` / `conflict` |
| `job-abort` | `{"id":"…"}` | 中止作业：停掉试跑实例（如果在跑），保留记录与已做步骤，step=aborted | `not-found` |

口径：

- 会动系统的一律先预演（install / cleanup），确认才执行。
- **试跑实例不被作业自动收掉**：用户可能要试一阵。作业在 verdict 步时，页面要显示「试跑实例还在跑」与它的地址，并防止再起第二只。
- 回滚 = 停试跑实例 + 恢复开工前的版本指定。**不删除新装的那份**（删不删是清理那一步的事，用户没要求回滚时连它一起删）。
- 作业记录里出现的路径与命令原文只进悬停/详情，不进正文。

## 5 界面文案（新增可见文案，全部列在这里待审）

- 侧栏：`维护`
- 页面标题：`维护`
- 作业卡标题：`升级 dsh`；副标题：`先留下旧版本，新版本你自己试过再切`
- 步骤名：`锁定当前版本` / `安装新版本` / `把新版本跑起来` / `你来试` / `切到新版本` / `回滚` / `清理旧版本`
- 状态词：`未开始` / `进行中` / `通过` / `不通过` / `跳过` / `没验到`
- 按钮：`开始` / `预演这一步` / `确认执行` / `把新版本跑起来` / `好用，切到新版` / `不好用，回滚` / `先放着` / `清理旧版本` / `中止作业`
- 试跑那一块：`新版本起来了：http://127.0.0.1:<端口>/ —— 你去用一用，插件、配置、会话都是你平时那一套`
- 试跑用的是一个跑起来才知道行不行的东西：`这只实例用的是你真实的 DSH_HOME 和 profile，所以试得出的就是平时那套`
- 切过去之后：`已经切到 <新版>；起实例会用这一版。旧版本留着当回滚锚，确认稳定后再清理`
- 回滚之后：`回滚了：起实例还是用 <旧版>；新装的那份留着没删，要删单独清理`
- 空态：见 §2
- 边界提示：`这一步会真的装东西，装完不会自动切过去` / `清理删的是旧版本的包目录，删掉不能再装回来`

## 6 硬约束

- 不进正文的：目录路径、命令原文 —— 进悬停或「详情」，正文只给结论
- 颜色不作唯一信号（三色灯 + 文字状态词）
- 验证时**不许真跑 `pnpm add -g`**，也不许真删任何包目录：install / cleanup 只验预演与拒绝路径
- 验证时**不许在真实 DSH_HOME 上起试跑实例**：那是用户点才做的事；验证用临时 DSH_HOME + 临时的同名 profile
- 不许跑 moon fmt；构建口径照旧（各自 .sandbox/moonhome + MOON_CC/MOON_AR/MOON_LD）
- 不提交 git
- 不要动 5390；隔离验证用 5391 + 临时 XDG_STATE_HOME + 临时 DSH_HOME

## 7 交回

改动清单、构建任务数、状态机实测（lock→install 预演→trial→verdict 三条分支：good / bad / later，其中 good/bad 只对临时 DSH_HOME 与临时 pin 验）、回滚是否真把版本指定恢复成开工前、试跑实例不自动收掉的证据、控制台重启后作业仍在、验收结果、新增可见文案是否与 §5 一致、没做到的明说。
## 8 第二版增补（用户口径）

### 8.1 维护页用满可用宽度

现在维护页套的是 `.dsh-page`（最大宽度 920px、贴左），1637 宽的窗口里右边空掉一大片。
维护页改成用满内容区宽度：`max-width: none`，只保留内边距。作业卡与步骤表跟着铺开。
关于页与设置页仍用 `.dsh-page` 的窄栏（散文与表单，一行太长反而难读），不跟着改。

### 8.2 目标版本：可搜索，允许自己写

- 目标版本控件换成**可搜索的下拉**：输入即过滤，列出候选（版本号 + 已装 / 最新 / 预发布 标记）。
- 候选来自 `GET /api/local/dsh-releases`（三源顺序见 design/dsh-release-sources.md）。
- 列表里没有想要的版本时，输入框里继续写就是**自定义版本**：给一行提示「列表里没有 <输入>，可以直接用这个版本」，点「用这个版本」按它开工。
- 自定义版本不做存在性校验（控制台不猜远端有什么），装不上由安装那一步如实报失败。

### 8.3 试跑用 profile：不可用的要说原因

- profile 下拉列出本机全部 profile，每条后面可以带状态：
  - **可用**：没有附加标记。
  - **不可用**：置灰不可选，原因写在悬停与下方一行提示里。
- 判据（只看事实，缺包不算不可用）：
  1. 目录读不到 / 没有 `package.json` → 不可用：「读不到这只 profile 的配置」。
  2. `dsh.profile.bundles` 里没有 `@deepseek-ai/dsh-web-app` → 不可用：「这只 profile 起的是命令行型（没有网页入口），试跑要能起网页实例的配置」。
  3. 缺包（`bundles.missing` 非空）**仍然可用**，但旁边注明「缺 N 个包，可能起不来」。
- 正在跑的那只 profile 也可以用（见 8.4），不被占用。

### 8.4 试跑用一次性 home，不占正在用的那份

（口径变更：不再在同一个 home 里复制临时 profile，改成一次性 home，见 design/deep-home-isolation.md 第 6 节）

1. 建 `~/.dsh-homes/trial-<作业 id 末 6 位>/`，按隔离 home 的铺法复制 profile 配置、软链 node_modules、凭证只写路径；
2. 用这份 home 起测试实例，`trial.home` 与 `trial.homeKind="trial"` 记下来；
3. 停止试跑（good / bad / trial-stop / abort）时删掉这个一次性 home。

用户可见的一句话放在试跑那一块：
`试跑跑在一次性的 home 里，你平时那份配置与状态都不动，作业收尾时它会被删掉。`

### 8.5 硬约束补充

- 临时配置只准建在 `<DSH_HOME>/profiles/` 下，名字固定前缀 `trial-`；删除时只删这个名前缀的目录。
- 软链只指向源 profile 的 `node_modules`，不复制、不移动用户的东西。
- 验证时同样不许在真实 `~/.dsh` 上建临时配置：用临时 DSH_HOME 验。
## 9 第三版增补（2026-10-18）

### 9.1 维护页用满宽度

维护页不再套 `.dsh-page` 的窄栏（最大宽度 920px、贴左）。改成用满内容区宽度，只留内边距；
作业卡、步骤表、试跑块跟着铺开。关于页、设置页保持原样。

### 9.2 目标版本可搜索

下拉换成可搜索的：输入即过滤（原生 `datalist` 或自己做的过滤列表都行），选中后仍显示版本号与标记。
列表里没有的版本继续写在输入框里，就是自定义版本，按它开工。三种状态都要有：加载中、有候选、一个源都没答上来。

### 9.3 试跑用 profile 的选择与不可用提示

- 下拉列出本机全部 profile，默认选在跑的那只，其次 web，再次第一只。
- 不可用的置灰并写明为什么：
  1. profile 目录读不到或没有 package.json：`读不到这只配置`
  2. `dsh.profile.bundles` 里没有 `@deepseek-ai/dsh-web-app`：`这只配置起的是命令行型，没有网页入口`
- 缺包（bundles.missing 非空）**不算不可用**，旁边注明 `缺 N 个包，可能起不来`。
- 正在跑的那只也可以选，不会被占用（见 9.4）。

### 9.4 试跑改成一次性 home

job-trial 不再用真实 home 里的 profile：

1. 在 homes root 下建 `trial-<作业 id 末 6 位>`，铺法照 design/deep-home-isolation.md 第 2 节：
   复制选中 profile 的配置、node_modules 与 skills 软链、凭证只写路径；
2. 用这份 home 与作业里的目标包目录起测试实例（`start_instance_with` 已支持指定包目录）；
3. `trial` 里记 `home`、`homeKind:"trial"`、`profileCopy`；
4. 收尾（verdict 的 good / bad、job-trial-stop、job-abort）时停实例并删掉这份 home；
5. home 已存在（上次没收干净）→ 先删再建，并在证据里写明删掉了旧的那一份。

界面在试跑那一块写：
`试跑跑在一次性的 home 里，你平时那份配置与状态都不动，作业收尾时它会被删掉。`

### 9.5 文案

新增文案不要破折号。试跑不可用的两句、`缺 N 个包，可能起不来`、一次性 home 那句都要列进交回清单。

# 深度隔离：每只 profile 一个 home

状态：规格（2026-10-18 定稿，不做兼容考虑）。使用者明确：当前无用户，不必保留旧形状。

## 0 一句话

控制台自己管一个 home 根 `~/.dsh-homes/<profile>/`。某只 profile 一旦被隔离，它起的实例就用这个 home，会话、插件状态、附件、日志都落在里面；它拿去炸的是自己的 home，不牵动别的 profile。

## 1 为什么不再把 `~/.dsh` 当运行时 home

现在所有 profile 共用一个 `~/.dsh`：`sessions/`、`storages/`、`attachments/`、`logs/`、home 根下那些插件目录（`linxi-guard-*`、`dsh-draw-dream/` 等）、`.credentials.yaml` 全部共享。一个插件把 `storages/` 写坏，所有 profile 一起坏。

新的口径：

- **控制台起的实例**一律用「这只 profile 的 home」。
- `~/.dsh` 不作兼容层保留成运行时 home，它退化为两件事的来源：profile 配置的**原件**（供复制）、以及使用者自己在终端跑的 dsh 用的 home。控制台不去改它。

## 2 home 的形状

```
~/.dsh-homes/<profile>/
  profiles/<profile>/            从 ~/.dsh/profiles/<profile> 复制
      cordis.yml
      cordis.patch.yml
      package.json
      pnpm-workspace.yaml        （源里有才复制）
      node_modules -> ~/.dsh/profiles/<profile>/node_modules   （软链，不复制）
  .credentials.yaml              内容只有一行指向真实凭证的路径（见 2.2），不复制密钥
  skills/                        -> ~/.dsh/skills（软链；技能共享更合理）
  logs/                          空目录，实例日志落这儿
  （其余 sessions/ storages/ attachments/ cache/ 由 dsh 首次运行时自己建）
```

### 2.1 插件写在 home 根下的目录

不软链、不复制：隔离 home 里就是空的，插件第一次跑会自己建。要共享的那几个（例如 `linxi-guard-directives`）由使用者自己决定往软链上放，控制台不替他选。

### 2.2 凭证：只给路径，不复制

实测过的坑：`.credentials.yaml` 用软链会被 `writeFileAtomic` 的 rename 换成明文副本，每个 home 里多一份密钥。

做法：隔离 home 的 `profiles/<profile>/cordis.patch.yml` 里加一条把凭据路径指向 `~/.dsh/.credentials.yaml` 的配置（`config.path`），隔离 home 自己**不放**凭证文件。具体配置键在实现时以 dsh 那一版的 schema 为准，写进证据。

## 3 动作

| 动作 | 参数 | 做什么 |
| --- | --- | --- |
| `isolate-profile` | `{"profile":"<名>"}` | 建 `~/.dsh-homes/<profile>/` 并按第 2 节铺好；已存在就报 conflict（不覆盖） |
| `deisolate-profile` | `{"profile":"<名>","confirm":"DELETE"}` | 删掉这只 profile 的隔离 home（只删这个目录，不碰 `~/.dsh`）；有实例在跑就拒 |
| `start-instance` | 不变 | 有隔离 home 就用它；没有就用 `~/.dsh`（此时界面标「共用 home」） |

- `isolate-profile` 复制完成后**要核对**：`package.json` 读得出来、`node_modules` 软链指得通、`cordis.patch.yml` 存在；任何一条不过就回滚（删掉刚建的目录）并报失败。
- 复制期间不许有实例正在用这份 profile 起（同 profile 有在跑的实例时拒）。这是为了避免复制到一半配置变了。

## 4 读数

- `GET /api/local/profiles` 每只 profile 增加：
  - `home`：`{"kind":"isolated"|"shared","path":"…","profileDir":"…","createdAt":"…"}`
  - `homeKindSource`：一句判断依据
- `GET /api/local/runtime` 不动（它说的是控制台自己的 home）。
- 实例行已有的 `dshHome` 继续如实报，隔离与共用一眼能看出区别。

## 5 界面

- 总览里每只 profile 的抽屉加格子：`配置 home`，值 `独立（~/.dsh-homes/web）` 或 `共用（~/.dsh）`；
- 关于页不用改；
- 动作按钮：`隔离到独立 home` / `取消隔离`（带确认，说明会删掉那份 home 里的会话与插件状态）。

文案（待审）：

- `配置 home`
- `独立` / `共用`
- `隔离到独立 home`，悬停：`把这支 profile 复制一份到 ~/.dsh-homes/<名字>/，以后用这支 profile 起的实例都在里面跑，现在这份不动`
- `取消隔离`，悬停：`删掉 ~/.dsh-homes/<名字>/，里面的会话与插件状态一起没了；~/.dsh 里那份不动`
- 确认框：`取消隔离会删掉 <路径> 里的全部内容（会话、插件状态、日志）。确定？`

## 6 升级作业里的试跑也用隔离 home

job-trial 不再在 `~/.dsh/profiles` 里复制临时 profile，而是：

1. 建一次性 home：`~/.dsh-homes/trial-<作业 id 末 6 位>/`，铺法照第 2 节（profile 那几份配置 + 软链 + 凭证路径）；
2. 用这份 home 与新旧版本的包目录起测试实例；
3. 停止试跑（good / bad / trial-stop / abort）时删掉这个一次性 home。

于是「用户试新版本」最坏炸掉的是一个临时 home，主线 `~/.dsh` 与已隔离的其它 home 都不受影响。

界面在试跑那一块写一句：`试跑跑在一次性的 home 里，你平时那份配置与状态都不动，作业收尾时它会被删掉。`

## 7 硬约束

- 只许建 `~/.dsh-homes/` 下的目录；前缀固定：隔离 home 用 profile 名，试跑 home 用 `trial-`。
- 删目录只删这个前缀的；删除前核对路径，不接收客户端给的路径。
- 不复制、不移动、不改 `~/.dsh/.credentials.yaml`，只把路径写进配置。
- 验证不许在真实 `~/.dsh` 与真实 `~/.dsh-homes` 上做：用 `DSH_CONSOLE_HOMES_ROOT` 指到临时目录验（新增这个环境变量，默认 `~/.dsh-homes`）。
- 不跑 moon fmt；构建口径照旧；不提交 git；不动 5390；验证用 5391。
## 8 稳定环境：`~/.dsh` 的定位（2026-10-18 补充）

`~/.dsh` 不做大改，它是**使用者自己用的稳定环境**：

- 它里面现有的配置、会话、插件状态保持原样，控制台不迁移、不重排、不建 home。
- 它同时是**逃生通道**：哪天控制台没了，或者某只隔离 home 玩坏了，在终端里 `dsh --profile web`照样能起一套，用的就是这台机器上装着的 dsh 与这份稳定环境。
- 因此控制台对 `~/.dsh` 只做三件事：读它、往 `profiles/` 里派生与改备注、删东西进回收站。**不做结构改造。**

由此定下 profile 的两档归属：

| 归属 | home | 默认给谁 |
| --- | --- | --- |
| 稳定（`shared`） | `~/.dsh` | 主线自己用的那几只（web 等），不隔离 |
| 隔离（`isolated`） | `~/.dsh-homes/<名字>/` | **新建与派生出来的 profile 默认隔离**；也可以在界面上把某一只改成隔离 |

- 派生出来的 profile 默认隔离：派生时顺手把 home 建好，界面上给一句「已隔离到 ~/.dsh-homes/<名字>」，允许改成共用。
- 隔离 home 必须**能手动启动**：`DSH_HOME=~/.dsh-homes/<名字> dsh --profile <名字>` 与用控制台起是同一套。这条写进关于页的手动启动说明。

关于页新增一小块「手动启动」，给两条现成命令（稳定环境一条、隔离 home 一条），照当前读数填路径。用途只有一个：控制台不可用时，使用者照着敲就能起来。
## 9 改成真移动（2026-10-19 定）

隔离不再是复制：把 profile 目录**移**进隔离 home，取消隔离再**移**回来。用户口径是「移动」不是「复制」也不是「删除」。

### 9.1 手段

用 `rename`（同一文件系统只改目录项，O(1)，与体积无关）。实测 `~/.dsh` 与缺省 homes root 都在 `/dev/sda3`（设备号 2051），所以是瞬时的。

### 9.2 前件与校验（任何一条不过就停手，不留半成品）

1. **同一文件系统**：`stat` 两边设备号不同 → 拒绝，message 写清「两边不在同一个文件系统，移动会退化成复制；把 homes root 放到与 DSH_HOME 同一个盘上再试」。
2. **这只 profile 没有实例在跑**（两个 home 都查）。
3. 目标不存在（不覆盖）。
4. 移动后核对：`profiles/<名字>` 在、`package.json` 读得出、`node_modules`（如果有）软链指得通。
5. 任一条不过：把目录移回原处，报 `io-error`，回执写「移动没完成，已经放回原处」。

### 9.3 隔离（移到独立 home）

`~/.dsh/profiles/<名字>` → `~/.dsh-homes/<名字>/profiles/<名字>`，再铺隔离 home 的其余部分（`skills` 软链、`logs/`、凭证路径那条 patch、隔离记录）。

### 9.4 取消隔离（移回共用 home）

1. `~/.dsh-homes/<名字>/profiles/<名字>` → `~/.dsh/profiles/<名字>`（同一套校验与回滚）；
2. 隔离 home 里剩下的东西（`sessions/`、`storages/`、`logs/`、插件写在根下的目录）**不移回、也不删**，整份移到控制台回收站 `$XDG_STATE_HOME/dsh-console/trash/homes/<名字>-<毫秒>/`，回执说清移到哪儿了、可以捞回来；
3. 确认框文案：「移回共用 home 会把这份额外 home 里剩下的会话与插件状态移到回收站，可以捞回来。」

### 9.5 文案（待审）

- `移到独立 home`（原「隔离到独立 home」）
- `移回共用 home`（原「取消隔离」）
- `正在移动…`（移动期间按钮上的瞬时态，禁用）
- `两边不在同一个文件系统，移动会退化成复制：把 homes root 放到与 DSH_HOME 同一个盘上再试`
- `移动没完成，已经放回原处`
- `移回共用 home？` / `移回共用 home 会把这份额外 home 里剩下的会话与插件状态移到回收站，可以捞回来。`

### 9.6 总览里认得出被隔离的 profile

被隔离的 profile 在总览卡上加一道**金色描边**与一个小金标 `独立 home`：

- 描边挂在卡片本身，不挂在状态灯上；状态灯的颜色照旧由运行状态决定（绿 / 红 / 灰）。
- CSS 上让隔离那条规则优先于状态色相关规则，状态怎么变都盖不掉它。
- 描边颜色不能是唯一信号，所以配文字金标。

不用破折号。

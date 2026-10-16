# dsh-console Phase 3 前置侦察：多 home 之后，谁会读错 home

> 状态：**只读侦察 + 隔离 DSH_HOME 实测**（2026-10-16）。没改产品代码。
> 对应计划：[`dsh-home-isolation-plan.md`](dsh-home-isolation-plan.md) 第四节、以及文末「决定」一节的第 4 条前置。
> 方法：先按包通读所有解析 home 的地方（后端 5 个包 + 前端 6 个文件），
> 再在 `/tmp/p3-probe`（隔离 `DSH_HOME` + 隔离 `XDG_STATE_HOME`，后端端口 5533）起一只**真后端**读接口、发动作，
> 5390 上使用者那只全程没碰（结尾复核：`~/.dsh` 与 `~/.local/state` 顶层 `-newermt` 为空，5390 PID 不变）。

---

## 结论先行

1. **控制台里「读控制台自己的 home」的地方一共五处**：profile 列表（`profiles.mbt:326`）、
   profile 的四个写动作（`profile_fs.mbt:11`）、停止卡的 home 标签与「复制开发指令」（`app.mbt:33/129/523`）、
   归档（`archive.mbt`）、回收站（`profile_fs.mbt:246` + `trash.mbt:213`）。
   多 home 之后它们分三类：**看不见 / 够不着**（profile 列表与写动作）、**同名会串**（归档、回收站、动作冲突判定）、
   **给出错路径**（停止卡 home 标签 → 复制出去的开发指令 DSH_HOME 是错的）。
2. **会给出「错读数」而不只是「少读数」的，是实例侧的 home 探测**：
   `procjoin.mbt:67-75` 的 fd 回退按**字面** `/.dsh/` 取前缀，而计划里的布局是 `~/.dsh-homes/<profile>/`。
   实测该回退直接落空，实例被判成 `$HOME/.dsh`，接着它的 `profileHealth`、日志目录、卡片 home
   全部指向主线 —— 实测拿到的是主线 `web` 的健康读数（missingBundles 3），而这只实例真正在的是隔离 home（应为 0）。
3. **会话历史不受影响**：全仓没有任何地方扫 `sessions` 目录，也没有任何地方用会话 id 做键（复核 Phase 0b 成立）。
   唯一在代码里出现 `sessions` 字样的就是上面那条 fd 回退（`procjoin.mbt:65` 注释）。

---

## 一张表

| 位置（文件:行） | 现在读谁的 home | 多 home 后会怎样 | 要改什么 | 量 |
| --- | --- | --- | --- | --- |
| `backend/profiles/profiles.mbt:326-327` | **控制台自己**（`resolve_dsh_home()`） | 隔离 home 里的 profile **一只都看不见**（实测只列出 fixture 的 `web`） | 跨 home 聚合：要多一份「要扫哪些 home」的出处（配置或注册表），逐 profile 标 home | L |
| `backend/actions/profile_fs.mbt:11`（派生/改名/删除/备注四条都经它） | **控制台自己** | 同上，够不着；同名的会**打到控制台 home 那一份**上 | 每个动作带上目标 home；名字校验之外再加 home 校验 | M |
| `backend/actions/instance.mbt:749-794` `running_for_profile(name)` | 按 **profile 名**比（home 字段拿到了却不用） | 别的 home 里同名实例在跑 → **本 home 起不来**（实测被主线 PID 7734 挡住）；改名/删除同样被挡 | 比 `(home, name)` | S |
| `backend/store/registry.mbt:142` `add_record` | 按 **pid 或 profile 名**去重 | 两只不同 home 的同名实例，后登记的**把前一条挤掉** | 改成 `(pid) 或 (home, profile)` | S |
| `backend/store/registry.mbt:165-185` `find_record` | 按 pid，其次按 **profile 名** | 按名找会命中另一 home 的那条 | 按名那条要求同时给 home | S |
| `backend/instances/instances.mbt:462-482` `lookup_profile_health` | **这只实例的** home（正确） | home 一旦探错（见下条）就跟着读错 profile 的健康 | 不用改；依赖 home 探测修对 | — |
| `backend/processes/procjoin.mbt:67-75` `dsh_home_prefix` | fd 路径里**字面** `/.dsh/` 的前缀 | 对 `~/.dsh-homes/<p>/` **一律返回 None** → 落到 `$HOME/.dsh`（实测） | 不再认字面段；或者认「fd 里出现过的会话/状态路径的可疑前缀」，认不出就如实写「未知」而不是默认主线 | M |
| `backend/processes/procjoin.mbt:327-339` 回退 | `$HOME/.dsh`（**控制台进程**的 OS home） | 外部起的隔离实例被标成主线实例（实测 `dshHome=~/.dsh`） | 同上；这条决定了卡片 home 那一格可不可信 | S |
| `backend/logs/logs.mbt:671-675` 实例来源 | **这只实例的** `dsh_home`，没有才回落控制台（正确） | home 探错时，它在**错的 home 的 logs 里挑文件**（实测 webUrl 已经先去 `~/.dsh/logs/console-web-5534.log` 找令牌）；挑不到就是「这个实例没有可读日志」 | 不用改；依赖 home 探测修对 | — |
| `backend/logs/logs.mbt:53-67` `fixed_sources`（host / audit） | **写死** `$HOME/.dsh` —— 既不看控制台的 `DSH_HOME`，也不是实例的 | 控制台若自己也跑在隔离 home 里，这两条**仍旧指主线**（实测：`DSH_HOME=/tmp/p3-probe/home-console` 时 host 读的仍是 `~/.dsh/logs/retry-control/host.log`，`readOk=true`） | 二选一：改成 `resolve_dsh_home()` 口径，或明确它就是「主线那一份」并在 UI 上写出来（现在前端**只有 instance 来源显示目录依据**，见 `view_logs.mbt:128-135`） | S |
| `backend/store/archive.mbt:8-11,20-25` | 键 = **只有 profile 名** | 同名两份档案**共用一条归档记录**（实测写入 `[{"profile":"zz-same",...}]`） | 键带 home | S |
| `backend/actions/profile_fs.mbt:244-247` 回收站落点 | 目录名 = `<profile>-<epochMs>`，**无 home** | 同名两份都删过就在回收站里并排两条同名的（只能靠时间戳分辨） | 目录名带 home（或写一份 sidecar 记录） | S |
| `backend/actions/trash.mbt:211-214` 恢复 | 目标 = `profiles_root()` = **控制台自己** | 实测：隔离实例删的 `zz-same` 恢复时回到 `home-console/profiles/zz-same`（**不是它来的那个 home**） | 按 home 归位；同名目标已存在时的 conflict 判定也要按 home | M |
| `backend/store/order.mbt:18-23,39-55` | 行 id = `port:<n>` / `profile:<名>` | 两组同名行的拖拽顺序会互相顶 | 行 id 带 home | S |
| `backend/store/laststarted.mbt:109,136,154-157` | id = `profile:<名>` / `port:<n>` | 不同 home 的同名 profile「上次启动」并成一条，取最晚 | 同上 | S |
| `backend/store/settings.mbt`（`settings.json`） | 控制台级，没有 home 语义 | **不受影响** ✓ | 不用改 | — |
| `backend/store/audit.mbt`（`audit.jsonl`） | 键是时间序，行为里有 `params.profile`；`outcome` 里带 `dir`/`trashPath` | 不是键，事后考古还追得回路径；只是按名筛选会混 | 低危；要精确就补 `params.home` | S（可缓） |
| `backend/console_api.mbt:47` | `runtime` 数组**已经带 home** ✓ | 不受影响（前端拿到真实 home） | 不用改 | — |
| `frontend/state.mbt:1948-1949` 停止卡 home | **控制台自己**（hint 直说「控制台当前使用的 DSH_HOME」） | 卡片挂着 `DSH_HOME` 的标签，写的却不是这只 profile 的 home | 这一格改成 profile 自己的 home（或写明「档案所在 home」） | M |
| `frontend/app.mbt:494-504,523-537`「复制开发指令」 | 取 `row.home`（停止行 = 控制台 home） | 复制出去的 `DSH_HOME=<控制台 home>`、`<home>/profiles/<名>` **是错的**，粘过去打不开目录 | 随上一格一起修 | S |
| `frontend/state.mbt:1820-1830` `in_use_by` | 按 **名字**比（注释已自认：「将来支持多 home 时，这里要改成 home + 名字一起比」） | 运行中的实例会把**另一 home 的同名** profile 从「已停止」组里挤掉：那一行整个消失 | 加 home 判据 | S |
| `frontend/app.mbt:248-253` `profile_pairs` | 只发 `{"profile": 名}` | 前端**没有任何办法表达 home**；后端 `start-instance` 那个 `home` 参数（`action.mbt:236`）只有手搓请求够得着 | 行上带 home，params 里带上 | S |
| `backend/actions/instance.mbt:457-478,527-535,565-573,690` 起实例 | **全链路已经是 home 参数化的** ✓（profile 目录、logs 目录、`DSH_HOME` 环境变量、登记表 home 都跟着走） | 实测：给 `home=/tmp/p3-probe/home-dev` 起，日志落在 `home-dev/logs/console-zz-same-5599.log` | 只需把 home 从 UI 一路带过来 | S（接参数） |
| `backend/actions/action.mbt:269` 重启 | 取登记里的 `target.home` ✓ | 重启不会丢 home ✓ | 不用改 | — |
| 会话 / `sessions` / 会话 id | **没有任何地方读** | 不受影响 ✓（会话挪到别的 home，控制台本来也不看它） | 不用改 | — |

---

## 逐项回答

### 1. profiles 读数

- 位置：`backend/profiles/profiles.mbt:325-327`（`read_profiles`）→ `backend/runtime/runtime.mbt:151-156`（`resolve_dsh_home`：读**控制台进程**的 `DSH_HOME`，没有才 `~/.dsh`）。
- 读的是**控制台自己的** home 的 `profiles/`；`profilesRoot` 字段也如实回这个路径。
- 多 home 后：隔离 home 里的 profile **完全不在读数里**（不是标错 home，是根本不出现），
  而 `profiles-missing`（`.mbt:328-330`）只在这一层目录不存在时报错，不看别的 home。
- 实测：隔离控制台 `DSH_HOME=/tmp/p3-probe/home-console` →
  `{"dshHome":"/tmp/p3-probe/home-console","dshHomeSource":"DSH_HOME 环境变量","root":"/tmp/p3-probe/home-console/profiles","names":["web"]}` ——
  同一台机上 `/tmp/p3-probe/home-dev/profiles/web` 一只都没出现。

### 2. logs 读数

两条来源，口径**不一样**：

- **实例来源**（`logs.mbt:613-747`）：home 取 `instance.dsh_home`，取不到才回落 `resolve_dsh_home()`（`:671-675`），
  再把「这条 home 是哪来的」写进 `homeSource`（`:693`）。**这条是对的**，而且 Phase 0 说的「保持读实例自己的 environ」已经做到了。
  它的弱点只有一个：**`instance.dsh_home` 本身探错时它跟着错** —— 而且它不会察觉，
  实测 `webUrlSource` 里已经能看到它先去主线 `~/.dsh/logs/console-web-5534.log` 找令牌
  （同一处 `instance_logs_dir` 口径，`weburl.mbt:389-399`）。
- **固定来源**（`logs.mbt:53-67`）：`host` = `$HOME/.dsh/logs/retry-control/host.log`，
  `audit` = `$HOME/.dsh/linxi-guard-audit.jsonl`。**这里用的是 OS home，连控制台自己的 `DSH_HOME` 都不看。**
  实测：控制台 `DSH_HOME=/tmp/p3-probe/home-console` 时，`GET /api/local/logs?source=host`
  回的 `path` 仍是 `~/.dsh/logs/retry-control/host.log`、`readOk=true`。
- 「目录依据」这条显示：前端只在 `kind == "instance"` 时显示（`frontend/view_logs.mbt:128-135`），
  host / audit 两条**不显示依据** —— 于是使用者更没法知道它指的不是当前 home。

### 3. instances 读数

- profile 名：`procjoin.mbt:299` 从 `/proc/<pid>/cmdline` 读 `--profile`。
- home：`procjoin.mbt:318-341`，三级：实例的 `environ` → fd 表里 `…/.dsh/…` 前缀 → `$HOME/.dsh`（控制台进程的 OS home）。
- 实例 id = `proc-<端口>`（`instances.mbt:625`）；行的唯一性是端口，不是 home。
- **两只不同 home 里的同名 profile，现在会怎样**：读接口**分得开**（每只实例的 home 各读各的，卡片各写各的），
  但只要 home 探测走的是 fd 回退那条路就会**合流**；而**写接口一律按名字**比，是实打实的串：
  - `instance.mbt:749-794` `running_for_profile` 只比名字（`home` 字段明明拿到了）；
  - `registry.mbt:142` `add_record` 按 `pid 或 profile 名` 去重，后一条会挤掉前一条；
  - `registry.mbt:165-185` `find_record` 的第二段按名字找。
  - 实测 A：隔离控制台发 `start-instance {profile: web, home: /tmp/p3-probe/home-dev}`
    → `conflict：profile web 已经在跑（PID 7734，端口 3080）` —— 挡住它的是**主线**那只 `web`。
  - 实测 B：`zz-same`（哪都没在跑）用同一个 `home` 起，一路走到 spawn，日志确实落在
    `/tmp/p3-probe/home-dev/logs/console-zz-same-5599.log`（profile 目录、`DSH_HOME` 环境变量都跟着 home 走了，只是我的 fixture profile 没有 `cordis.yml` 所以没起成）。

### 4. 备注、归档、回收站

- **备注**：文件就写在 `<profile 目录>/.dsh-note.txt`（`profiles.mbt:27-47`），**内容跟着目录走，本身不带 home**。
  但「操作哪一只」由 `profiles_root()`（`profile_fs.mbt:11`）定，即控制台 home。
  实测：`set-profile-note {profile: web}` 写到 `home-console/profiles/web/.dsh-note.txt`，
  `home-dev` 里那只同名的一份**一个字没动**。
  所以：profile 目录留在控制台 home、只有「实例用的 home」不同时，备注**不会串**；
  一旦 profile 目录本身搬进隔离 home，控制台连它都看不见（见第 1 条）。
- **归档**：`archive.json` 的一条只有 `{profile, archivedAt}`（`archive.mbt:8-11,20-25`）。
  **探测证实**：写进去的是 `[{"profile":"zz-same","archivedAt":"..."}]` —— **键里没有 home**，同名会串。
- **回收站**：落点目录名 = `<profile>-<epochMs>`（`profile_fs.mbt:244-247`），**没有 home**；
  恢复目标写死 `profiles_root()`（`trash.mbt:213-214`）。
  **探测证实**：`trash/zz-same-1792142929840`（里面那份的备注写着 `from home-console`），
  `restore-from-trash` 回的是 `/tmp/p3-probe/home-console/profiles/zz-same`；
  而 `home-dev/profiles/zz-same` 从头到尾既没被删、也没被恢复、更没在列表里出现过 ——
  **同一个名字两份档案，控制台既分不清也归不了位。**
- 排序表 `order.json` 也按名（`order.mbt:18-23`），同上。

### 5. 有没有直接扫 sessions / 用会话 id 做键

**没有。** 复核 Phase 0b 成立：

- 后端全 grep（`*.mbt`）：`sessions` 只出现在 `processes/procjoin.mbt:65` 的一条**注释**里
  （讲那条 fd 回退的形态 `…/.dsh/sessions/… → …/.dsh`）。没有任何地方 list / read `sessions` 目录，
  也没有 session-id 形状的键。
- 前端 `*.mbt`：`session` 零命中（只有 `dsh-session-manager` 这类包名不在此列）。
- 副作用（这才是要紧的）：那条 fd 回退**正是因为只认字面**
  `/.dsh/`，在 `~/.dsh-homes/<profile>/` 布局下失效 —— 见第 3 条实测 A（`dshHome` 落到 `$HOME/.dsh`，
  来源写「按默认值 $HOME/.dsh」）。
- 反过来说：**会话挪到别的 home，控制台里「看不见」这件事不会发生** —— 它本来就不看。

### 6. 前端把 home 当展示内容 / 当键

- **当展示内容**：是。卡片抽屉第六格前五格里就有 `DSH_HOME` 一格（`view_overview.mbt:800`），
  值来自 `row.home`：运行中行 = **实例自己的**（`state.mbt:1724-1728`，对）✓；
  已停止行 = **控制台自己的**（`state.mbt:1948-1949`，hint 也这么写）；
  归档孤行 = `"—"`（`state.mbt:2068`）。
- **更重的一处**：`app.mbt:494-504` `dev_home_of` + `app.mbt:523-537`「复制开发指令」——
  停止行拿到的 home 是控制台 home，于是复制出去的正文里
  `DSH_HOME=<控制台 home>`、目录 `<控制台 home>/profiles/<名>`、起法 `DSH_HOME=… dsh --profile …`
  **全是错的路径**。这是隔离功能对外的那个出口，多 home 之后它直接把开发会话引到主线上。
- **当键**：不是。行 id 只有三种：`port:<端口>`、`profile:<名>`（`state.mbt:1918`）、`archived:<名>`（`state.mbt:2052`），
  home 不进任何键。
- **前端从不发 home**：`app.mbt:248-253` `profile_pairs` 只给 `{"profile": 名}`，
  启动/派生/改名/备注/归档/删除都走它；后端 `start-instance` 那个可选 `home`（`action.mbt:236`）UI 够不着。
- 顺带：`state.mbt:1820-1830` `in_use_by` 明确按名字比，注释里已经写着「将来支持多 home 时这里要改成 home + 名字一起比」。

### 7. 控制台状态目录里，哪些其实是「按 home 分」的

| 文件 | 键 / 形状 | 有没有 home | 判定 |
| --- | --- | --- | --- |
| `runtime.json` | `{pid, port, home, profile, startedAt, logPath, detached}`（`registry.mbt:11-19`） | **有 home 字段** ✓ | 数据是 home 感知的；**但去重键是名字**（`:142`），这才是要改的 |
| `archive.json` | `[{profile, archivedAt}]` | 无 | 按 home 分，要补 |
| `order.json` | `["port:3080","profile:web"]` | 无 | 按 home 分（低危） |
| `trash/` | 目录名 `<profile>-<epochMs>` | 无 | 按 home 分，要补 |
| `audit.jsonl` | 追加流水；`params` 有 profile、`outcome` 有 dir/trashPath | 无（可考古） | 不是键，可缓 |
| `settings.json` | 探测参数 / 端口起点 / 删除方式 | 无 | **控制台自己的，不受影响** ✓（计划第四节第 4 条说对了） |

### 8. 顺带清掉计划里那条前置：控制台**没有**会话列表

计划「决定」一节第 4 条与 Phase 0b 第十节第 2 条都留着同一个悬案：「控制台自己是怎么列会话的」。
本轮把它追完了：**它不列会话。**

- 总览页那一屏的行来自三处拼装（`frontend/app.mbt:106-131` 的 rebuild）：
  运行中 = `GET /api/local/instances`（`/proc/net/tcp` 的 loopback LISTEN + 签名探测）；
  已停止 = `GET /api/local/profiles`（扫 `<home>/profiles` 目录）；
  归档行 = `GET /api/local/console` 的 archive 记录。**三者没有一个是会话。**
- 日志页的来源白名单写死三条（`backend/logs/logs.mbt:8-9`）：`host` / `audit` / `instance:<实例 id>`，也没有会话来源。
- 全仓没有任何地方 list / read `sessions`（见第 5 条）。

所以 Phase 0b 第十节第 2 条那条风险（「会话被挪走后在 UI 里消失」）**不成立** ——
控制台里本来就没有会话可消失。会话历史的可见性只由 dsh 自己（`--resume`、会话列表插件）决定，
与这个控制台无关。

---

## 实测记录（可复现）

环境：`BASE=/tmp/p3-probe`，后端 `DSH_CONSOLE_BACKEND_PORT=5533`、
`DSH_HOME=$BASE/home-console`、`XDG_STATE_HOME=$BASE/state`、
`settings.json` 里把 `probe.maxCandidates` 调到 1000（否则探针端口被前 40 个低端口挤掉）。
三个假实例都用 `exec -a <…/@deepseek-ai/dsh/lib/bin.js>` 造出「cmdline 看起来是 dsh」的进程：
5534 无 `DSH_HOME` 且 fd 里只有 `.dsh-homes` 路径；5535 无 `DSH_HOME` 且 fd 里有 `/.dsh/` 路径；
5536 显式 `DSH_HOME=$BASE/home-dev`。两个 home 里各放一只同名的 `web`（控制台 home 那份 2 个包都没装，隔离 home 那份都装好了）。

关键读数（`GET /api/local/instances`）：

```
5534 dshHome=~/.dsh        source=environ 里没有 DSH_HOME，fd 表里也没有 …/.dsh/… 路径；按默认值 $HOME/.dsh
     profileHealth={"missingBundles":3,"hasPatch":true}   ← 主线的 web（我 fixture 里那份应该是 2）
5535 dshHome=/tmp/p3-probe/homes/.dsh source=取 fd 表里 …/.dsh/… 路径的前缀（PID 529942）
     profileHealth=null                                  ← 那个 home 里没有 profiles，如实给了 null
5536 dshHome=/tmp/p3-probe/home-dev   source=$DSH_HOME 环境变量（PID 529943 的 environ）
     profileHealth={"missingBundles":0,"hasPatch":true}   ← 它自己 home 的那一份，对 ✓
```

其余两条关键读数：

```
GET /api/local/logs?source=host  → path=~/.dsh/logs/retry-control/host.log   readOk=true
                                   （此时控制台 DSH_HOME=/tmp/p3-probe/home-console）
start-instance {profile:web, home:/tmp/p3-probe/home-dev}
                                 → conflict：profile web 已经在跑（PID 7734，端口 3080）
archive.json                     → [{"profile":"zz-same","archivedAt":"2026-10-16T09:28:49.686Z"}]
trash/                           → zz-same-1792142929840     （里面那份的备注：from home-console）
restore-from-trash               → restoredTo=/tmp/p3-probe/home-console/profiles/zz-same
```

收尾：探针进程全收（5533-5536 无监听），`/tmp/p3-probe` 已删；
`~/.dsh` 与 `~/.local/state/dsh-console` 顶层 `find -newermt '2026-10-16 17:25'` 为空；
5390 上那只（PID 368085）自始至终没被碰。没读 `.credentials.yaml`。

---

## Phase 3 的最小必做集

**真会张冠李戴的，四条，砍不掉：**

1. **实例 home 探测的 fd 回退**（`procjoin.mbt:67-75` + `:327-339`）——
   不认字面 `/.dsh/`、认不出时如实写「未知」而不是默认主线。
   它是上游：它错一次，`profileHealth`、实例日志目录、卡片 home、前端开发指令**四处一起错**。
2. **按名字认实例**（`instance.mbt:749-794`、`registry.mbt:142`、`registry.mbt:165-185`）——
   改成 `(home, name)`。不改就没法在主线 `web` 在跑的时候起 dev `web`（实测已被挡）。
3. **归档 / 回收站 / 排序表的键带上 home**（`archive.mbt`、`profile_fs.mbt:244-247`、`trash.mbt:211-214`、`order.mbt`）——
   尤其**回收站恢复必须回它来的那个 home**，否则删了隔离 profile 一点「恢复」就落到主线上。
4. **前端停止卡的 home 与「复制开发指令」**（`state.mbt:1948`、`app.mbt:494-537`）——
   连同 `profile_pairs`（`app.mbt:248-253`）把 home 一路带到 params，后端那个 `home` 参数已经现成。

**看着吓人、其实可以慢的：**

- **profile 跨 home 聚合**（`profiles.mbt:326`、`profile_fs.mbt:11`）：只要「隔离 home 里的 profile 目录也一起搬过去」
  这个取舍还没定，聚合的形态就定不下来；它现在的表现是**少读数（看不见）而不是错读数**，
  而且派生出来的 dev profile 目录本来就在控制台 home 里 —— 先别动，等 Phase 1/2 的取舍落地。
- **order.json**：串了只是顺序错位，不破坏数据。
- **audit.jsonl**：`outcome` 里已经有 dir/trashPath，考古追得回，补 `params.home` 可以缓。
- **完全不受影响的**：`settings.json`（控制台级）、进程表 / 端口选空闲（按 `/proc` 事实）、
  重启（已经用登记里的 home）、以及**会话历史**（控制台根本不读 `sessions`，计划第五节第 1 条担心的
  「会话挪走控制台看不见」在多 home 下不会发生）。

**一句判断**：Phase 3 的枪口不该对着「多 home 聚合」这种大改造，而是对着上面四条 ——
其中第 1 条（fd 回退）和第 2 条（按名字认实例）加起来不到 60 行，却决定了「卡片上的读数是不是别人的」。
---

## 更正（2026-10-16，林汐复核代码后补）

本文档第 3 节说「fd 反推**写死**字面 `/.dsh/`」，并把必做集 a 记成「fd 回退别认字面 `/.dsh/`」。
**这个归因是错的**，复核如下：

- 那个函数的真实位置是 `backend/processes/procjoin.mbt`（不是 `instances/`）。
- 它的注释原话：只认绝对路径；路径里没有 `/.dsh/` 这一段就给 `None`（**不猜**）。
  代码也确实如此实现：`index_of(target, "/.dsh/")` 为 `None` 时返回 `None`。
- 所以对 `~/.dsh-homes/<p>/sessions/...` 这种路径，它**如实返回 None**，没有猜。

**真正在猜的是它下面的第三级回退**：三级探测（environ → fd 前缀 → 默认值）里，
前两级都认不出时会落到「默认 `$HOME/.dsh`」，于是实例被安上了一个它其实不属于的 home。

### 因此必做集 a 的正确口径

- **不要去改 `dsh_home_prefix` 的匹配规则** ✗ —— 把它放宽成「任何像 home 的路径都认」等于
  **把它改成会猜**，正好与它注释里那句「不猜」相反，也会让它开始误认。
- 要改的是**第三级回退**：认不出时**如实写未知**，不要默认成 `$HOME/.dsh`。
- 顺带：卡片与抽屉上要能看出「这条的 home 是未知的」，而不是显示一个看起来正常的路径。

### 复核方法

读 `backend/processes/procjoin.mbt` 里 `dsh_home_prefix` 的注释与实现（各约 10 行），
并 `grep -rn sessions backend --include=*.mbt`（全后端只有 1 处命中，是那句注释）——两处都可复现。
---

## 复核补充（2026-10-16，林汐读代码后补）

### 已复核证实的两条

- **第 6 节（前端）**：`frontend/state.mbt:1949` 的提示原话就是「控制台当前使用的 DSH_HOME」——
  已停止卡的 home 与「复制开发指令」同源；`app.mbt:514-519` 的目录算式是 `<DSH_HOME>/profiles/<名>`。
  多 home 之后，停止卡拼出来的就是控制台自己的 home，等于把开发会话引回主线。必做集 d 要改的就是这里。
- **第 4 节（归档/回收站）** 与第 3 节 `running_for_profile` 只比名字：见各节实测，此处不重复。

### 新发现一处缺口：不在必做集里的第二条张冠李戴

`backend/logs/logs.mbt:59` 与 `:64` 两条**固定来源**：
```
host  → join_all([home, ".dsh", "logs", "retry-control", "host.log"])
audit → join_all([home, ".dsh", "linxi-guard-audit.jsonl"])
```
这里的 `home` 是**操作系统的 home**，不是控制台解析出来的 DSH_HOME ——
也就是说这两条来源**连控制台自己的 DSH_HOME 都不看**，永远指向 `$HOME/.dsh/...`。
（实例来源那一侧是对的：`logs.mbt:671-675` 优先用 `instance.dsh_home`，并如实写来源。）

**为什么没进必做集**：这两份是使用者机器上的**全局文件**（retry-control 的日志、linxi-guard 的审计），
指向 `$HOME/.dsh` 在多数情况下是**对的**，所以它不是 a~d 那种「读数张冠李戴」。
**但在两种情况下会出错**：
1. 控制台自己是被带着别的 `DSH_HOME` 启动的（那时它的 home 不是 `$HOME/.dsh`）；
2. B 层隔离之后，如果使用者期望「日志来源也跟着选中的 profile 走」，那这两条就永远指错了地方。

**建议**：不在本轮改，但**记在案**，并在日志页把这两条的「目录依据」也显出来（现在只有实例来源显示，
`view_logs.mbt:128-135`），让人一眼看出它指的是 `$HOME/.dsh` 而不是当前实例的 home。
这两件的口径要不要改，属于**范围问题**，留给使用者定。

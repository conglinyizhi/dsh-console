# 证据：一行自己的 home（停止卡的 DSH_HOME 那一格 + 「复制开发指令」）

> 对应设计文档 `../../design/phase3-impact-map.md` 收尾验收清单**第四条**（前端停止卡的 home 与开发指令）。
> 改动只在 `frontend/`，视觉（布局 / 字号 / 颜色 / 按钮 / 卡片摆位）一个像素都没动 —— 改的是文案口径与
> 「拿谁当这一行的 home」这条判据。

## 改了什么（口径）

| 位置 | 改前 | 改后 |
| --- | --- | --- |
| 停止卡的 home 那一格 | `dsh_home_of(model)`：profiles 读数的 dshHome，读不到就回落 **runtime 读数**（控制台自己的 home），再读不到才是「—」 | **只认这一行自己的**：profiles 读数就是在 <它>/profiles 下把这只列出来的那个 home；读数没给 home 那一格写「未知」 |
| 停止卡 home 的悬停原文 | 「控制台当前使用的 DSH_HOME（来源见「关于」页的 DSH_HOME 一行）」 | 「这只 profile 自己的 home：profiles 读数就是在 <home>/profiles 下把这只列出来的……这一格说的是这一只属于哪儿，不是控制台在用什么」 |
| 归档孤行的 home | 固定显示「—」（记录里的 home 只用来认「撤哪一条」） | 记录里带了 home 就显示**那一个**（那是这一只自己的 home）；记录里没写才是「—」，并写明「拿控制台自己的 home 来填就是给它安一个它不属于的 home」 |
| 「复制开发指令」用的 home | `dev_home_of`：row.home 不是空也不是「—」就用它，否则**回落到控制台自己的 home** | `own_home_of`：只认这一行自己的（`—` / `未知` / 空串一律当「给不出」），**一次都不回落** |
| 拼不出指令时的提示 | 「这一行的读数里没有 DSH_HOME」 | 「这一行的读数里给不出它自己的 DSH_HOME（home 那一格：「未知」）—— 指令里的 DSH_HOME 与 profile 目录都得按它自己的 home 拼，拿控制台自己的 home 顶上就会把开发会话引回主线，所以这一枪不发」 |
| profile 写动作的 params | 只有 `{profile}` | 这一行自己的 home 认得出来就带上 `{profile, home}`；认不出只发名字（**不拿控制台的 home 顶上**） |
| 实例 ↔ profile 的配对（`running_rows` / `in_use_by`） | 只按**名字**比 | 按 **(名字, home)** 比：同名不同 home 是两份，home 认不出就不认 |

## 怎么复现（fixture 全在 /tmp，不碰使用者的 ~/.dsh 与 ~/.local/state）

```bash
F=/tmp/p3e
# 两个隔离 home：控制台自己的 home-console、另一只 profile 的 home-dev
mkdir -p $F/home-console/profiles/console-a $F/home-dev/profiles/dev-b $F/state/dsh-console
printf 'plugins:\n  - id: dsh-base\n' > $F/home-console/profiles/console-a/cordis.patch.yml
printf 'plugins:\n  - id: dsh-base\n  - id: dsh-web-app\n' > $F/home-dev/profiles/dev-b/cordis.patch.yml
printf '{"probe":{"maxCandidates":1000},"instance":{"basePort":8400}}' > $F/state/dsh-console/settings.json

# 新前端那一只（静态根 = 仓库 frontend/dist，构建之后就是新的）
cd <repo>/dsh-console/backend
DSH_HOME=$F/home-console XDG_STATE_HOME=$F/state DSH_CONSOLE_BACKEND_PORT=5561 \
  ./_build/native/debug/build/dsh-console-backend.exe &

# 改前那一只（同一个后端二进制，静态根换成改前的产物；用于「改前 / 改后」对照）
DSH_HOME=$F/home-console XDG_STATE_HOME=$F/state-old DSH_CONSOLE_DIST=$F/dist-before \
  DSH_CONSOLE_BACKEND_PORT=5562 ./_build/native/debug/build/dsh-console-backend.exe &
```

探针：`node probe-home-own.mjs <baseUrl> <mode> [target] [outPrefix] [actionName]`
（`real` / `synth-profiles:<json>` / `strip-profiles-home` / target=`__archive__`；
它同时装了请求记录器，POST /api/local/action 的请求体一并抓下来 ——
「params 里带没带 home」从网络这一侧看，不从页面里的字符串看）。

## 场景四：属于**另一个 home** 的 profile

**桩说明**：真实后端现在只列**一个** home 的 profile（跨 home 聚合还没落地，见设计文档第四节），
所以「这一批 profile 属于 dev home」这一支用 `synth-profiles` 合成读数注入
（`/tmp/p3e/synth-dev-b.json`：`dshHome=/tmp/p3e/home-dev`，一只 dev-b）。控制台自己的 home 是
`/tmp/p3e/home-console` —— 两者不同，正是要分开的那两件事。

| 量什么 | 改前（dist-before） | 改后 |
| --- | --- | --- |
| 卡片 home 那一格 | `/tmp/p3e/home-dev`（悬停写着「控制台当前使用的 DSH_HOME」✗） | `/tmp/p3e/home-dev`（悬停写明这是**这一只自己的** home） |
| 剪贴板回读的指令 | `DSH_HOME：/tmp/p3e/home-dev` + `cd /tmp/p3e/home-dev/profiles/dev-b` + `DSH_HOME=/tmp/p3e/home-dev dsh --profile dev-b …` | 同上（这三个位置都要指向这一只自己的 home ✓） |
| 点「启动」发出去的 params | `{"profile":"dev-b"}` → 后端按**控制台自己的 home** 找：`not-found：profile 目录不存在：/tmp/p3e/home-console/profiles/dev-b` ✗✗ | `{"profile":"dev-b","home":"/tmp/p3e/home-dev"}` → 起在它自己的 home 下（日志落在 `/tmp/p3e/home-dev/logs/console-dev-b-8400.log` ✓；这一只 fixture 缺依赖，所以 spawn 失败，与 home 对不对无关） |

截图：`e2-new-drawer.png`（home 那一格 = `/tmp/p3e/home-dev`）、`e2-old-drawer.png`。
原始输出：`e2-new.json` / `e2-old.json`。

## 认不出时（home 不知道）：卡片上不显示控制台的 home，指令里也不给错的

两支都跑：**(a) 真读数**（不需要桩）—— 用 `exec -a <…/@deepseek-ai/dsh/lib/bin.js>` 起一只
**没有 DSH_HOME 环境变量、fd 表里也没有 `…/.dsh/…`** 的假 dsh（`--profile zz-ghost`，监听 8410）：

```
GET /api/local/instances → 8410 profile=zz-ghost dshHome=null
  source="未知：PID … 的 environ 里没有 DSH_HOME，fd 表里也没有 …/.dsh/… 这一段；认不出它的 home，不按默认值 $HOME/.dsh 顶替"
```

| | 改前（dist-before） | 改后 |
| --- | --- | --- |
| 卡片 home 那一格 | `未知` | `未知`（这一格本来就是如实写的 ✓） |
| 「复制开发指令」 | **写进了剪贴板**：`DSH_HOME：未知` / `cd 未知/profiles/zz-ghost` / `DSH_HOME=未知 dsh --profile zz-ghost …` ✗✗ | **没写**：剪贴板里还是探针点之前写的哨兵串，页面上给出上面那句「这一枪不发」✓ |

**(b) 读数没给 home**（`strip-profiles-home`：把 profiles 响应里的 `dshHome` / `dshHomeSource` 删掉）：

| | 改前 | 改后 |
| --- | --- | --- |
| 卡片 home 那一格 | **空串**（那一格是个空洞） | `未知`，悬停写明「不拿控制台自己的 home 顶上 —— 那只是把别处的 home 说成它的」 |
| 「复制开发指令」 | 没写（提示很短：「这一行的读数里没有 DSH_HOME」） | 没写，提示说清为什么这一枪不发 |

原始输出：`e1-new.json` / `e1-old.json` / `e3-new.json` / `e3-old.json`。

## 归档孤行（另一 home 的那条记录）

`archive.json` 里放两条：`{profile:"dev-b", home:"/tmp/p3e/home-dev"}`（新形状）与
`{profile:"zz-legacy"}`（改动之前的旧形状，没有 home）。点归档区那一行的「取消归档」：

```
（新形状那一条）params = {"profile":"dev-b","home":"/tmp/p3e/home-dev"}     ← 这一只自己的 home 跟着走了 ✓
（旧形状那一条）params = {"profile":"zz-legacy"}                            ← 记录里没有 home，就不编一个 ✓
```

归档区那一行是**紧凑行**（没有抽屉、也不显示 home 那一格），所以这里量的是它发出去的 params；
孤行的 home 值（`row.home`）同时是行 id（`archived:<名>@<home>`）与取消归档的判据。原始输出：`e4-new.json` / `e4-legacy.json`。

## 反向证明：控制台自己 home 里的普通停止卡，行为与改前一致

在 5390（使用者那只控制台：旧后端进程 + 仓库 `frontend/dist` 静态根）上，改前 / 改后各量一次
profile `headless` 的抽屉与「复制开发指令」：

- 卡片列表与顺序一致：`web :3080 | web-dev | headless | review-dev`
- home 那一格的**值**一致：`~/.dsh`（只有悬停口径改了，见上表）
- **剪贴板回读的指令逐字相同**（`DSH_HOME=~/.dsh`、`cd ~/.dsh/profiles/headless`）
- 控制台报错 0 条

原始输出：`e5-5390-before.json` / `e5-5390-after.json`。

## 验收

- `./build.sh` / `./check.sh`：0 error（保留一条与本次改动无关的既有警告：`view_overview.mbt` 的 unused_field）。
- `node ../../design/run-acceptance.mjs http://127.0.0.1:5390/`：见 `acceptance-5390.log`。
  注意这台 5390 上跑的是**旧后端进程**（a/b/c 的后端改动要重建重启才生效），本轮只改前端，
  所以这份验收量的是「新前端 + 旧后端」这一档。

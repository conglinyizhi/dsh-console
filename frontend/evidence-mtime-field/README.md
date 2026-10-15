# 卡片第六格「最近改动」+ 已停止组按最近改动降序 · 实测证据

契约：`../../design/write-api-contract.md` 的「追加契约（第五轮）」第一节。
前端改动：`model.mbt` / `state.mbt` / `view_overview.mbt` / `dom.mbt` / `icons.mbt` / `styles/app.scss`。

## 谁是桩、谁是真跑（先说清楚，别把桩当读数）

后端那一路（`GET /api/local/profiles` 加 `dirMtimeMs` / `dirMtimeSource`）在本轮实现到一半时落地了。
这一份里四跑，各管一件事：

| 跑法 | 数据来源 | 管的是哪件事 |
| --- | --- | --- |
| `real` | **真实**：5390 上真实的两个只读接口 | 全链路：真响应 → 页面第六格 → 已停止组顺序（第一节） |
| `synth` | **桩**：合成 fixture 替掉 `profiles`，并把 `instances` 清空 | 排序的三条规则：降序 / `null` 沉底 / 同档字典序（第二节） |
| `strip` | **桩**：把 `dirMtimeMs` / `dirMtimeSource` 两键从响应里删掉 | 「后端还没有这个字段」那一支（第三节） |
| `synth-unresolved` | **桩**：合成 fixture 同时替掉 `profiles` 与 `instances` | 运行卡解析不出 profile 时那一格写「—」（第四节） |

为什么排序要用桩跑：已停止组会排除「正被某个实例用着」的 profile，而**机器上谁在跑是活的**
（并行那一路在抓取期间起过 `web-dev:8400`、`review-dev:8401`，已停止组一度只剩一张卡）。
清空 `instances` 才能让排序这件事稳定复现。

**诚实边界**：

- 「第六格真能出值」这条是拿**真响应**验的（第一节），不靠桩。
- 「字段整个不在响应里」「`null` 沉底 / 同档字典序」「运行卡解析不出 profile」这三条，
  真实环境给不出来（字段已落地；目录 mtime 没法让它读不到；真机上每只实例的 profile 都解析得出），
  所以用桩造条件。**桩造的是条件，不是读数。**
- 两个 `synth` 的 fixture 是**完全合成的**（profile 名字带 `fx-` 前缀），不碰磁盘上的任何 profile；
  里面用到的毫秒值借的是真实目录 mtime 的数，好让格式化结果能跟 `date -d @<epoch>` 对上。
- 本轮**没有**新建 / 删除使用者的任何 profile。
- 抓取期间实例集合是活的，每一份 JSON 都只是**那一刻**的快照。

## 怎么跑

```bash
cd dsh-console/frontend
node evidence-mtime-field/probe-mtime.mjs http://127.0.0.1:5390/ real  evidence-mtime-field/real
node evidence-mtime-field/probe-mtime.mjs http://127.0.0.1:5390/ \
  synth:evidence-mtime-field/fixture-synth-profiles.json evidence-mtime-field/synth
node evidence-mtime-field/probe-mtime.mjs http://127.0.0.1:5390/ strip evidence-mtime-field/strip-missing-field
node evidence-mtime-field/probe-mtime.mjs http://127.0.0.1:5390/ \
  synth:evidence-mtime-field/fixture-synth-unresolved.json evidence-mtime-field/synth-unresolved

# 把接口/桩给的 dirMtimeMs 与页面上卡片的先后顺序对照
node evidence-mtime-field/check-order.mjs evidence-mtime-field/real.json \
  evidence-mtime-field/real-profiles-response.json
node evidence-mtime-field/check-order.mjs evidence-mtime-field/synth.json
node evidence-mtime-field/check-order.mjs evidence-mtime-field/strip-missing-field.json
node evidence-mtime-field/check-order.mjs evidence-mtime-field/synth-unresolved.json
```

`probe-mtime.mjs` 的注入点装在 `window.fetch` 上（页面脚本之前就装上），所以不存在
「先渲染真读数、再被换成桩」的中间态。

## 一、真跑：第六格的实际文本与悬停

`real.json` / `real-top.png` / `real-stopped-first.png` 与 `real-profiles-response.json` 是**同一刻**抓的。

| 卡 | 状态 | 字段数 | 第六格文本 | 悬停里的 ISO | 对不对得上接口 |
| --- | --- | --- | --- | --- | --- |
| `web :3080` | running | 6 | `10-15 13:24` | 2026-10-15T05:24:40.054Z | ✓ `web` 的 `dirMtimeMs` |
| `web-dev :8400` | running | 6 | `10-15 18:50` | 2026-10-15T10:50:52.694Z | ✓ `web-dev` 的 `dirMtimeMs` |
| `review-dev :8401` | running | 6 | `10-15 16:16` | 2026-10-15T08:16:50.618Z | ✓ `review-dev` 的 `dirMtimeMs` |
| `headless` | stopped | 6 | `10-15 16:13` | 2026-10-15T08:13:38.396Z | ✓ |

`grid.cardsWithEmptyCell = []` —— **四张卡、每张六格，没有空格子**（这就是使用者说的「六个格子只填了五个」那一格）。
运行中那三张卡也不是「—」：它们的 profile 名解析得出来，用的是那只 profile 目录的 mtime。
控制台报错 0 条。

那一刻三只在跑、一只已停止（并行那一路起的实例），所以这一跑只剩一张已停止卡：
**已停止组的排序要看第二节那一跑**（那里的合成 fixture 把实例清空了）。

悬停全文（以 `web-dev` 为例）：

```
这只 profile 目录的最近改动时刻（mtime 2026-10-15T10:50:52.694Z，卡上按浏览器本地时间显示）。
口径是「最近改动」不是「创建时间」：多数文件系统上可靠的创建时间拿不到
（ctime 会在 chmod / 改名时变，birth time 不通用）；刚派生出来的 profile 一定是最新的。
来源：~/.dsh/profiles/web-dev 的 mtime
```

接口那一侧的原始字段（`real-profiles-response.json`）：

```
headless        1792052018396   "~/.dsh/profiles/headless 的 mtime"
review-dev      1792052210618   "~/.dsh/profiles/review-dev 的 mtime"
web             1792041880054   "~/.dsh/profiles/web 的 mtime"
web-dev         1792061452694   "~/.dsh/profiles/web-dev 的 mtime"
```

`stat` 对照（证明卡上的显示不是编的）：

```
headless    1792052018396   10-15 16:13:38 CST   ← 卡上 10-15 16:13
review-dev  1792052210618   10-15 16:16:50 CST   ← 卡上 10-15 16:16
web         1792041880054   10-15 13:24:40 CST   ← 卡上 10-15 13:24
web-dev     1792061452694   10-15 18:50:52 CST   ← 卡上 10-15 18:50
```

## 二、排序：合成 fixture 上的三件事

`fixture-synth-profiles.json` 是五只合成 profile，故意做成：

| profile | `dirMtimeMs` | 第六格 |
| --- | --- | --- |
| `fx-beta-newest` | 1792061452694 | 10-15 18:50 |
| `fx-gamma-mid` | 1792052210618 | 10-15 16:16 |
| `fx-alpha-old` | 1792041880054 | 10-15 13:24 |
| `fx-delta-broken` | `null`（读不到：EACCES） | 读不到 |
| `fx-zeta-null` | `null`（读不到：目录刚被移走） | 读不到 |

页面上的先后顺序（`synth.json` 的 `stoppedOrder`）：

```
["fx-beta-newest","fx-gamma-mid","fx-alpha-old","fx-delta-broken","fx-zeta-null"]
```

三条都成立：

1. **严格降序**：18:50 > 16:16 > 13:24。
2. **`null` 沉底**：两只读不到的在最后。
3. **同档按名字字典序**：`fx-delta-broken` 在 `fx-zeta-null` 前面。
   这一条是**故意挑的**：按 MoonBit 的 shortlex（先比长度）会翻过来
   （`fx-zeta-null` 12 字符 < `fx-delta-broken` 15 字符），所以它专门钉住第七节那个坑。

五张卡六格全满（`cardsWithEmptyCell = []`）。图：`synth-top.png`（列表顶部，18:50 那张在最前）、
`synth-stopped-first.png`、`synth-stopped-last.png`（最后那张是 `fx-zeta-null`，第六格「读不到」）。

## 三、`strip`：字段整个不在响应里时写什么

把 `dirMtimeMs` / `dirMtimeSource` 两键删掉再让页面读（`strip-missing-field.json`）：

| 卡 | 状态 | 字段数 | 第六格文本 | 悬停 |
| --- | --- | --- | --- | --- |
| `web :3080` | running | 6 | 读不到 | 读不到这只 profile 目录的最近改动：profiles 读数里没有 dirMtimeMs 字段（后端这一版还没给） |
| `web-dev :8400` | running | 6 | 读不到 | 同上 |
| `review-dev :8401` | running | 6 | 读不到 | 同上 |
| `headless` | stopped | 6 | 读不到 | 同上 |

**缺字段不崩、不显示 0、不假装有值**；这一支的话由前端补，与「后端读了但读不到」分开说。
这一份也是六格全满（`cardsWithEmptyCell = []`）。图：`strip-missing-field-top.png`。

## 四、`synth-unresolved`：运行卡解析不出 profile 时写「—」

契约那一句是「运行中的卡也补同一格（profile 解析得出就用它的 mtime；解析不出写「—」并说明原因）」。
真机上每只实例的 profile 都解析得出来，所以用一个合成 fixture 造出两种「解析不出」
（`fixture-synth-unresolved.json`：一只 profile 正常，两只实例的 profile 对不上）：

| 卡 | 状态 | 字段数 | 第六格文本 | 悬停 |
| --- | --- | --- | --- | --- |
| `dsh :9001` | running | 6 | **—** | 实例读数里没解析出 profile 名，没有 profile 目录可读最近改动（桩 fixture：cmdline 里没有 --profile，进程也没有 cwd 线索） |
| `fx-not-listed :9002` | running | 6 | **—** | 这只实例解析出的 profile 名是「fx-not-listed」，但 profiles 读数里没有这一只，没有目录可读最近改动（桩 fixture：cmdline 里写着 --profile fx-not-listed） |
| `fx-listed` | stopped | 6 | 10-15 18:50 | （用它的 mtime） |

两种缺法的原因分开说：一种是**没解析出 profile 名**，一种是**解析出来了但读数里没这一只**。
这一格写「—」而不是「读不到」，因为此时**根本没有可读的对象**；
「读了但读不到」才写「读不到」。三张卡依然六格全满（`cardsWithEmptyCell = []`），控制台报错 0 条。
## 五、判定输出：数据源与页面顺序逐条对照

`check-order.mjs` 用 JS 的 `sort` 独立算一遍期望顺序（降序 → null 沉底 → 名字字典序），
再跟页面上卡片的先后顺序对齐。三跑全过：

```
$ node check-order.mjs real.json real-profiles-response.json
依据: 快照 real-profiles-response.json（readAt=2026-10-15T11:19:43.020Z）
  已停止组的 dirMtimeMs: headless 1792052018396
期望顺序: ["headless"]
页面顺序: ["headless"]
严格降序（有值的部分）: true          判定: 页面顺序 == 期望顺序  ✓   exit=0
（也可以把第二个参数换成 http://127.0.0.1:5390/api/local/profiles 现拉一次）

$ node check-order.mjs synth.json
期望顺序: ["fx-beta-newest","fx-gamma-mid","fx-alpha-old","fx-delta-broken","fx-zeta-null"]
页面顺序: 同上
严格降序（有值的部分）: true          判定: 页面顺序 == 期望顺序  ✓   exit=0

$ node check-order.mjs strip-missing-field.json
（这一跑响应里没有 dirMtimeMs 字段：全员按「读不到」办）
期望顺序: ["headless","review-dev"]     页面顺序: ["headless","review-dev"]   ✓   exit=0
```

## 六、构建与验收

- `./check.sh`：`moon check --target js` 与 `./build.sh` 都是 **0 error**；尾部见 `build-check.log`。
  唯一一条 warning 是既有的依赖弃用提示（`hackwaly/moonback@0.8.1 is deprecated`），
  与本次改动无关（改动前的 `evidence-button-shape/build-check.log` 里同一条）。
- `moon check --target js -d`（把警告当错误）全量 43 个任务 **exit=0**，我们自己这侧一条警告都没有。
- `node design/run-acceptance.mjs http://127.0.0.1:5390/`：**判定 28 项，通过 28，失败 0；另有信息 2 条**，exit=0。
  全文见 `acceptance-5390.log`。
  这一条跑了两遍才干净：并行那一路在抓取期间起了 `web-dev:8400`，
  日志页的来源下拉在页面加载那一刻还没有它，于是「来源下拉含全部在跑实例」判失败。
  那是**并行起实例的竞态**，不是这次改动带来的（`run-acceptance.mjs` 自己写着这个前提）；
  实例集合稳定之后重跑即全过。

## 七、这一轮踩到的坑（值得记）

兜底的名字升序一开始写成 `if a < b { -1 } else if a > b { 1 } else { 0 }`，
三张卡排出来是 `web-dev / headless / review-dev`（**按字符串长度**），不是字典序 ——
MoonBit 的 `Compare` 对 String 是 shortlex（先比长度、长度相同再逐字符比）。
改用 `String::lexical_compare` 之后顺序才与接口对齐。
**是 DOM 实测抓出来的，不是看代码看出来的**：`dbg-order.mjs` 是当时定位用的最小探针，留着当复现步骤。

另一个坑在探针自己身上：一开始桩表和探针输出的文件名撞了（`stub-values.json` 既是输入又是输出），
重跑一次就把 fixture 覆盖成了上一次的输出。现在 fixture 一律叫 `fixture-*.json`，与输出前缀分开。

第三个坑在截图：内容在**内部滚动容器**里，`document.documentElement.scrollHeight` 恒等于视口高。
拿「页面坐标（`rect + scrollY`）+ `captureBeyondViewport`」去拍屏外的卡，拍出来是一张 966 字节的**空图** ——
文件在、能打开、看着像拍到了，其实什么都没有。现在改成 `scrollIntoView({block:'center'})` 之后
**按视口坐标**拍（`synth-stopped-last.png` 就是这么重拍的）。

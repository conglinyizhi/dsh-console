# 前端改写验收清单（Vue → rabbita + precss + md2）

这份清单是"功能面与现有三页对齐"的**对账依据**。重写完成后逐条验，不许用
"看着差不多"替代。左列是现有 Vue 版的行为，右列留空给重写版打勾与贴证据。

现有体量：`src/` 约 2900 行（18 个组件 + 3 个页面 + 数据层 + 探测）。

## 一、全局骨架

- [ ] 左侧导航三项：实例总览 / 日志 / 关于；**状态切页**（没有 URL 路由，刷新回到总览）
- [ ] 顶栏：标题「DSH 控制台」+ 设置按钮（当前无行为）
- [ ] 数据源徽标（SourceBadge）：两态——`真实数据` / `演示数据 · 真实读取失败`（后者必须带**具体原因**，不许静默空）
- [ ] 页脚：`本机运行，仅限回环访问`
- [ ] 无横向溢出（`documentElement.scrollWidth === clientWidth`）

## 二、实例总览

### 页头
- [ ] 标题「实例总览」+ 真实数据徽标 + `动作仍是演示` + 「＋ 新建实例」按钮（当前无行为）

### 分组一：当前运行的实例 (N)
- [ ] 空态文案：说明扫了多少回环监听端口、多少命中签名
- [ ] 卡片字段（**拿不到的写「未知」，不许编**）：实例名 / 类型标签 / 状态点 + 状态文案 / 运行时长（读不到写「运行时长未知」，不写 0）/ DSH 版本·来源 / Profile / 访问地址 / DSH_HOME / 插件数量（读不到写「—」）
- [ ] 按钮组：`[打开 Web UI] [停止] [重启] [⋯]`，`⋯` 收低频与危险动作
- [ ] 类型标签有**悬停说明**（写清这个标签依据什么，避免被误读成运行状态）

### 分组二：已停止的实例 (N)
- [ ] 卡片字段同上，另加 **idleNote**（如 `cordis.patch.yml 4 行 · 无 pnpm-lock.yaml`）
- [ ] 类型标签：`本地 profile`，当前档案写 `本地 profile · 默认`（**不是「当前」**）+ 悬停说明写清是 `DSH_PROFILE` 指向它
- [ ] 按钮组：`[启动 ｜ ▾] [重启]`（两段式：左半动作、右半开菜单）
- [ ] 空态文案

### 归档区
- [ ] 可折叠；归档行含取消归档
- [ ] 归档/取消归档的演示动作

### 交互（都要在重写版里活着）
- [ ] 启动等待态：`status=starting`，**整行按钮禁用**（含两段式的两半），菜单打不开
- [ ] 派生开发副本（fork）：新实例 `plugin-dev-N`，端口取当前最大 +1
- [ ] 删除确认对话框：确认/取消
- [ ] 重命名对话框：预填当前名并全选；空名/纯空格禁用确定；Enter 确认、Esc 取消；关闭后**焦点回到触发元素**
- [ ] 行内字段悬停背景（不是整行变色）

### 右栏
- [ ] 工作流入口两行（「从当前实例派生开发副本」/「将插件交回主线实例」）+ 各自说明
- [ ] 关于实例说明块

## 三、日志

- [ ] 来源下拉，顺序：**每个运行中的实例一条** → 分隔线 → `宿主日志` → `审计日志`
- [ ] 默认选中**第一个运行中的实例**（有实例时）；使用者手动选过之后不再替他改
- [ ] 元信息行（一行到底）：`尾部 N 行（请求 N） · 大小 · <真实文件路径> · 目录依据：<homeSource> · 读于 <时刻> · 只读`
- [ ] 日志区：等宽字体、**长行横向滚动不折断**、打开即滚到底、切来源后也滚到底
- [ ] 级别只在真读得出时上色（error 红 / warn 橙 / 其余次级灰）
- [ ] 刷新按钮：更新元信息时刻与内容
- [ ] 读取失败：显式回退文案 + 具体原因

## 四、关于

- [ ] 简介两句（第二句固定为「只读本机 ~/.dsh；页面上的动作均为演示。」）
- [ ] 版本面板：`dsh 版本` / `控制台版本`（为 null 时显示「未知」）/ `平台`
- [ ] **没有「node 版本」这一行**（已按使用者要求废掉）
- [ ] 页脚：`读于 <时刻> · 来源 GET /api/local/runtime`

## 五、必须保住的几何与行为不变量

这些是前几轮逐像素调出来的，重写版**不许回归**：

- [ ] 卡片头**两行**：第一行实例名；第二行 类型标签 + 状态点 + 状态文案
- [ ] 状态点占**独立槽位**（不随标签宽度漂移），两卡之间的状态点 x 坐标一致
- [ ] 类型标签列宽固定（最宽的胶囊 + 边距），标签与状态点间距 ≥10px
- [ ] **按钮组右缘贴卡片内容盒右缘**（两态一致，实测 Δ0.0）
- [ ] 两段式按钮：左半圆角 `6 0 0 6`、右半 `0 6 6 0`、中间 1px 分隔线、悬停只加深自己那一半
- [ ] 下拉菜单挂在**按钮组容器**上：`top = 按钮组底 + 6px`、`right: 0`
- [ ] 菜单打开后焦点落第一项；Esc 关闭且焦点回到**触发元素**
- [ ] 点菜单外关闭
- [ ] 不使用过渡动画（使用者明确要求过）
- [ ] 文案精简：一个信息只出现一处

## 六、依赖 md2 的方式（待决策）

`conglinyizhi/md2` **没有发布到 mooncakes**（`moon search "conglinyizhi/md2"` → No modules found），
本地源码在 `~/disk/ai_workspace/rabbita-material`（模块名 `conglinyizhi/md2@0.1.0`，
`preferred_target = "js"`，`supported_targets = "js+native"`）。

已知可行的本地依赖范式是 **`moon.work` 工作区文件**（见 `~/disk/ai_workspace/rabbit-css-integration`）：

```
members = [
  ".",
  "../moonbit-css-helper",
]
```

moon.mod 里照常写模块名与版本，工作区负责解析到本地目录。

**代价**：这样会把构建绑到一个**仓库之外**的绝对位置——换机器或重新 clone 就构建不起来。
三条出路（待使用者定，不要自行选择）：

1. 把 md2 发布到 mooncakes（最干净）
2. 把 md2 以子模块 / vendor 形式收进本仓库（体积与同步成本）
3. 维持外部相对路径（仅本机可用）

## 七、后端供静态产物的兼容性（已解决）

后端认静态根的判据原先写死为 `index.html` + `assets/`（那是 Vite 的布局）。
rabbita 这类把产物**平铺在根上**（`index.html` + `console.js` + `console.css`）的布局会判不出来，
上溯失败后静态服务返回 503。

已放宽为：**有 `index.html`，且同层有 `assets/` 目录或 `.js` / `.css` 文件**。
「`index.html` 之外还得有东西」这条保留 —— 只有 `index.html` 的目录仍判失败，
免得把仓库根那个开发入口当成产物。

实测（`DSH_CONSOLE_DIST` 指向造好的四种目录）：

| 布局 | 静态 `/` | 接口 |
| --- | --- | --- |
| Vite（`index.html` + `assets/`） | 200 | 200 |
| 平铺（`index.html` + `.js`/`.css`） | 200 | 200 |
| 只有 `index.html` | 503（如实报错） | 200 |
| 真实 `dist` + 环境变量 | 200 | 200 |
| 无环境变量（自动上溯） | 200 | 200 |

## 八、客户端数据与副作用（已探明，别自己造）

从 rabbita 0.15.7 源码里读出来的现成能力：

| 需要 | 现成的 API |
| --- | --- |
| 发请求 + 类型化解码 | `rabbita/http`：`Request::expect_json[T : FromJson]`、`RequestWithBody::with_json[T : ToJson]`、`expect_text` / `expect_bytes` / `expect_empty` |
| 副作用（取数、定时、导航） | `rabbita/cmd`：`@cmd.perform(msg, f)`、`@cmd.effect(f)`、`@cmd.attempt(...)`、`@cmd.batch([...])`、`Op::on_settle` / `on_resume` |
| JSON 层 | **`moonbitlang/core/json`**，含 `from_json.mbt` 与 derive 测试 → **支持 `derive(FromJson)`** |

所以数据层的写法是：**定义类型 + derive JSON + 用 cmd 发请求**，不要手写解析器。

## 八点五、服务层对新栈产物的演练（已通过）

在**新前端还不存在**的时候，先把后端指向一份**真实的 rabbita/md2 产物**
（`~/disk/ai_workspace/rabbita-material/out`，`DSH_CONSOLE_DIST` 显式指定）跑了一遍：

| 请求 | 实测 |
| --- | --- |
| `/` | 200 `text/html` 8345B（`<title>md2 · 组件陈列</title>`） |
| `/buttons.html` | 200 `text/html` 16040B（多页站点也伺候得了） |
| `/md2.css` | 200 `text/css` 193666B |
| `/demo-app.js` | 200 `text/javascript` 532180B |
| `/mdi/fonts/materialdesignicons-webfont.woff2` | 200 **`font/woff2`** 403216B |
| `/mdi/css/materialdesignicons.min.css` | 200 `text/css` 346626B |
| `/api/local/runtime` | 200 `application/json`（同端口共存，闸门有效） |

**结论**：静态服务层、MIME 表（含字体）、多页站点、与 API 同端口共存——四件都验过了，
新栈产物落地时不需要再改服务层。MIME 表覆盖 `.woff2` / `.woff` / `.ttf` / `.otf` /
`.svg` / `.wasm` 等，图标字体不会静默失效。

## 八点九、收尾时会踩的一个雷：控制台版本的来源（**已解决**）

> **已解决（提交 3ce3b32）**：后端改为优先读仓库根的 `VERSION` 文件（已建，内容 `0.1.0`），
> 前端 `package.json` 那条退为过渡期兜底。实测 `consoleVersionSource` 已变成
> 「仓库根的 VERSION 文件」。下面保留当时的分析，作为这条修改的依据。

### 当时的问题描述

后端的 `consoleVersion` 是**运行时**解析的：从二进制位置上溯，找**同时含 `package.json`
与 `src/` 的目录**，再读那份 `package.json` 的 version。实测现在拿到
`"0.1.0"`，来源写着「相对二进制位置上溯找到含 package.json + src/ 的目录」——**读的正是
Vue 前端的 package.json**。

**收尾把 `src/`、`package.json` 删掉之后，这个解析必然失败** → `consoleVersion: null` →
关于页那一行变成「未知」。这不是猜测：判据、当前实测值、失败路径三者都确认过了。

**收尾必须同时做掉这一件**，三条出路（选一条，别留半拉）：

1. 仓库根放一份 `VERSION`，后端读它（单一来源，最稳）
2. 后端直接报自己的模块版本（后端与前端现在是一起发布的一个产品）
3. 前端（MoonBit 侧）声明控制台版本，后端读 `frontend/moon.mod`

同时要把后端那段**判据**改掉（不能继续依赖 `package.json + src/`），并改掉
`consoleVersionSource` 的文案，别让它说谎。

## 八点九五、收尾的删除清单

仓库根现状（`dsh-console/`）：

| 保留 | 删除 |
| --- | --- |
| `backend/`（原生后端） | `src/`（Vue 源码） |
| `frontend/`（rabbita 前端） | `index.html`、`vite.config.ts`、`tsconfig.json` |
| `design/`（设计与验证文档） | `package.json`、`pnpm-lock.yaml` |
| `.git`、`.gitignore`（按需更新） | `node_modules/`、`dist/` |

删完的验收：构建验证链不再需要 Node；后端自动上溯落到新产物；
`.gitignore` 不再需要 `node_modules` 那几行。

## 九、收尾顺序（必须按这个顺序，否则会静默跑旧前端）

后端自动上溯的规则是「每一层先看 `<层>/dist`，再看这一层本身」。而 `dsh-console/dist`
是 **Vue 的产物**，重写后它仍然存在的话，**上溯会继续命中它，页面看着正常、跑的是旧前端**——
典型静默失败。所以顺序必须是：

1. 新前端产物跑通并验收
2. **删掉 `dist/`**（以及 `src/`、`vite.config.ts`、`package.json` 里的前端依赖）
3. 再验证一次自动上溯落到新产物上

在那之前自测请用 `DSH_CONSOLE_DIST` 显式指向新产物，别依赖上溯。

## 八点八、前端产物契约（后端供得出去的前提）

`frontend/build.sh` 的三步链（precss 编样式 → 编 js 客户端 → 拷产物）产出：

```
frontend/dist/
├── index.html          # 带 dsh-skin.css（我们的皮肤层）
├── md2-raw.html        # 同一内容但不挂皮肤层 —— 样式方向的 A/B 对照外壳
└── assets/
    ├── app.js          # rabbita 客户端（js 目标）
    ├── app.css         # md2 三层（vendor → theme → md2），precss 编出
    ├── dsh-skin.css    # 把 md2 主题变量覆写成 dsh-console 的设计 token
    ├── mdi/{css,fonts} # 图标字体（已 vendor 进仓库）
    └── licenses/       # md2 / vuetify / MDI 的许可文件
```

- 资源用**绝对路径** `/assets/...` 引用，正好对应后端以 `dist/` 为站点根
- 这个布局 = `index.html` + `assets/`，**后端原有的判据就满足**（放宽那条是防御性的）

## 九点五、样式移植的规模与特性（实测，别低估）

**实测**：现有样式 **941 行散在 18 个组件的 `<style scoped>` 块里**，全局 `app.css` 只有
**29 行**（纯 token）。也就是说"样式"这部分的工作量**跟逻辑代码几乎一样多**，
不是"顺手搬一下"。

按文件分布（前几名）：`LogsView` 152、`InstanceRow` 120、`SideInfoPanel` 96、
`SideNav` 86、`AboutView` 73、`InstanceActions` 70、`OverviewView` 60。

**好消息**：用到的 CSS 特性极朴素——`grid-template` 4 处，`@keyframes` 1 处，
**没有** `color-mix` / `:has()` / `@container` / `backdrop-filter`。所以移植是
**近乎逐行可搬**的（顶多加一层 SCSS 嵌套），precss 不需要支持什么冷门语法。

**唯一要保留的动效**：`dot-pulse`（`InstanceRow.vue` 里 `.sub-line.starting .dot`，
900ms 呼吸 + 琥珀色光晕）——它是**启动等待态的状态指示**，不是装饰，别在重写时丢掉。
其余地方仍然遵守「不用过渡动画」。

## 九点八、独立验证器

`design/verify-frontend.mjs`：不依赖任何自证，直接用无头浏览器量页面。

```bash
node design/verify-frontend.mjs <baseUrl> [截图前缀]
```

输出 JSON：标题、`scrollWidth`/`clientWidth` 与横向溢出、`innerText` 前 220 字、
三个关键标记（`真实数据` / `读取失败` / `实例总览`）、元素计数（按钮/卡片/下拉/图标）、
**控制台 error 与 warning**，并可出图。

已用**已知正常的 Vue 版**（后端服务 `dist/`）验通：无横向溢出、无控制台问题、
标记齐全。重写完成后先用它量一遍，再逐条对上面的一到五节。

## 九点九、看对比图前必须知道的前提

切片这一版的皮肤层（`frontend/styles/dsh-skin.scss`）做了两件事：

1. **换变量**：md2 的主题变量是 RGB 三元组，逐条换成 dsh 的调色板（`--bg` / `--panel` /
   `--accent` / `--violet` / `--ok` / `--warn` / `--danger` …）
2. **改形状**：Material 规范里与现有设计冲突的几处逐条对齐——卡片从"抬起来"改成
   "平铺 + 发丝描边"、按钮 36px 大写带阴影改成 30px 无阴影 6px 圆角、字号整体小一档紧一档

选择器用 `html.dsh-skin`（特异性 0,1,1）压过 md2 的 `:root` / `.v-theme--dark`，
不用 `!important`、不改 md2 产物；**两份外壳的差别就是这一个 class**。

**但它不含我们特有的版式**。现有设计里那些逐像素调过的东西——两行卡头、13px 状态点槽位、
字段行的悬停背景、三段式/两段式按钮组、菜单锚点——**都不在这一层，也不在切片里**
（切片只做关于页，而关于页恰好没有这些结构）。

所以看对比图时别得出超出证据的结论：这一版能回答的是"**md2 的观感 + 我们的调色板与控件形状**
对不对味"；回答不了"实例卡那套版式能不能保住"——那要等全量重写。

## 九点九五、切片的独立验证结果（已渲染，真数据）

用 `design/verify-frontend.mjs` 对后端服务出来的 `frontend/dist` 实测（不经过 worker 自己的脚本）：

```json
{ "title": "dsh-console · 关于（rabbita + md2）",
  "overflowX": false,
  "textHead": "关于 … dsh 版本 0.2.0-rc.2 / 控制台版本 0.1.0 / 平台 linux x64 (7.2.9-arch1-1)
               读于 21:07:08 · 来源 GET /api/local/runtime
               运行中实例（GET /api/local/instances）dsh …",
  "counts": { "cards": 9, "icons": 9, "buttons": 4 },
  "consoleIssueCount": 1 }
```

**结论**：rabbita(js) + md2 + precss + 原生后端这条链**端到端通了**——真数据经 rabbita 渲染、
暗色皮肤生效、MDI 图标出字形。切片还超出简报范围做了实例卡的版式。

### 待办（两个小问题，都已定位）

1. **`/favicon.ico` 404** —— 唯一那条控制台错误。`web/index.html` 里没有 favicon 链接
   （Vue 版当年是内联 data URI 解决的，照做即可）。
2. **`app.js` 1.15 MB（未压缩）** —— Vue 版是 112 KB。本地回环服务下可接受，
   但如果在意首屏解析时间，可以加一道压缩（后端目前不做 gzip）。
   另外 `/assets/mdi/fonts/materialdesignicons-webfont.woff` 是 404（只 vendor 了 woff2）——
   浏览器优先取 woff2，不影响出字形。

## 九点九九、已知成本与可选优化（实测，别忘）

切片的首屏传输量 **2.02 MiB**（后端不发 gzip），构成：

| 项 | 大小 | 说明 |
| --- | --- | --- |
| `app.js` | 1178817 B | rabbita 客户端，未压缩未分割（gzip 后 136 KB） |
| MDI CSS + woff2 字体 | **346626 + 403216 B** | **切片只用到 8 个图标名**（`mdi-dots-horizontal` / `home-outline` / `label-outline` / `layers-outline` / `link-variant` / `open-in-new` / `puzzle-outline` / `refresh`） |
| app.css | 197222 B | md2 三层（vendor→theme→md2） |
| dsh-skin.css | 2537 B | 覆写层 |

**最明显的一条**：750 KB 的图标字体只为 8 个字形服务（平均每个近 94 KB）。
md2 自己已经在 select 上走通「内联 SVG」的路子，照做可以整块摘掉字体。

另外两条：`app.js` 未做分割；后端不做 gzip（回环下影响有限，但数字要如实记）。

这些都不阻塞功能对齐，属于**验收通过后的优化项**。

## 九点九七、验收探针的已知调整点（实测发现）

1. **新前端的类名与 Vue 不同名，探针需要一份新的选择器映射。**
   已观察到机器生成的 `app.scss` 给部分类名加了 `dsh-` 前缀：
   `.dsh-case` / `.dsh-case-head` / `.dsh-ident` / `.dsh-name` / `.dsh-kind`，
   另一部分沿用原名：`.tile` / `.title-line` / `.btn` / `.dot-slot` / `.log-box` / `.nav-item`。
   `probe-invariants.mjs` 的 `vue` profile 因此**不能直接复用**——交付后先 dump 一次 DOM
   拿到真实类名，补一份 `new` profile 再量。
   （`probe-animation.mjs` 与 `verify-frontend.mjs` 是选择器无关的，可直接用。）

2. **worker 不能派子 agent**（实测报错 `depth 2 exceeds maxDepth 1`）。
   往后的简报里不要写"可以派子 agent 分工"，那是空头承诺——它只能自己干或先把活拆小。

3. 它把解释几何不变量的**注释也一起搬进了生成的 SCSS**（例如"点槽恒为 13px（7px 点 +
   两边各 3px 光环）"）。这是好做法：搬的是**为什么**，不只是**是什么**。

## 九点九九五、新前端的首轮独立验收结果（20 项：10 通过 / 10 失败）

用 `node design/run-acceptance.mjs <baseUrl>` 对 `frontend/dist` 实测。**逐项区分了"探针的问题"与"真偏差"**：

**已通过（10）**：无横向溢出（两处）、真数据标记、无读取失败标记、状态点跨卡对齐
（`[400,400,400,400]`）、按钮组右缘贴内容右缘（`[0,0,0,0]`）、两段式无缝（gap 0，
主半 `6px`、右半 `0px 6px 6px 0px`）、菜单落焦第一项、来源下拉 4 项、等待态禁用按钮 3 个。

**真偏差（3 项，要改）**：
- **日志框没有被限高**。实测 `.dsh-log-box` 的 `rect.h = 4096.1`、
  `scrollHeight = clientHeight = 4094`（Vue 基线是 `clientHeight 735`）——
  它随内容长长，**页面整体变高而不是框内滚动**，于是「打开即滚到底」「可内部滚动」这两条
  **无从成立**。横向滚动是有的（`scrollWidth 1162 > clientWidth 1044` ✓）。
  日志内容本身是对的：200 行、6 个错误级着色、三段行结构（时间/级别/正文）、元信息含目录依据。

- **菜单挂在卡片上，不挂在按钮组上**。实测 `position: absolute`、`offsetParent` 是卡片
  （`v-card … dsh-case`）、parent 是 `.dsh-case-head`；于是 `deltaTop = 127.5`（基线 6）、
  `deltaRight = +16`（基线 0，菜单右缘越过按钮组右缘 16px）。
  清单第五节明确要求「菜单挂在按钮组容器上：`top = 按钮组底 + 6px`、`right: 0`」——这条没做到。

**我的探针/判据的问题（8 项，已修）**：
- 日志页 5 项：`probe-logs.mjs` 写死了 Vue 的类名（`.log-box` / `.log-line` / `.lv-error` / `.meta`），
  新前端用的是 `dsh-log-*`。要像 `probe-invariants` 一样支持外部选择器映射。
- 动效 2 项：新前端静止时有 12 个 `v-progress-linear__indeterminate` 在跑，但**实测 `height: 0`**
  （不占空间、看不见）——是 md2 进度条的固有行为，**不是视觉缺陷**，只是后台空转。
  判据已改为只看**可见**动效（宽高 > 0）。
- 控制台 1 项：`/favicon.ico` 404（切片遗留，对方本该修）。

## 十、接口契约（不变）

`GET /api/local/runtime | profiles | logs?source=&tail= | processes | instances`
- 同源相对路径 `/api/local/...`
- 响应形状见 [backend/README.md](../backend/README.md)（与已退役的 Node 版逐字段一致）
- 失败时前端必须有显式回退与原因，不许静默空白

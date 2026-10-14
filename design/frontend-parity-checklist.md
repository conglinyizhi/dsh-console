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

## 十、接口契约（不变）

`GET /api/local/runtime | profiles | logs?source=&tail= | processes | instances`
- 同源相对路径 `/api/local/...`
- 响应形状见 [backend/README.md](../backend/README.md)（与已退役的 Node 版逐字段一致）
- 失败时前端必须有显式回退与原因，不许静默空白

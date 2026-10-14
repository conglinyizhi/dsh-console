# dsh-console 前端（rabbita + md2 + precss）

三页全量：左侧导航三项（实例总览 / 日志 / 关于）+ 状态切页（没有 URL 路由，刷新回总览）。
数据全部来自后端五个只读接口，读不到就照实写「未知」/「—」，不编。

Vue 版（`../src/`）是这次重写的功能参照与视觉对照，验收通过后按清单退役。
对比图与换栈决策在 `../../dsh-console-design/`。

## 30 秒上手

```bash
./check.sh            # 类型检查 + 构建（单退出码）
./check.sh --fast     # 只做类型检查，几秒
./build.sh            # 只构建：样式 → js → 拷 dist
```

跑起来看（后端起在 5390，同时供静态与接口，同源）。**自测请显式给 DSH_CONSOLE_DIST**：
仓库里还有一份旧的 Vue 产物 `../dist/`，不给环境变量时后端上溯会命中它，页面看着正常、跑的是旧前端。

```bash
DSH_CONSOLE_DIST="$PWD/dsh-console/frontend/dist" \
  dsh-console/backend/_build/native/debug/build/dsh-console-backend.exe
# http://127.0.0.1:5390/               rabbita + md2 + dsh 皮肤
# http://127.0.0.1:5390/md2-raw.html   同一份产物，只有 md2 原生暗色（对比用）
```

`MOON_HOME` 默认指向 `$PWD/.sandbox/moonhome`：本机 `~/.moon` 挂在只读文件系统上，
`moon` 往里写不了 registry 缓存。要覆盖就 `MOON_HOME=... ./build.sh`。

## 验收怎么跑

```bash
# 独立验证器：横向溢出 / 控制台报错 / 真数据到位（不依赖任何自证）
node ../design/verify-frontend.mjs http://127.0.0.1:5391

# 逐条对账：清单第五节的 12 条几何不变量 + 菜单 / 对话框 / 日志页 / 派生等行为
node ../design/measure-parity.mjs http://127.0.0.1:5391
```

`measure-parity.mjs` 的量法是 DOM 实测（bounding box、computed style、activeElement、
滚动位置），不是「看着一样」。悬停态用 `CSS.forcePseudoState` 定住再量。

## 目标平台为什么是 js

`moon.mod` 里 `preferred_target = "js"`，`supported_targets = "js+native"`（native 只给
`cmd/build-styles` 这个构建期步骤用）。理由三条：

1. **这一侧的运行期就是浏览器**。页面要自己 `fetch` 五个只读接口、自己渲染，
   native 目标给不了这件事。
2. **native 那一侧已经被后端占了**。`../backend/`（MoonBit + moonback）已经是同端口
   服务静态与 JSON 的进程，前端再出一个 native 服务就是两个进程抢同一件事。
3. **md2 自己的 `preferred_target` 也是 js**，组件库的验证基线是在 js 上采的。

## 依赖：md2 是怎么进来的

**`conglinyizhi/md2` 没有发布到 mooncakes。** 这一条是查过的，不是猜的：

```
$ moon search md2
No modules found.
$ moon add conglinyizhi/md2
Error: Module `conglinyizhi/md2` not found in registry
```

所以走**本地路径依赖 / moon.work 工作区**：

- `moon.mod` 里按版本号声明 `"conglinyizhi/md2@0.1.0"`（`import` 只接受带版本号的写法，
  不写版本会直接报 `moon.mod only supports versioned registry dependencies`）；
- `moon.work` 里用成员路径把它指到磁盘上那份检出；
- moon 解析模块图时，命中的成员路径顶掉 registry 查询。

这份路径指向 `../../../../disk/ai_workspace/rabbita-material`，跟着它一起演进 ——
改 md2 立刻反映到这里，好处是联调不用发包；代价是本工程不自包含。

**要脱离那个目录**：把 md2 源码拷到 `vendor/md2/`，改 `moon.work` 的成员路径，
再改 `cmd/build-styles/main.mbt` 里的 `md2_root`。两处，别处不用动。

### 另一个坑：本模块根包的别名要显式给

模块名 `conglinyizhi/dsh-console-frontend` 带连字符，`cmd/app` 里引自己的根包时，
默认别名会从最后一段推导、推出来的标识符不合法。必须写成：

```
import {
  "conglinyizhi/dsh-console-frontend" @frontend,
}
```

## 目录

```
.
├── moon.mod / moon.work / moon.pkg   模块与工作区定义
├── model.mbt                          五个只读接口的数据模型与解析（外壳 → 字段，不做业务推导）
├── state.mbt                          Model / Msg / 行模型 / 演示数据 / 工作流文案
├── app.mbt                            update 循环：拉取、行操作、对话框、日志、端口探测
├── clock.mbt                          浏览器本地时刻（页脚「读于 <时刻>」）
├── dom.mbt                            浏览器副作用 FFI：焦点、滚动、短时刻、端口探测
├── view_shell.mbt                     外壳：左导航 / 顶栏 / 内容区
├── view_overview.mbt                  实例总览：卡片、按钮组与菜单、归档区、右栏、两个对话框
├── view_logs.mbt                      日志页：原生 select 来源、元信息行、日志区
├── view_about.mbt                     关于页：简介 + 版本表
├── view_parts.mbt                     共用小件：图标、徽标、分组头、空态、字段行、对话框外壳
├── cmd/app/                           js 可执行：把 app() 挂到 #dsh-console-root
├── cmd/build-styles/                  native 可执行：precss 编 SCSS
├── styles/
│   ├── app.scss                       全部版式（Vue 版 941 行 scoped 样式机械迁移而来）
│   └── dsh-skin.scss                  设计 token 覆写层 + md2 组件形状（唯一的品牌层）
├── web/                               index.html（挂皮肤）/ md2-raw.html（不挂）
├── vendor/mdi/                        MDI 字体（第三方资产，随产物分发）
└── dist/                              构建产物，后端直接服务它
```

## md2 用在哪、没用在哪

用：`card`（卡片与面板外壳）、`btn`（**仅实例卡上那四个动作按钮**）、`icon`（全部图标）、
`chip`（数据源徽标）。这四个的形状与 DOM 在皮肤层里逐条对齐过，圆角/高度/字号都是量出来的。

没用，以及为什么：

- `navigation_drawer` / `app_bar`：两者把 `position: fixed`、`z-index`、side 偏移写成**内联样式**
  （见 md2 的 v_navigation_drawer.mbt / v_app_bar.mbt），而本外壳是文档流里的 flex 两列。
  内联样式没法从样式表压过，除非上 `!important`；换栈决策里明确不这么做。
- `menu`：md2 的菜单锚在 activator 的包裹层上，位置由 `anchor_styles` 出内联样式；
  我们的不变量是「锚在按钮组容器上、top = 按钮组底 + 6px、right: 0」，两者对不上。
- `dialog`：md2 的对话框内容是内联 `translate(-50%,-50%)`，遮罩不给点击回调；
  我们要的是「点遮罩关闭」，而 rabbita 的 `div.on_click` 收不到事件对象，判断不了 target。
  改成遮罩与卡片同级（遮罩 z-index 60、居中层 61），点遮罩天然成立。
- `list` / `list_item` / `expansion_panel` / `empty_state` / `text_field`：这几处的版式是
  逐像素调过的（36px 导航项、3 列网格的工作流入口、28px 归档行按钮、32px 重命名输入框），
  md2 的 Material 档位要改成我们的值，就得把每条覆写搬进皮肤层 —— 那是换栈决策里
  标为「最贵的长期代价」的那件事，收益为零。

调用范式的出处是 `../design/rabbita-md2-cheatsheet.md`（从能编译的源码里抽的）。

## 样式为什么是两个文件

`app.css` = md2 三层（vendor → theme → md2）+ 我们的全部版式，中、右两列共用。
`dsh-skin.css` 是设计 token 覆写 + md2 组件形状，挂在 `html.dsh-skin` 上（特异性 0,1,1，
压过 md2 的 `:root` / `.v-theme--dark`，不用 `!important`）。

这么分是为了**让对比图里的差异可归因**：两列 rabbita 页面是同一个 `app.js`、同一份
`app.css`、同一套 DOM，唯一差别是 `<html>` 上有没有 `dsh-skin` 这个 class。
看到的任何差异都只能来自主题覆写，不掺别的变量（最直观的一条：不挂皮肤时按钮文案会被
Material 的 `text-transform` 变成「打开 WEB UI」）。

`app.scss` 是机械迁移来的：脚本按类名映射表把 Vue 版散在 18 个组件的 `<style scoped>`
改名前缀、把设计 token 换成 md2 主题变量。迁移脚本没进版本库（一次性），但映射表与
自检（选择器里不许留没改名的类）在提交说明里有记录；要重跑，重新写一遍映射表即可。

## 动效

唯一的动效是启动等待态状态点的 `dot-pulse`（900ms 呼吸 + 琥珀光晕）。
md2 组件自带的 transition（按钮 280ms、卡片 box-shadow）在皮肤层里逐条关掉了，
卡片那条高度为 0 的 loading 进度条也不显示 —— 量「还有没有动效」时结果是 0。

## 这一版没做的

- 卡片上的动作都是**演示**：点了不发请求，本页不接写接口、不拉起真实进程。
- 没有水合、没有 SSR。md2 的既有约定是「纯 CSS 能做的用 CSS，做不了的由独立
  behaviors 脚本补」；这一版的控件都不需要 behaviors。
- `dist/assets/app.js` 1.44 MB（未压缩，gzip 约 150 KB）。后端不发 `Content-Encoding: gzip`，
  回环访问下可接受；构建链刻意不依赖 Node，所以没有加一道压缩步骤。
- 图标仍是 MDI 字体（css 347 KB + woff2 403 KB 只为十几个字形）。换内联 SVG 是独立可摘的一条。

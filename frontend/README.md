# dsh-console 前端（rabbita + precss）

三页全量：左侧导航三项（实例总览 / 日志 / 关于）+ 状态切页（没有 URL 路由，刷新回总览）。
数据全部来自后端五个只读接口，读不到就照实写「未知」/「—」，不编。

**依赖只有 rabbita 与 precss**：没有组件库、没有图标字体、没有仓库外的模块成员。
组件 DOM 与类名照 Vue 版（已按清单退役，见 `git log`）逐条对齐，样式与图标都是我们自己的。

Vue 版留下的对照物：`../design/vue-baseline-*.json`（几何基线）与
`../../dsh-console-design/`（三列对比图与换栈决策）。

## 30 秒上手

```bash
./check.sh            # 类型检查 + 构建（单退出码）
./check.sh --fast     # 只做类型检查，几秒
./build.sh            # 只构建：样式 → js → 拷 dist
```

跑起来看（后端起在 5390，同时供静态与接口，同源）。**自测请显式给 DSH_CONSOLE_DIST**：
它不接受「猜」，指错了会直接算失败并写清原因，所以别赌后端上溯能命中。

```bash
DSH_CONSOLE_DIST="$PWD/dsh-console/frontend/dist" \
  dsh-console/backend/_build/native/debug/build/dsh-console-backend.exe
# http://127.0.0.1:5390/
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
3. **构建期的样式编译**（`cmd/build-styles`）要读文件、写产物，只有 native 给得了；
   它由 `build.sh` 用 `--target native` 单独跑，不进浏览器产物。

## 依赖：只剩 rabbita 与 precss

`moon.mod` 的 import 表就是全部依赖，三个都从 registry 解析：

| 依赖 | 谁在用 |
| --- | --- |
| `moonbit-community/rabbita` | 全部视图与 update 循环 |
| `conglinyizhi/precss` | 只在 `cmd/build-styles`（构建期把 SCSS 编成 CSS） |
| `moonbitlang/async` | 只在 `cmd/build-styles`：`async fn main` 语法与 `@fs` 读写都来自它 |

**没有 `moon.work`，也没有外部模块成员**：上一版把组件库以本地路径写进 `moon.work`
（它没发布到 mooncakes），代价是本工程不自包含。组件库摘掉之后这份工作区文件一起删了，
仓库自包含；`icons.mbt` 需要的图标路径也是取一次、固化成常量的，不留 Node 依赖。

想删 `moonbitlang/async` 之前先看这条：浏览器那一侧确实不用它（`app.mbt` 里的
`async fn` 是 MoonBit 的语言语法），但 `cmd/build-styles` 要，删掉会直接报
「its containing module is not imported by … cannot be imported by its package」。

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
├── moon.mod / moon.pkg                模块定义（依赖只有 rabbita / precss / async）
├── icons.mbt                          26 个图标的内联 SVG：路径常量 + icon() 助手
├── model.mbt                          五个只读接口的数据模型与解析（外壳 → 字段，不做业务推导）
├── state.mbt                          Model / Msg / 行模型 / 演示数据 / 工作流文案
├── app.mbt                            update 循环：拉取、行操作、对话框、日志、端口探测
├── clock.mbt                          浏览器本地时刻（页脚「读于 <时刻>」）
├── dom.mbt                            浏览器副作用 FFI：焦点、滚动、短时刻、端口探测
├── view_shell.mbt                     外壳：左导航 / 顶栏 / 内容区
├── view_overview.mbt                  实例总览：卡片、按钮组与菜单、归档区、右栏、两个对话框
├── view_logs.mbt                      日志页：原生 select 来源、元信息行、日志区
├── view_about.mbt                     关于页：简介 + 版本表
├── view_parts.mbt                     共用小件：徽标、分组头、空态、字段行、对话框外壳
├── cmd/app/                           js 可执行：把 app() 挂到 #dsh-console-root
├── cmd/build-styles/                  native 可执行：precss 编 SCSS
├── styles/app.scss                    全部样式：reset + 设计 token + 版式
├── web/index.html                     页面外壳
├── vendor/licenses/mdi-NOTICE.md      图标路径数据的第三方声明（不再分发字体文件）
└── dist/                              构建产物，后端直接服务它
```

## 组件与图标都是自建的

卡片、按钮、徽标、对话框的 DOM 与类名照 Vue 版逐条对齐，形状全部出自 `styles/app.scss`
（那份表就是从 Vue 的组件样式块机械迁移来的）。没有组件库要对抗，也就不再有
「把 Material 的尺寸档掰回我们的值」那层覆写。

图标是**内联 SVG**，不是图标字体：

- 26 条路径固化成常量放在 `icons.mbt`，助手 `icon(name, size)` 产出
  `<svg class="dsh-icon" viewBox="0 0 24 24" width=… height=…><path d="…"/></svg>`；
- 尺寸在调用点上逐处给（12 / 13 / 14 / 16 / 17 / 20 / 26），与 Vue 版 `AppIcon` 的
  `:size` 一一对应。**别随手改**：侧栏图标大一号就会把「从当前实例派生开发副本」
  那行挤成两行（实测过）；
- 路径数据取自 `@mdi/js` 7.4.47 之后**固化**，Node 依赖没有进仓库；
  声明在 `vendor/licenses/mdi-NOTICE.md`；
- 所以 `dist/` 里没有任何字体或图标资源，只有 `app.css`、`app.js`、`index.html`
  和一份许可声明。

**不套现成组件，以及为什么**（这些是上一版逐个对比过的结论，仍然成立）：

- 抽屉 / 顶栏类组件把 `position: fixed`、`z-index`、side 偏移写成**内联样式**，
  而本外壳是文档流里的 flex 两列；内联样式没法从样式表压过，除非上 `!important`。
- 菜单锚在 activator 的包裹层上，位置由内联样式给；我们的不变量是
  「锚在按钮组容器上、top = 按钮组底 + 6px、right: 0」。
- 对话框内容是内联 `translate(-50%,-50%)`，遮罩不给点击回调；我们要「点遮罩关闭」，
  而 rabbita 的 `div.on_click` 收不到事件对象、判断不了 target。
  改成遮罩与卡片同级（遮罩 z-index 60、居中层 61），点遮罩天然成立。

## 样式：一份文件 + 自带的 reset

`dist/assets/app.css` 由 `styles/app.scss` 一份编出（`cmd/build-styles`，precss）。
文件内部按 **reset → 设计 token → 版式** 排；颜色、圆角、间距一律用 SCSS 变量。

**reset 必须自己带。** 这一层以前由组件库的 vendor 层提供，摘库的时候最容易漏：
清单里那些几何量（卡片 padding、字段行高 28px、侧栏 190px…）都是建立在
「所有元素 margin/padding 归零」这个前提上的，少一条整页就位移。
所以 app.scss 开头有一节显式的 reset，表单控件的浏览器默认皮也在那里摘干净
（原生 `select` 的箭头显式关掉：我们没画替代品，不关的话系统箭头会冒出来）。

**precss 不做颜色函数求值。** `rgba($ok, 0.1)` 会原样吐成 `rgba(#4ec27a, 0.1)` ——
浏览器认不了，整条声明被丢掉，背景/描边会静默回落成上一条规则的值（踩过：徽标的
`.real` 底色没了）。需要透明度时用 RGB 三元组变量：`rgba($ok-rgb, 0.1)`，
那几个变量在 app.scss 的 token 一节。

`app.scss` 是机械迁移来的：脚本按类名映射表把 Vue 版散在 18 个组件的 `<style scoped>`
改名前缀。迁移脚本没进版本库（一次性），映射表与自检在提交说明里有记录。

## 动效

唯一的动效是启动等待态状态点的 `dot-pulse`（900ms 呼吸 + 琥珀光晕）。
组件库自带的 transition（按钮背景/阴影、卡片 box-shadow、那条高度为 0 的 loading
进度条）随库一起去掉了，量「还有没有动效」时结果是 0。

## 这一版没做的

- 卡片上的动作都是**演示**：点了不发请求，本页不接写接口、不拉起真实进程。
- 没有水合、没有 SSR。控件的交互都走 rabbita 的事件，不需要额外的 behaviors 脚本。
- `dist/assets/app.js` 1.35 MB（未压缩，gzip 约 150 KB）。后端不发 `Content-Encoding: gzip`，
  回环访问下可接受；构建链刻意不依赖 Node，所以没有加一道压缩步骤。
- 两个空态图标（运行中空态、已停止空态）本机有实例时走不到，只在源码层面核对过路径常量。

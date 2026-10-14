# dsh-console 前端（rabbita + md2 + precss）

这一批是**垂直切片**，不是全量重写：只做「关于页」+ 一张运行中实例卡，
目的是把技术栈跑通、并且拿到一张能支撑决策的视觉对比图。
现有的 Vue 版（`../src/`）原样保留，作为功能参照与视觉对照，验收通过再删。

对比图与决策建议在 `../../dsh-console-design/`。

## 30 秒上手

```bash
./check.sh            # 类型检查 + 构建（单退出码）
./check.sh --fast     # 只做类型检查，几秒
./build.sh            # 只构建：样式 → js → 拷 dist
```

跑起来看（后端起在 5390，同时供静态与接口，同源）：

```bash
DSH_CONSOLE_DIST="$PWD/dsh-console/frontend/dist" \
  dsh-console/backend/_build/native/debug/build/dsh-console-backend.exe
# http://127.0.0.1:5390/            rabbita + md2 + dsh 皮肤
# http://127.0.0.1:5390/md2-raw.html  同一份产物，只有 md2 原生暗色（对比用）
```

`MOON_HOME` 默认指向 `$PWD/.sandbox/moonhome`：本机 `~/.moon` 挂在只读文件系统上，
`moon` 往里写不了 registry 缓存。要覆盖就 `MOON_HOME=... ./build.sh`。

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

同样的路径在 `cmd/build-styles/main.mbt` 里又写了一遍（编 md2 的三层 SCSS 要用）。
**改一处要改两处**，这是已知的重复。

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
├── model.mbt                          只读接口的数据模型与解析（外壳 → 字段，不做业务推导）
├── clock.mbt                          浏览器本地时刻（页脚「读于 <时刻>」）
├── app.mbt                            Msg / Model / update / app()
├── views.mbt                          关于页 + 实例卡的视图
├── cmd/app/                           js 可执行：把 app() 挂到 #dsh-console-root
├── cmd/build-styles/                  native 可执行：precss 编 SCSS
├── styles/
│   ├── app.scss                       布局层（颜色一律取 md2 主题变量）
│   └── dsh-skin.scss                  设计 token 覆写层（唯一的品牌层）
├── web/                               index.html（挂皮肤）/ md2-raw.html（不挂）
├── vendor/mdi/                        MDI 字体（第三方资产，随产物分发）
└── dist/                              构建产物，后端直接服务它
```

## 样式为什么是两个文件

`app.css` = md2 三层（vendor → theme → md2）+ 我们的布局层，中、右两列共用。
`dsh-skin.css` 只有 2.5 KB，是设计 token 覆写。

这么分是为了**让对比图里的差异可归因**：两列 rabbita 页面是同一个 `app.js`、同一份
`app.css`、同一套 DOM，唯一差别是 `<html>` 上有没有 `dsh-skin` 这个 class。
看到的任何差异都只能来自主题覆写，不掺别的变量。

## 这一批没做的

- 只有「关于页」和一张卡片。实例总览、日志页、侧栏、交互（菜单、对话框）都没迁。
- 卡片上的四个按钮是**演示**：点了不发请求。这一批不接写接口。
- 没有水合、没有 SSR。md2 的既有约定是「纯 CSS 能做的用 CSS，做不了的由独立
  behaviors 脚本补」；这一批的页面没有需要 behaviors 的控件，所以没引入那一步。

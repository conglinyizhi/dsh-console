# 开合过渡与骨架屏一行封顶（第十一轮）

使用者原话：「加一点合理的过度效果：① 面板展开和折叠 ② 骨架屏每个分组最多占用一行空间」。

这一轮只动前端（`dsh-console/frontend/`）：

| 文件 | 改了什么 |
| --- | --- |
| `styles/app.scss` | 抽屉与遮罩的进出 keyframes（220ms / ease-out，出入同一条）、`prefers-reduced-motion` 那条 media query；`.dsh-skeleton-row`（与卡片栅格共用同一套列轨 + 一行封顶） |
| `state.mbt` | `drawer_anim_ms = 220`、Model 的 `drawer_closing`、Msg `DrawerClosed(String)` |
| `dom.mbt` | `js_reduced_motion()` / `prefers_reduced_motion()`（`matchMedia('(prefers-reduced-motion: reduce)')`） |
| `app.mbt` | `DrawerClose` 进收的状态并把焦点立刻送回卡片、`DrawerClosed` 撤节点；`OrderDone` 成功那条正文压成「顺序已保存」 |
| `view_overview.mbt` | `detail_drawer` 多一个 `closing` 参数（`data-state`），总览页把正在收的那一只也画出来 |
| `view_parts.mbt` | `card_loading` 把 6 块占位块装进 `.dsh-skeleton-row` |

## 环境（一条硬线：不碰使用者那一份）

- 5390 上那只控制台**没 kill、没重启**（后端是使用者刚重建的那份）；前端产物由 `./check.sh` 重建，
  后端静态服务按请求读盘，刷新页面即是新构建（实测 `/assets/app.css` 34632 字节 = dist 里的那份）。
- 顺序回执那一趟跑在**隔离实例** 5533 上：`DSH_HOME=/tmp/dsh-console-fixture/home`、
  `XDG_STATE_HOME=/tmp/dsh-console-fixture/state`、`DSH_CONSOLE_DIST=…/frontend/dist`。
  使用者那份 `~/.dsh` 与 `~/.local/state/dsh-console` 一个字节都没动（这一轮也没跑任何改使用者状态的探针）。
- 探针都只读页面；唯一的写动作在 5533 那一趟（拖一次排序，写的是 /tmp 下 fixture 的 order.json）。

## 一、详情抽屉的开合

每 40ms 采一格（`probe-drawer-motion.mjs`，`transform` / `x` / `opacity` / 动画名 / `data-state` / 焦点）：

**开（点卡片，1280 宽，抽屉终态 x=760、宽 520）**

| t | x | opacity | 动画名 | 焦点 |
| --- | --- | --- | --- | --- |
| 29ms | 1216.1 | 0.123 | `dsh-drawer-in` | `dsh-drawer-close` |
| 68ms | 1099.7 | 0.347 | `dsh-drawer-in` | `dsh-drawer-close` |
| 108ms | 996.5 | 0.545 | `dsh-drawer-in` | `dsh-drawer-close` |
| 148ms | 868.9 | 0.791 | `dsh-drawer-in` | `dsh-drawer-close` |
| 188ms | 806.0 | 0.911 | `dsh-drawer-in` | `dsh-drawer-close` |
| 228ms | 760.2 | 1 | `dsh-drawer-in` | `dsh-drawer-close` |

**关（Esc）**

| t | 抽屉 | x | opacity | 动画名 | 焦点 |
| --- | --- | --- | --- | --- | --- |
| 11ms | 在（`state=closing`） | 823.9 | 0.877 | `dsh-drawer-out` | `dsh-card-port-3080` |
| 44ms | 在 | 940.3 | 0.653 | `dsh-drawer-out` | `dsh-card-port-3080` |
| 84ms | 在 | 1043.5 | 0.455 | `dsh-drawer-out` | `dsh-card-port-3080` |
| 124ms | 在 | 1171.1 | 0.209 | `dsh-drawer-out` | `dsh-card-port-3080` |
| 164ms | 在 | 1234.1 | 0.088 | `dsh-drawer-out` | `dsh-card-port-3080` |
| 204ms | 在 | 1272.6 | 0.014 | `dsh-drawer-out` | `dsh-card-port-3080` |
| 244ms | **没了** | — | — | — | `dsh-card-port-3080` |

- 两段都是**滑动 + 淡入淡出**，不是瞬移：位置逐格推进、透明度跟着走。
- 出入同一条 220ms / ease-out（样式 `animation` 与 `state.mbt` 的 `drawer_anim_ms`）。
- 节点在 244ms 那一格已经撤掉 —— 远早于验收探针的 700ms 上限。
- **关的那一段里焦点已经在卡片上**（11ms 那一格就是这个状态）：焦点不等动画，`DrawerClose` 那一拍
  就调了 `focus_after_render(card_id)`；收的这 220ms 里抽屉 `pointer-events: none`，不再吃点击。

**过程图**（播放速率 0.4，只影响这两张图；每张都记了拍前 / 拍后的 x，两个数都在 760–1280 之间）：

| 图 | 拍前 | 拍后 | 说明 |
| --- | --- | --- | --- |
| `drawer-motion-open-mid.png` | x=968.2 opacity=0.6 | x=883.8 opacity=0.762 | 滑入在途（左缘还在屏幕右半边） |
| `drawer-motion-close-mid.png` | x=929.2 opacity=0.675 | x=1033.7 opacity=0.474 | 滑出在途（卡片上已有焦点环） |

**`prefers-reduced-motion: reduce`**（CDP `Emulation.setEmulatedMedia` 模拟，页面里 `matchMedia(...).matches` 实测 `true`）

| 那一趟 | 采样结果 |
| --- | --- |
| 开 | 第一格就是 `x=760 / opacity=1 / animationName=none`，往后 12 格完全不变 —— **没有位移、没有淡入** |
| 关 | 第一格（t=10ms）`drawer=null` —— 节点**当场撤掉**，不做任何过渡 |
| 开合本身 | 开得开（`还开着: true`）、关得掉（`drawerPresent: false`）、焦点照旧回卡片 |
| 复位 | 关掉模拟之后 `matchMedia(...).matches` 回到 `false`（不是被粘住的状态） |

## 二、行为一条都没退（`probe-drawer-behavior.mjs`）

| 那一枪 | 1280 宽 | 360 宽 |
| --- | --- | --- |
| 点卡片开 | 1 个抽屉节点、`state=open`、x=760 宽=520、**13 颗按钮全可达**、焦点进关闭键 | x=0 宽=360（**占满整幅**）、13 颗全可达、焦点进关闭键 |
| 关的中途（50ms） | 抽屉还在（`state=closing`，x=940.5）、`pointer-events: none`、焦点已在卡片 | 同左（x=125、宽 360） |
| Esc 之后 | 节点 0、焦点在卡片 | 节点 0、焦点在卡片 |
| 点外部之后 | 节点 0、焦点在卡片 | （窄屏抽屉占满整幅，没有「外部」可点，见下） |
| 关闭键之后 | 节点 0、焦点在卡片 | 节点 0、焦点在卡片 |
| 收的中途又点卡片 | 重新打开，DOM 里**只有 1 个**抽屉节点（id 不撞） | 同左 |

- 窄屏那一档「点外部」本来就不成立：抽屉宽 = 视口宽，遮罩全被盖住，点哪儿都在抽屉里。
  验收探针（`probe-drawer.mjs`）在 1280 上量「点外部关」，量到的是 0 个节点、焦点回卡片。
- 收的那 220ms 里 `allReachable` 会是 `false`：`pointer-events: none` 之后 `elementFromPoint`
  命中的是底下的页面 —— 那正是要的（半透明的面板不该再吃点击），不是在途时按钮坏了。

## 三、骨架屏每个分组最多一行（`probe-skeleton-rows.mjs`）

口径照上一轮：Fetch 拦截把 `/api/local/*` 压后 2 秒，加载中那一刻量一次、放行后再量一次。

| 视口 | 这档列数 | 露在外面的占位块 | 骨架区 `max-height` / 内容高 | 骨架区实测高 | 骨架块宽×高 | 放行后卡片高度 | 列轨（加载 / 放行） | 列起点（占位块 vs 卡片） |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1920 | 6 | 6 / 6 | `70px` / 70 | **70** | 271×70 | 70 | 6 / 6 | [212,495,778,1061,1344,1627] vs 同列起点 |
| 1280 | 4 | 4 / 6 | `70px` / 152 | **70** | 252.5×70 | 70 | 4 / 4 | [212,476.5,741,1005.5] vs [212,476.5,741] |
| 768 | 2 | 2 / 6 | `70px` / 234 | **70** | 261×70 | 70 | 2 / 2 | [212,485] vs [212,485] |
| 360 | 1 | 1 / 6 | `60px` / 420 | **60** | 126×60 | 66（带第二行） | 1 / 1 | [212] vs [212] |

- 「内容高」是 `.dsh-skeleton-row` 的 `scrollHeight`（6 块全排开有多高），「骨架区实测高」是它的
  `getBoundingClientRect().h` —— 两者差出来的部分就是被 `overflow: hidden` 裁掉的第 2 行往后。
  4 列那一档 152 = 70 + 12 + 70；2 列 234 = 70×3 + 12×2；1 列 420 = 60×6 + 12×5。
- **露在外面的块数 = 这一档的列数**（6/4/2/1），也就是「最多一行」。
- 1920 / 1280 / 768 三档：骨架区高 **= 真卡片那一行**（都是 70，逐像素相同）。
- 360 那一档：骨架区高 60，而带第二行的真卡片是 66。差的这 6px 不是这一轮来的：占位块的
  第二行高 8（真条目 16），窄屏那一档图标位收成 34、两行文字仍占 40 —— 第八轮定的
  「占位块永远不会比真条目高」就是这个结果。本轮只裁行数，不动块本身的形状。
- **列轨与宽度不变**：`grid-template-columns` 的列数与每列尺寸、每列起点逐项相同
  （`skeleton-rows.json` 的 `compare` 一段），主区宽 1730 / 1090 / 578 / 170 加载前后一致，
  横向溢出 false。
- 加载态截图：`skeleton-rows-loading-{1920,1280,768,360}.png`；放行后：`skeleton-rows-loaded-*.png`。

## 四、顺序保存那条回执（`probe-order-toast.mjs`，隔离实例 5533）

| 项 | 实测 |
| --- | --- |
| toast 正文 | `顺序已保存` |
| 悬停（`title`） | `顺序表已写入 /tmp/dsh-console-fixture/state/dsh-console/order.json（4 条）` |
| order.json 拖后 | `["port:3080","profile:plain","profile:bare","profile:web-dev"]`（拖前 `[…web-dev, plain, bare]`） |
| 失败提示条 | null（这一趟成功了，没有失败文案） |
| 截图 | `order-toast.png`（悬停是 DOM 的 `title`，原生 tooltip 不进 CDP 截图，所以另有 `order-toast-hover.png` 与 JSON 里的 `title` 字段为证） |

**新增 / 改动的可见文案就这一条**：`顺序表已写入 <完整路径>（N 条）` → `顺序已保存`
（路径与条数收进悬停，不丢）。其余全是标记与状态，不是文案。

## 五、验收与构建

- `./check.sh`（moon check + 完整构建）退出码 0：见 `build-check.log`。
- `node ../../design/run-acceptance.mjs http://127.0.0.1:5390/`：**判定 30 项通过 30、失败 0，
  另有信息 6 条**（日志见 `acceptance-5390.log`）。其中与这一轮直接相关的：抽屉能开、
  抽屉里按钮都可达、开抽屉焦点进关闭键、Esc 能关抽屉、关后焦点回那张卡、
  点击前无可见动效（0 个）—— 最后这一条证明新加的两个 keyframes 不在加载时乱跑
  （它们只挂在抽屉上，而抽屉不在页面里）。

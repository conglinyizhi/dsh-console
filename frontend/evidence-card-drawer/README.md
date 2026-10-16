# 卡片变条目 + 详情抽屉 + 三色状态灯：实测证据

契约第七轮。这里的每一个数都是 DOM / computed style 实测，不是看截图认出来的。
探针只读页面；**没有改 design/ 下的任何脚本**，也没碰 backend/。

跑法（控制台在 5390 上跑着）：

```bash
cd dsh-console/frontend/evidence-card-drawer
node probe-states.mjs            http://127.0.0.1:5390/ states   # 三色 + 黄的两个成因
node probe-drawer.mjs            http://127.0.0.1:5390/ drawer   # 卡片 DOM / 抽屉开合与焦点 / 按钮可达 / 窄屏
node probe-widths.mjs            http://127.0.0.1:5390/ widths   # 20 档宽度的列数与溢出
node probe-dialog-from-drawer.mjs http://127.0.0.1:5390/ dialog  # 从抽屉开对话框那四条判据
node probe-actions.mjs           http://127.0.0.1:5390/ actions  # 抽屉里的按钮真的发得出去
node diag-overflow.mjs           http://127.0.0.1:5390/          # 逐元素找横向溢出的那一环
```

## 一、三色状态灯

灯的档位与颜色取的是 `getComputedStyle(dot).backgroundColor`（`states.json`）。

| 卡片 | data-state | computed background-color | 来源 |
| --- | --- | --- | --- |
| `web :3080` | `running` | `rgb(78, 194, 122)` | 真读数：签名探测 `dsh-auth-401` 通过 |
| `web :<fake>` | `fault` | `rgb(224, 164, 88)` | 成因 b：真起一个「端口在听、cmdline 像 dsh、签名不通过」的进程 |
| `review-dev` | `fault` | `rgb(224, 164, 88)` | 成因 c：真读数，缺 3 个包 |
| `headless` | `stopped` | `rgb(224, 104, 95)` | 真读数：没有在跑，包不缺、patch 也在 |

**黄的两个成因分开说**（抽屉里那句「为什么」，原样摘录）：

- b：`黄 · 故障：端口在听、持有它的进程 cmdline 看着是 dsh，但签名探测不通过（HTTP 200 text/plain，没有命中任何签名）。契约里黄的两种成因 —— b：…；c：…`
- c：`黄 · 故障：没有在跑的实例，但这只 profile 缺 3 个包（@deepseek-ai/dsh-experimental-agent-team-profile、@deepseek-ai/dsh-experimental-auto-review、@deepseek-ai/dsh-experimental-schedule-bundle）—— 契约里黄的成因 c。`

成因 b 的隔离环境（`fixture.mjs` 的 `startFakeDsh`）：真起一个进程，用 `exec -a` 把 argv[0]
写成 dsh 的入口路径，HTTP 应答故意不是 dsh 签名。实测拿到：

```
/proc/<pid>/cmdline = node /…/@deepseek-ai/dsh/lib/bin.js web --port 41545 -e require('http')…
GET http://127.0.0.1:41545/  → 200 text/plain，body = "not a dsh signature"
```

**这一版后端还不列这种端口**：探针把这样一个进程起起来之后打 `/api/local/instances`，
返回里只有 3080 一条 —— 「签名不过也要列出来并标 fault」这条行为还没落地。所以 b 那一条
是探针按契约往响应里**追加**的，它的 field 值（HTTP 200 / text/plain / 没有命中签名）逐字来自真实探测。
`state` / `stateReason` / `profileHealth` 三个字段本身**已经落地**，绿 / 红 / 黄 c 走的都是真读数。

## 二、后端还没给 state 时的诚实显示

`probe-drawer.mjs` 第一步先注入一个脚本，把 instances 响应里的三个字段删掉
（模拟「后端这一版还没给」），实测：

```
卡片 data-light = unknown，.dsh-dot.light-unknown，background-color = rgba(0, 0, 0, 0)（透明，不上色）
aria-label      = 未知（后端没给 state）
抽屉「状态」      = 未知（后端没给 state）
抽屉那句为什么    = 这一版后端还没给 state 字段，颜色不猜（这一格是「未知」，不是三色里的任何一档）。
                  已有的读数里能说的只有：签名探测通过（dsh-auth-401）；端口在听、持有它的进程像不像
                  dsh、profile 缺不缺包，要等后端把 state 接上才说得准。
后端 state       = 没有这个字段（这一版后端还没给）
```

截图：`drawer-no-state-field.png`。

profile 行上没有「不适用」与「没给」混说的问题：抽屉里那一行写的是
`后端 state：不适用（这是磁盘上的 profile 行，不是实例读数）`。

## 三、卡片只剩三样

`drawer.json` 的 `card` 字段（一张真卡片，`outerHTML` 也在里面）：

```
<article data-name="instance-card" data-instance="web :3080" data-status="running"
         data-light="running" role="button" tabindex="0" aria-haspopup="dialog"
         aria-label="web :3080 —— 点开看读数与控制（绿 · 运行中）" class="dsh-case" id="dsh-card-port-3080">
  <div class="dsh-case-head">
    <span class="dsh-tile-slot"><span class="dsh-tile accent">…svg…</span>
      <span data-name="status-light" data-state="running" class="dsh-dot light-run">…</span></span>
    <span data-name="card-name" class="dsh-name">web :3080</span>
  </div>
</article>
```

- textContent = `web :3080`（只有名字；有备注的那种多一行「备注 …」）
- 卡片内 `button` 0 个、`[data-name="row-menu"]/[aria-haspopup="menu"]/.dsh-menu` 0 个、
  `.dsh-fields/.dsh-field/[data-name="drawer-field"]` 0 个、`.dsh-actions` 0 个
- 图标 1、状态灯 1、名字 1

## 四、抽屉开合与焦点

| 动作 | 结果 | 焦点 |
| --- | --- | --- |
| 点卡片 | 抽屉开（`role=dialog` `aria-modal=true` + 遮罩） | `dsh-drawer-close` |
| 卡片上按 Enter | 同上 | `dsh-drawer-close` |
| Esc | 关 | `dsh-card-port-3080`（触发它的那张卡） |
| 点外部（遮罩） | 关 | `dsh-card-port-3080` |
| 点关闭键 | 关 | `dsh-card-port-3080` |

窄屏（视口 400px）：抽屉宽 400 = 视口宽（`fullWidth: true`），页面与抽屉都不横向溢出，
13 颗按钮全部可达（先 `scrollIntoView` 再 `elementFromPoint` 反查 —— 内容超出高度时
下面的按钮在视口外，`elementFromPoint` 对视口外坐标恒返回 null，那是「还没滚到」不是「点不到」）。
宽屏 520px 固定宽，抽屉内容不滚（`scrollH == clientH`），同样全部可达。

截图：`drawer-wide.png`、`drawer-narrow.png`、`drawer-buttons-wide.png`。

## 五、多档宽度的列数与溢出

`probe-widths.mjs` 在 20 档宽度上量 `grid-template-columns` 的轨道数（比数卡片可靠：
本机只有 4 张卡，永远看不到第 6 列）、页面 / 栅格 / 主区 / 每张卡 / 卡头各自的
`scrollWidth > clientWidth`：

| 视口 | 列数 | 每卡宽 | 横向溢出 |
| --- | --- | --- | --- |
| 360 / 480 / 620 / 725 | 1 | 126 / 246 / 386 / 491 | 无 |
| 726 / 900 / 977 | 2 | 240 / 327 / 365.5 | 无 |
| 978 / 1100 / 1229 | 3 | 240 / 280.7 / 323.7 | 无 |
| 1230 / 1280 / 1440 / 1481 | 4 | 240 / 252.5 / 292.5 / 302.8 | 无 |
| 1482 / 1600 / 1733 | 5 | 240 / 263.6 / 290.2 | 无 |
| 1734 / 1920 / 2560 | 6（上限） | 240 / 271 / 377.7 | 无 |

断点上每卡正好 240px（设计的最小可用宽度），往上变宽；**20 档全部无横向溢出**。
截图：`widths-360.png`、`widths-1280.png`、`widths-1920.png`。

`diag-overflow.mjs` 是找到溢出那一环用的：改动前 360 / 480 下 `.dsh-head-note`
（`flex: none` + nowrap，209px）会顶穿 `.dsh-main`；改成页头允许折行 + 说明自己省略号之后归零。

## 六、抽屉里每个按钮可达

宽屏与窄屏各一次 `elementFromPoint` 反查（`drawer.json` 的 `reachWide` / `narrow`）：

- 运行中的卡：13 颗（打开 Web UI / 停止 / 重启 / 在新标签页打开 / 复制访问地址 / 复制开发指令 /
  重命名 / 备注 / 派生开发副本 / 查看日志 / 打开工作目录 / 编辑配置 / 关闭）—— 不可达 0
- 已停止的卡：12 颗（启动 / 重启 / 复制访问地址 / 复制开发指令 / 重命名 / 备注 / 归档 /
  查看日志 / 打开工作目录 / 编辑配置 / 关闭）—— 不可达 0
- 六格读数（DSH 版本 / Profile / 访问地址 / DSH_HOME / 插件数量 / 最近改动）都在抽屉里，6 格

## 七、按钮不是摆设

`probe-actions.mjs`：从抽屉里点「查看日志」→ 页面切到 `/logs?source=instance%3Aproc-3080`，
来源下拉选中 `instance:proc-3080`，抽屉自动收起。点「复制访问地址」→ 回执如实报失败
（`Document is not focused`，无头浏览器里剪贴板本来就不给写），**没有伪装成「已复制」**。

`probe-dialog-from-drawer.mjs`：重命名 / 备注 / 删除三个框都从抽屉里的按钮开，
实测居中、在最上层可点、取消键与遮罩都能关、关闭后焦点回那张卡，且开框时抽屉先收起。

## 八、环境限制

- 无头浏览器里 `navigator.clipboard` 写入一定失败（document 没有焦点），
  所以「复制」这一条只验到「失败时如实报」，验不到成功路径。
- 假 dsh 那个进程由探针自己起、自己按记录下来的 pid 结束；跑完扫过 `/proc`，
  除探针自身外没有残留（第一次跑崩过一次，留下的那只已按 pid 清掉）。

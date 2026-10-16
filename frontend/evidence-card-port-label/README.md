# 条目右上角那一格加「端口：」标签（第十三轮）

使用者原话：「这里加一个 端口： 吧」（圈着条目右上角那个光秃秃的 `3080`）。

只动前端两个文件，没有碰 `backend/` 与 `design/`：

| 文件 | 改动 |
| --- | --- |
| `view_overview.mbt` | `card_port()` 里多一个 `.dsh-card-port-label`（写 `端口：`），数字仍是这一格的内容 |
| `styles/app.scss` | `.dsh-card-port-label { color: $text-dim; }`；并在 `@media (max-width: 420px)` 下 `display: none` |

**新增 / 改动的可见文案，逐条列全，就一条**：

| 位置 | 改前 | 改后 |
| --- | --- | --- |
| 条目第一行右端那一格 `.dsh-card-port` | `3080` | `端口：3080` |

（全角冒号，照使用者写的那个形式。别处一个字的可见文案都没动：卡片 aria-label 仍是
「web :3080 —— 点开看读数与控制（运行中）」，名字那一格仍是 `web`，第二行仍是「上次启动 …」。）

## 那一格长什么样

```html
<span data-name="card-port" data-uid="96xfaeh2" class="dsh-card-port">
  <span class="dsh-card-port-label">端口：</span>3080</span>
```

- 那一格的 DOM 文本：`"端口：3080"`（标签与数字之间不插空白，探针取到的就是这一串）
- 标签：`rgba(232, 230, 225, 0.72)`（`$text-dim`），12.5px —— **比数字淡一档，与条目里其它 label
  （`.dsh-archive-stamp-label` 那一档）同一个调子**
- 数字：`rgba(232, 230, 225, 0.82)`（`$text-mid`），12.5px —— 与改动前一个像素都没变
- 同一个字号是刻意的：同一行里混两个字号会把基线错开，而这一格的高（16px）正是
  「带端口的条目与不带的等高」那一条的支点

**判据一个字没动**：还是「这一行知不知道端口」才产出这一格。标签挂在这一格**里面**，
所以没有端口的那一行连标签一起不产出 —— 不会剩一个「端口：」孤零零挂在右端。
拖动虚影走同一处渲染，跟着一起变。

## ≤420 那一档：标签让位（这一条是量出来的）

卡宽 = 视口 − 234，第一行那一格 = 卡宽 − 70（内边距 13×2 + 图标 34 + 间隙 8）：

| 视口 | 卡宽 | 第一行那一格 | 现在的「名字 + 8 + 数字」 | 「端口：」39px 放得下吗 |
| --- | --- | --- | --- | --- |
| 360 | 126 | 56 | 24 + 8 + 24 = 56（**正好用满**） | 放不下 |
| 421 | 187 | 117 | 46 + 8 + 63 = 117 | 放得下 |

360 下硬塞只有两种收场：名字被压到 0 宽（连省略号都没有，等于把名字挤没），
或者那一串顶出内容盒右缘（右缘对不齐、窄屏溢出）。两条都是硬要求里明令不许的，
所以这一档由标签让位（`display: none`，节点还在 DOM 里，只是不显示）：

- 名字照旧省略号，条目几何**与加标签之前逐像素一致**
- 断点取 420，与页面内边距那一条同档；≥421 起标签回来

**这一条是这一轮唯一需要使用者拍板的地方**：360 下标签是看不见的（数字还在）。
真要在 360 也看见「端口：」，就只能接受名字被挤没或那一串顶出右缘。

## 实测（1280 / 360 两档为准，另附断点两侧）

| 视口 | 这一趟 | 条目 w×h | 第一行高 | 第一行宽 | 名字左缘 | 名字宽 | 标签宽 | 那一串宽 | 右缘 − 内容盒右缘 | 第一行溢出 | 整页横向滚动 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1280 | 改前 | 252.5×70 | 22 | 168.5 | 50 | 134.5 | — | 24 | 0 | false | false |
| 1280 | 改后 | 252.5×70 | 22 | 168.5 | 50 | 95.5 | 39 | 63 | 0 | false | false |
| 620 | 改后 | 386×66 | 22 | 316 | 42 | 245 | 39 | 63 | 0 | false | false |
| 474（卡宽 240） | 改后 | 240×66 | 22 | 170 | 42 | 99 | 39 | 63 | 0 | false | false |
| 421 | 改后 | 187×66 | 22 | 117 | 42 | 46 | 39 | 63 | 0 | false | false |
| 420 | 改后 | 186×66 | 22 | 116 | 42 | 84 | 让位 | 24 | 0 | false | false |
| 360 | 改前 | 126×66 | 22 | 56 | 42 | 24 | — | 24 | 0 | false | false |
| 360 | 改后 | 126×66 | 22 | 56 | 42 | 24 | 让位 | 24 | 0 | false | false |

- `改前` 两行量的是**当前 5390 上那一版构建**（`frontend/dist`，与 HEAD 一致）——
  改动的就是它，所以这一趟是真·改动前后，不是另编一份旧版
- **无端口那一行逐像素一致**：条目宽高、第一行、名字那一格的位置三项全等
  （`compare-port-geometry.mjs` 逐条打印，结论「全部满足」）
- 有端口那一行只有右上角那串变长：24 → 63（标签 39 + 数字 24），名字那一格相应变窄

## 名字长了仍是一行省略号

往那一格注入一个 46 字的名字（`a-very-long-profile-name-to-check-the-ellipsis`，
带 `data-injected` 标记；只改 DOM 文本、不发状态）再量：

| 视口 | 名字那一格 | 名字行盒 | 省略号生效 | 名字 scrollWidth/clientWidth | 那一串右缘 − 内容盒右缘 | 标签横向越出那一格 | 第一行/条目/整页溢出 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1280 | 95.5 | 1 | true | 368 / 96 | 0 | false | false / false / false |
| 620 | 245 | 1 | true | 368 / 245 | 0 | false | false / false / false |
| 474 | 99 | 1 | true | 368 / 99 | 0 | false | false / false / false |
| 421 | 46 | 1 | true | 368 / 46 | 0 | false | false / false / false |
| 420 | 84 | 1 | true | 368 / 84 | 0 | 让位 | false / false / false |
| 360 | 24 | 1 | true | 368 / 24 | 0 | 让位 | false / false / false |

标签只有一个行盒（`labelLineBoxes = 1`）—— 它不换行。它的**行内盒**比这一格高 3px
（12.5px 的 CJK 兜底字体内容盒 19px vs 行盒 16px），那是字体自己的盒子：
这一格没有背景也没有边框，画不出任何越界的东西，行高与条目高度也由 `line-height` 定住
（上面那一栏已逐条量过第一行高 22、条目高 70/66，改动前后相等）。

## DOM 文本与「没有端口就没有那个节点」

见 `dom-text.txt`（由 `dump-dom-proof.mjs` 生成，读的是 `after-*.json`）：

- 有端口那一行：那一格文本 `"端口：3080"`；全页扫「端口：」只有一处，
  落在 `.dsh-card-port-label` 里（`insidePort: true`）
- 没有端口那一行（`profile:web-dev`）：`nodes.port = false`、`portLabel = false`、
  那一格文本 `null`、卡片整段文本里 `端口：` 出现 0 次；头那一行 HTML 里只有名字那一个 span

## 出图

| 文件 | 看什么 |
| --- | --- |
| `after-1280-running.png` | 运行中那一条（放大 3×）：右上角「端口：3080」，标签比数字淡 |
| `after-1280-noport.png` | 没有端口的那一条：**没有**「端口：」这个节点 |
| `after-1280-longname.png` | 注入 46 字名字之后：名字一行省略号，标签仍在 |
| `after-360-running.png` | 360 那一档：标签让位，只剩数字（名字与几何与改前一致） |
| `before-1280-running.png` / `before-360-running.png` | 改动前那一格只有数字 |

## 复现

```bash
cd dsh-console/frontend/evidence-card-port-label
# 1) 量（改前那一趟是在改动前的构建上跑的，已经落成 before-*.json）
PROBE_VIEWPORT_W=1280 PROBE_VIEWPORT_H=900 node probe-port-label.mjs http://127.0.0.1:5390/ after-1280.json after-1280
PROBE_VIEWPORT_W=360  PROBE_VIEWPORT_H=720 node probe-port-label.mjs http://127.0.0.1:5390/ after-360.json  after-360
# 2) 改前/改后逐像素对照
node compare-port-geometry.mjs before-1280.json after-1280.json before-360.json after-360.json
# 3) DOM 文本 + 「没有端口就没有节点」
node dump-dom-proof.mjs > dom-text.txt
# 4) 常驻验收（ACC_NO_START=1 跳过会真起实例的那一支）
cd ../../design && ACC_NO_START=1 node run-acceptance.mjs http://127.0.0.1:5390/
```

## 这一轮的判定

- `cd dsh-console/frontend && ./check.sh`：**0 error**（moon check + build.sh 全过；
  唯一一条 warning 是 `DragItem.id` 那个既有字段，不是这一轮引入的）
- `ACC_NO_START=1 node design/run-acceptance.mjs http://127.0.0.1:5390/`：
  **判定 31 项，通过 31，失败 0**（另有信息 5 条），见 `acceptance-5390.log`。
  其中「类名契约候选（无规则的类）＝ 无」说明新加的 `.dsh-card-port-label` 有规则、
  不是个没样式的空类名
- 没有 kill / 重启 5390 上那台控制台，也没有碰使用者的 `~/.dsh` 与 `~/.local/state`：
  前端产物落在 `frontend/dist/`，5390 直接服务它，刷新页面即为新版

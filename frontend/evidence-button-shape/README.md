# 已停止卡的按钮组：分段按钮 → 独立的 ⋯

改的是 `dsh-console/frontend/`：`view_overview.mbt`（DOM）、`styles/app.scss`（样式）、
`icons.mbt`（顺手摘掉只有分段 caret 在用的 `class` 参数与过时的尺寸注释）。

## 改成什么

- 已停止卡：`[启动 ▾]` 分段按钮撤掉 → 「启动」是普通主色按钮（`.dsh-btn primary violet`），
  与「重启」「⋯」并排三个独立按钮
- `⋯` 与运行中卡 **同一段代码**（`.dsh-btn icon-only`，30×30、圆角 6px、组内 gap 6px），
  点开的还是已停止卡原来那份菜单，条目与顺序一条没动
- 删掉了因此失效的分段按钮样式：容器 gap / 左右半圆角 `6 0 0 6` 与 `0 6 6 0` /
  `border-left` 分隔线 / 悬停只加深一半 / `.dsh-caret` 的 90° 旋转

## 为什么

分段的形状在暗示「有多个变体可选」，而我们只有一种启动方式。控件的形状应该和它的真实语义一致：
「更多动作」归行尾独立的 ⋯，于是已停止卡与运行中卡是同一个骨架，只有第一颗按钮的语义随状态翻转。
理由写在 `view_overview.mbt` 的 `instance_actions` 与 `styles/app.scss` 原分段规则的位置上，
不是只留一句「按需求改」。

## 证据怎么复现

```bash
cd dsh-console/frontend
MOON_HOME=$PWD/.sandbox/moonhome ./check.sh            # 类型 + 构建（内含 build.sh）
node evidence-button-shape/probe-actions-shape.mjs http://127.0.0.1:5390/ evidence-button-shape/after '改后'
node evidence-button-shape/probe-actions-shape.mjs http://127.0.0.1:5390/ evidence-button-shape/before '改前'   # 需旧产物
node evidence-button-shape/compare.mjs evidence-button-shape/before.json evidence-button-shape/after.json
node evidence-button-shape/probe-dialog-via-dots.mjs http://127.0.0.1:5390/ evidence-button-shape/dialog-via-dots
```

- `before.json` 是**旧产物**（改前那次构建）在 5390 上的读数，`after.json` 是新产物；
  `compare.txt` 是两者的逐条对照（按钮组构成 / ⋯ 的类名与矩形 / 菜单条目）
- 探针只点「行尾 ⋯」与菜单里的「重命名」，不点启动、停止、重启，也不点任何会改数据的菜单项；
  展开后按 Escape 收起
- `acceptance-5390.log` 是 `node design/run-acceptance.mjs http://127.0.0.1:5390/` 的完整输出
- `build-check.log` 是 `./check.sh` 的关键行（0 error；唯一的 Warning 是依赖
  `hackwaly/moonback@0.8.1` 的 deprecated 提示，从 rabbita 传递进来，与本次改动无关）

## 读数（compare.txt 摘要）

| 项 | 改前 | 改后 |
| --- | --- | --- |
| 已停止卡按钮组子节点 | `<div .dsh-split>[`启动` | caret]` + `重启`（2 个） | `启动` + `重启` + `⋯`（3 个独立 button） |
| 已停止卡 ⋯ | `dsh-btn primary split-caret` 26×30，圆角 `0 6 6 0` | `dsh-btn icon-only` 30×30，圆角 `6px` |
| 运行中卡 ⋯ | `dsh-btn icon-only` 30×30，圆角 `6px` | 同左（未动） |
| 两类卡的 ⋯ 一致 | false | true（类名 / 矩形 / 圆角 / 内边距逐项相同） |
| 按钮组右缘 − 内容盒右缘 | [0,0,0] | [0,0,0] |
| 菜单条目 | 查看日志 / 打开工作目录 / 编辑配置 / — / 重命名 / 编辑备注 / 归档 / 删除 | 逐条相同（8 行，含 1 条分隔） |
| 菜单锚点 | top+6 / right 0 | top+6 / right 0 |

## 验收结果与遗留

`design/run-acceptance.mjs`（5390）：**判定 24 项，通过 22，失败 2**。
「两段式无缝」那条退役后已经不再进判定表，实测确实没出现。

失败的两条是「对话框居中」「对话框在最上层可点」，原因是**探针的入口选择器过期**，不是界面回归：

`design/probe-dialog.mjs` 第 18、47 行写的是
`(c.querySelector('.split-caret') || c.querySelectorAll('button')[1]).click()` ——
改后选择器落到 `buttons[1]`，也就是「重启」，于是菜单没打开、重命名对话框也没开。
这两条的 `closedByCancel` / `closedByScrim` 因此是「没有对话框所以关着」的假通过。

同一条链路用 `[aria-haspopup="menu"]` 当入口实测（`probe-dialog-via-dots.mjs` / `dialog-via-dots.json`）：
菜单打开、重命名对话框打开、`centered: true`、中心点命中对话框自己（在最上层）、
取消能关、点遮罩能关、焦点回到 ⋯。所以是探针要改一行，界面本身没坏。

`design/` 下还有这些地方仍提到分段按钮（都在验收脚本那一侧，本次没动）：
`new-selectors.draft.json` 的 `splitMain` / `splitCaret`、`measure-parity.mjs` 的
「四点六、两段式按钮几何」（`document.querySelector('.dsh-split')` 会 null 解引用）、
`frontend-parity-checklist.md` 与 `button-variants.html` 里的历史记录。

## 产物核对

`dist/` 里 grep `dsh-split` / `split-caret` / `split-main` / `dsh-caret` → 全 0 命中
（app.css、app.js、index.html 三份文件逐一数过），源码侧同样 0 命中。

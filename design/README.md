# design/ 目录说明

这个目录同时放着「现在还生效的规格」与「当时的取证记录」。混在一起容易误读，先按用途分开：

## 还在维护的

| 文件 | 是什么 |
| --- | --- |
| `backlog.md` | 待办队列：需要提督决策的、可直接做的、待验清单、已完成、流程教训 |
| `design-fixes.md` | 界面与交互的修正记录，一节一件事；顶部有 50 节的索引与状态 |
| `ops-maintenance-jobs.md` | 维护页作业台（升级 dsh、试跑、回滚、快照）的规格 |
| `deep-home-isolation.md` | profile 的隔离 home、搬家、凭证引用的规格 |
| `write-api-contract.md` | 后端 API 契约（动作名、参数、二次确认串） |
| `dsh-release-sources.md` | 版本来源（github / npm / 镜像）与缓存 |
| `dsh-version-switch.md` | 换版本与钉版本的行为 |
| `sidebar-collapse.md` | 侧栏折叠（190 ↔ 56）与窄屏覆盖层 |
| `drag-reorder-cards.md` | 卡片拖动与落点语义 |
| `data-name-plan.md` | 探针与自动化依赖的 `data-name` 约定 |
| `rabbita-md2-cheatsheet.md` | rabbita 的写法备忘（查语法用） |
| `manual-start.md` | 手动启动 dsh 的静态说明（不经过网页渲染；关于页只留一句指向） |
| `evidence/` | 取证截图与探针输出（menu / weburl / menu-flip 三个目录） |

## 历史取证（不再维护，读时先看日期）

- `dsh-home-phase0-findings.md`、`dsh-home-phase0b-findings.md`、`dsh-home-isolation-plan.md`：隔离 home 动工前的调研与方案，结论已并进 `deep-home-isolation.md`。
- `phase3-impact-map.md`：重写阶段的改动影响面盘点。
- `frontend-parity-checklist.md`：与 Vue 版逐项对齐时的清单，那条线已收尾。
- `full-rewrite-brief.md`：整版重写时的任务书。

## 跑的东西

- `run-acceptance.mjs`：验收套件（30 项判定 + 信息项）。`ACC_NO_START=1 node run-acceptance.mjs <url> <outDir>`。
- `probe-*.mjs`、`verify-*.mjs`：各页的可达性、拖动、日志、抽屉、类名契约等探针。
- `vue-baseline-*.json`：当年 Vue 版量出来的基线（几何、动画、日志）。
- `*.html`、`new-selectors.draft.json`、`compare-card-geometry.mjs`、`measure-parity.mjs`：取证期的对比页与量数脚本。

## 约定

1. 规格类文档只增不改历史：要推翻旧结论，新开一节写「旧结论为什么不对」，不把旧文字抹掉。
2. 做完的事从 `backlog.md` 的排队区移到「已完成」，带提交号；没做的写清「怎么算做完」。
3. 需要提督决定的事，要写清「缺什么信息才能决定」，不要只写一句「待定」。
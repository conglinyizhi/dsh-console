# 路由与加载态的验收（第五轮）

跑法（控制台已经起在 5390 时）：

```bash
node verify-routing.mjs http://127.0.0.1:5390/
```

探针只读：不点任何写动作按钮。截图与 `verify-routing.json` 由它自己写在本目录。

## 这一轮修的两件事

1. **刷新落回原来那一页**：页面（总览 / 日志 / 设置 / 关于）与设置页的五个分组都进地址
   （`/settings/safety` 这种），日志页的来源也进地址（`/logs?source=instance:…`）。
   走 `history.pushState` + `popstate`，浏览器前进 / 后退可用。
2. **读数没到 ≠ 没有数据**：三个读数还在路上时那一格是加载态（`.dsh-loading`，
   徽标写「读取中」、分组计数写 `(…)`）；空态只在真读到空的时候出现。
   日志页同理：`log_loading` 与 `log_source_read` 一起判，
   **内容不属于当前来源时显示加载态**，不拿上一个来源的行顶着新来源显示。

## 证据怎么读

| 文件 | 是什么 |
| --- | --- |
| `verify-routing.json` | 探针的全部结构化结果（下面逐条对着它说） |
| `overview-loading.png` | 用 `Fetch` 把 `/api/local/*` 压后 2 秒，第 1 秒拍的：两格都是加载态 |
| `overview-loaded.png` | 同一页，放行之后：3 张卡、徽标「真实数据」、计数 `(1)` / `(2)` |
| `overview-empty.png` | instances / profiles 的响应换成空数组之后：这才是空态（计数 `(0)`） |
| `logs-loading.png` | 日志接口同样压后 2 秒：`log-loading` 块，没有「没有可显示的行」 |
| `logs-loaded.png` | 放行之后：`log-box` + 200 行 |
| `logs-empty.png` | 日志响应换成空数组：`.dsh-log-empty`，这才是空态 |
| `settings-safety-after-reload.png` | `Page.reload` 之后仍在「设置 / 危险动作」这一组 |
| `route-fallback-settings.png` | 敲 `/settings/not-a-group`：回落设置首页 + 顶部那条说明 |
| `route-fallback-overview.png` | 敲 `/nope/deep`：回落总览 + 顶部那条说明 |
| `acceptance-5390.log` | `node ../design/run-acceptance.mjs http://127.0.0.1:5390/` 的完整输出 |

## 判定表（对着 verify-routing.json）

- 逐页切过去：`/` → `/logs?source=instance%3Aproc-3080` → `/settings/instance` →
  `/about` → `/`（`routing.pages`）。
- 设置五个分组：`/settings/instance` `/settings/process` `/settings/logs`
  `/settings/ui` `/settings/safety`（`routing.groups`）。
- 刷新：日志页刷新后仍是 `/logs?source=instance%3Aproc-3080` + 日志页；
  设置刷新前后都是 `/settings/safety` + 「危险动作」那一组（`routing.reloads`）。
- 前进 / 后退：从 `/settings/safety` 前进到 `/`，`history.back()` 回到 `/settings/safety`、
  `history.forward()` 再回到 `/`，页面与地址一致（`routing.history`）。
- 错误 path：`/settings/not-a-group` → 地址改写 `/settings/instance`、页面是设置首页、
  `route-notice` 说清「那个分组不存在，现有的是这几个」；
  `/nope/deep` → 地址改写 `/`、页面是总览、说明列出认得的几条路由。
  两次都不白屏（`routing.badGroup` / `routing.badPath`）。
- 加载态：压后 2 秒的第 1 秒里 `running-loading` / `stopped-loading` 在、
  `running-empty` / `stopped-empty` 与那两句空态文案都不在，徽标是「读取中」、
  计数是 `(…)`；放行之后反过来（`loading.duringLoad` / `loading.afterLoad`）。
- 空态：把响应换成空数组之后 `running-empty` / `stopped-empty` 才出现，计数 `(0)`，
  而且这时候**没有**加载块（`empty.overview`）。
- 日志：压后 2 秒时是 `log-loading`、`.dsh-log-empty` 不在；放行后是 `log-box` + 200 行；
  空数组响应下才是 `.dsh-log-empty`（`loading.logDuringLoad` / `loading.logLoaded` / `empty.logs`）。

## 一句话说明

加载态与空态在视觉上就是两副样子（实线面板 vs 虚线框、`(…)` vs `(0)`、
「读取中」vs「真实数据」），截图里一眼能分开；读取失败的第三种情况仍是既有的
「演示数据 · 真实读取失败」标记，没有被并进加载态。

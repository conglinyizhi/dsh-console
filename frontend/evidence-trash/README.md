# 回收站这一轮的证据（第六轮追加契约）

使用者原话：「回收站呢？」—— 删除进回收站是真的（磁盘上那份在），但界面上没有入口，
而删完那条回执把 `mode=trash · trashPath=… · hardDeleted=false` 摊在了正文上。

这一轮的改动：后端加回收站读数与两个动作，前端加「回收站」页（侧栏第五项 / `/trash`），
删完的回执改成说人话（路径与 mode 收进悬停）。

## 环境（一条硬线：不碰使用者那一份）

- 使用者那份 `~/.dsh/profiles` 与 `~/.local/state/dsh-console`（含他回收站里的
  `web-dev-1792070484767`）**一个字节都没动**；5390 上那只控制台进程也没 kill / 没重启。
- 真链路全在隔离环境里跑，端口 5491：

  ```bash
  bash setup.sh                       # DSH_HOME 与 XDG_STATE_HOME 都在 /tmp/dsh-console-trash-e2e 下
  cd ../../backend && DSH_HOME=/tmp/dsh-console-trash-e2e/dsh-home \
    XDG_STATE_HOME=/tmp/dsh-console-trash-e2e/state \
    DSH_CONSOLE_BACKEND_PORT=5491 \
    DSH_CONSOLE_DIST=$PWD/../frontend/dist \
    ./_build/native/debug/build/dsh-console-backend.exe
  ```

## 跑了什么、结论是什么

| 证据文件 | 内容 | 结论 |
| --- | --- | --- |
| `api-chain.log` | 后端真链路（`api-chain.mjs`）：删除 → 列表 → 恢复 → 再删 → 彻底删除；含穿越负例与 conflict 负例 | 9 条判定全过 |
| `ui-chain.log` | 浏览器里走界面（`trash-ui-chain.mjs`）：侧栏进回收站、删除回执、列表行、确认框、取消、彻底删除、conflict、恢复 | 13 条判定全过 |
| `extra.log` | 硬删那条路的回执（`safety.deleteToTrash=false`）+ 5390（新前端 / 旧后端）时回收站页说什么 | 5 条判定全过 |
| `shape-diff.log` | `GET /api/local/console` 的**字段名集合**对照（5390 旧后端 vs 5491 新后端） | 只在旧里有：无；只在新里有：`trash` |
| `audit-sample.log` | `audit.jsonl` 里 `restore-from-trash` / `purge-trash-item` 的原文（成功与 conflict 各一条） | 两个动作照常进审计 |
| `acceptance-5390.log` | `node design/run-acceptance.mjs http://127.0.0.1:5390/` | 28 项判定：27 通过、1 失败（见下） |
| `trash-list.png` / `trash-purge-dialog.png` | 回收站列表与「彻底删除」确认框的实际样子（隔离环境） | — |

## 三条要如实说的事

1. **5390 上的后端还是旧二进制**（按指示没重启）。新前端在它上面打开 `/trash` 时说的是
   「这一版后端还没有回收站读数……重启控制台后端即可」，**不说「回收站是空的」**——
   读不到与没有是两件事。要看真的回收站内容，5390 的后端需要重启一次（用同一份 exe 重启即可）。
2. **验收里 1 条红：`元信息含目录依据`**，与这一轮改动无关：
   `design/probe-logs.mjs` 在 9810084 里把来源**钉死成 host**（为了让判据与实例增删无关），
   而 `host` 那条来源在后端是 `kind=fixed`、没有 `homeSource`，前端因此不写「目录依据」段；
   判据要的那段只有在来源是 `instance:<id>` 时才存在（实测：`source=host` → `kind=fixed`；
   `source=instance:proc-3080` → `kind=instance` + `homeSource=实例自身的 DSH_HOME`）。
   钉死 host 这一条判定就不可能过 —— 要么把探针钉回实例来源，要么判据按来源分档。
   探针是验收装置（不在本轮范围），没动它。
3. 本轮**顺手修了一处既有缺陷**：删除的二次确认串以前被塞进 `params`，而后端是从 body **顶层**
   读 `confirm` 的 —— `safety.deleteToTrash=false` 时硬删永远以 `bad-params` 告终。
   现在走 `action_body_with_confirm`（顶层），硬删那条路实测通了（见 `extra.log`）。

# 版本切换（回退）与「一只进程一行」

状态：已拍板，交实现。目标一句话：**控制台能指定用哪一版 dsh 起实例，能回退到旧版；同一只进程的多个监听端口不再各占一行。**

## 0 背景事实（已核实，别重复验证）

- 本机有两份 dsh 装了：
  - `0.2.0-rc.2` → `~/.local/share/pnpm/global/5/node_modules/.pnpm/@deepseek-ai+dsh@0.2.0-rc.2_4983f4004aac5b5700d5a6d3a8f53a6f/node_modules/@deepseek-ai/dsh`
  - `0.2.1-rc.2` → `~/.local/share/pnpm/global/v11/499c6f07a790dd7f679cefbbb26ef27a4ada938b7769be3aeb15c04209a68b61/node_modules/@deepseek-ai/dsh`
  - 两份都能跑：`node <dir>/lib/bin.js --version` 分别输出 `0.2.0-rc.2` / `0.2.1-rc.2`
- PATH 上的 `dsh` shim 现在解到 0.2.1-rc.2；在跑的实例（3080，pid 62931）也是 0.2.1-rc.2
- 起实例的方式是 `node <包目录>/lib/bin.js --profile <名> --no-open [--port <端口>]`，包目录来自 `@runtime.installed_dsh_dir()`。**换版本不需要动系统 shim，也不需要动 pnpm 全局安装** —— 只要换这个包目录。

## 1 缺陷：同一 pid 的第二个监听端口被当成第二只实例

现状（`GET /api/local/instances`）：pid 62931 同时听着 3080 与 9230，于是出现两行：

- `proc-3080` state=running（签名 dsh-auth-401 通过）
- `proc-9230` state=fault（「端口在听，但签名探测不通过：HTTP 404」）

9230 不是 dsh web 入口，探 `GET /` 得 404 是正常的。**界面在说假话。**

改法：

1. 组装 instances 时按 **pid 归并**：一个 pid 一行。
2. 主端口 = 该 pid 名下**签名命中 dsh 判据**的那个端口；都不命中时取端口号最小的那个（并照旧按规则判状态）。
3. 同 pid 的其余端口收进该行的 `alsoPorts: [{port, httpStatus, signatureId, note}]`，不再单独成行；`note` 用一句人话（例：「同一只进程的另一个监听端口，不是 dsh web 入口」）。
4. `state` / `stateReason` 只按主端口算。
5. `probeResults` 保持原样（那是全局事实，不是实例行）。
6. 前端：详情抽屉里在主端口那行下面补一行「还听着 9230」（次要色，原因进 title）；卡片上不显示、不因此变色。

验收：`instances` 里每个 pid 恰好一行；3080 那行的 `alsoPorts` 含 9230；`state` 仍为 running。

## 2 版本切换（回退）

### 2.1 候选枚举

把现有的三级链拆出可复用的一层：

- `installed_dsh_candidates() -> Array[DshPackage]`：shim 解开的那份 + 各全局根下扫到的全部，按**真实路径**去重，各自带 `source`（沿用现有来源串）。
- `installed_dsh_dir()` 改成「先看有没有指定版本 → 没有就走原来的自动挑（choose_installed）」。

在这台机器上必须能列出**两份**（0.2.0-rc.2 与 0.2.1-rc.2）。注意 pnpm v11 的布局是 `global/v11/<目录>/node_modules/@deepseek-ai/dsh`，旧的 `global/5` 是 `global/5/node_modules/.pnpm/<条目>/node_modules/@deepseek-ai/dsh` —— 扫描深度与符号链接都要照顾到（允许对同一真实目录去重）。

### 2.2 指定状态

落盘：`$XDG_STATE_HOME/dsh-console/dsh-pin.json`（走 `@store.state_paths()` 同一套口径），形状：

```json
{ "dir": "<包目录>", "version": "0.2.0-rc.2", "pinnedAt": "2026-10-18T04:00:00.000Z" }
```

- 文件不存在 / 读不动 / 字段不全 → 当没指定（`auto`），不报错、不偷偷写。
- 指定的目录在候选里、且它的 `package.json` 版本与记录一致 → 生效（`pinned`）。
- 目录不在了 / 版本对不上 → 回落到自动挑，并如实标 `pin-missing`（读数里说清「你指定过 X，现在这台机器上找不到它了，按自动挑」）。

### 2.3 读数

`GET /api/local/runtime` 原有字段不动；生效版本变了时 `dshVersion` / `dshPackageDir` / `dshSourceLabel` 跟着变（来源串写「按你指定的版本」）。新增：

- `dshCandidates`: `[{version, name, dir, source, active: bool, running: bool}]` —— `active` = 当前生效的那份；`running` = 有在跑实例用的就是这份目录。
- `dshPinState`: `"auto" | "pinned" | "pin-missing"`。

### 2.4 动作

走现有 `POST /api/local/action`（`X-DSH-Console: 1` 与 Origin 校验照旧，别绕过）：

- `pin-dsh`，参数 `{"dir": "<候选里的包目录>"}`：不在候选里 → 失败 `dsh-not-installed`，人话说清「这个目录不是这台机器上装了的一份 dsh」。成功回 `{action, outcome: {dir, version}}` 并写审计（一行，别把 token/环境写进去）。
- `unpin-dsh`，无参数：删掉指定，回到自动。

起实例（`start-instance` / `restart-instance`）用**生效版本**；指定失效时按自动挑，并在 outcome 里带一句说明。

### 2.5 界面

放「关于」页（`frontend/view_about.mbt`），在「版本」面板下面加一块：「这台的 dsh 版本」。

- 每个候选一行：版本号（主文本）+ 在用/在跑标记 + 「用这一版」按钮；pinned 时该行另有「回到自动」。
- 包目录不进正文，进 title。
- 按钮真实发动作（`mark(...)` 加 data-name；沿用现有按钮样式，别新造一套）。
- 读取中 / 读取失败 与现有版本表的处理一致。

## 3 硬约束（违反就退回）

- **不许跑 `moon fmt`**（它会重排全部源码）。包文件已经是 `moon.pkg`，不需要迁移。
- 构建：`cd frontend && MOON_HOME=$PWD/.sandbox/moonhome ./build.sh`；`cd backend && MOON_HOME=$PWD/.sandbox/moonhome MOON_CC=clang MOON_AR=ar MOON_LD=clang moon build --target native`。`no work to do` 不算构建成功，要真编一遍并核对任务数。
- 不要提交 git（我审完自己提）。
- 不要动 5390 上那份控制台进程；不要起任何 dsh 实例；不要 `pgrep -f` / `pkill -f`（会匹配到自己）。
- 隔离验证：自己那份控制台用 `DSH_CONSOLE_BACKEND_PORT=5391 XDG_STATE_HOME=/tmp/... DSH_HOME=$HOME/.dsh ./_build/native/debug/build/dsh-console-backend.exe`，验收 `cd design && ACC_NO_START=1 node run-acceptance.mjs http://127.0.0.1:5391 /tmp/acc-vs`。
- 新增的可见文案必须能列成清单交我过目（不许出现内部术语）。

## 4 交回什么

1. `git status` + `git diff --stat`（改动文件清单）
2. 后端真编过的证据（任务数）
3. `runtime` 读数里两份候选、pin / unpin 两次前后的 `dshVersion` 与 `dshPinState` 实测输出
4. `instances` 归并前后：9230 不再有独立行、3080 行里有 `alsoPorts`
5. 验收结果（条目数 / 失败项），没跑到的明说没跑到
6. 新增可见文案清单

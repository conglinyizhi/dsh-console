# 目标版本的来源与安装方式

状态：规格。实现按它做。

## 0 一句话

维护页「升级 dsh」的目标版本不再靠手打：**按 GitHub → npm → 国内镜像的顺序去问有没有新版**，问到就列出来选；问不到就退回手填，并说清每个源为什么没答。关于页补一行**安装方式**（pnpm / npm / yarn 全局安装，认不出来写未知）。

## 1 目标版本来源（读接口）

新增只读接口 `GET /api/local/dsh-releases`，与其它 GET 一样走只读外壳（readOnly: true）。

### 1.1 三个源

| id | 地址 | 取什么 |
|---|---|---|
| `github` | `https://api.github.com/repos/deepseek-ai/deepseek-harness/releases?per_page=30` | 每个 release 的 `tag_name`，只认以 `dsh-v` 开头的，去掉前缀当版本号；`prerelease` 标记照实带上 |
| `npm` | `https://registry.npmjs.org/@deepseek-ai/dsh` | `versions` 的键 + `dist-tags`（latest / next / …） |
| `mirror` | `https://registry.npmmirror.com/@deepseek-ai/dsh` | 同上 |

### 1.2 怎么问

- 三个源**并发**问，每个 6 秒硬超时（不许把页面拖住）。
- 每个源都记：`ok` / `ms` / `error`（一句人话：超时 / 连不上 / 回的格式不对）。
- 回答的**采用顺序**是 github → npm → mirror：第一个 ok 的当准，其余照实列出来但不覆盖它。
- 走 curl 子进程（`curl -sS -m 6 --fail`）。环境里有 `HTTPS_PROXY` / `https_proxy` 就带上它，没有就直连；**不要写死任何代理端口**。

### 1.3 返回形状

```json
{
  "readAt": "…",
  "chosen": "github",
  "versions": [
    { "version": "0.2.1-rc.2", "prerelease": true, "latest": false, "next": true, "installed": true }
  ],
  "latest": "0.2.0-rc.2",
  "next": "0.2.1-rc.2",
  "installed": ["0.2.1-rc.2", "0.2.0-rc.2"],
  "sources": [
    { "id": "github", "ok": true, "ms": 320, "error": "", "count": 30 },
    { "id": "npm", "ok": false, "ms": 6007, "error": "6 秒内没有回话", "count": 0 },
    { "id": "mirror", "ok": true, "ms": 540, "error": "", "count": 43 }
  ]
}
```

- `installed` 来自现有的 dsh 候选（`installed_dsh_candidates`），版本号相同即算已装。
- 三个源都失败：`chosen` 给空串，`versions` 给空数组，**照样 200**（读不到不是错误，是一件事），每个源的 error 写清。

## 2 维护页：目标版本怎么填

- 默认走**下拉选择**：列出 `versions`，每条显示版本号 + 标记（`已装` / `最新` / `预发布`），按版本从新到旧。
- 下拉旁给一行小字：`来源：GitHub` / `来源：npm` / `来源：国内镜像`；悬停列出三个源各自的结果与耗时。
- 一个源都没答上来：下拉换成一句 `没问到可选的版本，下面可以手动填`，手填入口照常可用。
- **手填入口一直在**：一个「手动填写版本」的开关，打开就是原来的输入框。选了下拉里的版本时手填框不用出现。

## 3 关于页：安装方式

`GET /api/local/runtime` 增加两格：

- `dshInstallKind`：`"pnpm" | "npm" | "yarn" | "unknown"`
- `dshInstallKindSource`：一句判断依据（给人看，进悬停）

判断只看包目录的路径特征，按顺序命中第一条：

1. 路径里有 `/node_modules/.pnpm/` 或 `/pnpm/global/` → `pnpm`
2. 路径里有 `/yarn/` 或 `/.config/yarn/global/` → `yarn`
3. 路径里有 `/npm-global/` 或 `/lib/node_modules/` 或 `/.npm/` → `npm`
4. 其它 → `unknown`，依据写「按路径认不出是哪个包管理器装的（<路径>）」

关于页版本表加一行：`安装方式`，值 = `pnpm 全局安装` / `npm 全局安装` / `yarn 全局安装` / `未知`；悬停写依据。**不许把这条写死成 pnpm**。

## 4 硬约束

- 网络只准从三个源读版本，不许顺手做别的请求；超时必须真生效（`curl -m 6`）
- 读不到就如实说读不到，不许编版本、不许把「没问到」写成「没有新版」
- 不跑 moon fmt；构建口径照旧；不提交 git；不动 5390；隔离验证用 5391 + 临时 XDG_STATE_HOME
- 验证时不要真的 `pnpm add -g`、不要动任何包目录

## 5 交回

改动清单、构建任务数、三个源的真实探测结果（在本机：GitHub 走代理才通、npm 直连通、国内镜像直连通，照实记录）、`installed` 与本地候选是否一致、关于页那一行在 pnpm 装的这份上的实际显示、手填入口在「三个源全失败」时的表现（用改坏 URL 的方式造）、新增可见文案逐条列出。

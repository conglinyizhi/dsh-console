# dsh-console Phase 0b：profile 层 patch 能不能自己挪 sessions / storages

> 状态：**在 /tmp 隔离环境实测，未改产品代码、未写使用者 home**（2026-10-16）。
> 上游：`dsh-home-phase0-findings.md`（Phase 0 侦察）、`dsh-home-isolation-plan.md` 第七节「便宜的中间态」。
> 侦察对象：本机安装的 `deepseek-ai/dsh@0.2.0-rc.2`。下文 `包名/lib/xxx.js:行` 相对本机 dsh 安装树的 `.pnpm` 目录。

---

## 结论先行

**有条件能。**

每只 profile **自己那份** `<profile>/cordis.patch.yml` 和 home 级 patch 有同样的覆盖力：
`sessions` 与 `storages` 的 root 都能被它指到该 profile 目录下，`DSH_HOME` 完全不用变。
同一机制实测还能挪 `attachments` 与 `credentials`。

三条附带结论，都是**已实测**：

1. **不会冲掉原有配置** ✓ —— 往一份 182 行的**真 patch**（`web-dev`）里加条目，组合结果里只有被点名的行变化，其余一行没动，也没有新增告警。
2. **落点稳定** ✓ —— 同一只 profile 起两次、换两个工作目录，都落在同一个根下；根之下仍按 cwd 分组（`<root>/--<cwd-key>--/<session-id>`）。
3. **它是半价，不是全价** ✗ —— profile 层只能覆盖**有 config 行的东西**。跟着 `dshHomePath` 服务或 `process.env.DSH_HOME` 走的插件状态、`logs/`、`profiles/`、`skills/`、`cache/` 仍然留在共用 home 上。

**对计划的直接含义**：Phase 3 那套「多 home 聚合」**不能整个跳过**（第八节那几样挪不动），
但「让开发 profile 的会话与插件 KV 不落主线」这件事**不用等 Phase 3**，一只 profile 自己加两行就能做到。
建议把第七节从「半价」改写成一张**能/不能清单**，并在 Phase 3 之前插一个 Phase 2.5。

---

## 一、验法与边界

- 隔离环境：`DSH_HOME=/tmp/dsh-phase0b/home`、`XDG_STATE_HOME=/tmp/dsh-phase0b/state`，工作目录 `/tmp/dsh-phase0b/work/{a,b,c}`。**用完已 `rm -rf`**。
- 复制了两只真 profile 过去（原目录只读）：`web-dev`（182 行 patch，带真内容）与 `headless`（4 行，patch 是 `[]`）。
- `web-dev` **只做 `--dump-config`，从未启动**（它是 web-app 型 profile，启动会起服务）。真正落盘的启动全部用 `headless`（`dsh --profile headless "..."`，一次性任务）与它的一个复制体 `headless-ctx`。
- 每次启动都是 `exit=1` + `MISSING_CREDENTIAL`：隔离 home 里没有凭据。**这不影响结论 —— 会话在调模型之前就已经落盘**（与 Phase 0 同）。
- 全程**没有读 `.credentials.yaml` 的内容**，只按路径配置它。
- 5390 上跑着的控制台、`frontend/` 均未触碰。

---

## 二、E1：profile 层确实压过 base 层（组合层证据）

复制体 `profiles/web-dev/cordis.patch.yml` 原样（182 行），先取基线：

```bash
$ DSH_HOME=/tmp/dsh-phase0b/home XDG_STATE_HOME=/tmp/dsh-phase0b/state \
    dsh --profile web-dev --dump-config > dump-before.yml
```

基线里两个根都是 base 层给的值，profile 层没碰：

```
119: - id: session-persistence-jsonl
122:     root: !!js dshHomePath('sessions')
135: - id: storage-json
138:     root: !!js dshHomePath('storages')
```

然后**往这只 profile 自己的 patch 末尾追加**（追加，不是替换文件）：

```yaml
- id: session-persistence-jsonl
  config:
    root: /tmp/dsh-phase0b/home/profiles/web-dev/sessions
- id: storage-json
  config:
    root: /tmp/dsh-phase0b/home/profiles/web-dev/storages
```

再 dump 一次，`diff dump-before.yml dump-after.yml` 的全部输出：

```
119d118
< # == @deepseek-ai/dsh-base
123c122,123
<     root: !!js dshHomePath('sessions')
---
>     root: /tmp/dsh-phase0b/home/profiles/web-dev/sessions
> # == @deepseek-ai/dsh-base
134a135
> # == @deepseek-ai/dsh-base, patched by /tmp/dsh-phase0b/home/profiles/web-dev/cordis.patch.yml
138c139,140
<     root: !!js dshHomePath('storages')
---
>     root: /tmp/dsh-phase0b/home/profiles/web-dev/storages
> # == @deepseek-ai/dsh-base
```

读法：**变化只有两个 root**。那几行 `# == ... patched by ...` 是 dump 自己的分段标记 —— 它会在每个被打补丁的条目处切段，所以标记位置跟着动，不是配置变化。

**stderr 前后逐行相同（`diff` 无输出）**：没有新增「entry not found」之类的告警。

> 说明：复制体里 `@local/*` 与 `dsh-session-manager` 这 7 个 bundle 解析不到（隔离环境没有 `node_modules` 链接），
> 所以它们对应的 6 条 profile 行显示 `entry "..." not found`。这是**复制产物**，与 patch 写法无关；
> 本节要验的两行都在 `deepseek-ai/dsh-base` 里，正常解析。

---

## 三、E2：不会冲掉原有配置（本轮第二问）

E1 的 diff 就是答案，但为了排除「刚好只有两行」的巧合，再追加两条**别的**行，看是不是也只有这两条变：

```yaml
- id: attachment-local
  config:
    dshHome: /tmp/dsh-phase0b/probe-attachments
- id: credentials
  config:
    path: /tmp/dsh-phase0b/probe-creds.yaml
```

`diff dump-after.yml dump-after2.yml` 只多出这两条的 `config` 块（外加 home 级 patch 那几行，原因见第五节），
**没有任何原有条目消失或回退**，stderr 依旧无新增。

**结论**：profile patch 是「顶层条目数组」，加条目就是加条目；
`config` 整体替换的语义只作用在**被同 id 点到的那一条**上，不波及其它。
（这条语义在 `web-dev` 自己的注释里也写着：`config is replaced WHOLESALE, never deep-merged`，
指的是**同一行**里的 config，不是整份 patch 文件。）

---

## 四、E3：落盘证据 —— 会话与状态确实进了 profile 目录

用 `headless` 复制体（patch 从 `[]` 改成两条重定向，root 指到它自己的目录）。

### 4.1 对照组：patch 未改（默认为 home 根）

```bash
$ cd /tmp/dsh-phase0b/work/a
$ DSH_HOME=/tmp/dsh-phase0b/home XDG_STATE_HOME=/tmp/dsh-phase0b/state \
    dsh --profile headless "phase0b control run"
dsh: MISSING_CREDENTIAL: llm-deepseek: ...        （exit=1，会话已落盘）
```

```
/tmp/dsh-phase0b/home/sessions/--tmp-dsh-phase0b-work-a--/session-edfb4f40-.../
    session.v4.jsonl.zstd
/tmp/dsh-phase0b/home/storages/session_projcache/sessions/session-edfb4f40-....json
```

profile 目录**一个字节没多**。这说明后面看到的位移确实是 patch 造成的。

### 4.2 实验组：patch 指到 profile 自己目录

```yaml
- id: session-persistence-jsonl
  config:
    root: /tmp/dsh-phase0b/home/profiles/headless/sessions
- id: storage-json
  config:
    root: /tmp/dsh-phase0b/home/profiles/headless/storages
```

两次启动（cwd 不同）：

```
run2  cwd=/tmp/dsh-phase0b/work/a
  /tmp/dsh-phase0b/home/profiles/headless/sessions/--tmp-dsh-phase0b-work-a--/
      session-f5010756-1955-48c0-acd8-2987e94a3ca8/{session.v4.jsonl.zstd,session.lock}
  /tmp/dsh-phase0b/home/profiles/headless/storages/session_projcache/sessions/
      session-f5010756-1955-48c0-acd8-2987e94a3ca8.json

run3  cwd=/tmp/dsh-phase0b/work/b
  /tmp/dsh-phase0b/home/profiles/headless/sessions/--tmp-dsh-phase0b-work-b--/
      session-418d3523-44a1-43d7-8c6b-13dc8c62c0a3/{session.v4.jsonl.zstd,session.lock}
  /tmp/dsh-phase0b/home/profiles/headless/storages/session_projcache/sessions/
      session-418d3523-44a1-43d7-8c6b-13dc8c62c0a3.json
```

同时 `home/sessions` 与 `home/storages` 里**始终只有对照组那一条**：两次实验的会话没有漏回 home 根。

**结论**：假设成立。profile 层 patch 能把会话与插件 KV 挪进自己的地盘，`DSH_HOME` 不变。

### 4.3 稳定性（本轮第三问）

- 同一只 profile 起两次：同一个根 ✓
- 换工作目录：根不变，根之下按 cwd 新建分组目录 ✓（`--tmp-dsh-phase0b-work-a--` / `--tmp-dsh-phase0b-work-b--` 并列）
- 会话身份因此变成 **`(patch 给的 root, cwd, session-id)`**，与 Phase 0 的 `(DSH_HOME, cwd, session-id)` 同构，只是第一项换了来源。

---

## 五、E4：profile 层与 home 级 patch 的优先级是**逐行**的

在隔离 home 里再放一份 home 级 patch（`$DSH_HOME/cordis.patch.yml`），只重定向 sessions：

```yaml
- id: session-persistence-jsonl
  config:
    root: /tmp/dsh-phase0b/homelevel-sessions
```

此时 profile 层仍然写着 sessions 与 storages 都指向自己目录。从 cwd=work/b 起一次：

```
/tmp/dsh-phase0b/homelevel-sessions/--tmp-dsh-phase0b-work-b--/session-a62d53d8-.../   <- sessions 被 home 层拿走
/tmp/dsh-phase0b/home/profiles/headless/storages/session_projcache/sessions/
      session-a62d53d8-....json                                                  <- storages 仍归 profile 层
```

**同一个进程、同一次启动里两条路各走各的**：被 home 层点到的行归 home 层，没被点到的行照旧沿用 profile 层的值。
优先级是**逐条 patch 行**，不是「整份文件覆盖」。这与 Phase 0 从 `dsh/lib/profile-boot-BZ2ZjNWi.js:193-198` 读到的层序一致（home 层压过 profile 层，`--patch` 最上）。

**要写进计划的注意点**：以后谁在共用 home 上写一条全局 `sessions` 重定向，会把所有 profile 级意图一起吃掉。
反过来，「主线继续共用 home」这句话本身没问题，只要别在 home 层放这两条。

---

## 六、E5：表达式怎么写（三种都行，推荐第三种）

base 层用的是 `!!js dshHomePath('sessions')`。profile 层同样吃 `!!js`，三种写法**实测都能落对地方**：

| 写法 | 实测 | 评价 |
| --- | --- | --- |
| 字面绝对路径 `/tmp/.../profiles/headless/sessions` | ✓ run2/run3 | 最直白，但 home 一挪就断 |
| `!!js dshHomePath('profiles', 'headless', 'sessions')` | ✓ run4 | 跟着 `DSH_HOME` 走，但**写死了 profile 名** |
| `!!js new URL('sessions', ctx.baseUrl).pathname` | ✓ run6b | **profile 相对，名字与 home 都不写死 —— 推荐** |

第三种实测（全新复制体 `headless-ctx`，无 home 级 patch，cwd=work/c）：

```
/tmp/dsh-phase0b/home/profiles/headless-ctx/sessions/--tmp-dsh-phase0b-work-c--/
    session-f3a76d50-2a7b-4989-abaa-2bbf04a62427/session.v4.jsonl.zstd
/tmp/dsh-phase0b/home/profiles/headless-ctx/storages/session_projcache/sessions/
    session-f3a76d50-2a7b-4989-abaa-2bbf04a62427.json
```

为什么能这么写（源码）：

```
@deepseek-ai/dsh-app-boot/lib/index.js:4070
  ctx.baseUrl = pathToFileURL(dirname(absoluteConfigPath)).href + "/";
@deepseek-ai/dsh-app-boot/lib/index.js:4071
  ctx.provide("dshHomePath", dshHomePath);
@deepseek-ai/cordis-plugin-loader/lib/index.js:233-237
  const evaluate = new Function("ctx", "expr", "with (ctx) { return eval(expr) }");
```

`!!js` 是在 loader 上下文里 `with (ctx) { eval(expr) }` 求值的，所以 `ctx` 本身、`ctx.baseUrl`、
以及 `ctx.provide` 上去的 `dshHomePath` 都在作用域里；而 `baseUrl` 就是 profile 目录（配置文件所在目录）。

**推荐第三种的理由**：控制台的「派生 profile」是**复制 patch 文件**的（本机 `web-dev` 的 `.dsh-note.txt` 写着「从 web 派生 · 10-16 15:02 CST」）。
写死名字的写法被复制到新 profile 后，会继续往**老 profile 的目录**里写 —— 静默串味；`ctx.baseUrl` 形式天然跟着新家走。

**验证上的坑**：`--dump-config` **不评估** `!!js`（原样打印），所以想确认表达式求值结果，只能看落盘或起实例，dump 看不出对错。

---

## 七、E6：同一机制还能覆盖什么

在 `web-dev` 复制体上追加（仅 dump，未挂载）：

| 行 id | 配置项 | dump 实测 | 作用 |
| --- | --- | --- | --- |
| `attachment-local` | `dshHome` | ✓ 被替换 | 把会话附件挪走 |
| `credentials` | `path` | ✓ 被替换 | 指回共用那份凭据（Phase 0 Q4 的推荐做法） |

这两条与那两个 root 走的是同一个机制，所以**在 profile 层同样成立**。也就是说第四节的四项都可以由 profile 自己搞定。

---

## 八、E7：profile 层**挪不动**的东西（半价的那一半）

profile 层只能替换**存在的 config 行**。以下要么根本没有配置行，要么数据来自服务/环境变量，profile 层够不着，只能靠 `DSH_HOME`：

| 数据 | 来源 | 为什么挪不动 |
| --- | --- | --- |
| `logs/` | `dsh/lib/bin.js:178` `join(context.home, "logs")` | 无配置行 |
| `profiles/` | `dsh-app-boot/lib/index.js:485,526` | 无配置行（而且它就是 patch 自己的家） |
| `skills/` | `dsh-skill-filesystem/lib/index.js:172` | 无配置行 |
| `cache/`、`.anonymous-user-id` | `dsh-home-paths` / 各自包 | 无配置行 |
| `dsh-session-manager/annotations.v1.json` | 走 Host 服务 `ctx.get("dshHomePath")`（Phase 0 Q5） | 服务派生，不是 config 行 |
| `linxi-modes.json`、`dock/`、`dsh-draw-dream/` 等 | 读 `process.env.DSH_HOME`（Phase 0 Q5） | 同上 |

**所以「DSH_HOME 根本不用变」这句话只对了一半**：会话、插件 KV、附件、凭据不用变；
日志、技能、以及那几个直接写 home 根的插件状态，仍然跟着 `DSH_HOME` 走。
计划第一节列的那几个「想隔离」项里，`linxi-guard-audit.jsonl` / `linxi-guard-directives/` / `dsh-draw-dream/` 这一类**不在便宜方案覆盖范围内**。

---

## 九、对计划文档的修改建议

1. **第七节要改口径**：现在的「半价」太笼统。改成一张明确的**能/不能清单**（本文件第七、八节那两张表可以直接搬），并把结论写成「profile 级隔离能覆盖会话/插件 KV/附件/凭据；不能覆盖日志/技能/直接读 env 的插件状态」。
2. **Phase 3 从「整块」缩成「一小块 + 可选的大块」**：
   - 必做（小）：控制台要能**读出**某只 profile 把状态挪到哪了 —— 读那只 profile 的 `cordis.patch.yml`，或在卡片上加一格「状态根」。否则「这只实例的会话在哪」在 UI 上是空的。
   - 可选（大，取决于目标）：只要目标里有 `logs/`、技能、或那几个 home 根插件目录，多 home 聚合（第四节 1/2/3 条）就还得做。**能不能砍掉 Phase 3，先取决于「隔离范围」要不要包括它们**，这问题得先问使用者，不是技术问题。
   - 已实测的一条便利：控制台 backend **没有**直接枚举 `sessions` 目录（`grep` 整个 `backend/`，只有 `processes/procjoin.mbt:65` 一处用 fd 路径反推 home）。所以「会话被挪走后控制台看不见」这个担心**没有证据**；会话列表的真实来源本轮未追（见第十节）。
3. **第六节建议顺序里插一个 Phase 2.5（便宜）**：给某只开发 profile 加两条重定向并验证落点。配方（推荐写法）：

```yaml
- id: session-persistence-jsonl
  config:
    root: !!js new URL('sessions', ctx.baseUrl).pathname
- id: storage-json
  config:
    root: !!js new URL('storages', ctx.baseUrl).pathname
```

   `attachments` 与 `credentials` 若也要挪，用第七节那两个配置项，其中 `credentials.path` 应指向**共用那份**（Phase 0 Q4：绝不能用符号链接）。
4. **新增一条风险**：home 级 patch 会逐行压过 profile 层（E4）。共用 home 上**不要**放 `sessions`/`storages` 的全局重定向，否则所有 profile 的 profile 级意图一起失效。
5. **第五节第 2 条「凭据不能复制」**维持 Phase 0 的修正口径，本轮无新信息。

---

## 十、未验证 / 存疑（如实列出）

1. **web-app 型 profile 没有真正启动过**。`web-dev` 全程只 `--dump-config`。一次性任务流只在 `headless` 上验过。「web 型 profile 起服务后落点是否同样」属**未验证**，但落点由组合层配置决定，与 app 类型无关，风险低。
2. **控制台会话列表的真实来源未追**。只确认 backend 不直接扫 `sessions` 目录。若会话列表其实由某插件按 `DSH_HOME` 扫盘给出，那么被挪走的会话会在 UI 里消失 —— **这条要在做 Phase 2.5 之前确认**。
3. **复制体缺 `node_modules`**，7 个 `@local/*` bundle 解析不到，dump 里那 6 条 profile 行显示 `not found`。这是复制产物；本轮结论所依赖的两行不受影响。
4. **`--dump-config` 不求值 `!!js`**，所以组合层证据只能证明「行被替换了」，「表达式算出什么」由落盘证据（E3/E5）负责。
5. 使用者 home 的只读核对：`~/.dsh` 下只有 `storages/session_projcache/sessions` 的 mtime 落在实验窗口内 —— 那是 5390 上正在跑的实例自己写的会话缓存，不是本轮探针（所有探针都带 `DSH_HOME=/tmp/dsh-phase0b/home` 启动）。`sessions/`、`profiles/headless`、`.credentials.yaml` 的 mtime 都没动。
6. `.credentials.yaml` 的**内容**全程未读。

---

## 附：本轮的完整命令清单

```bash
# 隔离环境
mkdir -p /tmp/dsh-phase0b/home/profiles /tmp/dsh-phase0b/state /tmp/dsh-phase0b/work/{a,b,c}
cp -a ~/.dsh/profiles/web-dev /tmp/dsh-phase0b/home/profiles/web-dev
cp -a ~/.dsh/profiles/headless /tmp/dsh-phase0b/home/profiles/headless

# E1/E2：组合层（只 dump，不启动）
DSH_HOME=/tmp/dsh-phase0b/home XDG_STATE_HOME=/tmp/dsh-phase0b/state \
  dsh --profile web-dev --dump-config > dump-before.yml
#   ...追加两条重定向...
DSH_HOME=/tmp/dsh-phase0b/home XDG_STATE_HOME=/tmp/dsh-phase0b/state \
  dsh --profile web-dev --dump-config > dump-after.yml

# E3/E4/E5：落盘
cd /tmp/dsh-phase0b/work/a && DSH_HOME=/tmp/dsh-phase0b/home \
  XDG_STATE_HOME=/tmp/dsh-phase0b/state dsh --profile headless "..."
cd /tmp/dsh-phase0b/work/b && ... dsh --profile headless "..."
cd /tmp/dsh-phase0b/work/c && ... dsh --profile headless-ctx "..."

# 收尾
rm -rf /tmp/dsh-phase0b
```

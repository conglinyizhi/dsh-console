# 三处前端改动：首页右栏、复制开发指令、设置页恢复默认

本轮改的是这三件事（都只落在 `frontend/`）：

1. **首页右栏删掉** —— 「工作流入口」两个按钮 + 「关于实例」三行说明那一栏。
   左边那条导航留着（它是唯一的路）。控制器里的「派生开发副本」本来就在行菜单里，
   删掉面板不丢功能；「将插件交回主线实例」只存在这里且从未实现，一并删掉。
2. **行菜单加「复制开发指令」** —— 按下去把一段**给另一个会话**的任务说明写进剪贴板，
   粘到别的 profile 的会话里，让那边的 agent 针对这一只 profile 开发（开发会话与开发对象分开，
   这就是要的隔离）。
3. **设置页去掉那行元信息**（「当前 5000 | 来源 文件 | 缺省 5000」），
   改成：值不等于缺省值时才出现一颗「恢复默认」，缺省值多少收进悬停。

## 一、怎么跑

```bash
# 本目录里的验收探针（一次跑完 A/B/C/D 四组）
node accept.mjs http://127.0.0.1:5390/ ./run

# 仓库原有的整机验收（几何不变量、对话框四条、日志页……）
cd ../../design && node run-acceptance.mjs http://127.0.0.1:5390/ ../frontend/evidence-dev-commands/acc
```

`accept.mjs` 用 CDP 的 `Browser.grantPermissions` 给了剪贴板读写权限，并且开了
`Emulation.setFocusEmulationEnabled` —— 少任何一条，headless 下的 `writeText`/`readText`
都会以 `Document is not focused` 直接拒绝，那量到的是「没聚焦」而不是「没写进去」（真踩过）。

## 二、结果

产物对应关系：

| 文件 | 是什么 |
| --- | --- |
| `run-report.json` | 四组结果全在里面（这份 README 的数字都出自它） |
| `run-A-overview.png` | 首页：右栏没了、单栏铺满 |
| `run-B-menu.png` | 行菜单里「复制开发指令」的位置 |
| `run-C-copy-failed.png` | 剪贴板被打断时的提示条 |
| `run-D1/D2/D3-*.png` | 设置页：默认 / 非默认 / 恢复之后 |
| `run-clipboard.txt` `run-clipboard-profile.txt` | `navigator.clipboard.readText()` 读回来的原文 |
| `run-acceptance.log` `acc-inv.json` | 整机验收的判定表与几何原始读数 |
| `check-final.log` | `./check.sh`（类型检查 + 构建）全量输出 |

### A 首页：面板没了、单栏

```
sidePanelNodes              0      （.dsh-side-info/.dsh-info-card/.dsh-flows/.dsh-flow/.dsh-notes/.dsh-note 全为 0）
sidePanelMarks              0      （[data-name=side-info] / [data-name=workflow-entry] 全为 0）
textHasWorkflowTitle/About   false  （页面上不再出现「工作流入口」「关于实例」「将插件交回主线实例」）
overviewChildren            ["dsh-overview-page"]   ← 只有一个孩子
singleColumn                true
ovRect / pageRect           x=190 w=1090 right=1280（两者逐值相同）
pageRightVsMainContent      0      ← 内容右缘 = 主区内容盒右缘（不再有 260px 那条右栏）
dotXs                       [400,400,400]   dotXsAllEqual true   （状态点跨卡对齐）
actionsDeltas               [0,0,0]         actionsAllZero true  （按钮组右缘贴内容右缘）
overflowX                   false
```

### B 菜单：「复制开发指令」的位置与顺序

| 卡 | 状态 | 菜单项顺序 | 它是第几项 |
| --- | --- | --- | --- |
| web :3080 | running | 在新标签页打开 / 复制访问地址 / **复制开发指令** / —分隔线— / 重命名 / 备注 / 派生开发副本 / —分隔线— / 查看日志 / 打开工作目录 / 编辑配置 | 第 3 项 |
| headless | stopped | 查看日志 / 打开工作目录 / 编辑配置 / **复制开发指令** / —分隔线— / 重命名 / 备注 / 归档 / 删除 | 第 4 项 |
| review-dev | stopped | 同 headless | 第 4 项 |

两种菜单里它都摆在**第一簇（不动本机状态的那一簇）末尾**，分隔线之后才是改名 / 备注 / 派生 /
归档 / 删除这些会真改东西的动作。`data-action="copy-dev"`、`data-name="menu-item"`。

剪贴板回读（`run-clipboard.txt`，从运行中的 `web :3080` 卡复制，profile 名 `web`）：

```
【给另一个会话的插件开发任务】请在你当前这个会话里，针对下面这一只 profile 做开发，不要切进它自己的会话来改。这段说明由 DSH 控制台的「复制开发指令」生成，粘过来直接可用。

开发对象：profile「web」
它在磁盘上的目录：~/.dsh/profiles/web
DSH_HOME：~/.dsh

起它做验证（与在控制台里点这只 profile 的「启动」等价）：
  cd ~/.dsh/profiles/web
  DSH_HOME=~/.dsh dsh --profile web --no-open --port 8400
  （8400 换成任何一个空闲端口都行；控制台自己也是从设置里的端口起点往后找第一个空闲的）

约束（这一条是隔离的全部意义，务必守住）：
1. 只改 ~/.dsh/profiles/web 这一份下的文件；
2. 不要动主线的 profile，也不要动别的 profile，各是各的一份；
3. 改完按上面那条命令把它起一次，确认这一份真能起来。
```

已停止的 profile 卡（`headless`）复制出来的是同一段、只有 profile 名与目录跟着换
（见 `run-clipboard-profile.txt`）—— 命令里那个 8400 是 `instance.basePort` 的缺省起点。

成功的回执走既有那条 toast：`web :3080 的开发指令已写入剪贴板（navigator.clipboard）。`
（`ok=true`，4 秒自己走掉）。

### C 失败路径

把 `navigator.clipboard.writeText` 换成 reject、`document.execCommand` 换成返回 false 之后：

```
noticeBarPresent  true
noticeOk          false
noticeText        web :3080 的开发指令没能写进剪贴板：探针：模拟剪贴板不可用；document.execCommand 也返回 false。
toastPresent      false        ← 失败不走 toast，留在提示条上不许自动消失
```

两条失败原因都带上了，没有「已复制」这种假回执。

### D 设置页

默认那一档（页面上 0 个恢复入口）：

```
metaNodes      0     ← 元信息行（.dsh-setting-meta）已经不存在
resetNodes     0     ← 全页 [data-name=setting-reset] 一个节点都没有
ui.archiveOpenByDefault：value=关  resetCount=0  rowInnerText="归档区默认展开 | | 打开实例总览时，「已归档」分组是否直接展开。 | | 关"
```

改成非默认（点开关，一次 PUT）：

```
value=开  resetCount=1  resetText="恢复默认"  resetTitle="把这一项写回出厂缺省 关"
pageResetNodes=1   rowInnerText="... | | 恢复默认 | 开"
toast: 归档区默认展开 已保存：开
```

点「恢复默认」之后：

```
value=关  resetCount=0  pageResetNodes=0   ← 值回到缺省，入口自己也消失
toast: 归档区默认展开 已保存：关
```

可见文本扫描（`.dsh-settings-page` 的 `innerText`，三个时刻各扫一遍）：

| 时刻 | 字数 | 来源 | 缺省 | 当前 |
| --- | --- | --- | --- | --- |
| 默认 | 238 | 0 | 0 | 0 |
| 非默认（页面上多一颗「恢复默认」） | 97 | 0 | 0 | 0 |
| 恢复之后 | 92 | 0 | 0 | 0 |

「缺省」两个字只剩在悬停里（`title="把这一项写回出厂缺省 关"`），正文不占。

## 三、旁的改动（为了这三件事不半途而废）

- 设置页里另外三处会让那三个词露头的文案一并改了：保存回执去掉「（来源 文件）」、
  下拉里「（当前值，不在候选里）」改成「（这个值不在候选项里）」、接口不在时那句提示
  不再提「缺省值 / 当前值」、日志分组的说明里「日志页的来源下拉」改成「日志页自己写着……」。
- `icons.mbt` 加了 `content-copy`（路径取自同一份 `@mdi/js` 7.4.47，`.sandbox/mdi-js` 那份包里现取的），
  图标表头从 29 改成 30。`frontend/README.md` 里那两处「26 个图标」在改动之前就已经对不上了，这轮没动。
- `design/frontend-parity-checklist.md` 里还把右栏列为待对齐项（那是 `design/` 下的文档，
  本轮按要求只改 `frontend/`，没动）。

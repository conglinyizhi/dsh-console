# 启动实例成功后自动开标页（第六轮，待办队列第 5 条）

使用者原话：「启动某个实验 profile 的时候，我们能通过 webui 来启动新的标签页吗？因为首次握手需要控制台打印的 key」

跑法（控制台已经起在 5390 时）：

    node probe-start-tab.mjs --mode auto    --tag auto       # 真起一只 review-dev：标页自动开且带令牌
    node probe-start-tab.mjs --mode fail    --profile headless --tag fail    # 起不来的 profile：占位标页被关掉
    node probe-start-tab.mjs --mode blocked --tag blocked    # 模拟弹窗拦截：退到方案 B 那颗按钮
    node probe-start-tab.mjs --mode external --tag external  # 外部实例（webUrl 为 null）点「打开 Web UI」

探针用真手势点按钮（Input.dispatchMouseEvent），走浏览器级 CDP endpoint 再
Target.attachToTarget（flatten），控制台页与每一个新标页各是一个会话。
auto / blocked 两个模式会在收尾时把本次新起的实例停掉（只停新出现的端口）。

## 这一轮做了什么

点「启动」的那一枪，在**用户手势的同一个同步栈里**先开一个占位标页
（window.open('', '_blank')，见 frontend/dom.mbt 的 js_tab_hold），
等启动回执与 instances 读数给出带令牌的地址（webUrl）之后，把那个占位页导航过去
（js_tab_goto）。开不成、没地址、被拦，都在提示条里说清，并且不留白页。

为什么不能在响应回来之后再 window.open：启动一只实例要等实例真起来（这一轮实测
bootMs 1.8～3.8 秒），那时用户手势早没了，弹窗拦截器一律拦。占位页必须在点击那一栈里开。

三处状态，各自都要说实话：

| 情况 | 标页 | 提示条 |
| --- | --- | --- |
| 地址到手 | 导航到带令牌的地址 | 「已在启动时自动打开的那个标页里填上带令牌的地址」+ 一颗「打开 Web UI」 |
| 启动失败 | w.close()，不留白页 | 「刚开的那个占位标页已经关掉，不留空白页」 |
| 被拦（window.open 给 null） | 一个标页都不开 | 「浏览器把自动开的标页拦掉了（弹窗拦截），一个标页都没开」+ 一颗「打开 Web UI」 |
| 等不到地址（有界重读 3 轮） | 关掉占位页 | 把后端给的读不到令牌的原因原样写出来 |

方案 B（兜底）落在提示条里那颗「打开 Web UI」：用户再点一下就是新手势，一定开得成。
按钮只在**这条提示对应的地址还在**时出现（notice_url_notice 与当前提示文字一致），
提示条被别的动作改写之后它自动失效。

## 证据怎么读

| 文件 | 是什么 |
| --- | --- |
| auto-result.json | 自动开标页那一趟的全部结构化结果（下面逐条对着它说） |
| auto-auto-tab.png | **自动开出来的那个标页自己**：dsh web 的界面已经加载出来 |
| auto-console.png | 控制台页：提示条里那句「已填上带令牌的地址」+ 那颗「打开 Web UI」 |
| auto-after1s.png | 点击后 1 秒：标页还是占位页（正在启动 review-dev…） |
| fail-result.json / fail-console.png | 起不来的 profile：占位标页被关掉，提示条写清原因 |
| blocked-result.json / blocked-console.png | 模拟被拦那一趟；退到方案 B 的提示条 |
| blocked-fallback-tab.png | 方案 B 那颗按钮开出来的标页（界面加载出来了 = 令牌握手过了） |
| external-result.json / external-console.png | 外部实例（3080，webUrl 为 null）：一个标页都不开，只给原因 |
| acceptance-5390.log | 一键验收的完整输出 |

## 判定表

### 1. 自动开标页（auto）

- 真手势点的是已停止卡 review-dev 上的「启动」（steps.click，x=843.5 y=565.8），
  不是 element.click()。
- 点击后约 150 毫秒里就多了一个 page 目标，openerId 指向控制台页
  （events.targetCreated，t=5474）。
- 那个标页**发出去的第一个文档请求带令牌**：Network.requestWillBeSent t=8738 →
  http://127.0.0.1:8400/?token=YNUVN5lR-h9j0Xm7nmx02auahXNSrLj5zrvRte9wP-Q
  （t=8742 紧跟一条 http://127.0.0.1:8400/，redirectCount: 1 —— dsh web 握完手把
  ?token= 302 掉，所以**后来**地址栏里没有令牌，不等于开的时候没带）。
- 标页自己报的地址与标题：steps.childLocation / steps.childTitle =
  http://127.0.0.1:8400/ / DeepSeek Harness；auto-auto-tab.png 里是它的界面。
- 提示条：steps.final.notice ≈「启动 review-dev：…；已在启动时自动打开的那个标页里
  填上带令牌的地址（能直接过握手，不是 401）。带令牌的地址：http://127.0.0.1:8400/?token=…」，
  hasButton: true。
- 时序（timeline）：t=5498 标页还是 about:blank，t=8932 已经是 http://127.0.0.1:8400/
  且提示条与按钮都在 —— 从点击到地址填好约 3.4 秒，与 bootMs 对得上。
- 控制台页零 console 问题（consoleIssues: []，childConsoleIssues: []）。

### 2. 起不来就不留白页（fail，profile=headless）

- events.targetCreated t=5484 多出占位标页；events.targetDestroyed **t=7997 那个
  targetId 被销毁** —— 这是 w.close() 生效的浏览器级证据（不是界面上的字）。
- 提示条：steps.final.notice 结尾「…要跑这种 profile，按它自己的用法跑一次
  （dsh --profile headless …），别拿它起常驻实例；**刚开的那个占位标页已经关掉，不留空白页**」，
  hasButton: false（没有地址可给，不摆按钮）。fail-console.png 是那一屏。
- 失败原因来自后端原文（spawn-failed：error: unknown option '--no-open'），前端不吞不换。

### 3. 被拦就退到方案 B（blocked）

模拟方法（结果 JSON 的 simulation 里有原文）：

    const real = window.open.bind(window)
    window.open = (...args) => (args[0] === '' ? null : real(...args))

用 Page.addScriptToEvaluateOnNewDocument 装上（页面刷新后仍然生效）+ 当场
Runtime.evaluate 再写一次，然后 Page.reload。**只让「空 URL 那一枪」返回 null**，
其余调用照旧转给真的 window.open —— 不这么分，方案 B 那颗按钮也会一起被换掉，
「点了能开」就成了无从验证的事。探针自己验了模拟生效：
probe: "window.open(空 URL) 现在返回 null"。

判定：

- 从点击（t≈5.4 秒）到点兜底按钮（t≈26.9 秒）之间，events.targetCreated 里
  **一个 page 目标都没有多**（只有控制台页自己）—— 被拦时不开标页。
- 提示条：steps.final.notice ≈「…；浏览器把自动开的标页拦掉了（弹窗拦截），
  一个标页都没开。带令牌的地址：http://127.0.0.1:8401/?token=…」，hasButton: true。
- 那张按钮真的能点开：真手势点它 → events.targetCreated t=26941 多出一个 page 目标，
  openerId 指向控制台页；提示条变成「打开 Web UI：已在新标签页打开带令牌的地址
  （能直接过握手，不是 401）」。
- 那个标页加载出了 dsh web 的界面（blocked-fallback-tab.png），
  steps.fallbackNavigationEntry.redirectCount = 1 —— 握手重定向真的发生过
  （裸地址直接开会是 401 页面，不会有这一次重定向）。
  这一条**没有**录到它第一条文档请求的原始 URL：兜底那一枪是 window.open(url) 直接
  带地址开的，请求比 Network.enable 早，抓不到；auto 那一趟抓到了（见上）。

### 4. 外部实例（external，3080）

- 点运行中卡 web :3080 的「打开 Web UI」：events.targetCreated 里
  **没有新的 page 目标**（列表里只有控制台页自己，t=304 那条）。
- 提示条把原因写全（webUrl 为 null：外部实例，令牌在启动它的终端里；控制台可读的
  文件都没给出带令牌的地址），这正是第 2 条待办定下的口径，本轮无回归。

## 已知边界

- **无头浏览器里标页会抢焦点**，控制台那一页于是变成「看不见的页」，
  requestAnimationFrame 停摆、DOM 不再被 patch —— 界面看着像没反应，其实 model 早改了。
  探针每轮都 Page.bringToFront 才读界面，这是无头环境的口径，不是产品行为：
  真人用的时候切换回控制台标签页，界面就是最新的。
- 等地址是**有界**重读（start_tab_max_tries = 3，间隔 1.2 秒）。实测这一轮第一轮读数
  就拿到了地址；留给慢机器的是「端口先监听、横幅后落盘」那点窗口，等满仍读不到就关标页
  并把后端给的原因写出来。
- 页面刷新会丢掉占位标页的句柄（句柄挂在 window 上），刷新后提示条照旧给出地址与按钮。

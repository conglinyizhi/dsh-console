# rabbita + md2 调用范式速查（从能编译的源码里抽出）

每条都标了出处（都在使用者的 `~/disk/ai_workspace/rabbita-material`，那是**能编译、82 测试全绿**的代码）。
写新前端时**照抄这些形状**，别猜 API —— 猜错的代价是每轮编译修错循环。

## 1. 包配置（可执行 + js 目标）

```moon
import {
  "conglinyizhi/md2",
  "moonbit-community/rabbita",
  "moonbit-community/rabbita/cmd",
  "moonbit-community/rabbita/html",
}

supported_targets = "js"

pkgtype(kind: "executable")
```

出处：`cmd/demo-app/moon.pkg`。注意冒号是 `kind: "executable"`（**不是** `kind = `）。

## 2. 客户端入口

```moon
///|
fn main {
  // mount 收的是**裸 id**，不是 "#md2-app"
  @rabbita.new(view_fn).mount("dsh-console-root")
}
```

出处：`cmd/demo-app/main.mbt` 末尾。

## 3. 类型与状态

```moon
///|
using @rabbita {type Html, type Val}

///|
enum Msg {
  Refresh
  SourceChanged(String)
}

///|
struct Model {
  source : String
  log_lines : Array[String]
}
```

出处：`cmd/demo-app/main.mbt` 开头。`using` 把 `Html` / `Val` 引进作用域，视图函数返回 `Html`。

## 4. 组件调用

```moon
@md2.btn(children=[@html.text("提交")], on_click=emit(Submitted))
@md2.btn(children=[@html.text("重置")], variant=Outlined, on_click=emit(ResetForm))
@md2.checkbox(id="agree-terms", label="同意条款", checked=m.agreed,
              on_change=@cmd.Emit(fn(v) { emit(AgreedChanged(v)) }))
@html.i(class="mdi-check-circle mdi v-icon notranslate", @html.nothing)
```

出处：`cmd/demo-app/main.mbt`。要点：

- 子节点用 `children=[...]`，文本要包 `@html.text("...")`
- `variant` 是枚举（`Outlined` 等），直接裸写名字
- 无事件处理器的地方传 `@html.nothing`
- 带参数的处理器包一层：`@cmd.Emit(fn(v) { emit(Msg(v)) })`

## 5. HTML 原语

```moon
@html.div(class="md2-form-actions", [ ... ])
@html.p(class="md2-form-error", m.agreed_error)
@html.i(class="mdi-dots-horizontal mdi v-icon", @html.nothing)
```

## 6. 视图里的条件渲染

```moon
if m.result.length() > 0 {
  @html.div(class="md2-form-result", [ ... ])
} else {
  @html.nothing
}
```

出处：同上。用 `@html.nothing` 占位，不要漏掉 `else` 分支。

## 7. 图标（MDI）

类名规则是 `mdi-<名字> mdi v-icon`（有时加 `notranslate`）。字形来自 vendor 的
`materialdesignicons.min.css` + `webfont.woff2`。

**用之前先确认名字存在**：md2 那边查过 `mdi-more-horiz` **不存在**，对应的是
`mdi-dots-horizontal`。在 `vendor/mdi/css/materialdesignicons.min.css` 里按子串搜一遍再写。

## 8. 模块名带连字符时的 import 别名

```moon
import {
  "conglinyizhi/moonbit-llm-faceoff" @faceoff,
}
```

出处：`~/disk/ai_workspace/moonbit-llm-faceoff`（模块名也是带连字符的）。
本工程模块名是 `conglinyizhi/dsh-console-frontend`，根包别名按同一套规则走。

## 8.5 环境税：别把大段代码内联进 `run_code` 的 TS 字符串

在这个环境里写 MoonBit，最容易反复交的税是**宿主语言（TS）和嵌入语言（MoonBit/bash/SCSS）的语法打架**。实测过三种：

1. **MoonBit 的插值 `\{var}`** 写在 TS 模板串里会被 JS 吃掉反斜杠（`"\{var}"` 等于 `"{var}"`），
   于是插值被写成字面量。**要写 `\\{var}`**。
2. **整个程序解析失败**（`Identifier cannot follow number` / `Expected ident`）——
   嵌进去的内容里有让 TS 解析器误判的序列，报错行号还指向无关的地方，极难定位。
3. 于是就有了**二分排查**：一轮轮试哪一段炸的，每轮都是一次模型往返。**这是纯浪费。**

**做法**：要写超过十几行的脚本或源码，**先用 `write` 工具落成文件，再用 `bash` 执行**，
不要在 `run_code` 里内联一大段字符串。本项目里 `design/probe-*.mjs`、`dsh-console-design/*.mjs`
都是这么来的——**一次就位，不用跟转义纠缠**。

## 9. 数据获取与副作用

见 `rabbita/http`（`Request::expect_json[T : FromJson]`）与 `rabbita/cmd`
（`@cmd.perform` / `@cmd.effect` / `@cmd.batch`），JSON 用 `moonbitlang/core/json`
的 `Json` / `parse` 与 `derive(FromJson)`。

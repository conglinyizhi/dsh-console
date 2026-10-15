// dsh-console 前端：rabbita（js 目标）+ precss 样式层。
//
// 没有组件库依赖：卡片、按钮、图标都是我们自己的 —— 样式在 styles/app.scss，
// 图标在 icons.mbt（内联 SVG，路径取自 @mdi/js 7.4.47 后固化）。
//
// preferred_target = "js" 的理由见 README.md「目标平台为什么是 js」。
// 一句话：前端产物是静态文件，由已有的 native 后端同端口服务；浏览器里
// 跑 rabbita 才有运行期（能自己 fetch 只读接口），native 那一侧已经被后端占了。

name = "conglinyizhi/dsh-console-frontend"

version = "0.1.0"

readme = "README.md"

license = "Apache-2.0"

keywords = [ "dsh", "console", "rabbita", "precss" ]

description = "dsh-console 前端：rabbita + precss"

preferred_target = "js"

supported_targets = "js+native"

import {
  "conglinyizhi/precss@0.1.4",
  "moonbit-community/rabbita@0.15.7",
  // 浏览器那一侧不用它：app.mbt 里的 `async fn` 是 MoonBit 的语言语法，不是这个包。
  // 但 cmd/build-styles 要（@fs 读写 SCSS 与产物），而它就在本模块里。
  // 试过删掉：moon 报「Import moonbitlang/async@0.21.2 … its containing module
  // is not imported by conglinyizhi/dsh-console-frontend … cannot be imported by
  // its package 'cmd/build-styles'」。所以留着。
  "moonbitlang/async@0.21.2",
}

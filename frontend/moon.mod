// dsh-console 前端：rabbita（js 目标）+ md2 组件库 + precss 样式层。
//
// preferred_target = "js" 的理由见 README.md「目标平台为什么是 js」。
// 一句话：前端产物是静态文件，由已有的 native 后端同端口服务；浏览器里
// 跑 rabbita 才有运行期（能自己 fetch 只读接口），native 那一侧已经被后端占了。

name = "conglinyizhi/dsh-console-frontend"

version = "0.1.0"

readme = "README.md"

license = "Apache-2.0"

keywords = [ "dsh", "console", "rabbita", "md2", "precss" ]

description = "dsh-console 前端（垂直切片）：rabbita + md2 + precss"

preferred_target = "js"

supported_targets = "js+native"

import {
  "conglinyizhi/md2@0.1.0",
  "conglinyizhi/precss@0.1.4",
  "moonbit-community/rabbita@0.15.7",
  "moonbitlang/async@0.21.2",
}

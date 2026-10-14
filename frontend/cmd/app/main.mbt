// 浏览器入口：把根包里的页面挂到 #dsh-console-root 上。
//
// mount 收的是**裸 id**，不是 "#dsh-console-root"（md2 的 demo-app 踩过同一个坑）。

///|
fn main {
  @rabbita.new(@frontend.app).mount("dsh-console-root")
}

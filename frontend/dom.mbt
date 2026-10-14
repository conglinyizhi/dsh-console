// 浏览器侧的几处副作用：焦点、滚动、时间格式化、端口探测。
//
// 全部走 extern "js"。rabbita 的 dom 包能表达这些，但这里每个都只是一行脚本，
// 直接 FFI 比引一整个包直白；本包只出 js 产物（moon.pkg 里写死了 supported_targets）。

///|
/// 按 id 聚焦。找不到就什么都不做（元素可能已经随列表卸载 —— 例如删掉的那一行）。
extern "js" fn js_focus_id(id : String) -> Unit =
  #| id => { const el = document.getElementById(id); if (el && typeof el.focus === 'function') el.focus(); }

///|
/// 聚焦并全选：重命名框打开时预填当前名并整段选中。
extern "js" fn js_focus_select_id(id : String) -> Unit =
  #| id => {
  #|   const el = document.getElementById(id);
  #|   if (!el) return;
  #|   el.focus();
  #|   if (typeof el.select === 'function') el.select();
  #| }

///|
/// 滚到底：日志区打开与切来源都要看到最新的一行。
extern "js" fn js_scroll_bottom_id(id : String) -> Unit =
  #| id => { const el = document.getElementById(id); if (el) el.scrollTop = el.scrollHeight; }

///|
/// 查询串编码，与 Vue 版的 encodeURIComponent 同一口径。
extern "js" fn js_encode_uri_component(text : String) -> String =
  #| text => encodeURIComponent(text)

///|
/// ISO 时刻 → 卡片上的短格式（10-13 22:50）。解析不出来给空串，界面据此写「—」。
extern "js" fn js_short_time(iso : String) -> String =
  #| iso => {
  #|   const d = new Date(iso);
  #|   if (isNaN(d.getTime())) return '';
  #|   const p = (n) => String(n).padStart(2, '0');
  #|   return p(d.getMonth() + 1) + '-' + p(d.getDate()) + ' ' + p(d.getHours()) + ':' + p(d.getMinutes());
  #| }

///|
/// 派生副本时的端口探测（前端演示动作的一部分：只发 no-cors 请求探活，不改任何真实进程）。
/// resolve 说明对端有东西在应答 → 占用；reject（拒绝连接 / 超时）→ 这一次没听到应答。
extern "js" fn js_probe_port_busy(port : Int) -> @js.Promise =
  #| port => fetch('http://127.0.0.1:' + port + '/', { mode: 'no-cors', signal: AbortSignal.timeout(600) })
  #|   .then(() => true, () => false)

///|
/// 渲染完成之后再聚焦：菜单打开要落到第一项，关闭要把焦点还给触发元素。
/// 用 AfterRender 时机，否则 DOM 还没打补丁，query 到的是上一帧的节点。
fn focus_after_render(id : String) -> @cmd.Cmd {
  @cmd.custom_cmd(fn(_scheduler) { js_focus_id(id) }, kind=@cmd.after_render)
}

///|
fn focus_select_after_render(id : String) -> @cmd.Cmd {
  @cmd.custom_cmd(fn(_scheduler) { js_focus_select_id(id) }, kind=@cmd.after_render)
}

///|
/// 容器里的第一个匹配元素落焦：菜单打开要落到第一项。
extern "js" fn js_focus_first_in(container_id : String, selector : String) -> Unit =
  #| (id, sel) => {
  #|   const root = document.getElementById(id);
  #|   if (!root) return;
  #|   const el = root.querySelector(sel);
  #|   if (el && typeof el.focus === 'function') el.focus();
  #| }

///|
fn focus_first_after_render(container_id : String, selector : String) -> @cmd.Cmd {
  @cmd.custom_cmd(fn(_scheduler) { js_focus_first_in(container_id, selector) }, kind=@cmd.after_render)
}

///|
fn scroll_bottom_after_render(id : String) -> @cmd.Cmd {
  @cmd.custom_cmd(fn(_scheduler) { js_scroll_bottom_id(id) }, kind=@cmd.after_render)
}

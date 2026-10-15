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
/// 聚焦并把光标推到文末：备注框打开时预填当前备注，要接着改而不是整段覆盖。
/// 与 js_focus_select_id 相对：那个是全选（重命名要改名），这个是落在末尾（备注是接着写）。
extern "js" fn js_focus_end_id(id : String) -> Unit =
  #| id => {
  #|   const el = document.getElementById(id);
  #|   if (!el) return;
  #|   el.focus();
  #|   const n = typeof el.value === 'string' ? el.value.length : 0;
  #|   if (typeof el.setSelectionRange === 'function') el.setSelectionRange(n, n);
  #| }

///|
/// 滚到底：日志区打开与切来源都要看到最新的一行。
extern "js" fn js_scroll_bottom_id(id : String) -> Unit =
  #| id => { const el = document.getElementById(id); if (el) el.scrollTop = el.scrollHeight; }

///|
/// 把控件上的值写回 DOM。用在「保存失败要把草稿退回去」这一处：
/// 只靠 vdom 的 value 属性未必会落到真实节点上（用户改过的值是直接写在 DOM 上的，
/// 而 diff 只比上一次渲染的属性），所以失败之后显式写一次，控件上不会留着没保存的数。
extern "js" fn js_set_control_value(id : String, value : String) -> Unit =
  #| (id, value) => { const el = document.getElementById(id); if (el && 'value' in el) el.value = value; }

///|
fn set_control_after_render(id : String, value : String) -> @cmd.Cmd {
  @cmd.custom_cmd(fn(_scheduler) { js_set_control_value(id, value) }, kind=@cmd.after_render)
}

///|
/// 新标签页打开一个地址，回一句结局：'ok' / 'blocked' / 'error: …'。
///
/// 为什么要回结局：带令牌的地址是这一轮的重点，而「点开了没有」不许猜 ——
/// 浏览器拦弹窗时 window.open 给 null（被拦和没被拦长得一样，只有返回值能分）。
/// 不用 window.open(url, '_blank', 'noopener')：那样返回值恒为 null，
/// 「被拦了」与「开了」就分不出来了；改成开完再把 opener 抹掉。
extern "js" fn js_open_url(url : String) -> String =
  #| url => {
  #|   try {
  #|     const w = window.open(url, '_blank')
  #|     if (!w) return 'blocked'
  #|     try { w.opener = null } catch (e) {}
  #|     return 'ok'
  #|   } catch (e) {
  #|     return 'error: ' + String((e && e.message) || e)
  #|   }
  #| }

///|
/// 写剪贴板，回一段 JSON：{ ok, how, error }。
///
/// 先 navigator.clipboard（唯一「知道成没成」的正路：它 reject 就说得出原因），
/// 它不在或拒了就退到 execCommand 那条老路 —— 两条都失败时如实回 ok:false，
/// **不假装复制成功**（提示条上那句「已复制」必须对应真写进去的东西）。
extern "js" fn js_copy_text(text : String) -> @js.Promise =
  #| text => (async () => {
  #|   let clipboardError = ''
  #|   try {
  #|     if (navigator.clipboard && navigator.clipboard.writeText) {
  #|       await navigator.clipboard.writeText(text)
  #|       return JSON.stringify({ ok: true, how: 'navigator.clipboard' })
  #|     }
  #|     clipboardError = '这个环境里没有 navigator.clipboard'
  #|   } catch (e) {
  #|     clipboardError = String((e && e.message) || e)
  #|   }
  #|   try {
  #|     const ta = document.createElement('textarea')
  #|     ta.value = text
  #|     ta.setAttribute('readonly', '')
  #|     ta.style.position = 'fixed'
  #|     ta.style.top = '-1000px'
  #|     document.body.appendChild(ta)
  #|     ta.select()
  #|     const ok = document.execCommand('copy')
  #|     document.body.removeChild(ta)
  #|     if (ok) return JSON.stringify({ ok: true, how: 'document.execCommand' })
  #|     return JSON.stringify({ ok: false, how: '', error: clipboardError + '；document.execCommand 也返回 false' })
  #|   } catch (e) {
  #|     return JSON.stringify({
  #|       ok: false, how: '',
  #|       error: clipboardError + '；' + String((e && e.message) || e),
  #|     })
  #|   }
  #| })()

///|
/// 复制这一枪：回执走 CopyDone（成功与失败都要有话说，不吞）。
fn copy_cmd(
  label : String,
  text : String,
  emit : @cmd.Emit[Msg],
) -> @cmd.Cmd {
  @cmd.attempt(
    fn(res : Result[String, Error]) { emit(CopyDone(label, res)) },
    async fn() {
      let text : String = js_copy_text(text).wait().cast()
      text
    },
  )
}

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
fn focus_end_after_render(id : String) -> @cmd.Cmd {
  @cmd.custom_cmd(fn(_scheduler) { js_focus_end_id(id) }, kind=@cmd.after_render)
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

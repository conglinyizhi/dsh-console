// 浏览器本地时刻。
//
// 页脚「读于 <时刻>」在 Vue 版里是 `new Date().toLocaleTimeString()` —— 读数落地的
// 那一刻，用浏览器自己的时钟。这里取同一个读数来源，不从响应的 readAt 反推：
// readAt 是服务端的 UTC，反推要时区，而时区在浏览器里才有权威值。
//
// 本包 supported_targets = "js"，所以这处 extern 不会挡住别的目标。

///|
/// HH:MM:SS（24 小时制，本地时区）。
pub extern "js" fn local_time_now() -> String = "() => { const d = new Date(); const p = (n) => String(n).padStart(2, '0'); return p(d.getHours()) + ':' + p(d.getMinutes()) + ':' + p(d.getSeconds()); }"

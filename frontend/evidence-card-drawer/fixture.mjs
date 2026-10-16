// 契约第七轮那三个新字段（state / stateReason / profileHealth）的**参考实现**：
// 只给探针用，不碰 dsh-console/backend/。
//
// 为什么要有这一份：后端那三个字段由另一路并行实现，还没落地。前端按契约实现好了，
// 但「三色实测」得有数据可测 —— 所以这里在**浏览器这一侧**把 instances 响应包一层，
// 按契约的判据补上那三个字段（真数据一个字节都没改，只是加了新字段）。
// 补完的响应形状与契约第七轮第一节逐字段对齐，前端的解析路径因此被真跑过。
//
// 绿的来源：3080 那只真实例（签名探测真的通过了）。
// 黄的成因 b 的来源：本机真起一个「端口在听、cmdline 像 dsh、签名探测不通过」的进程。
// 黄的成因 c 与红的来源：真实 profile 读数（缺包 / 不缺包）——那两条不需要新字段。

import { spawn } from 'node:child_process'
import { writeFileSync } from 'node:fs'

/// 起一个**假的 dsh**：端口真在听，cmdline 真写着 dsh 的入口路径，但 HTTP 应答不是 dsh 签名。
/// 这正是契约里「黄 · 成因 b」的样子；现在的后端不列这种端口（第七轮要改的就是这条）。
export function startFakeDsh(port, pidFile) {
  const fake = '~/.local/share/pnpm/global/v11/499c6f07a790dd7f679cefbbb26ef27a4ada938b7769be3aeb15c04209a68b61/node_modules/@deepseek-ai/dsh/lib/bin.js'
  const script = "require('http').createServer((q,s)=>{s.writeHead(200,{'content-type':'text/plain'});s.end('not a dsh signature')}).listen(" + port + ")"
  // exec -a：argv[0] 写成 dsh 的入口路径。/proc/<pid>/cmdline 因此看起来就是一只 dsh 进程。
  const proc = spawn('/bin/bash', ['-c', 'exec -a ' + JSON.stringify('node ' + fake + ' web --port ' + port) + ' /usr/bin/node -e ' + JSON.stringify(script)], {
    stdio: 'ignore', detached: false,
  })
  if (pidFile) writeFileSync(pidFile, String(proc.pid))
  return proc
}

/// 往实例响应里补契约字段的注入源（Page.addScriptToEvaluateOnNewDocument 用）。
/// spec 形如 { byPort: { "3080": { state, stateReason, profileHealth? } }, extra: [ {...实例对象} ] }
export function instancesPatchSource(spec) {
  return `(() => {
  const SPEC = ${JSON.stringify(spec)};
  const origFetch = window.fetch.bind(window);
  window.fetch = async (input, init) => {
    const url = typeof input === 'string' ? input : (input && input.url) || '';
    const res = await origFetch(input, init);
    if (!url.includes('/api/local/instances')) return res;
    let j;
    try { j = await res.clone().json() } catch (e) { return res }
    const items = (j && j.data && j.data.instances) || [];
    for (const it of items) {
      const s = SPEC.byPort[String(it.port)];
      if (!s) continue;
      if (s.state !== undefined) it.state = s.state;
      if (s.stateReason !== undefined) it.stateReason = s.stateReason;
      if (s.profileHealth !== undefined) it.profileHealth = s.profileHealth;
    }
    for (const extra of SPEC.extra || []) items.push(extra);
    return new Response(JSON.stringify(j), {
      status: res.status, statusText: res.statusText,
      headers: { 'content-type': 'application/json' },
    });
  };
})();`
}

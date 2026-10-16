// 「条目三样各就各位」这一轮的四情况 fixture。
//
// 为什么要 fixture：本机真实存在的组合里少了**「运行中 + 有备注」**这一种 ——
// 唯一带备注的 profile（headless）当时没有在跑；而要给一只真在跑的 profile 写一条备注，
// 就得往使用者的 profile 目录里落文件（不许碰）。所以这一种只能在浏览器这一侧造出来。
//
// 造了什么、哪些是真读数，逐条说清：
//   * 运行中 + 无备注：真实例 3080（profile web，无备注）—— **原样**
//   * 已停止 + 有备注：真 profile headless —— **原样**（备注「测试测试」读自它自己的目录）
//   * 已停止 + 无备注：真 profile review-dev —— **原样**
//   * 运行中 + 有备注：**造的一条实例行 + 一只造的 profile**。实例行的字段照抄真实例
//     3080 那一行，只改 id / port / url / profile；profile 指向造的「fx-run-note」，
//     它的备注文本与来源照抄 headless 的（"测试测试" / "文件"）。
//     所以卡上那两行备注**内容一模一样**，差异只在状态 —— 正是要对照的那一点。
//     端口 41545 也是编的（本机没有在听它），它只作为右上角那一格的字。
//
// 注入点在 window.fetch 上（页面脚本之前装上），只换 instances / profiles 两份读数，
// 其余接口（console / logs / processes）一律放行 —— 页面仍然是真页面、真渲染路径。

/// 用两份真读数（GET /api/local/instances 与 /profiles 的 data）拼出四情况 spec。
export function fourCaseFixture(instancesData, profilesData) {
  const real = instancesData.instances || []
  const base = real.find((i) => i.profile) || real[0]
  if (!base) throw new Error('真读数里一条实例都没有，拼不出「运行中」那两行')
  const headless = (profilesData.profiles || []).find((p) => p.name === 'headless' && p.note)
  if (!headless) throw new Error('真读数里没有带备注的 profile（headless），拼不出「有备注」那两行')

  // 造的那只 profile：字段照抄 headless，只换 name / dir
  const fakeProfile = Object.assign({}, headless, {
    name: 'fx-run-note',
    dir: '~/.dsh/profiles/fx-run-note',
    isCurrent: false,
    dirMtimeSource: '桩 fixture：这一只 profile 是造的（运行中 + 有备注那一路），不指向磁盘上的任何目录',
  })
  // 造的那条实例行：字段照抄真实例，只换 id / port / url / profile
  const fakeInstance = Object.assign({}, base, {
    id: 'proc-41545',
    port: 41545,
    url: 'http://127.0.0.1:41545/',
    profile: 'fx-run-note',
    state: 'running',
    stateReason: '桩 fixture：把一只带备注的 profile 摆成运行中的实例行 —— 本机真实组合里没有这一种',
    signature: { id: 'dsh-auth-401', describe: '桩 fixture：签名那一栏照抄真实例', evidence: 'fixture' },
  })

  return {
    instances: [base, fakeInstance],
    profiles: [fakeProfile].concat(profilesData.profiles || []),
    _note: 'instances[1] 与 profiles[0]（fx-run-note）是造的，其余是真读数',
  }
}

/// 把 spec 装进页面：只改 /api/local/instances 与 /api/local/profiles 两份响应的 data。
export function fixtureSource(spec) {
  return `(() => {
  const SPEC = ${JSON.stringify(spec)};
  const origFetch = window.fetch.bind(window);
  async function withBody(res, over) {
    let j;
    try { j = await res.clone().json() } catch (e) { return res }
    if (!j || !j.data) return res;
    Object.assign(j.data, over);
    return new Response(JSON.stringify(j), {
      status: res.status, statusText: res.statusText,
      headers: { 'content-type': 'application/json' },
    });
  }
  window.fetch = async (input, init) => {
    const url = typeof input === 'string' ? input : (input && input.url) || '';
    const res = await origFetch(input, init);
    if (url.includes('/api/local/instances')) return withBody(res, { instances: SPEC.instances });
    if (url.includes('/api/local/profiles')) return withBody(res, { profiles: SPEC.profiles });
    return res;
  };
})();`
}

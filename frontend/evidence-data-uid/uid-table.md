# 语义路径 → uid 对照表（实测，`accept-data-uid.mjs`）

同一状态刷新两次各抓一遍，路径与 uid 逐一对应。取任意一个 uid，
在表里查到的那一行就是它：角色（data-name）+ 限定（哪张卡 / 哪个框 / 自己的键）。

## 初始页（实例总览）（132 个元素）

| data-name（角色） | 限定（是哪一个） | data-uid | 元素 | 文本样例 |
| --- | --- | --- | --- | --- |
| `side-nav` | — | `psintiol` | aside | DSH 控制台实例总览日志设置关于本 |
| `nav-overview` | — | `wgisl1kv` | button | 实例总览 |
| `nav-logs` | — | `naxovvpn` | button | 日志 |
| `nav-settings` | — | `m72eapcx` | button | 设置 |
| `nav-about` | — | `uiuwfiyw` | button | 关于 |
| `overview-page` | — | `64s1c0on` | div | 实例总览真实数据菜单里的动作走 PO |
| `source-badge` | — | `8wau1c09` | span | 真实数据 |
| `new-instance` | — | `7lipfsbu` | button | ＋新建实例 |
| `section-title` | — | `zl8g5sbj` | h2 | 当前运行的实例 (1) |
| `source-badge` | — | `i478edtj` | span | 真实数据 |
| `instance-card` | 卡片 web | `38hhruar` | div | web :3080本机监听的 dsh |
| `card-name` | 卡片 web | `3mvsupwm` | span | web :3080 |
| `sub-line` | 卡片 web | `mt1hrwue` | div | 本机监听的 dsh 实例运行中已运行 |
| `sub-kind` | 卡片 web | `uzemkqnc` | span | 本机监听的 dsh 实例 |
| `status-dot` | 卡片 web | `5g85qamy` | span |  |
| `sub-state` | 卡片 web | `tu2meziy` | span | 运行中 |
| `sub-uptime` | 卡片 web | `4c2r00wc` | span | 已运行 9 小时 35 分钟 |
| `port-note` | 卡片 web | `lzts978i` | span | 缺 3 个包：@deepseek-a |
| `open-web-ui` | 卡片 web | `et9ch8vc` | button | 打开 Web UI |
| `stop` | 卡片 web | `c1dfucbp` | button | 停止 |
| `restart` | 卡片 web | `5nmvfpef` | button | 重启 |
| `menu-trigger` | 卡片 web | `2w6gczwr` | button |  |
| `card-field` | 卡片 web | `rh2ae69b` | li | DSH 版本 / 来源0.2.0-r |
| `field-label` | 卡片 web | `s4sqc0ic` | span | DSH 版本 / 来源 |
| `field-value` | 卡片 web | `sdk41prz` | span | 0.2.0-rc.2（入口包） |
| `card-field` | 卡片 web | `ip2wffvw` | li | Profileweb |
| `field-label` | 卡片 web | `ux13u3fn` | span | Profile |
| `field-value` | 卡片 web | `z1ssmn1k` | span | web |
| `card-field` | 卡片 web | `6rdfx3zc` | li | 访问地址http://127.0.0 |
| `field-label` | 卡片 web | `yrdz3tbj` | span | 访问地址 |
| `field-value` | 卡片 web | `zch7tzu4` | span | http://127.0.0.1:3 |
| `card-field` | 卡片 web | `r83iml89` | li | DSH_HOME/home/clyz |
| `field-label` | 卡片 web | `espkbgqa` | span | DSH_HOME |
| `field-value` | 卡片 web | `7e306nnx` | span | ~/.dsh |
| `card-field` | 卡片 web | `6s1wvdpf` | li | 插件数量声明 13 · 已装 10 |
| `field-label` | 卡片 web | `b3wr2r3c` | span | 插件数量 |
| `field-value` | 卡片 web | `ucd0ir2z` | span | 声明 13 · 已装 10 |
| `card-field` | 卡片 web | `lbb52eq5` | li | 最近改动10-15 13:24 |
| `field-label` | 卡片 web | `maq879uu` | span | 最近改动 |
| `field-value` | 卡片 web | `p2gjr8cp` | span | 10-15 13:24 |
| `section-title` | — | `nbgatsyx` | h2 | 已停止的实例 (3) |
| `source-badge` | — | `hsv3ns45` | span | 真实数据 |
| `instance-card` | 卡片 web-dev | `oik6nbmu` | div | web-dev本地 profile已 |
| `card-name` | 卡片 web-dev | `f1c4ogo5` | span | web-dev |
| `sub-line` | 卡片 web-dev | `xutwe5zh` | div | 本地 profile已停止cordi |
| `sub-kind` | 卡片 web-dev | `li4pcf7l` | span | 本地 profile |
| `status-dot` | 卡片 web-dev | `yphoujw1` | span |  |
| `sub-state` | 卡片 web-dev | `k5syc8vx` | span | 已停止 |
| `sub-uptime` | 卡片 web-dev | `kncfhmqd` | span | cordis.patch.yml 1 |
| `port-note` | 卡片 web-dev | `iwsyku8b` | span | 缺 11 个包：@deepseek- |
| `start` | 卡片 web-dev | `sy8tftrv` | button | 启动 |
| `restart` | 卡片 web-dev | `8x8apiai` | button | 重启 |
| `menu-trigger` | 卡片 web-dev | `yoehocfs` | button |  |
| `card-field` | 卡片 web-dev | `t6h54myq` | li | DSH 版本 / 来源0.2.0-r |
| `field-label` | 卡片 web-dev | `avy2vy65` | span | DSH 版本 / 来源 |
| `field-value` | 卡片 web-dev | `yct09x0q` | span | 0.2.0-rc.2（本机已安装） |
| `card-field` | 卡片 web-dev | `vio1dlrd` | li | Profileweb-dev |
| `field-label` | 卡片 web-dev | `33mm3w6a` | span | Profile |
| `field-value` | 卡片 web-dev | `sz4hc9bx` | span | web-dev |
| `card-field` | 卡片 web-dev | `w0jdcftt` | li | 访问地址已停用，无法访问 |
| `field-label` | 卡片 web-dev | `e46ce2fu` | span | 访问地址 |
| `field-value` | 卡片 web-dev | `c8vd9ecl` | span | 已停用，无法访问 |
| `card-field` | 卡片 web-dev | `pu95nuim` | li | DSH_HOME/home/clyz |
| `field-label` | 卡片 web-dev | `wjkhubqh` | span | DSH_HOME |
| `field-value` | 卡片 web-dev | `lnftyjce` | span | ~/.dsh |
| `card-field` | 卡片 web-dev | `x2yuqay4` | li | 插件数量声明 13 · 已装 2 |
| `field-label` | 卡片 web-dev | `h8i6mh43` | span | 插件数量 |
| `field-value` | 卡片 web-dev | `1vszc0a0` | span | 声明 13 · 已装 2 |
| `card-field` | 卡片 web-dev | `n3tvalto` | li | 最近改动10-15 18:50 |
| `field-label` | 卡片 web-dev | `f8svqmyb` | span | 最近改动 |
| `field-value` | 卡片 web-dev | `6kgbb7js` | span | 10-15 18:50 |
| `instance-card` | 卡片 review-dev | `6alh2f4j` | div | review-dev本地 profi |
| `card-name` | 卡片 review-dev | `uao96y5y` | span | review-dev |
| `sub-line` | 卡片 review-dev | `91fnzx3q` | div | 本地 profile已停止cordi |
| `sub-kind` | 卡片 review-dev | `w2biryu0` | span | 本地 profile |
| `status-dot` | 卡片 review-dev | `sgozq3d6` | span |  |
| `sub-state` | 卡片 review-dev | `3xya93nu` | span | 已停止 |
| `sub-uptime` | 卡片 review-dev | `gscj1n30` | span | cordis.patch.yml 1 |
| `port-note` | 卡片 review-dev | `vd0w30tu` | span | 缺 3 个包：@deepseek-a |
| `start` | 卡片 review-dev | `vnn86ol6` | button | 启动 |
| `restart` | 卡片 review-dev | `1pokuw9z` | button | 重启 |
| `menu-trigger` | 卡片 review-dev | `5scvmr8b` | button |  |
| `card-field` | 卡片 review-dev | `kr8gr673` | li | DSH 版本 / 来源0.2.0-r |
| `field-label` | 卡片 review-dev | `mrp6qjb8` | span | DSH 版本 / 来源 |
| `field-value` | 卡片 review-dev | `zjsj2u7j` | span | 0.2.0-rc.2（本机已安装） |
| `card-field` | 卡片 review-dev | `iv1tjjz0` | li | Profilereview-dev |
| `field-label` | 卡片 review-dev | `ang8r1eb` | span | Profile |
| `field-value` | 卡片 review-dev | `a3a6la8o` | span | review-dev |
| `card-field` | 卡片 review-dev | `4a4y032w` | li | 访问地址已停用，无法访问 |
| `field-label` | 卡片 review-dev | `74kkybj3` | span | 访问地址 |
| `field-value` | 卡片 review-dev | `se0hnsws` | span | 已停用，无法访问 |
| `card-field` | 卡片 review-dev | `b7l66xc9` | li | DSH_HOME/home/clyz |
| `field-label` | 卡片 review-dev | `orah2shu` | span | DSH_HOME |
| `field-value` | 卡片 review-dev | `dkm7iov1` | span | ~/.dsh |
| `card-field` | 卡片 review-dev | `ee898q7n` | li | 插件数量声明 15 · 已装 12 |
| `field-label` | 卡片 review-dev | `l7rw0qyg` | span | 插件数量 |
| `field-value` | 卡片 review-dev | `t70b2cvf` | span | 声明 15 · 已装 12 |
| `card-field` | 卡片 review-dev | `ald5k9zx` | li | 最近改动10-15 16:16 |
| `field-label` | 卡片 review-dev | `uy1ws8ja` | span | 最近改动 |
| `field-value` | 卡片 review-dev | `d0d77h21` | span | 10-15 16:16 |
| `instance-card` | 卡片 headless | `56dajw30` | div | headless本地 profile |
| `card-name` | 卡片 headless | `42rjxdej` | span | headless |
| `sub-line` | 卡片 headless | `rstvp2k3` | div | 本地 profile已停止cordi |
| `sub-kind` | 卡片 headless | `z8id3t03` | span | 本地 profile |
| `status-dot` | 卡片 headless | `hjmhlqrr` | span |  |
| `sub-state` | 卡片 headless | `1j9ku31j` | span | 已停止 |
| `sub-uptime` | 卡片 headless | `j5fp35nf` | span | cordis.patch.yml 4 |
| `start` | 卡片 headless | `dmp4gap5` | button | 启动 |
| `restart` | 卡片 headless | `odjh9zso` | button | 重启 |
| `menu-trigger` | 卡片 headless | `4sh0p2w6` | button |  |
| `card-field` | 卡片 headless | `usfybzxs` | li | DSH 版本 / 来源0.2.0-r |
| `field-label` | 卡片 headless | `81t6dohj` | span | DSH 版本 / 来源 |
| `field-value` | 卡片 headless | `y9gmlan8` | span | 0.2.0-rc.2（本机已安装） |
| `card-field` | 卡片 headless | `uinmulvf` | li | Profileheadless |
| `field-label` | 卡片 headless | `ylj4eqqo` | span | Profile |
| `field-value` | 卡片 headless | `aiiwqvnn` | span | headless |
| `card-field` | 卡片 headless | `kd6m398r` | li | 访问地址已停用，无法访问 |
| `field-label` | 卡片 headless | `zo8uxnxs` | span | 访问地址 |
| `field-value` | 卡片 headless | `wy4hoq37` | span | 已停用，无法访问 |
| `card-field` | 卡片 headless | `jleacxm8` | li | DSH_HOME/home/clyz |
| `field-label` | 卡片 headless | `t6ma3liv` | span | DSH_HOME |
| `field-value` | 卡片 headless | `ic3liqw4` | span | ~/.dsh |
| `card-field` | 卡片 headless | `iny05v3y` | li | 插件数量声明 2 · 已装 2 |
| `field-label` | 卡片 headless | `r6tcpmcp` | span | 插件数量 |
| `field-value` | 卡片 headless | `gaoottym` | span | 声明 2 · 已装 2 |
| `card-field` | 卡片 headless | `suevhn5i` | li | 最近改动10-15 16:13 |
| `field-label` | 卡片 headless | `zdkr8735` | span | 最近改动 |
| `field-value` | 卡片 headless | `js2hrvva` | span | 10-15 16:13 |
| `archived-toggle` | — | `7k4ofpqh` | button | 已归档 (1) |
| `side-info` | — | `1nqb7zbn` | aside | 工作流入口从当前实例派生开发副本派生 |
| `workflow-entry` | — | `l6ienh4d` | button | 从当前实例派生开发副本派生隔离副本， |
| `workflow-entry` | — | `ovqtv21c` | button | 将插件交回主线实例把插件提交回稳定实 |

## 展开行菜单（141 个元素）

| data-name（角色） | 限定（是哪一个） | data-uid | 元素 | 文本样例 |
| --- | --- | --- | --- | --- |
| `side-nav` | — | `psintiol` | aside | DSH 控制台实例总览日志设置关于本 |
| `nav-overview` | — | `wgisl1kv` | button | 实例总览 |
| `nav-logs` | — | `naxovvpn` | button | 日志 |
| `nav-settings` | — | `m72eapcx` | button | 设置 |
| `nav-about` | — | `uiuwfiyw` | button | 关于 |
| `overview-page` | — | `64s1c0on` | div | 实例总览真实数据菜单里的动作走 PO |
| `source-badge` | — | `8wau1c09` | span | 真实数据 |
| `new-instance` | — | `7lipfsbu` | button | ＋新建实例 |
| `section-title` | — | `zl8g5sbj` | h2 | 当前运行的实例 (1) |
| `source-badge` | — | `i478edtj` | span | 真实数据 |
| `instance-card` | 卡片 web | `38hhruar` | div | web :3080本机监听的 dsh |
| `card-name` | 卡片 web | `3mvsupwm` | span | web :3080 |
| `sub-line` | 卡片 web | `mt1hrwue` | div | 本机监听的 dsh 实例运行中已运行 |
| `sub-kind` | 卡片 web | `uzemkqnc` | span | 本机监听的 dsh 实例 |
| `status-dot` | 卡片 web | `5g85qamy` | span |  |
| `sub-state` | 卡片 web | `tu2meziy` | span | 运行中 |
| `sub-uptime` | 卡片 web | `4c2r00wc` | span | 已运行 9 小时 35 分钟 |
| `port-note` | 卡片 web | `lzts978i` | span | 缺 3 个包：@deepseek-a |
| `open-web-ui` | 卡片 web | `et9ch8vc` | button | 打开 Web UI |
| `stop` | 卡片 web | `c1dfucbp` | button | 停止 |
| `restart` | 卡片 web | `5nmvfpef` | button | 重启 |
| `menu-trigger` | 卡片 web | `2w6gczwr` | button |  |
| `card-field` | 卡片 web | `rh2ae69b` | li | DSH 版本 / 来源0.2.0-r |
| `field-label` | 卡片 web | `s4sqc0ic` | span | DSH 版本 / 来源 |
| `field-value` | 卡片 web | `sdk41prz` | span | 0.2.0-rc.2（入口包） |
| `card-field` | 卡片 web | `ip2wffvw` | li | Profileweb |
| `field-label` | 卡片 web | `ux13u3fn` | span | Profile |
| `field-value` | 卡片 web | `z1ssmn1k` | span | web |
| `card-field` | 卡片 web | `6rdfx3zc` | li | 访问地址http://127.0.0 |
| `field-label` | 卡片 web | `yrdz3tbj` | span | 访问地址 |
| `field-value` | 卡片 web | `zch7tzu4` | span | http://127.0.0.1:3 |
| `card-field` | 卡片 web | `r83iml89` | li | DSH_HOME/home/clyz |
| `field-label` | 卡片 web | `espkbgqa` | span | DSH_HOME |
| `field-value` | 卡片 web | `7e306nnx` | span | ~/.dsh |
| `card-field` | 卡片 web | `6s1wvdpf` | li | 插件数量声明 13 · 已装 10 |
| `field-label` | 卡片 web | `b3wr2r3c` | span | 插件数量 |
| `field-value` | 卡片 web | `ucd0ir2z` | span | 声明 13 · 已装 10 |
| `card-field` | 卡片 web | `lbb52eq5` | li | 最近改动10-15 13:24 |
| `field-label` | 卡片 web | `maq879uu` | span | 最近改动 |
| `field-value` | 卡片 web | `p2gjr8cp` | span | 10-15 13:24 |
| `section-title` | — | `nbgatsyx` | h2 | 已停止的实例 (3) |
| `source-badge` | — | `hsv3ns45` | span | 真实数据 |
| `instance-card` | 卡片 web-dev | `oik6nbmu` | div | web-dev本地 profile已 |
| `card-name` | 卡片 web-dev | `f1c4ogo5` | span | web-dev |
| `sub-line` | 卡片 web-dev | `xutwe5zh` | div | 本地 profile已停止cordi |
| `sub-kind` | 卡片 web-dev | `li4pcf7l` | span | 本地 profile |
| `status-dot` | 卡片 web-dev | `yphoujw1` | span |  |
| `sub-state` | 卡片 web-dev | `k5syc8vx` | span | 已停止 |
| `sub-uptime` | 卡片 web-dev | `kncfhmqd` | span | cordis.patch.yml 1 |
| `port-note` | 卡片 web-dev | `iwsyku8b` | span | 缺 11 个包：@deepseek- |
| `start` | 卡片 web-dev | `sy8tftrv` | button | 启动 |
| `restart` | 卡片 web-dev | `8x8apiai` | button | 重启 |
| `menu-trigger` | 卡片 web-dev | `yoehocfs` | button |  |
| `row-menu` | 卡片 web-dev | `n8no9gza` | div | 查看日志打开工作目录编辑配置重命名编 |
| `menu-item` | 卡片 web-dev | `l2xms5l1` | button | 查看日志 |
| `menu-item` | 卡片 web-dev | `0aajyjme` | button | 打开工作目录 |
| `menu-item` | 卡片 web-dev | `cq79vv06` | button | 编辑配置 |
| `menu-item` | 卡片 web-dev | `poy0hryy` | button | 重命名 |
| `menu-item` | 卡片 web-dev | `a9iwtgyi` | button | 编辑备注 |
| `menu-item` | 卡片 web-dev | `x6j8skpf` | button | 归档 |
| `menu-item` | 卡片 web-dev | `crb4qsoz` | button | 删除 |
| `menu-overlay` | 卡片 web-dev | `pbo910cc` | div |  |
| `card-field` | 卡片 web-dev | `t6h54myq` | li | DSH 版本 / 来源0.2.0-r |
| `field-label` | 卡片 web-dev | `avy2vy65` | span | DSH 版本 / 来源 |
| `field-value` | 卡片 web-dev | `yct09x0q` | span | 0.2.0-rc.2（本机已安装） |
| `card-field` | 卡片 web-dev | `vio1dlrd` | li | Profileweb-dev |
| `field-label` | 卡片 web-dev | `33mm3w6a` | span | Profile |
| `field-value` | 卡片 web-dev | `sz4hc9bx` | span | web-dev |
| `card-field` | 卡片 web-dev | `w0jdcftt` | li | 访问地址已停用，无法访问 |
| `field-label` | 卡片 web-dev | `e46ce2fu` | span | 访问地址 |
| `field-value` | 卡片 web-dev | `c8vd9ecl` | span | 已停用，无法访问 |
| `card-field` | 卡片 web-dev | `pu95nuim` | li | DSH_HOME/home/clyz |
| `field-label` | 卡片 web-dev | `wjkhubqh` | span | DSH_HOME |
| `field-value` | 卡片 web-dev | `lnftyjce` | span | ~/.dsh |
| `card-field` | 卡片 web-dev | `x2yuqay4` | li | 插件数量声明 13 · 已装 2 |
| `field-label` | 卡片 web-dev | `h8i6mh43` | span | 插件数量 |
| `field-value` | 卡片 web-dev | `1vszc0a0` | span | 声明 13 · 已装 2 |
| `card-field` | 卡片 web-dev | `n3tvalto` | li | 最近改动10-15 18:50 |
| `field-label` | 卡片 web-dev | `f8svqmyb` | span | 最近改动 |
| `field-value` | 卡片 web-dev | `6kgbb7js` | span | 10-15 18:50 |
| `instance-card` | 卡片 review-dev | `6alh2f4j` | div | review-dev本地 profi |
| `card-name` | 卡片 review-dev | `uao96y5y` | span | review-dev |
| `sub-line` | 卡片 review-dev | `91fnzx3q` | div | 本地 profile已停止cordi |
| `sub-kind` | 卡片 review-dev | `w2biryu0` | span | 本地 profile |
| `status-dot` | 卡片 review-dev | `sgozq3d6` | span |  |
| `sub-state` | 卡片 review-dev | `3xya93nu` | span | 已停止 |
| `sub-uptime` | 卡片 review-dev | `gscj1n30` | span | cordis.patch.yml 1 |
| `port-note` | 卡片 review-dev | `vd0w30tu` | span | 缺 3 个包：@deepseek-a |
| `start` | 卡片 review-dev | `vnn86ol6` | button | 启动 |
| `restart` | 卡片 review-dev | `1pokuw9z` | button | 重启 |
| `menu-trigger` | 卡片 review-dev | `5scvmr8b` | button |  |
| `card-field` | 卡片 review-dev | `kr8gr673` | li | DSH 版本 / 来源0.2.0-r |
| `field-label` | 卡片 review-dev | `mrp6qjb8` | span | DSH 版本 / 来源 |
| `field-value` | 卡片 review-dev | `zjsj2u7j` | span | 0.2.0-rc.2（本机已安装） |
| `card-field` | 卡片 review-dev | `iv1tjjz0` | li | Profilereview-dev |
| `field-label` | 卡片 review-dev | `ang8r1eb` | span | Profile |
| `field-value` | 卡片 review-dev | `a3a6la8o` | span | review-dev |
| `card-field` | 卡片 review-dev | `4a4y032w` | li | 访问地址已停用，无法访问 |
| `field-label` | 卡片 review-dev | `74kkybj3` | span | 访问地址 |
| `field-value` | 卡片 review-dev | `se0hnsws` | span | 已停用，无法访问 |
| `card-field` | 卡片 review-dev | `b7l66xc9` | li | DSH_HOME/home/clyz |
| `field-label` | 卡片 review-dev | `orah2shu` | span | DSH_HOME |
| `field-value` | 卡片 review-dev | `dkm7iov1` | span | ~/.dsh |
| `card-field` | 卡片 review-dev | `ee898q7n` | li | 插件数量声明 15 · 已装 12 |
| `field-label` | 卡片 review-dev | `l7rw0qyg` | span | 插件数量 |
| `field-value` | 卡片 review-dev | `t70b2cvf` | span | 声明 15 · 已装 12 |
| `card-field` | 卡片 review-dev | `ald5k9zx` | li | 最近改动10-15 16:16 |
| `field-label` | 卡片 review-dev | `uy1ws8ja` | span | 最近改动 |
| `field-value` | 卡片 review-dev | `d0d77h21` | span | 10-15 16:16 |
| `instance-card` | 卡片 headless | `56dajw30` | div | headless本地 profile |
| `card-name` | 卡片 headless | `42rjxdej` | span | headless |
| `sub-line` | 卡片 headless | `rstvp2k3` | div | 本地 profile已停止cordi |
| `sub-kind` | 卡片 headless | `z8id3t03` | span | 本地 profile |
| `status-dot` | 卡片 headless | `hjmhlqrr` | span |  |
| `sub-state` | 卡片 headless | `1j9ku31j` | span | 已停止 |
| `sub-uptime` | 卡片 headless | `j5fp35nf` | span | cordis.patch.yml 4 |
| `start` | 卡片 headless | `dmp4gap5` | button | 启动 |
| `restart` | 卡片 headless | `odjh9zso` | button | 重启 |
| `menu-trigger` | 卡片 headless | `4sh0p2w6` | button |  |
| `card-field` | 卡片 headless | `usfybzxs` | li | DSH 版本 / 来源0.2.0-r |
| `field-label` | 卡片 headless | `81t6dohj` | span | DSH 版本 / 来源 |
| `field-value` | 卡片 headless | `y9gmlan8` | span | 0.2.0-rc.2（本机已安装） |
| `card-field` | 卡片 headless | `uinmulvf` | li | Profileheadless |
| `field-label` | 卡片 headless | `ylj4eqqo` | span | Profile |
| `field-value` | 卡片 headless | `aiiwqvnn` | span | headless |
| `card-field` | 卡片 headless | `kd6m398r` | li | 访问地址已停用，无法访问 |
| `field-label` | 卡片 headless | `zo8uxnxs` | span | 访问地址 |
| `field-value` | 卡片 headless | `wy4hoq37` | span | 已停用，无法访问 |
| `card-field` | 卡片 headless | `jleacxm8` | li | DSH_HOME/home/clyz |
| `field-label` | 卡片 headless | `t6ma3liv` | span | DSH_HOME |
| `field-value` | 卡片 headless | `ic3liqw4` | span | ~/.dsh |
| `card-field` | 卡片 headless | `iny05v3y` | li | 插件数量声明 2 · 已装 2 |
| `field-label` | 卡片 headless | `r6tcpmcp` | span | 插件数量 |
| `field-value` | 卡片 headless | `gaoottym` | span | 声明 2 · 已装 2 |
| `card-field` | 卡片 headless | `suevhn5i` | li | 最近改动10-15 16:13 |
| `field-label` | 卡片 headless | `zdkr8735` | span | 最近改动 |
| `field-value` | 卡片 headless | `js2hrvva` | span | 10-15 16:13 |
| `archived-toggle` | — | `7k4ofpqh` | button | 已归档 (1) |
| `side-info` | — | `1nqb7zbn` | aside | 工作流入口从当前实例派生开发副本派生 |
| `workflow-entry` | — | `l6ienh4d` | button | 从当前实例派生开发副本派生隔离副本， |
| `workflow-entry` | — | `ovqtv21c` | button | 将插件交回主线实例把插件提交回稳定实 |

## 打开对话框（重命名）（138 个元素）

| data-name（角色） | 限定（是哪一个） | data-uid | 元素 | 文本样例 |
| --- | --- | --- | --- | --- |
| `side-nav` | — | `psintiol` | aside | DSH 控制台实例总览日志设置关于本 |
| `nav-overview` | — | `wgisl1kv` | button | 实例总览 |
| `nav-logs` | — | `naxovvpn` | button | 日志 |
| `nav-settings` | — | `m72eapcx` | button | 设置 |
| `nav-about` | — | `uiuwfiyw` | button | 关于 |
| `overview-page` | — | `64s1c0on` | div | 实例总览真实数据菜单里的动作走 PO |
| `source-badge` | — | `8wau1c09` | span | 真实数据 |
| `new-instance` | — | `7lipfsbu` | button | ＋新建实例 |
| `section-title` | — | `zl8g5sbj` | h2 | 当前运行的实例 (1) |
| `source-badge` | — | `i478edtj` | span | 真实数据 |
| `instance-card` | 卡片 web | `38hhruar` | div | web :3080本机监听的 dsh |
| `card-name` | 卡片 web | `3mvsupwm` | span | web :3080 |
| `sub-line` | 卡片 web | `mt1hrwue` | div | 本机监听的 dsh 实例运行中已运行 |
| `sub-kind` | 卡片 web | `uzemkqnc` | span | 本机监听的 dsh 实例 |
| `status-dot` | 卡片 web | `5g85qamy` | span |  |
| `sub-state` | 卡片 web | `tu2meziy` | span | 运行中 |
| `sub-uptime` | 卡片 web | `4c2r00wc` | span | 已运行 9 小时 35 分钟 |
| `port-note` | 卡片 web | `lzts978i` | span | 缺 3 个包：@deepseek-a |
| `open-web-ui` | 卡片 web | `et9ch8vc` | button | 打开 Web UI |
| `stop` | 卡片 web | `c1dfucbp` | button | 停止 |
| `restart` | 卡片 web | `5nmvfpef` | button | 重启 |
| `menu-trigger` | 卡片 web | `2w6gczwr` | button |  |
| `card-field` | 卡片 web | `rh2ae69b` | li | DSH 版本 / 来源0.2.0-r |
| `field-label` | 卡片 web | `s4sqc0ic` | span | DSH 版本 / 来源 |
| `field-value` | 卡片 web | `sdk41prz` | span | 0.2.0-rc.2（入口包） |
| `card-field` | 卡片 web | `ip2wffvw` | li | Profileweb |
| `field-label` | 卡片 web | `ux13u3fn` | span | Profile |
| `field-value` | 卡片 web | `z1ssmn1k` | span | web |
| `card-field` | 卡片 web | `6rdfx3zc` | li | 访问地址http://127.0.0 |
| `field-label` | 卡片 web | `yrdz3tbj` | span | 访问地址 |
| `field-value` | 卡片 web | `zch7tzu4` | span | http://127.0.0.1:3 |
| `card-field` | 卡片 web | `r83iml89` | li | DSH_HOME/home/clyz |
| `field-label` | 卡片 web | `espkbgqa` | span | DSH_HOME |
| `field-value` | 卡片 web | `7e306nnx` | span | ~/.dsh |
| `card-field` | 卡片 web | `6s1wvdpf` | li | 插件数量声明 13 · 已装 10 |
| `field-label` | 卡片 web | `b3wr2r3c` | span | 插件数量 |
| `field-value` | 卡片 web | `ucd0ir2z` | span | 声明 13 · 已装 10 |
| `card-field` | 卡片 web | `lbb52eq5` | li | 最近改动10-15 13:24 |
| `field-label` | 卡片 web | `maq879uu` | span | 最近改动 |
| `field-value` | 卡片 web | `p2gjr8cp` | span | 10-15 13:24 |
| `section-title` | — | `nbgatsyx` | h2 | 已停止的实例 (3) |
| `source-badge` | — | `hsv3ns45` | span | 真实数据 |
| `instance-card` | 卡片 web-dev | `oik6nbmu` | div | web-dev本地 profile已 |
| `card-name` | 卡片 web-dev | `f1c4ogo5` | span | web-dev |
| `sub-line` | 卡片 web-dev | `xutwe5zh` | div | 本地 profile已停止cordi |
| `sub-kind` | 卡片 web-dev | `li4pcf7l` | span | 本地 profile |
| `status-dot` | 卡片 web-dev | `yphoujw1` | span |  |
| `sub-state` | 卡片 web-dev | `k5syc8vx` | span | 已停止 |
| `sub-uptime` | 卡片 web-dev | `kncfhmqd` | span | cordis.patch.yml 1 |
| `port-note` | 卡片 web-dev | `iwsyku8b` | span | 缺 11 个包：@deepseek- |
| `start` | 卡片 web-dev | `sy8tftrv` | button | 启动 |
| `restart` | 卡片 web-dev | `8x8apiai` | button | 重启 |
| `menu-trigger` | 卡片 web-dev | `yoehocfs` | button |  |
| `card-field` | 卡片 web-dev | `t6h54myq` | li | DSH 版本 / 来源0.2.0-r |
| `field-label` | 卡片 web-dev | `avy2vy65` | span | DSH 版本 / 来源 |
| `field-value` | 卡片 web-dev | `yct09x0q` | span | 0.2.0-rc.2（本机已安装） |
| `card-field` | 卡片 web-dev | `vio1dlrd` | li | Profileweb-dev |
| `field-label` | 卡片 web-dev | `33mm3w6a` | span | Profile |
| `field-value` | 卡片 web-dev | `sz4hc9bx` | span | web-dev |
| `card-field` | 卡片 web-dev | `w0jdcftt` | li | 访问地址已停用，无法访问 |
| `field-label` | 卡片 web-dev | `e46ce2fu` | span | 访问地址 |
| `field-value` | 卡片 web-dev | `c8vd9ecl` | span | 已停用，无法访问 |
| `card-field` | 卡片 web-dev | `pu95nuim` | li | DSH_HOME/home/clyz |
| `field-label` | 卡片 web-dev | `wjkhubqh` | span | DSH_HOME |
| `field-value` | 卡片 web-dev | `lnftyjce` | span | ~/.dsh |
| `card-field` | 卡片 web-dev | `x2yuqay4` | li | 插件数量声明 13 · 已装 2 |
| `field-label` | 卡片 web-dev | `h8i6mh43` | span | 插件数量 |
| `field-value` | 卡片 web-dev | `1vszc0a0` | span | 声明 13 · 已装 2 |
| `card-field` | 卡片 web-dev | `n3tvalto` | li | 最近改动10-15 18:50 |
| `field-label` | 卡片 web-dev | `f8svqmyb` | span | 最近改动 |
| `field-value` | 卡片 web-dev | `6kgbb7js` | span | 10-15 18:50 |
| `instance-card` | 卡片 review-dev | `6alh2f4j` | div | review-dev本地 profi |
| `card-name` | 卡片 review-dev | `uao96y5y` | span | review-dev |
| `sub-line` | 卡片 review-dev | `91fnzx3q` | div | 本地 profile已停止cordi |
| `sub-kind` | 卡片 review-dev | `w2biryu0` | span | 本地 profile |
| `status-dot` | 卡片 review-dev | `sgozq3d6` | span |  |
| `sub-state` | 卡片 review-dev | `3xya93nu` | span | 已停止 |
| `sub-uptime` | 卡片 review-dev | `gscj1n30` | span | cordis.patch.yml 1 |
| `port-note` | 卡片 review-dev | `vd0w30tu` | span | 缺 3 个包：@deepseek-a |
| `start` | 卡片 review-dev | `vnn86ol6` | button | 启动 |
| `restart` | 卡片 review-dev | `1pokuw9z` | button | 重启 |
| `menu-trigger` | 卡片 review-dev | `5scvmr8b` | button |  |
| `card-field` | 卡片 review-dev | `kr8gr673` | li | DSH 版本 / 来源0.2.0-r |
| `field-label` | 卡片 review-dev | `mrp6qjb8` | span | DSH 版本 / 来源 |
| `field-value` | 卡片 review-dev | `zjsj2u7j` | span | 0.2.0-rc.2（本机已安装） |
| `card-field` | 卡片 review-dev | `iv1tjjz0` | li | Profilereview-dev |
| `field-label` | 卡片 review-dev | `ang8r1eb` | span | Profile |
| `field-value` | 卡片 review-dev | `a3a6la8o` | span | review-dev |
| `card-field` | 卡片 review-dev | `4a4y032w` | li | 访问地址已停用，无法访问 |
| `field-label` | 卡片 review-dev | `74kkybj3` | span | 访问地址 |
| `field-value` | 卡片 review-dev | `se0hnsws` | span | 已停用，无法访问 |
| `card-field` | 卡片 review-dev | `b7l66xc9` | li | DSH_HOME/home/clyz |
| `field-label` | 卡片 review-dev | `orah2shu` | span | DSH_HOME |
| `field-value` | 卡片 review-dev | `dkm7iov1` | span | ~/.dsh |
| `card-field` | 卡片 review-dev | `ee898q7n` | li | 插件数量声明 15 · 已装 12 |
| `field-label` | 卡片 review-dev | `l7rw0qyg` | span | 插件数量 |
| `field-value` | 卡片 review-dev | `t70b2cvf` | span | 声明 15 · 已装 12 |
| `card-field` | 卡片 review-dev | `ald5k9zx` | li | 最近改动10-15 16:16 |
| `field-label` | 卡片 review-dev | `uy1ws8ja` | span | 最近改动 |
| `field-value` | 卡片 review-dev | `d0d77h21` | span | 10-15 16:16 |
| `instance-card` | 卡片 headless | `56dajw30` | div | headless本地 profile |
| `card-name` | 卡片 headless | `42rjxdej` | span | headless |
| `sub-line` | 卡片 headless | `rstvp2k3` | div | 本地 profile已停止cordi |
| `sub-kind` | 卡片 headless | `z8id3t03` | span | 本地 profile |
| `status-dot` | 卡片 headless | `hjmhlqrr` | span |  |
| `sub-state` | 卡片 headless | `1j9ku31j` | span | 已停止 |
| `sub-uptime` | 卡片 headless | `j5fp35nf` | span | cordis.patch.yml 4 |
| `start` | 卡片 headless | `dmp4gap5` | button | 启动 |
| `restart` | 卡片 headless | `odjh9zso` | button | 重启 |
| `menu-trigger` | 卡片 headless | `4sh0p2w6` | button |  |
| `card-field` | 卡片 headless | `usfybzxs` | li | DSH 版本 / 来源0.2.0-r |
| `field-label` | 卡片 headless | `81t6dohj` | span | DSH 版本 / 来源 |
| `field-value` | 卡片 headless | `y9gmlan8` | span | 0.2.0-rc.2（本机已安装） |
| `card-field` | 卡片 headless | `uinmulvf` | li | Profileheadless |
| `field-label` | 卡片 headless | `ylj4eqqo` | span | Profile |
| `field-value` | 卡片 headless | `aiiwqvnn` | span | headless |
| `card-field` | 卡片 headless | `kd6m398r` | li | 访问地址已停用，无法访问 |
| `field-label` | 卡片 headless | `zo8uxnxs` | span | 访问地址 |
| `field-value` | 卡片 headless | `wy4hoq37` | span | 已停用，无法访问 |
| `card-field` | 卡片 headless | `jleacxm8` | li | DSH_HOME/home/clyz |
| `field-label` | 卡片 headless | `t6ma3liv` | span | DSH_HOME |
| `field-value` | 卡片 headless | `ic3liqw4` | span | ~/.dsh |
| `card-field` | 卡片 headless | `iny05v3y` | li | 插件数量声明 2 · 已装 2 |
| `field-label` | 卡片 headless | `r6tcpmcp` | span | 插件数量 |
| `field-value` | 卡片 headless | `gaoottym` | span | 声明 2 · 已装 2 |
| `card-field` | 卡片 headless | `suevhn5i` | li | 最近改动10-15 16:13 |
| `field-label` | 卡片 headless | `zdkr8735` | span | 最近改动 |
| `field-value` | 卡片 headless | `js2hrvva` | span | 10-15 16:13 |
| `archived-toggle` | — | `7k4ofpqh` | button | 已归档 (1) |
| `side-info` | — | `1nqb7zbn` | aside | 工作流入口从当前实例派生开发副本派生 |
| `workflow-entry` | — | `l6ienh4d` | button | 从当前实例派生开发副本派生隔离副本， |
| `workflow-entry` | — | `ovqtv21c` | button | 将插件交回主线实例把插件提交回稳定实 |
| `rename-dialog-scrim` | — | `vumu3fru` | div |  |
| `rename-dialog` | 对话框 rename-dialog | `eautne2p` | div | 重命名实例 web-dev确定取消 |
| `dialog-title` | 对话框 rename-dialog | `nh0s417u` | h2 | 重命名实例 web-dev |
| `rename-input` | 对话框 rename-dialog | `yyyonoio` | input |  |
| `dialog-ok` | 对话框 rename-dialog | `06p5av3f` | button | 确定 |
| `dialog-cancel` | 对话框 rename-dialog | `836np62j` | button | 取消 |

## 设置页（35 个元素）

| data-name（角色） | 限定（是哪一个） | data-uid | 元素 | 文本样例 |
| --- | --- | --- | --- | --- |
| `side-nav` | — | `psintiol` | aside | DSH 控制台实例总览日志设置关于本 |
| `nav-overview` | — | `wgisl1kv` | button | 实例总览 |
| `nav-logs` | — | `naxovvpn` | button | 日志 |
| `nav-settings` | — | `m72eapcx` | button | 设置 |
| `nav-about` | — | `uiuwfiyw` | button | 关于 |
| `settings-page` | — | `vy479vpt` | section | 设置真实数据改动即保存。实例与端口4 |
| `source-badge` | — | `0lv13e4b` | span | 真实数据 |
| `settings-note` | — | `00g65vpy` | p | 改动即保存。 |
| `settings-index` | — | `ymb6dxoj` | aside | 实例与端口4进程2日志1界面1危险动 |
| `settings-tab` | instance | `y91orgwp` | button | 实例与端口4 |
| `settings-tab` | process | `evd3msbg` | button | 进程2 |
| `settings-tab` | logs | `v7mno3a9` | button | 日志1 |
| `settings-tab` | ui | `tr4fr6ea` | button | 界面1 |
| `settings-tab` | safety | `g5uvbdkq` | button | 危险动作1 |
| `settings-panel` | — | `gs4poxql` | div | 实例与端口起实例时的端口起点，以及每 |
| `setting-row` | instance.basePort | `b78ln22l` | div | 启动端口起点启动 / 派生实例时，从 |
| `setting-name` | — | `iio7j98g` | span | 启动端口起点 |
| `setting-desc` | — | `sqwc6f86` | p | 启动 / 派生实例时，从这个端口开始 |
| `setting-meta` | — | `mxnxe0ue` | div | 当前 8400·来源 文件·缺省 8 |
| `setting-input` | — | `4qoktlp8` | input |  |
| `setting-row` | probe.timeoutMs | `zr7irs7h` | div | 签名探测超时探测一个候选端口时等应答 |
| `setting-name` | — | `jcqhg46o` | span | 签名探测超时 |
| `setting-desc` | — | `73d0hrc6` | p | 探测一个候选端口时等应答的上限（毫秒 |
| `setting-meta` | — | `oxyq42hi` | div | 当前 500·来源 文件·缺省 50 |
| `setting-input` | — | `xzhkkz4c` | input |  |
| `setting-row` | probe.concurrency | `xyjd0o8j` | div | 探测并发同时探测多少个候选端口。调大 |
| `setting-name` | — | `6apqk7rq` | span | 探测并发 |
| `setting-desc` | — | `zegbhhyo` | p | 同时探测多少个候选端口。调大扫得快， |
| `setting-meta` | — | `hlp12o6g` | div | 当前 8·来源 文件·缺省 8 |
| `setting-input` | — | `kg6xjq2u` | input |  |
| `setting-row` | probe.maxCandidates | `t8owpaie` | div | 候选端口上限一次扫描最多探测多少个本 |
| `setting-name` | — | `fqonlpsl` | span | 候选端口上限 |
| `setting-desc` | — | `z1336d93` | p | 一次扫描最多探测多少个本机 loop |
| `setting-meta` | — | `wce7ezbf` | div | 当前 40·来源 文件·缺省 40 |
| `setting-input` | — | `8ww6k4fj` | input |  |

## 日志页（16 个元素）

| data-name（角色） | 限定（是哪一个） | data-uid | 元素 | 文本样例 |
| --- | --- | --- | --- | --- |
| `side-nav` | — | `psintiol` | aside | DSH 控制台实例总览日志设置关于本 |
| `nav-overview` | — | `wgisl1kv` | button | 实例总览 |
| `nav-logs` | — | `naxovvpn` | button | 日志 |
| `nav-settings` | — | `m72eapcx` | button | 设置 |
| `nav-about` | — | `uiuwfiyw` | button | 关于 |
| `logs-page` | — | `ctnetfnr` | section | 日志真实数据来源dsh :3080— |
| `source-badge` | — | `l8m7aj21` | span | 真实数据 |
| `log-source-label` | — | `un2dt3aa` | label | 来源 |
| `log-source` | — | `9bro6lyt` | select | dsh :3080————宿主日志审 |
| `log-source-option` | instance:proc-3080 | `naccxwhj` | option | dsh :3080 |
| `log-source-divider` | __divider__ | `ges90p8a` | option | ———— |
| `log-source-option` | host | `d9zkcroq` | option | 宿主日志 |
| `log-source-option` | audit | `3b44v382` | option | 审计日志 |
| `logs-meta` | — | `zlbvjg9l` | span | 尾部 200 行（请求 200） · |
| `log-refresh` | — | `tzvrg0l0` | button | 刷新 |
| `log-box` | — | `e8bal6gm` | div | 14:54:46.242··[ret |

## 关于页（17 个元素）

| data-name（角色） | 限定（是哪一个） | data-uid | 元素 | 文本样例 |
| --- | --- | --- | --- | --- |
| `side-nav` | — | `psintiol` | aside | DSH 控制台实例总览日志设置关于本 |
| `nav-overview` | — | `wgisl1kv` | button | 实例总览 |
| `nav-logs` | — | `naxovvpn` | button | 日志 |
| `nav-settings` | — | `m72eapcx` | button | 设置 |
| `nav-about` | — | `uiuwfiyw` | button | 关于 |
| `about-page` | — | `0s23oae0` | section | 关于面向个人本机使用的 DSH 控制 |
| `about-panel` | — | `dxsgtsjs` | div | 面向个人本机使用的 DSH 控制台， |
| `version-panel` | — | `kfbhkwer` | div | 版本dsh 版本0.2.0-rc.2 |
| `kv-row` | — | `jl2i7hwm` | div | dsh 版本0.2.0-rc.2 |
| `kv-label` | — | `hrz4se1d` | span | dsh 版本 |
| `kv-value` | — | `r4hhrurq` | span | 0.2.0-rc.2 |
| `kv-row` | — | `y8ply7dt` | div | 控制台版本0.1.0 |
| `kv-label` | — | `6txjhdsq` | span | 控制台版本 |
| `kv-value` | — | `gfvdngo5` | span | 0.1.0 |
| `kv-row` | — | `6ziiif90` | div | 平台linux x64 (7.2.9 |
| `kv-label` | — | `i9ke1hzf` | span | 平台 |
| `kv-value` | — | `ml8d7vwg` | span | linux x64 (7.2.9-a |

## 展开归档区（139 个元素）

| data-name（角色） | 限定（是哪一个） | data-uid | 元素 | 文本样例 |
| --- | --- | --- | --- | --- |
| `side-nav` | — | `psintiol` | aside | DSH 控制台实例总览日志设置关于本 |
| `nav-overview` | — | `wgisl1kv` | button | 实例总览 |
| `nav-logs` | — | `naxovvpn` | button | 日志 |
| `nav-settings` | — | `m72eapcx` | button | 设置 |
| `nav-about` | — | `uiuwfiyw` | button | 关于 |
| `overview-page` | — | `64s1c0on` | div | 实例总览真实数据菜单里的动作走 PO |
| `source-badge` | — | `8wau1c09` | span | 真实数据 |
| `new-instance` | — | `7lipfsbu` | button | ＋新建实例 |
| `section-title` | — | `zl8g5sbj` | h2 | 当前运行的实例 (1) |
| `source-badge` | — | `i478edtj` | span | 真实数据 |
| `instance-card` | 卡片 web | `38hhruar` | div | web :3080本机监听的 dsh |
| `card-name` | 卡片 web | `3mvsupwm` | span | web :3080 |
| `sub-line` | 卡片 web | `mt1hrwue` | div | 本机监听的 dsh 实例运行中已运行 |
| `sub-kind` | 卡片 web | `uzemkqnc` | span | 本机监听的 dsh 实例 |
| `status-dot` | 卡片 web | `5g85qamy` | span |  |
| `sub-state` | 卡片 web | `tu2meziy` | span | 运行中 |
| `sub-uptime` | 卡片 web | `4c2r00wc` | span | 已运行 9 小时 35 分钟 |
| `port-note` | 卡片 web | `lzts978i` | span | 缺 3 个包：@deepseek-a |
| `open-web-ui` | 卡片 web | `et9ch8vc` | button | 打开 Web UI |
| `stop` | 卡片 web | `c1dfucbp` | button | 停止 |
| `restart` | 卡片 web | `5nmvfpef` | button | 重启 |
| `menu-trigger` | 卡片 web | `2w6gczwr` | button |  |
| `card-field` | 卡片 web | `rh2ae69b` | li | DSH 版本 / 来源0.2.0-r |
| `field-label` | 卡片 web | `s4sqc0ic` | span | DSH 版本 / 来源 |
| `field-value` | 卡片 web | `sdk41prz` | span | 0.2.0-rc.2（入口包） |
| `card-field` | 卡片 web | `ip2wffvw` | li | Profileweb |
| `field-label` | 卡片 web | `ux13u3fn` | span | Profile |
| `field-value` | 卡片 web | `z1ssmn1k` | span | web |
| `card-field` | 卡片 web | `6rdfx3zc` | li | 访问地址http://127.0.0 |
| `field-label` | 卡片 web | `yrdz3tbj` | span | 访问地址 |
| `field-value` | 卡片 web | `zch7tzu4` | span | http://127.0.0.1:3 |
| `card-field` | 卡片 web | `r83iml89` | li | DSH_HOME/home/clyz |
| `field-label` | 卡片 web | `espkbgqa` | span | DSH_HOME |
| `field-value` | 卡片 web | `7e306nnx` | span | ~/.dsh |
| `card-field` | 卡片 web | `6s1wvdpf` | li | 插件数量声明 13 · 已装 10 |
| `field-label` | 卡片 web | `b3wr2r3c` | span | 插件数量 |
| `field-value` | 卡片 web | `ucd0ir2z` | span | 声明 13 · 已装 10 |
| `card-field` | 卡片 web | `lbb52eq5` | li | 最近改动10-15 13:24 |
| `field-label` | 卡片 web | `maq879uu` | span | 最近改动 |
| `field-value` | 卡片 web | `p2gjr8cp` | span | 10-15 13:24 |
| `section-title` | — | `nbgatsyx` | h2 | 已停止的实例 (3) |
| `source-badge` | — | `hsv3ns45` | span | 真实数据 |
| `instance-card` | 卡片 web-dev | `oik6nbmu` | div | web-dev本地 profile已 |
| `card-name` | 卡片 web-dev | `f1c4ogo5` | span | web-dev |
| `sub-line` | 卡片 web-dev | `xutwe5zh` | div | 本地 profile已停止cordi |
| `sub-kind` | 卡片 web-dev | `li4pcf7l` | span | 本地 profile |
| `status-dot` | 卡片 web-dev | `yphoujw1` | span |  |
| `sub-state` | 卡片 web-dev | `k5syc8vx` | span | 已停止 |
| `sub-uptime` | 卡片 web-dev | `kncfhmqd` | span | cordis.patch.yml 1 |
| `port-note` | 卡片 web-dev | `iwsyku8b` | span | 缺 11 个包：@deepseek- |
| `start` | 卡片 web-dev | `sy8tftrv` | button | 启动 |
| `restart` | 卡片 web-dev | `8x8apiai` | button | 重启 |
| `menu-trigger` | 卡片 web-dev | `yoehocfs` | button |  |
| `card-field` | 卡片 web-dev | `t6h54myq` | li | DSH 版本 / 来源0.2.0-r |
| `field-label` | 卡片 web-dev | `avy2vy65` | span | DSH 版本 / 来源 |
| `field-value` | 卡片 web-dev | `yct09x0q` | span | 0.2.0-rc.2（本机已安装） |
| `card-field` | 卡片 web-dev | `vio1dlrd` | li | Profileweb-dev |
| `field-label` | 卡片 web-dev | `33mm3w6a` | span | Profile |
| `field-value` | 卡片 web-dev | `sz4hc9bx` | span | web-dev |
| `card-field` | 卡片 web-dev | `w0jdcftt` | li | 访问地址已停用，无法访问 |
| `field-label` | 卡片 web-dev | `e46ce2fu` | span | 访问地址 |
| `field-value` | 卡片 web-dev | `c8vd9ecl` | span | 已停用，无法访问 |
| `card-field` | 卡片 web-dev | `pu95nuim` | li | DSH_HOME/home/clyz |
| `field-label` | 卡片 web-dev | `wjkhubqh` | span | DSH_HOME |
| `field-value` | 卡片 web-dev | `lnftyjce` | span | ~/.dsh |
| `card-field` | 卡片 web-dev | `x2yuqay4` | li | 插件数量声明 13 · 已装 2 |
| `field-label` | 卡片 web-dev | `h8i6mh43` | span | 插件数量 |
| `field-value` | 卡片 web-dev | `1vszc0a0` | span | 声明 13 · 已装 2 |
| `card-field` | 卡片 web-dev | `n3tvalto` | li | 最近改动10-15 18:50 |
| `field-label` | 卡片 web-dev | `f8svqmyb` | span | 最近改动 |
| `field-value` | 卡片 web-dev | `6kgbb7js` | span | 10-15 18:50 |
| `instance-card` | 卡片 review-dev | `6alh2f4j` | div | review-dev本地 profi |
| `card-name` | 卡片 review-dev | `uao96y5y` | span | review-dev |
| `sub-line` | 卡片 review-dev | `91fnzx3q` | div | 本地 profile已停止cordi |
| `sub-kind` | 卡片 review-dev | `w2biryu0` | span | 本地 profile |
| `status-dot` | 卡片 review-dev | `sgozq3d6` | span |  |
| `sub-state` | 卡片 review-dev | `3xya93nu` | span | 已停止 |
| `sub-uptime` | 卡片 review-dev | `gscj1n30` | span | cordis.patch.yml 1 |
| `port-note` | 卡片 review-dev | `vd0w30tu` | span | 缺 3 个包：@deepseek-a |
| `start` | 卡片 review-dev | `vnn86ol6` | button | 启动 |
| `restart` | 卡片 review-dev | `1pokuw9z` | button | 重启 |
| `menu-trigger` | 卡片 review-dev | `5scvmr8b` | button |  |
| `card-field` | 卡片 review-dev | `kr8gr673` | li | DSH 版本 / 来源0.2.0-r |
| `field-label` | 卡片 review-dev | `mrp6qjb8` | span | DSH 版本 / 来源 |
| `field-value` | 卡片 review-dev | `zjsj2u7j` | span | 0.2.0-rc.2（本机已安装） |
| `card-field` | 卡片 review-dev | `iv1tjjz0` | li | Profilereview-dev |
| `field-label` | 卡片 review-dev | `ang8r1eb` | span | Profile |
| `field-value` | 卡片 review-dev | `a3a6la8o` | span | review-dev |
| `card-field` | 卡片 review-dev | `4a4y032w` | li | 访问地址已停用，无法访问 |
| `field-label` | 卡片 review-dev | `74kkybj3` | span | 访问地址 |
| `field-value` | 卡片 review-dev | `se0hnsws` | span | 已停用，无法访问 |
| `card-field` | 卡片 review-dev | `b7l66xc9` | li | DSH_HOME/home/clyz |
| `field-label` | 卡片 review-dev | `orah2shu` | span | DSH_HOME |
| `field-value` | 卡片 review-dev | `dkm7iov1` | span | ~/.dsh |
| `card-field` | 卡片 review-dev | `ee898q7n` | li | 插件数量声明 15 · 已装 12 |
| `field-label` | 卡片 review-dev | `l7rw0qyg` | span | 插件数量 |
| `field-value` | 卡片 review-dev | `t70b2cvf` | span | 声明 15 · 已装 12 |
| `card-field` | 卡片 review-dev | `ald5k9zx` | li | 最近改动10-15 16:16 |
| `field-label` | 卡片 review-dev | `uy1ws8ja` | span | 最近改动 |
| `field-value` | 卡片 review-dev | `d0d77h21` | span | 10-15 16:16 |
| `instance-card` | 卡片 headless | `56dajw30` | div | headless本地 profile |
| `card-name` | 卡片 headless | `42rjxdej` | span | headless |
| `sub-line` | 卡片 headless | `rstvp2k3` | div | 本地 profile已停止cordi |
| `sub-kind` | 卡片 headless | `z8id3t03` | span | 本地 profile |
| `status-dot` | 卡片 headless | `hjmhlqrr` | span |  |
| `sub-state` | 卡片 headless | `1j9ku31j` | span | 已停止 |
| `sub-uptime` | 卡片 headless | `j5fp35nf` | span | cordis.patch.yml 4 |
| `start` | 卡片 headless | `dmp4gap5` | button | 启动 |
| `restart` | 卡片 headless | `odjh9zso` | button | 重启 |
| `menu-trigger` | 卡片 headless | `4sh0p2w6` | button |  |
| `card-field` | 卡片 headless | `usfybzxs` | li | DSH 版本 / 来源0.2.0-r |
| `field-label` | 卡片 headless | `81t6dohj` | span | DSH 版本 / 来源 |
| `field-value` | 卡片 headless | `y9gmlan8` | span | 0.2.0-rc.2（本机已安装） |
| `card-field` | 卡片 headless | `uinmulvf` | li | Profileheadless |
| `field-label` | 卡片 headless | `ylj4eqqo` | span | Profile |
| `field-value` | 卡片 headless | `aiiwqvnn` | span | headless |
| `card-field` | 卡片 headless | `kd6m398r` | li | 访问地址已停用，无法访问 |
| `field-label` | 卡片 headless | `zo8uxnxs` | span | 访问地址 |
| `field-value` | 卡片 headless | `wy4hoq37` | span | 已停用，无法访问 |
| `card-field` | 卡片 headless | `jleacxm8` | li | DSH_HOME/home/clyz |
| `field-label` | 卡片 headless | `t6ma3liv` | span | DSH_HOME |
| `field-value` | 卡片 headless | `ic3liqw4` | span | ~/.dsh |
| `card-field` | 卡片 headless | `iny05v3y` | li | 插件数量声明 2 · 已装 2 |
| `field-label` | 卡片 headless | `r6tcpmcp` | span | 插件数量 |
| `field-value` | 卡片 headless | `gaoottym` | span | 声明 2 · 已装 2 |
| `card-field` | 卡片 headless | `suevhn5i` | li | 最近改动10-15 16:13 |
| `field-label` | 卡片 headless | `zdkr8735` | span | 最近改动 |
| `field-value` | 卡片 headless | `js2hrvva` | span | 10-15 16:13 |
| `archived-toggle` | — | `7k4ofpqh` | button | 已归档 (1) |
| `source-badge` | — | `eeiuh8px` | span | 真实数据 |
| `archived-row` | — | `ojt3367i` | article | dsh-uid-accept-dem |
| `archive-name` | — | `nssshif1` | span | dsh-uid-accept-dem |
| `archive-kind` | — | `3zlgwomo` | span | 已归档 · 磁盘上没有这只 prof |
| `archive-stamp` | — | `a1z7r9qg` | span | 10-15 18:00 |
| `unarchive` | — | `xkciwdz4` | button | 取消归档 |
| `archive-delete` | — | `ca9du0sj` | button | 删除 |
| `side-info` | — | `1nqb7zbn` | aside | 工作流入口从当前实例派生开发副本派生 |
| `workflow-entry` | — | `l6ienh4d` | button | 从当前实例派生开发副本派生隔离副本， |
| `workflow-entry` | — | `ovqtv21c` | button | 将插件交回主线实例把插件提交回稳定实 |

## 同名不同卡：uid 把两个「同一个角色」分开

| data-name | 所在卡片 | data-uid |
| --- | --- | --- |
| `instance-card` | web | `38hhruar` |
| `instance-card` | web-dev | `oik6nbmu` |
| `instance-card` | review-dev | `6alh2f4j` |
| `instance-card` | headless | `56dajw30` |
| `card-name` | web | `3mvsupwm` |
| `card-name` | web-dev | `f1c4ogo5` |
| `card-name` | review-dev | `uao96y5y` |
| `card-name` | headless | `42rjxdej` |
| `sub-line` | web | `mt1hrwue` |
| `sub-line` | web-dev | `xutwe5zh` |
| `sub-line` | review-dev | `91fnzx3q` |
| `sub-line` | headless | `rstvp2k3` |
| `sub-kind` | web | `uzemkqnc` |
| `sub-kind` | web-dev | `li4pcf7l` |
| `sub-kind` | review-dev | `w2biryu0` |
| `sub-kind` | headless | `z8id3t03` |
| `status-dot` | web | `5g85qamy` |
| `status-dot` | web-dev | `yphoujw1` |
| `status-dot` | review-dev | `sgozq3d6` |
| `status-dot` | headless | `hjmhlqrr` |
| `sub-state` | web | `tu2meziy` |
| `sub-state` | web-dev | `k5syc8vx` |
| `sub-state` | review-dev | `3xya93nu` |
| `sub-state` | headless | `1j9ku31j` |
| `sub-uptime` | web | `4c2r00wc` |
| `sub-uptime` | web-dev | `kncfhmqd` |
| `sub-uptime` | review-dev | `gscj1n30` |
| `sub-uptime` | headless | `j5fp35nf` |
| `port-note` | web | `lzts978i` |
| `port-note` | web-dev | `iwsyku8b` |
| `port-note` | review-dev | `vd0w30tu` |
| `restart` | web | `5nmvfpef` |
| `restart` | web-dev | `8x8apiai` |
| `restart` | review-dev | `1pokuw9z` |
| `restart` | headless | `odjh9zso` |
| `menu-trigger` | web | `2w6gczwr` |
| `menu-trigger` | web-dev | `yoehocfs` |
| `menu-trigger` | review-dev | `5scvmr8b` |
| `menu-trigger` | headless | `4sh0p2w6` |
| `card-field` | web | `lbb52eq5` |
| `card-field` | web-dev | `n3tvalto` |
| `card-field` | review-dev | `ald5k9zx` |
| `card-field` | headless | `suevhn5i` |
| `field-label` | web | `maq879uu` |
| `field-label` | web-dev | `f8svqmyb` |
| `field-label` | review-dev | `uy1ws8ja` |
| `field-label` | headless | `zdkr8735` |
| `field-value` | web | `p2gjr8cp` |
| `field-value` | web-dev | `6kgbb7js` |
| `field-value` | review-dev | `d0d77h21` |
| `field-value` | headless | `js2hrvva` |
| `start` | web-dev | `sy8tftrv` |
| `start` | review-dev | `vnn86ol6` |
| `start` | headless | `dmp4gap5` |

（`allDistinct`：instance-card=true，card-name=true，sub-line=true，sub-kind=true，status-dot=true，sub-state=true，sub-uptime=true，port-note=true，restart=true，menu-trigger=true，card-field=true，field-label=true，field-value=true，start=true）

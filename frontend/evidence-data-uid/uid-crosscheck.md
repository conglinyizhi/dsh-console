# 语义路径 → uid 对照（活页面复核）

路径按 uid.mbt 的口径手写；「算出来的 uid」由 JS 侧独立重写的同一套算法算出；
「页面上的 data-uid」是页面上那个元素实际带的值。三列一致才算过。

| 页面 | 元素 | 语义路径 | 算出来的 uid | 页面上的 data-uid | 一致 |
| --- | --- | --- | --- | --- | --- |
| 实例总览 | 页面 | overview | page | 64s1c0on | 64s1c0on | ✓ |
| 实例总览 | 侧栏导航项「设置」 | shell | nav | settings | m72eapcx | m72eapcx | ✓ |
| 实例总览 | 「新建实例」按钮 | overview | new-instance | 7lipfsbu | 7lipfsbu | ✓ |
| 实例总览 | 运行中分组标题 | overview | section | running | title | zl8g5sbj | zl8g5sbj | ✓ |
| 实例总览 | 页眉来源徽标 | overview | head | source-badge | 8wau1c09 | 8wau1c09 | ✓ |
| 实例总览 | 运行中分组来源徽标 | overview | section | running | source-badge | i478edtj | i478edtj | ✓ |
| 实例总览 | 已停止分组来源徽标 | overview | section | stopped | source-badge | hsv3ns45 | hsv3ns45 | ✓ |
| 实例总览 | 已停止的那张卡（review-dev） | overview | card | profile:review-dev | 6alh2f4j | 6alh2f4j | ✓ |
| 实例总览 | 该卡的「重启」按钮 | overview | card | profile:review-dev | restart | 1pokuw9z | 1pokuw9z | ✓ |
| 实例总览 | 该卡的「⋯」触发按钮 | overview | card | profile:review-dev | menu-trigger | 5scvmr8b | 5scvmr8b | ✓ |
| 实例总览 | 该卡的字段「最近改动」 | overview | card | profile:review-dev | field | mtime | ald5k9zx | ald5k9zx | ✓ |
| 实例总览 | 该卡字段「最近改动」的值 | overview | card | profile:review-dev | field | mtime | value | d0d77h21 | d0d77h21 | ✓ |
| 日志页 | 页面 | logs | page | ctnetfnr | ctnetfnr | ✓ |
| 日志页 | 来源下拉 | logs | source-select | 9bro6lyt | 9bro6lyt | ✓ |
| 日志页 | 来源项「宿主日志」 | logs | source-option | host | d9zkcroq | d9zkcroq | ✓ |
| 设置页 | 页面 | settings | page | vy479vpt | vy479vpt | ✓ |
| 设置页 | 左索引项「界面」 | settings | tab | ui | tr4fr6ea | tr4fr6ea | ✓ |
| 设置页 | 条目「签名探测超时」 | settings | row | probe.timeoutMs | zr7irs7h | zr7irs7h | ✓ |
| 设置页 | 该条目的数字输入框 | settings | row | probe.timeoutMs | input | xzhkkz4c | xzhkkz4c | ✓ |

共 19 条，不一致 0 条。

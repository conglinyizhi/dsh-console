# 第三方声明

## Vuetify

本项目的组件 DOM 结构与 CSS 类名契约对齐 Vuetify 3。

**样式来源**：`styles/vendor.scss` 是从 Vuetify 的编译产物 `dist/vuetify.css`
中**机械导出**的、本项目实际用得到的那部分规则（由 `tools/extract-rules.mjs` 生成，
约 1274 条），经本项目的构建链编入 `out/md2.css`。本项目不再分发 Vuetify 的原始样式表，
但仍随附其许可原文（见下）。

- 来源：https://github.com/vuetifyjs/vuetify （v3-stable，v3.13.4）
- 许可：MIT License
- 版权：Copyright (c) 2016-now Vuetify, LLC
  （v2-stable 及更早为 Copyright (c) 2016-2022 John Jeremy Leider）

MIT 许可原文见随 Vuetify 分发的 `LICENSE.md`。可复制的完整文本：

```
The MIT License (MIT)

Copyright (c) 2016-now Vuetify, LLC

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.
```

本项目从 Vuetify 复用的具体内容：

1. **CSS 类名契约** —— 组件产出的类名（`v-btn`、`v-btn--variant-elevated`、
   `v-btn--density-compact`、`elevation-*`、`rounded-*`、`bg-*` / `text-*` 等）
   与 Vuetify 的 `composables/{density,size,variant,elevation,rounded}` 一致，
   以便其编译产物样式可以直接套用。
2. **DOM 结构** —— `v-btn__overlay` / `v-btn__underlay` / `v-btn__content` 的层级。
3. **样式表** —— `node_modules/vuetify/dist/vuetify.css` 由 demo 直接挂载。
4. **主题变量表** —— `styles/theme.scss` 由 `tools/extract-theme.mjs` 从
   Vuetify 的主题生成器提取（含其按对比度推导的 `on-*` 颜色）。

MoonBit 侧的实现为本项目原创，未翻译 Vuetify 的源代码。

## 名称与字样的使用边界

MIT 给的是版权与专利授权，**不授予商标权**；同时它**要求保留版权声明**。
所以「Vuetify」字样在本项目里分两类，处理方式相反：

### 必须保留（删掉才是违规）

- `NOTICE.md` 全文与本文件里的 MIT 许可原文、版权行
  （MIT 要求在任何副本或实质部分中保留版权声明与许可文本）
- `styles/theme.scss` 的生成头注释：该文件是从 Vuetify 的主题生成器提取的派生数据
- `package.json` 里 `vuetify` 依赖声明：必须与实际依赖一致
- 分发产物中的 `out/vuetify.css` 与随附的 `out/vuetify.LICENSE.md`

### 可以保留（叙述性引用，无风险）

源码注释里的「契约（Vuetify 3 SSR 实测）」「对应 Vuetify 的 `useLocation`」这类句子，
是在陈述**契约来源**这一事实，属于正当的指称性使用。留着有利于后来者追溯；
删掉反而让「这些类名凭什么长这样」失去依据。

### 不可以做

- 拿 `Vuetify` 当本项目的名称、包名、标语（如 `vuetify-moonbit`、`Vuetify for MoonBit`）
- 暗示本项目由 Vuetify 团队出品或获其背书
- 使用其 logo

本项目目前的命名：模块 `conglinyizhi/md2`，描述 "Material Design 2 component library
for Rabbita"，均未使用 `Vuetify` 作品牌。

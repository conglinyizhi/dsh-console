# 第三方声明

## @mdi/js（Pictogrammers）

`icons.mbt` 里的 26 条 SVG 路径数据取自 `@mdi/js` 7.4.47。

- 来源：https://github.com/Templarian/MaterialDesign-JS （npm 包 `@mdi/js`）
- 许可：Apache License 2.0。上游 LICENSE 写明：图标与字体部分适用 Apache 2.0，
  其余代码文件适用 MIT；图标集整体按 Pictogrammers Free License 发布。
- 版权：Copyright (c) Pictogrammers（Austin Andrews 等贡献者）

**取数方式**：路径是取一次、固化成 MoonBit 常量（见 `icons.mbt` 头部注释），
**没有把 Node 依赖引进本仓库**；本仓库也不分发上游的字体文件与样式表。
要更新或增补图标，重跑一次取数脚本即可，做法记在 `icons.mbt` 里。

Apache License 2.0 原文：https://www.apache.org/licenses/LICENSE-2.0

# 全量重写简报（Vue → rabbita + md2 + precss）

> 这份是**派给 worker 的完整简报草稿**。切片已验收（见下），本简报用于把切片扩成三页全量。

## 一、先读这四样，别自己摸索

| 读什么 | 为什么 |
| --- | --- |
| `design/frontend-parity-checklist.md` | **功能面与几何不变量的对账依据**，逐条验 |
| `design/rabbita-md2-cheatsheet.md` | 从能编译的源码抽出的调用范式（包配置、入口、组件、条件渲染、图标、import 别名） |
| `frontend/`（**切片，已验证可运行**） | 参考实现：`build.sh` 三步链、`cmd/build-styles`（precss）、`cmd/app`（js 入口）、`styles/dsh-skin.scss`（皮肤层）、`web/index.html` |
| `dsh-console-design/stack-compare-*.png` | 三列对比（Vue / md2 原生 / md2+皮肤）。**以右列为观感基准** |

## 二、切片已经做到的（别推翻）

- `rabbita(js) + md2 + precss + 原生后端` 端到端跑通，真数据渲染、暗色皮肤生效、MDI 图标出字形
- 已验证：`node design/verify-frontend.mjs <baseUrl>` → 无横向溢出、真数据到位（`dsh 版本 0.2.0-rc.2` 等）
- 切片含：关于页 + 运行中实例卡（超出原简报范围，但方向对）
- 产物布局：`frontend/dist/{index.html, md2-raw.html, assets/*}`，后端判据满足

## 三、要做的（按清单逐条）

### 页面与导航
- 左侧导航三项（实例总览 / 日志 / 关于），**状态切页**（无 URL 路由，刷新回总览）
- 顶栏（标题 + 设置按钮占位）+ 页脚「本机运行，仅限回环访问」

### 实例总览（最大的一块）
- 页头：标题 + 数据源徽标 + `动作仍是演示` + 「＋ 新建实例」占位按钮
- 分组一「当前运行的实例 (N)」+ 空态；分组二「已停止的实例 (N)」+ 空态
- 卡片：两行卡头（实例名 / 类型标签 + 状态点 + 状态文案 + idleNote）、字段区（左图标 + 右值两列）、
  两态按钮组（运行中 `[打开 Web UI][停止][重启][⋯]`；已停止 `[启动｜▾][重启]`）
- 归档区（可折叠 + 取消归档）
- 交互：启动等待态（**整行按钮禁用**，含两段式两半）、派生开发副本、删除确认对话框、
  重命名对话框（预填全选、空格禁用确定、Enter/Esc、**焦点回触发元素**）、菜单（打开落焦第一项、
  Esc 回触发元素、点外关闭、挂按钮组容器 `top:100%+6px; right:0`）
- 右栏：工作流入口两行 + 关于实例说明

### 日志页
- 来源下拉三层顺序（运行实例条目 → 分隔线 → 宿主日志 → 审计日志），**默认选第一个运行实例**，
  使用者选过之后不再替他改
- 元信息一行到底：`尾部 N 行（请求 N） · 大小 · <真实路径> · 目录依据：<homeSource> · 读于 <时刻> · 只读`
- 日志区：等宽、**长行横向滚动不折断**、打开与切来源都**滚到底**、级别只在真读得出时上色
- 刷新按钮；失败显式回退 + 具体原因

### 关于页
- 简介两句 + 版本列表（dsh / 控制台 / 平台，null 显示「未知」）+ 页脚读于与来源
- **没有「node 版本」那一行**

### 数据层
- 五个接口：`/api/local/{runtime,profiles,logs,processes,instances}`（字段见 `backend/README.md`）
- `moonbitlang/core/json` 的 `parse` + `derive(FromJson)`；副作用走 `@cmd`
- **读不到的字段照实写「未知」/「—」，不许编**

### 样式
- 移植现有 **941 行**（散在 `src/**/*.vue` 的 `<style scoped>` 里）；全局 token 在 `src/styles/app.css`
- 特性朴素（只有 4 处 `grid-template`、1 处 `@keyframes`），**近乎逐行可搬**
- **唯一要保留的动效**：启动等待态状态点的 `dot-pulse`（900ms 呼吸 + 琥珀光晕）
- 其余不加过渡动画

## 四、顺手修掉切片里的两个问题

1. `web/index.html` 缺 favicon → `/favicon.ico` 404（Vue 版用内联 data URI 解决，照做）
2. `app.js` 1.15 MB 未压缩 —— 本地可接受，但报告里如实写清；若能低成本缩小（例如构建参数）就做

## 五、铁律

- **只改 `frontend/` 与 `dsh-console-design/`**；不碰 `backend/`、`src/`、`vite.config.ts`
- 自测用 `DSH_CONSOLE_DIST=<abs>/frontend/dist` 指向产物起后端（**别依赖自动上溯**，
  只要 `dist/` 还在，上溯会命中旧的 Vue 产物）
- `~/.moon` 只读：构建用 `MOON_HOME=.sandbox/moonhome`；native 步骤要
  `MOON_CC=clang MOON_AR=ar MOON_LD=clang`
- 通过 `run_code` 的 TS 字符串生成 `.mbt` 时，MoonBit 插值 `\{var}` 要写成 `\\{var}`
- 交付前跑 `node design/verify-frontend.mjs <baseUrl>`（无横向溢出、无控制台错误、真数据到位）
- 按清单逐条自验并**贴证据**（DOM 实测数字，不是"看着一样"）

## 六、提交

按使用者要求，**这个 worker 自己提交**：先读 `~/.agents/skills/git-commit/SKILL.md`，
跑它的 `pre-commit-check.ts`，通过后按约定式提交（中文、≤30 字描述）。

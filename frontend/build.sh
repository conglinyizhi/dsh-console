#!/usr/bin/env bash
#
# 一条命令跑完构建链。顺序有依赖，不要乱调：
#   0. 清 dist/      产物目录整体重建
#   1. build-styles  precss 编 SCSS        → dist/assets/app.css
#   2. app           rabbita 客户端（js）  → _build/js/release/build/cmd/app/app.js
#   3. 拷产物        js / 页面外壳 / 许可  → dist/
#
# 为什么要包一层：踩过「第 2 步漏跑 → 第 3 步静默拷到上一次的 js，页面看着
# 完全正常、代码是旧的」。所以宁可多一层包装，每一步都 echo，产物还要过两道断言。
#
# MOON_HOME：本机 ~/.moon 挂在只读文件系统上，moon 往里写不了 registry 缓存。
# 指到工程内一个可写目录就行（.sandbox/ 不进版本管理）。

set -euo pipefail

cd "$(dirname "$0")"

# native 构建必须显式指定工具链
export MOON_CC=clang MOON_AR=ar MOON_LD=clang
export MOON_HOME="${MOON_HOME:-$PWD/.sandbox/moonhome}"

echo "== 0/3 清 dist/ =="
# **不能只增不减**：摘掉的依赖会以旧文件的形式留在 dist 里 —— mdi 字体、
# dsh-skin.css 这些已经不再生成的东西留着，验收「产物里没有」时就会假通过。
# 这一步必须在 build-styles 之前：app.css 就是写进 dist/assets 的。
rm -rf dist
mkdir -p dist/assets/licenses

echo
echo "== 1/3 编样式（precss）=="
moon run cmd/build-styles --target native

echo
echo "== 2/3 编客户端应用（--target js --release）=="
moon build cmd/app --target js --release

echo
echo "== 3/3 拷产物到 dist/ =="
app_js="_build/js/release/build/cmd/app/app.js"
if [ ! -f "$app_js" ]; then
  echo "找不到产物 $app_js —— 第 2 步没跑成，或产物布局变了" >&2
  exit 1
fi
# 只判「文件在不在」不够：换过构建布局之后，旧布局下的产物还躺在 _build 里，
# 断言照样通过，拷过去的是上一版代码（真踩过，见上面那段注释）。
stale_src="$(find . -name '*.mbt' -not -path './_build/*' -not -path './.mooncakes/*' -newer "$app_js" -print -quit)"
if [ -n "$stale_src" ]; then
  echo "产物 $app_js 比源文件 $stale_src 还旧 —— 这一版没编出来" >&2
  exit 1
fi
cp "$app_js" dist/assets/app.js
cp vendor/licenses/mdi-NOTICE.md dist/assets/licenses/
cp web/index.html dist/index.html

echo
echo "产物："
ls -la dist dist/assets

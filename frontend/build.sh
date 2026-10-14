#!/usr/bin/env bash
#
# 一条命令跑完构建链。顺序有依赖，不要乱调：
#   1. build-styles   precss 编 SCSS        → dist/assets/app.css, dist/assets/dsh-skin.css
#   2. app            rabbita 客户端（js）  → _build/js/release/build/cmd/app/app.js
#   3. 拷产物         js / mdi / 页面外壳   → dist/
#
# 为什么要包一层：md2 那边踩过「第 2 步漏跑 → 第 3 步静默拷到上一次的 js，页面看着
# 完全正常、代码是旧的」。所以宁可多一层包装，并且每一步都 echo 出来。
#
# MOON_HOME：本机 ~/.moon 挂在只读文件系统上，moon 往里写不了 registry 缓存。
# 指到工程内一个可写目录就行（.sandbox/ 不进版本管理）。

set -euo pipefail

cd "$(dirname "$0")"

# native 构建必须显式指定工具链
export MOON_CC=clang MOON_AR=ar MOON_LD=clang
export MOON_HOME="${MOON_HOME:-$PWD/.sandbox/moonhome}"

echo "== 1/3 编样式（precss）=="
moon run cmd/build-styles --target native

echo
echo "== 2/3 编客户端应用（--target js --release）=="
moon build cmd/app --target js --release

echo
echo "== 3/3 拷产物到 dist/ =="
mkdir -p dist/assets/mdi/css dist/assets/mdi/fonts dist/assets/licenses
# 产物路径带模块路径（工作区成员模式下 _build 的布局）。写死 + 存在性断言：
# 路径变了就直接炸，不会静默拷到上一版。
app_js="_build/js/release/build/conglinyizhi/dsh-console-frontend/cmd/app/app.js"
if [ ! -f "$app_js" ]; then
  echo "找不到产物 $app_js —— 第 2 步没跑成，或产物布局变了" >&2
  exit 1
fi
cp "$app_js" dist/assets/app.js
cp vendor/mdi/css/materialdesignicons.min.css dist/assets/mdi/css/
cp vendor/mdi/fonts/materialdesignicons-webfont.woff2 dist/assets/mdi/fonts/
cp vendor/licenses/vuetify.LICENSE.md dist/assets/licenses/
cp vendor/licenses/md2-NOTICE.md dist/assets/licenses/
cp web/index.html dist/index.html
cp web/md2-raw.html dist/md2-raw.html

echo
echo "产物："
ls -la dist dist/assets
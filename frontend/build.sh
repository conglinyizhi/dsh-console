#!/usr/bin/env bash
#
# 一条命令跑完构建链。顺序有依赖，不要乱调：
#   0. 清 dist/      产物目录整体重建
#   1. build-styles  precss 编 SCSS        → dist/assets/app.css
#   2. app           rabbita 客户端（js）  → _build/js/release/build/cmd/app/app.js
#   3. 拷产物        js / 页面外壳 / 许可  → dist/
#   4. 预压缩        app.js / app.css      → 同名 .gz（后端静态服务直接发它）
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

# 0) 构建信息：sha + 构建时刻（页脚要显示它，每次构建前重生成）
bash "$(dirname "$0")/../scripts/gen-build-info.sh" "$(cd "$(dirname "$0")/.." && pwd)"

echo "== 0/4 清 dist/ =="
# **不能只增不减**：摘掉的依赖会以旧文件的形式留在 dist 里 —— mdi 字体、
# dsh-skin.css 这些已经不再生成的东西留着，验收「产物里没有」时就会假通过。
# 这一步必须在 build-styles 之前：app.css 就是写进 dist/assets 的。
rm -rf dist
mkdir -p dist/assets/licenses

echo
echo "== 1/4 编样式（precss）=="
moon run cmd/build-styles --target native
# precss 对「多写一个右花括号」这类结构错误不报错，会**安静地产出半份 CSS**：
# 真踩过一次 —— app.scss 里一处注释末尾多写了个 "}"，产物从 63KB 掉到 22KB，
# 页面看着「只是少了几条规则」，很难当场发现。这里按体量设一道下限（当前约 63KB），
# 低于它就当这一版没编出来，直接失败。
css_bytes=$(wc -c < dist/assets/app.css)
if [ "$css_bytes" -lt 50000 ]; then
  echo "app.css 只有 $css_bytes 字节，疑似 precss 半途截断（查 app.scss 里有没有多余的 }）" >&2
  exit 1
fi

echo
echo "== 2/4 编客户端应用（--target js --release）=="
moon build cmd/app --target js --release

echo
echo "== 3/4 拷产物到 dist/ =="
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

# 3.1) 资源 URL 带内容哈希：文件内容一变，URL 就变，浏览器没有缓存可用。
#      用内容哈希而不是 git sha —— 没提交的改动也能让 URL 跟着变。
# dev 用内容哈希（改代码就变）；release 用 git sha（可追溯到提交）。
if [ "${BUILD_MODE:-dev}" = "release" ]; then
  APP_HASH=$(git -C "$(dirname "$0")/.." rev-parse --short HEAD 2>/dev/null || echo unknown)
else
  if command -v sha256sum >/dev/null 2>&1; then
    APP_HASH=$(sha256sum dist/assets/app.js | cut -c1-8)
  else
    APP_HASH=$(shasum -a 256 dist/assets/app.js | cut -c1-8)
  fi
fi
# 不用 sed -i：macOS 的 BSD sed 要求 -i 后面跟一个空参数，跨平台会踩。
sed "s/__BUILD__/${APP_HASH}/g" dist/index.html > dist/index.html.tmp
mv dist/index.html.tmp dist/index.html
echo "  资源版本号：$APP_HASH"

echo
echo "== 4/4 预压缩静态资源（gzip -9 -n -k）=="
# 后端静态服务（backend/dist_static）在 Accept-Encoding 含 gzip、且同名 .gz 真在时直接发 .gz，
# 首屏那个 1.5MB 的 app.js 因此走压缩版；.gz 不在就照旧发原文件。
# 压缩链刻意不依赖 Node：系统 gzip 就够（前端构建链本来就只有 moon 与 shell）。
#   -9  最大压缩
#   -n  不写时间戳与原文件名，同内容每次产出逐字节一致（能比对、能被缓存复用）
#   -k  保留原文件（原文件仍要发，是回退路径）
#   -f  重跑时覆盖旧 .gz，不交互
for asset in dist/assets/app.js dist/assets/app.css; do
  gzip -9 -n -k -f "$asset"
  # 只判「文件在不在」不够：.gz 是空文件时后端会照样发出去，页面直接白屏
  if [ ! -s "$asset.gz" ]; then
    echo "预压缩没产出 $asset.gz" >&2
    exit 1
  fi
done

echo
echo "产物："
ls -la dist dist/assets
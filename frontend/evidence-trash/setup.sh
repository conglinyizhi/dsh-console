#!/usr/bin/env bash
# 隔离环境的回收站真链路测试：DSH_HOME 与 XDG_STATE_HOME 全在 /tmp 下，
# 不碰使用者那一份。服务器端口 5491（5390 上那只使用者跑的实例不动）。
set -euo pipefail
BASE=/tmp/dsh-console-trash-e2e
rm -rf "$BASE"
mkdir -p "$BASE/dsh-home/profiles" "$BASE/state" "$BASE/out"
mkfix() {
  local name="$1"
  mkdir -p "$BASE/dsh-home/profiles/$name/sub"
  printf 'hello %s\n' "$name" > "$BASE/dsh-home/profiles/$name/a.txt"
  printf 'nested\n' > "$BASE/dsh-home/profiles/$name/sub/b.txt"
  printf 'x\n' > "$BASE/dsh-home/profiles/$name/cordis.patch.yml"
}
mkfix zz-trash-a
mkfix zz-trash-b
mkfix zz-trash-keep
ls -la "$BASE/dsh-home/profiles"
echo "BASE=$BASE"

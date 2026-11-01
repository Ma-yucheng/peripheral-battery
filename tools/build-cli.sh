#!/usr/bin/env bash
# 数据源自检：不启动界面，直接在终端打印实时读到的外设电量
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD="$ROOT/.build"
mkdir -p "$BUILD/tmp" "$BUILD/mc-cli"
export TMPDIR="$BUILD/tmp"
rm -f "$BUILD"/mc-cli/*.lock "$BUILD"/mc-cli/*.lock-* 2>/dev/null || true

SOURCES=()
while IFS= read -r file; do
  SOURCES+=("$file")
done < <(find "$ROOT/Sources/Model" "$ROOT/Sources/Providers" "$ROOT/Sources/Store" -name '*.swift' | sort)

swiftc -swift-version 5 -Onone -target "$(uname -m)-apple-macosx14.0" \
  -module-cache-path "$BUILD/mc-cli" \
  -framework Foundation -framework CoreBluetooth -framework IOKit -framework GameController \
  "${SOURCES[@]}" "$ROOT/tools/cli/main.swift" \
  -o "$BUILD/pbcli"

"$BUILD/pbcli"

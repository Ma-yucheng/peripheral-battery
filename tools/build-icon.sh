#!/usr/bin/env bash
# 重新生成 App 图标（Resources/AppIcon.icns）
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD="$ROOT/.build"
mkdir -p "$BUILD/tmp" "$BUILD/modulecache"
export TMPDIR="$BUILD/tmp"
swiftc -swift-version 5 -module-cache-path "$BUILD/modulecache" -O \
  "$ROOT/tools/make-icon.swift" -o "$BUILD/make-icon"
cd "$ROOT" && "$BUILD/make-icon"
echo "==> 图标已更新: $ROOT/Resources/AppIcon.icns"

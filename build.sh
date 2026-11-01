#!/usr/bin/env bash
# 构建「外设电量」菜单栏应用（.app）
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD="$ROOT/.build"
APP="$ROOT/build/PeripheralBattery.app"
ARCH="$(uname -m)"
TARGET="${ARCH}-apple-macosx14.0"

mkdir -p "$BUILD/tmp" "$BUILD/modulecache"
export TMPDIR="$BUILD/tmp"

# 清理上次中断可能留下的模块缓存锁
rm -f "$BUILD"/modulecache/*.lock "$BUILD"/modulecache/*.lock-* 2>/dev/null || true

echo "==> 清理旧产物"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

SOURCES=()
while IFS= read -r file; do
  SOURCES+=("$file")
done < <(find "$ROOT/Sources" -name '*.swift' | sort)

echo "==> 编译 $ARCH / macOS 14.0+（${#SOURCES[@]} 个源文件）"
swiftc \
  -swift-version 5 \
  -Onone \
  -target "$TARGET" \
  -module-cache-path "$BUILD/modulecache" \
  -framework AppKit \
  -framework SwiftUI \
  -framework Combine \
  -framework CoreBluetooth \
  -framework IOKit \
  -framework GameController \
  "${SOURCES[@]}" \
  -o "$APP/Contents/MacOS/PeripheralBattery"

cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
if [[ -f "$ROOT/Resources/AppIcon.icns" ]]; then
  cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
fi

echo "==> 本地签名（ad-hoc）"
codesign --force --sign - "$APP" >/dev/null 2>&1 || echo "   （跳过签名，不影响本地运行）"

echo "==> 完成: $APP"

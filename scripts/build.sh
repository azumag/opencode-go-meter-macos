#!/bin/bash
# OpenCodeGoMeter のビルドスクリプト。
# SwiftPM は使わず swiftc で直接コンパイルし、dist/OpenCodeGoMeter.app を組み立てる。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT/build"
APP="$ROOT/dist/OpenCodeGoMeter.app"
CONTENTS="$APP/Contents"
MACOS_DIR="$CONTENTS/MacOS"

mkdir -p "$BUILD_DIR" "$ROOT/dist"

echo "==> swiftc でコンパイル中…"
# shellcheck disable=SC2086
swiftc -O -swift-version 5 \
  -framework AppKit -framework UserNotifications \
  -o "$BUILD_DIR/OpenCodeGoMeter" \
  "$ROOT"/Sources/*.swift

echo "==> .app バンドルを組み立て中…"
rm -rf "$APP"
mkdir -p "$MACOS_DIR"
cp "$BUILD_DIR/OpenCodeGoMeter" "$MACOS_DIR/OpenCodeGoMeter"
cp "$ROOT/Resources/Info.plist" "$CONTENTS/Info.plist"

# ad-hoc 署名（失敗しても警告のみで続行）
codesign --force --deep --sign - "$APP" || echo "warning: codesign に失敗しました（署名なしで続行）"

echo "==> 完了: $APP"

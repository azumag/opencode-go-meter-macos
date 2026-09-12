#!/bin/bash
# OpenCodeGoMeter のインストールスクリプト。
# dist/OpenCodeGoMeter.app を ~/Applications にコピーし、LaunchAgent を設置・ロードする。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="OpenCodeGoMeter.app"
SRC_APP="$ROOT/dist/$APP_NAME"
DEST_APP="$HOME/Applications/$APP_NAME"
AGENT_LABEL="com.azumag.opencode-go-meter"
AGENT_DIR="$HOME/Library/LaunchAgents"
AGENT_PLIST="$AGENT_DIR/$AGENT_LABEL.plist"

if [[ ! -d "$SRC_APP" ]]; then
  echo "エラー: $SRC_APP がありません。先に bash scripts/build.sh を実行してください。" >&2
  exit 1
fi

echo "==> ~/Applications にコピー中…"
mkdir -p "$HOME/Applications"
rm -rf "$DEST_APP"
cp -R "$SRC_APP" "$DEST_APP"

echo "==> LaunchAgent を設置中…"
mkdir -p "$AGENT_DIR"
# テンプレートの __APP_EXECUTABLE__ を実際の実行ファイルパスに置換する
sed "s|__APP_EXECUTABLE__|$DEST_APP/Contents/MacOS/OpenCodeGoMeter|" \
  "$ROOT/launchagent/$AGENT_LABEL.plist" > "$AGENT_PLIST"

echo "==> LaunchAgent をロード中…"
/bin/launchctl bootstrap "gui/$(id -u)" "$AGENT_PLIST" 2>/dev/null \
  || /bin/launchctl load -w "$AGENT_PLIST" 2>/dev/null \
  || echo "warning: launchctl のロードに失敗しました。手動で開くか再ログインしてください。"

echo "==> 完了: $DEST_APP"
echo "    メニューバーの「Go …」から利用できます。"

#!/bin/bash
# OpenCodeGoMeter のアンインストールスクリプト。
# LaunchAgent の停止・削除と ~/Applications からの削除を行う（設定ファイルは残す）。
set -euo pipefail

AGENT_LABEL="com.azumag.opencode-go-meter"
AGENT_PLIST="$HOME/Library/LaunchAgents/$AGENT_LABEL.plist"
DEST_APP="$HOME/Applications/OpenCodeGoMeter.app"

echo "==> 実行中のアプリを終了中…"
pkill -f OpenCodeGoMeter 2>/dev/null || true

echo "==> LaunchAgent を停止・削除中…"
/bin/launchctl bootout "gui/$(id -u)/$AGENT_LABEL" 2>/dev/null || true
/bin/launchctl unload -w "$AGENT_PLIST" 2>/dev/null || true
rm -f "$AGENT_PLIST"

echo "==> アプリを削除中…"
rm -rf "$DEST_APP"

echo "==> 完了"
echo "    設定・状態 (~/.config/opencode-go-meter/) は残しています。完全に消す場合は手動で削除してください。"

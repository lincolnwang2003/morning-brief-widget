#!/bin/zsh
# Link the widget into Übersicht and schedule the morning run.
set -e
ROOT="$(cd "$(dirname "$0")" && pwd)"
WIDGETS="$HOME/Library/Application Support/Übersicht/widgets"
PLIST="com.peilinwang.dailytodo.plist"

mkdir -p "$WIDGETS" "$ROOT/logs" "$ROOT/data"
ln -sfn "$ROOT/widget/daily-todo.widget" "$WIDGETS/daily-todo.widget"
echo "Widget linked into Übersicht."

cp "$ROOT/launchd/$PLIST" "$HOME/Library/LaunchAgents/$PLIST"
launchctl bootout "gui/$(id -u)/com.peilinwang.dailytodo" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$HOME/Library/LaunchAgents/$PLIST"
echo "Scheduled: runs daily at 7:00 and at login."

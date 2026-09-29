#!/bin/zsh
# Build Morning Brief and package it as dist/MorningBrief.dmg
set -e
cd "$(dirname "$0")"
xcodegen generate >/dev/null
xcodebuild -project MorningBrief.xcodeproj -scheme MorningBrief -configuration Release \
  -derivedDataPath build -destination 'generic/platform=macOS' build 2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)"

STAGE=build/dmg
rm -rf "$STAGE" dist && mkdir -p "$STAGE" dist
cp -R "build/Build/Products/Release/Morning Brief.app" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
cat > "$STAGE/READ ME FIRST.txt" <<'TXT'
Morning Brief - your Canvas, email and calendar in one ranked to-do list.

1. Drag "Morning Brief" into Applications.
2. The first time, RIGHT-CLICK the app -> Open -> Open.
   (It isn't signed by a paid Apple developer account, so macOS asks once.)
   On macOS 15+, if there's no Open button: System Settings -> Privacy & Security
   -> scroll down -> "Open Anyway".
3. Follow the 3-step setup window.
4. Optional desktop widget: right-click the desktop -> Edit Widgets -> search "Morning Brief".

You need a Claude Pro or Max subscription (Morning Brief uses Claude as its AI).
TXT
hdiutil create -volname "Morning Brief" -srcfolder "$STAGE" -ov -format UDZO dist/MorningBrief.dmg >/dev/null

# Install locally if asked, then remove build copies so macOS doesn't register duplicate widgets.
if [[ "$1" == "--install" ]]; then
  pkill -x "Morning Brief" || true
  rm -rf "/Applications/Morning Brief.app"
  cp -R "$STAGE/Morning Brief.app" /Applications/
  pluginkit -a "/Applications/Morning Brief.app/Contents/PlugIns/MorningBriefWidget.appex"
  open "/Applications/Morning Brief.app"
  echo "Installed to /Applications."
fi
rm -rf "$STAGE" build/Build/Products
echo "Built dist/MorningBrief.dmg ($(du -h dist/MorningBrief.dmg | cut -f1))"

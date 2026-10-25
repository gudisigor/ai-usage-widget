#!/bin/bash
# Builds AIUsage.app next to this script.  Usage: ./build.sh && open AIUsage.app
set -euo pipefail
cd "$(dirname "$0")"
swift build -c release
APP=AIUsage.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/AIUsage "$APP/Contents/MacOS/AIUsage"
mkdir -p "$APP/Contents/Resources" && cp Resources/*.svg "$APP/Contents/Resources/"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>local.aiusage.widget</string>
  <key>CFBundleName</key><string>Расход ИИ</string>
  <key>CFBundleExecutable</key><string>AIUsage</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.1</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$APP" >/dev/null 2>&1 || true
echo "Built $APP"

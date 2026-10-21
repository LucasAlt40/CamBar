#!/bin/zsh
# Builds CamBar.app (menu bar only, no Dock icon). Requires: brew install ffmpeg
set -e
cd "$(dirname "$0")"
swift build -c release --product CamBar
APP=build/CamBar.app
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS"
cp .build/release/CamBar "$APP/Contents/MacOS/CamBar"
mkdir -p "$APP/Contents/Resources"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>CamBar</string>
<key>CFBundleIdentifier</key><string>local.cambar</string>
<key>CFBundleExecutable</key><string>CamBar</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSUIElement</key><true/>
<key>NSLocalNetworkUsageDescription</key><string>Acessar as câmeras da sua rede.</string>
<key>NSAppTransportSecurity</key><dict><key>NSAllowsLocalNetworking</key><true/></dict>
</dict></plist>
PLIST
codesign --force --sign - "$APP"
echo "OK: $APP"

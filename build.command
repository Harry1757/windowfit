#!/bin/zsh
set -eu
cd "${0:A:h}"
mkdir -p "창맞춤.app/Contents/MacOS" "창맞춤.app/Contents/Resources"
swiftc -O Source/Layout.swift Source/main.swift -framework AppKit -framework ApplicationServices -framework Carbon -o "창맞춤.app/Contents/MacOS/WindowFit"
cat > "창맞춤.app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>WindowFit</string>
<key>CFBundleIdentifier</key><string>local.windowfit.mac</string>
<key>CFBundleName</key><string>창맞춤</string>
<key>CFBundleDisplayName</key><string>창맞춤</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "창맞춤.app"
echo "빌드 완료: 창맞춤.app"

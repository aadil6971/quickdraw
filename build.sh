#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
APP="$PWD/dist/QuickDraw.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" .build/module-cache
for ARCH in arm64 x86_64; do
    xcrun swiftc Sources/main.swift -target "$ARCH-apple-macosx13.0" -o ".build/QuickDraw-$ARCH" -framework AppKit -framework Carbon -module-cache-path "$PWD/.build/module-cache" -O
done
lipo -create .build/QuickDraw-arm64 .build/QuickDraw-x86_64 -output "$APP/Contents/MacOS/QuickDraw"
cp Assets/QuickDraw.icns "$APP/Contents/Resources/QuickDraw.icns"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>QuickDraw</string>
<key>CFBundleIdentifier</key><string>local.quickdraw.overlay</string>
<key>CFBundleName</key><string>QuickDraw</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.0.0</string>
<key>CFBundleVersion</key><string>2</string>
<key>CFBundleIconFile</key><string>QuickDraw</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$APP"
"$APP/Contents/MacOS/QuickDraw" --self-test
echo "Built $APP"

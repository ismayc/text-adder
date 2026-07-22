#!/bin/zsh
# Build a release binary and wrap it in a double-clickable TextAdder.app bundle.
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release

APP=TextAdder.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/TextAdder "$APP/Contents/MacOS/TextAdder"

cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>TextAdder</string>
    <key>CFBundleIdentifier</key>
    <string>com.chesterismay.textadder</string>
    <key>CFBundleName</key>
    <string>TextAdder</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF

codesign --force --sign - "$APP"
echo "Built $APP — move it to /Applications if you like, then double-click to run."

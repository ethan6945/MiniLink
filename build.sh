#!/bin/bash
# 构建 MiniLink.app：swift build → 组装 .app 包 → ad-hoc 签名
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release

APP="build/MiniLink.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/MiniLink "$APP/Contents/MacOS/MiniLink"
cp AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleExecutable</key>
	<string>MiniLink</string>
	<key>CFBundleIdentifier</key>
	<string>com.ethan.MiniLink</string>
	<key>CFBundleName</key>
	<string>MiniLink</string>
	<key>CFBundleDisplayName</key>
	<string>MiniLink</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>1.2.0</string>
	<key>CFBundleVersion</key>
	<string>3</string>
	<key>CFBundleIconFile</key>
	<string>AppIcon</string>
	<key>LSMinimumSystemVersion</key>
	<string>14.0</string>
	<key>LSUIElement</key>
	<true/>
	<key>NSHighResolutionCapable</key>
	<true/>
	<key>NSAppleEventsUsageDescription</key>
	<string>MiniLink 需要控制「终端」来打开 SSH 连接。</string>
</dict>
</plist>
EOF

codesign --force --sign - "$APP"
echo "✅ 构建完成：$PWD/$APP"
echo "   启动：open $APP"
echo "   建议拖入 /Applications 长期使用（开机自启需要）"

#!/bin/bash
# 构建 MiniLink.app：swift build → 组装 .app 包 → ad-hoc 签名
set -euo pipefail
cd "$(dirname "$0")"

select_compatible_sdk() {
    # 尊重调用者明确指定的 SDK。
    if [[ -n "${SDKROOT:-}" ]]; then
        return
    fi

    local target_arch
    target_arch="$(uname -m)"

    # Command Line Tools 偶尔会出现 swiftc 与默认 SDK 补丁版本不同步。
    # 先做一个轻量 SwiftUI 类型检查；失败时自动选择已安装且兼容的版本化 SDK。
    if printf 'import SwiftUI\n' | swiftc -typecheck \
        -target "${target_arch}-apple-macosx14.0" - >/dev/null 2>&1; then
        return
    fi

    local sdk
    for sdk in /Library/Developer/CommandLineTools/SDKs/MacOSX[0-9]*.sdk; do
        [[ -d "$sdk" ]] || continue
        if printf 'import SwiftUI\n' | swiftc -typecheck \
            -target "${target_arch}-apple-macosx14.0" -sdk "$sdk" - >/dev/null 2>&1; then
            export SDKROOT="$sdk"
            echo "ℹ️  默认 SDK 与 Swift 编译器不兼容，改用：$SDKROOT"
            return
        fi
    done

    echo "❌ 找不到与当前 Swift 编译器兼容的 macOS SDK" >&2
    exit 1
}

select_compatible_sdk
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
	<string>1.3.0</string>
	<key>CFBundleVersion</key>
	<string>4</string>
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

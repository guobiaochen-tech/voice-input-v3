#!/bin/bash
# 编译 VoiceInput v3 并打包为 DMG
# 使用 sherpa-onnx 动态库（和 Typeoff 一致）
set -e

cd "$(dirname "$0")"

# === 配置 ===
BRIDGING_HEADER="SherpaOnnx-Bridging-Header.h"
SWIFT_WRAPPER="SherpaOnnx.swift"

# 动态库路径（从 Typeoff 的 sherpa-onnx-darwin-arm64 npm 包复制）
DYLIB_DIR="Frameworks/sherpa-onnx-dylib"

echo "🔧 编译 Voice Input v3..."

# === 1. 检查动态库 ===
if [ ! -d "$DYLIB_DIR" ] || [ ! -f "$DYLIB_DIR/libsherpa-onnx-c-api.dylib" ]; then
    echo "❌ 找不到 sherpa-onnx 动态库: $DYLIB_DIR"
    echo "   请先从 Typeoff 或 npm(sherpa-onnx-darwin-arm64) 获取以下文件:"
    echo "   libonnxruntime.dylib"
    echo "   libsherpa-onnx-c-api.dylib"
    echo "   libsherpa-onnx-cxx-api.dylib"
    echo "   放到 $DYLIB_DIR/ 目录"
    exit 1
fi

# === 2. 下载 SherpaOnnx.swift wrapper（如果不存在）===
if [ ! -f "$SWIFT_WRAPPER" ]; then
    echo "📦 下载 SherpaOnnx.swift wrapper..."
    curl -sL "https://raw.githubusercontent.com/k2-fsa/sherpa-onnx/master/swift-api-examples/SherpaOnnx.swift" -o "$SWIFT_WRAPPER"
    echo "✅ SherpaOnnx.swift 已下载"
fi

# === 3. 下载 Bridging Header（如果不存在）===
if [ ! -f "$BRIDGING_HEADER" ]; then
    echo "📦 下载 Bridging Header..."
    curl -sL "https://raw.githubusercontent.com/k2-fsa/sherpa-onnx/master/swift-api-examples/SherpaOnnx-Bridging-Header.h" -o "$BRIDGING_HEADER"
    echo "✅ Bridging Header 已下载"
fi

# === 4. 确定 Headers 路径 ===
# v1.12.29 头文件（和 dylib 版本匹配）
HEADER_DIR="Frameworks/sherpa-onnx-headers-v1.12.29"
if [ ! -d "$HEADER_DIR" ]; then
    echo "📦 下载 sherpa-onnx v1.12.29 头文件..."
    mkdir -p "$HEADER_DIR/sherpa-onnx/c-api"
    curl -sL "https://github.com/k2-fsa/sherpa-onnx/raw/v1.12.29/sherpa-onnx/c-api/c-api.h" -o "$HEADER_DIR/sherpa-onnx/c-api/c-api.h"
fi

if [ ! -d "$HEADER_DIR" ]; then
    echo "❌ 找不到 sherpa-onnx 头文件"
    exit 1
fi

echo "   Headers: $HEADER_DIR"
echo "   Dylibs: $DYLIB_DIR"

# === 5. 编译 ===
echo "🔧 编译中..."

SOURCES=(Sources/VoiceInput/*.swift)
ALL_SOURCES=("${SOURCES[@]}" "$SWIFT_WRAPPER")

BUILD_DIR=".build/release"
mkdir -p "$BUILD_DIR"

# 链接动态库 + 编译标志 SHERPA_ONNX
swiftc \
    -O \
    -DSHERPA_ONNX \
    -sdk $(xcrun --show-sdk-path) \
    -target arm64-apple-macosx14.0 \
    -I "$HEADER_DIR" \
    -import-objc-header "$BRIDGING_HEADER" \
    -module-name VoiceInput \
    -emit-executable \
    -o "$BUILD_DIR/VoiceInput" \
    "${ALL_SOURCES[@]}" \
    -L "$DYLIB_DIR" \
    -lsherpa-onnx-c-api \
    -lsherpa-onnx-cxx-api \
    -lonnxruntime \
    -lc++ \
    -Xlinker -undefined -Xlinker dynamic_lookup \
    -Xlinker -rpath -Xlinker @executable_path/../Frameworks \
    -framework CoreML \
    -framework AVFoundation \
    -framework AppKit \
    -framework CoreAudio \
    -framework CoreMedia \
    -framework AudioToolbox \
    -framework Carbon \
    -framework Security \
    -framework Accelerate

if [ ! -f "$BUILD_DIR/VoiceInput" ]; then
    echo "❌ 编译失败"
    exit 1
fi

echo "✅ 编译成功"

# === 6. 打包 .app ===
APP_DIR="VoiceInput.app"
CONTENTS="$APP_DIR/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"

rm -rf "$APP_DIR"
mkdir -p "$MACOS"
mkdir -p "$RESOURCES"

# 复制二进制
cp "$BUILD_DIR/VoiceInput" "$MACOS/VoiceInput"
chmod +x "$MACOS/VoiceInput"

# 复制动态库到 Frameworks（运行时需要）
APP_FW="$CONTENTS/Frameworks"
mkdir -p "$APP_FW"
cp "$DYLIB_DIR"/*.dylib "$APP_FW/"

# 复制图标
if [ -f "logo.icns" ]; then
    cp logo.icns "$RESOURCES/AppIcon.icns"
fi
if [ -f "menu-icon.png" ]; then
    cp menu-icon.png "$RESOURCES/menu-icon.png"
fi

# 创建 Info.plist
cat > "$CONTENTS/Info.plist" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>VoiceInput</string>
    <key>CFBundleIdentifier</key>
    <string>com.paul.voice-input</string>
    <key>CFBundleName</key>
    <string>Voice Input</string>
    <key>CFBundleVersion</key>
    <string>3.3</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSSpeechRecognitionUsageDescription</key>
    <string>语音输入需要语音识别权限来转写您的语音</string>
    <key>NSMicrophoneUsageDescription</key>
    <string>语音输入需要麦克风权限来录制您的语音</string>
    <key>NSAccessibilityUsageDescription</key>
    <string>语音输入需要辅助功能权限来模拟键盘输入</string>
</dict>
</plist>
EOF

# 对整个 .app 做一次稳定的本机临时签名。
# 麦克风、辅助功能这类 TCC 权限依赖应用身份；只让 swiftc 生成的二进制保持
# linker-signed 状态，会导致 bundle identifier 和资源没有绑定进签名，重装后权限不稳定。
echo "🔏 签名 App..."
codesign --force --deep --sign - "$APP_DIR"
codesign --verify --deep --strict "$APP_DIR"

echo "✅ 打包完成: $APP_DIR"

# === 7. DMG 打包 ===
DMG_NAME="VoiceInput-3.3.dmg"
DMG_STAGING="dmg_staging"

echo "📦 正在打包 DMG..."

rm -rf "$DMG_STAGING" "$DMG_NAME"
mkdir -p "$DMG_STAGING"

cp -r "$APP_DIR" "$DMG_STAGING/"
ln -s /Applications "$DMG_STAGING/Applications"

hdiutil create -volname "Voice Input" \
    -srcfolder "$DMG_STAGING" \
    -ov -format UDZO \
    "$DMG_NAME"

rm -rf "$DMG_STAGING"

echo ""
echo "✅ 全部完成:"
echo "   App:  $APP_DIR"
echo "   DMG:  $DMG_NAME"
echo ""
echo "   安装方式: 双击 $DMG_NAME → 拖到 Applications 文件夹"

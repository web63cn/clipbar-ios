#!/bin/bash
#
# 编译 ClipBar iOS 版 → unsigned IPA
#
# 需要装了完整 Xcode 的 Mac：
#   xcode-select -s /Applications/Xcode.app/Contents/Developer
#
# 编译出来的是**未签名** IPA，装进手机要用 Sideloadly 之类的工具现场签名。
#
set -e

cd "$(dirname "$0")"

# ---------- 检查环境 ----------
if ! xcodebuild -version >/dev/null 2>&1; then
    echo "❌ 找不到 xcodebuild。"
    echo "   完整 Xcode 没装的话，用 GitHub Actions 远程编译（见 README）。"
    exit 1
fi

SDK=$(xcrun --sdk iphoneos --show-sdk-version 2>/dev/null || echo "")
if [ -z "$SDK" ]; then
    echo "❌ 找不到 iOS SDK。装完整 Xcode 后重试。"
    exit 1
fi
echo "▸ iOS SDK: $SDK"

# ---------- 校验工程 ----------
if [ -f verify_pbxproj.py ]; then
    echo "▸ 校验工程文件…"
    python3 verify_pbxproj.py
fi

# ---------- 编译 ----------
OUT="build"
rm -rf "$OUT"
mkdir -p "$OUT"

echo "▸ 编译（无签名）…"
xcodebuild \
    -project ClipBar.xcodeproj \
    -scheme ClipBar \
    -configuration Release \
    -sdk iphoneos \
    -derivedDataPath "$OUT/DerivedData" \
    CODE_SIGN_IDENTITY="" \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGNING_ALLOWED=NO \
    ENABLE_BITCODE=NO \
    build | tail -20

# ---------- 打包 IPA ----------
APP="$OUT/DerivedData/Build/Products/Release-iphoneos/ClipBar.app"
if [ ! -d "$APP" ]; then
    echo "❌ 没找到编译产物：$APP"
    exit 1
fi

echo "▸ 打包 IPA…"
rm -rf "$OUT/Payload"
mkdir -p "$OUT/Payload"
cp -R "$APP" "$OUT/Payload/"
# 扩展要放进 appex 目录
APEX="$APP/PlugIns/ClipBarKeyboard.appex"
if [ -d "$APEX" ]; then
    echo "  ✓ 包含键盘扩展"
else
    echo "  ⚠️  没找到键盘扩展（KeyboardController 没打进去）"
fi

cd "$OUT"
zip -qry ClipBar-unsigned.ipa Payload
cd ..

IPA="$OUT/ClipBar-unsigned.ipa"
SIZE=$(du -h "$IPA" | cut -f1)
echo ""
echo "✅ 完成：$IPA（$SIZE）"
echo ""
echo "下一步："
echo "  1. 下载 Sideloadly：https://sideloadly.io"
echo "  2. 把上面的 IPA 拖进 Sideloadly 窗口"
echo "  3. 填你的 Apple ID（免费账号即可），选设备，点 Start"
echo "  4. 手机上开启开发者模式：设置 → 隐私与安全性 → 开发者模式"
echo "  5. 信任证书：设置 → 通用 → VPN与设备管理 → 信任你的 Apple ID"

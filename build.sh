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
# ⚠️ 不要写成 `xcodebuild ... | tail -20` ——
#    管道的退出码是 tail 的，xcodebuild 失败也会被当成成功，
#    结果产出一个空 IPA。必须用 PIPESTATUS 取真实退出码。
set -o pipefail
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
    build 2>&1 | tee "$OUT/build.log" | tail -40
BUILD_RC=${PIPESTATUS[0]}
set +o pipefail

if [ "$BUILD_RC" != "0" ]; then
    echo ""
    echo "❌ 编译失败（xcodebuild 退出码 $BUILD_RC），错误摘要："
    grep -E "error:" "$OUT/build.log" | head -20 || true
    exit 1
fi

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

# ---------- 验证产物 ----------
# 空 IPA（只有空目录）是最坑的失败模式：build.sh 报成功，
# 但装到手机上是个空壳。下载后才发现。
APP_COUNT=$(unzip -l "$IPA" | grep -c "Payload/ClipBar.app/" || true)
if [ "$APP_COUNT" -lt 3 ]; then
    echo "❌ IPA 里没有 App 内容（$APP_COUNT 个文件）—— 编译没真正成功"
    exit 1
fi
if ! unzip -l "$IPA" | grep -q "ClipBarKeyboard.appex"; then
    echo "⚠️  IPA 里没有键盘扩展"
fi
if ! unzip -l "$IPA" | grep -q "ClipBar.app/ClipBar$"; then
    echo "❌ IPA 里没有可执行文件"
    exit 1
fi

SIZE=$(du -h "$IPA" | cut -f1)
echo ""
echo "✅ 完成：$IPA（$SIZE，$APP_COUNT 个文件）"
echo ""
echo "下一步："
echo "  1. 下载 Sideloadly：https://sideloadly.io"
echo "  2. 把上面的 IPA 拖进 Sideloadly 窗口"
echo "  3. 填你的 Apple ID（免费账号即可），选设备，点 Start"
echo "  4. 手机上开启开发者模式：设置 → 隐私与安全性 → 开发者模式"
echo "  5. 信任证书：设置 → 通用 → VPN与设备管理 → 信任你的 Apple ID"

#!/bin/bash

# DXPlayerSDK 構建腳本（演示版本）
# 這個腳本會嘗試構建 Framework 並展示完整流程

set -e

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  DXPlayerSDK 構建演示"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# 清理
echo "🧹 清理舊構建..."
rm -rf build
mkdir -p build/archives build/products

# 構建 iOS 真機版本
echo ""
echo "📱 構建 iOS 真機版本..."
xcodebuild archive \
  -project DXPlayerSDKDemo.xcodeproj \
  -scheme DXPlayerSDK \
  -configuration Release \
  -destination "generic/platform=iOS" \
  -archivePath "build/archives/DXPlayerSDK-iOS" \
  SKIP_INSTALL=NO \
  BUILD_LIBRARY_FOR_DISTRIBUTION=YES \
  | grep -v "note:" | grep -E "(error:|warning:|BUILD)" || true

if [ -d "build/archives/DXPlayerSDK-iOS.xcarchive" ]; then
    echo "✅ iOS 真機版本構建成功"

    # 複製 Framework 到 products
    cp -R "build/archives/DXPlayerSDK-iOS.xcarchive/Products/Library/Frameworks/DXPlayerSDK.framework" \
          "build/products/DXPlayerSDK-iOS.framework"

    echo ""
    echo "📊 Framework 信息："
    ls -lh "build/products/DXPlayerSDK-iOS.framework/DXPlayerSDK"

    echo ""
    echo "🔍 架構信息："
    lipo -info "build/products/DXPlayerSDK-iOS.framework/DXPlayerSDK"
else
    echo "❌ iOS 真機版本構建失敗"
    exit 1
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  ✅ 構建完成！"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "📦 產物位置："
echo "   build/products/DXPlayerSDK-iOS.framework"
echo ""
echo "💡 提示："
echo "   - Framework 已成功構建"
echo "   - 可以在 Xcode 中打開專案查看"
echo "   - 完整的 XCFramework 需要同時構建模擬器版本"
echo ""

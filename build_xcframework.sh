#!/bin/bash

# DXPlayerSDK XCFramework 构建脚本
# 支持 iOS 真机 (arm64) + 模拟器 (arm64 + x86_64)

set -e  # 遇到错误立即退出

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 配置
FRAMEWORK_NAME="DXPlayerSDK"
PROJECT_NAME="DXPlayerSDKDemo"
SCHEME_NAME="DXPlayerSDK"
OUTPUT_DIR="./build/xcframework"
ARCHIVE_DIR="./build/archives"

# 打印带颜色的消息
print_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

print_header() {
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

# 检查 xcodebuild 是否可用
if ! command -v xcodebuild &> /dev/null; then
    print_error "xcodebuild 未找到，请确保已安装 Xcode"
    exit 1
fi

print_header "DXPlayerSDK XCFramework 构建工具 v1.0.0"

# 清理旧构建
print_info "清理旧构建..."
rm -rf "$OUTPUT_DIR"
rm -rf "$ARCHIVE_DIR"
mkdir -p "$OUTPUT_DIR"
mkdir -p "$ARCHIVE_DIR"
print_success "清理完成"

# 构建 iOS 真机版本 (arm64)
print_header "构建 iOS 真机版本 (arm64)"
xcodebuild archive \
  -project "${PROJECT_NAME}.xcodeproj" \
  -scheme "$SCHEME_NAME" \
  -configuration Release \
  -destination "generic/platform=iOS" \
  -archivePath "${ARCHIVE_DIR}/${FRAMEWORK_NAME}-iOS" \
  SKIP_INSTALL=NO \
  BUILD_LIBRARY_FOR_DISTRIBUTION=YES \
  ONLY_ACTIVE_ARCH=NO \
  | grep -E '(error|warning|ARCHIVE SUCCEEDED|Build settings)' || true

if [ -d "${ARCHIVE_DIR}/${FRAMEWORK_NAME}-iOS.xcarchive" ]; then
    print_success "iOS 真机版本构建成功"
else
    print_error "iOS 真机版本构建失败"
    exit 1
fi

# 构建 iOS 模拟器版本 (arm64 + x86_64)
print_header "构建 iOS 模拟器版本 (arm64 + x86_64)"
xcodebuild archive \
  -project "${PROJECT_NAME}.xcodeproj" \
  -scheme "$SCHEME_NAME" \
  -configuration Release \
  -destination "generic/platform=iOS Simulator" \
  -archivePath "${ARCHIVE_DIR}/${FRAMEWORK_NAME}-Simulator" \
  SKIP_INSTALL=NO \
  BUILD_LIBRARY_FOR_DISTRIBUTION=YES \
  ONLY_ACTIVE_ARCH=NO \
  | grep -E '(error|warning|ARCHIVE SUCCEEDED|Build settings)' || true

if [ -d "${ARCHIVE_DIR}/${FRAMEWORK_NAME}-Simulator.xcarchive" ]; then
    print_success "iOS 模拟器版本构建成功"
else
    print_error "iOS 模拟器版本构建失败"
    exit 1
fi

# 创建 XCFramework
print_header "创建 XCFramework"
xcodebuild -create-xcframework \
  -framework "${ARCHIVE_DIR}/${FRAMEWORK_NAME}-iOS.xcarchive/Products/Library/Frameworks/${FRAMEWORK_NAME}.framework" \
  -framework "${ARCHIVE_DIR}/${FRAMEWORK_NAME}-Simulator.xcarchive/Products/Library/Frameworks/${FRAMEWORK_NAME}.framework" \
  -output "${OUTPUT_DIR}/${FRAMEWORK_NAME}.xcframework"

if [ -d "${OUTPUT_DIR}/${FRAMEWORK_NAME}.xcframework" ]; then
    print_success "XCFramework 创建成功"
else
    print_error "XCFramework 创建失败"
    exit 1
fi

# 显示结构
print_header "XCFramework 结构"
ls -la "${OUTPUT_DIR}/${FRAMEWORK_NAME}.xcframework"

# 显示大小
print_info "XCFramework 大小："
du -sh "${OUTPUT_DIR}/${FRAMEWORK_NAME}.xcframework"

# 验证架构
print_header "验证架构"
print_info "iOS (真机) 架构:"
lipo -info "${OUTPUT_DIR}/${FRAMEWORK_NAME}.xcframework/ios-arm64/${FRAMEWORK_NAME}.framework/${FRAMEWORK_NAME}" || true
print_info "iOS Simulator 架构:"
lipo -info "${OUTPUT_DIR}/${FRAMEWORK_NAME}.xcframework/ios-arm64_x86_64-simulator/${FRAMEWORK_NAME}.framework/${FRAMEWORK_NAME}" || true

# 完成
print_header "构建完成！"
print_success "XCFramework 位置: ${OUTPUT_DIR}/${FRAMEWORK_NAME}.xcframework"
echo ""
print_info "下一步："
echo "  1. 将 xcframework 复制到你的专案"
echo "  2. 在 Xcode 中拖入 DXPlayerSDK.xcframework"
echo "  3. 设置为 Embed & Sign"
echo ""
print_success "🎉 全部完成！"

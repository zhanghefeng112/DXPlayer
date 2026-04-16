//
//  DXPlayerSDKVersion.swift
//  DXPlayerSDK
//
//  Created by DXPlayer Team
//

import Foundation

/// DXPlayerSDK 版本信息
public struct DXPlayerSDKVersion {
    /// SDK 版本號
    public static let version = "0.0.1"

    /// 构建號
    public static let buildNumber = "1"

    /// 完整版本字符串
    public static var fullVersion: String {
        return "\(version) (\(buildNumber))"
    }

    /// SDK 名稱
    public static let sdkName = "DXPlayerSDK"

    /// 最低 iOS 版本要求
    public static let minimumIOSVersion = "15.0"

    /// 依赖的 FSPlayer 最低版本（如果适用）
    public static let minimumFSPlayerVersion = "1.0.0"

    /// 打印版本信息
    public static func printVersionInfo() {
        print("""
        ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        \(sdkName) v\(fullVersion)
        iOS \(minimumIOSVersion)+
        ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        """)
    }
}

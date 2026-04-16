//
//  DXPlayerLogger.swift
//  DXPlayerSDK
//
//  Created by DXPlayer Team
//

import Foundation

/// 日誌级别
public enum DXPlayerLogLevel: Int, Comparable {
    case debug = 0
    case info = 1
    case warning = 2
    case error = 3

    public static func < (lhs: DXPlayerLogLevel, rhs: DXPlayerLogLevel) -> Bool {
        return lhs.rawValue < rhs.rawValue
    }

    var emoji: String {
        switch self {
        case .debug: return "🔍"
        case .info: return "ℹ️"
        case .warning: return "⚠️"
        case .error: return "❌"
        }
    }

    var name: String {
        switch self {
        case .debug: return "DEBUG"
        case .info: return "INFO"
        case .warning: return "WARN"
        case .error: return "ERROR"
        }
    }
}

/// DXPlayerSDK 日誌管理器
public class DXPlayerLogger {

    // MARK: - 公共配置

    /// 全局日誌级别（低于此级别的日誌不会輸出）
    public static var logLevel: DXPlayerLogLevel = .warning

    /// 是否启用日誌輸出
    public static var isEnabled: Bool = true

    /// 是否显示文件名和行號
    public static var showFileInfo: Bool = true

    /// 是否显示时间戳
    public static var showTimestamp: Bool = false

    // MARK: - 內部日誌方法

    /// Debug 级别日誌（僅供 SDK 內部使用）
    internal static func debug(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(level: .debug, message: message, file: file, function: function, line: line)
    }

    /// Info 级别日誌（僅供 SDK 內部使用）
    internal static func info(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(level: .info, message: message, file: file, function: function, line: line)
    }

    /// Warning 级别日誌（僅供 SDK 內部使用）
    internal static func warning(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(level: .warning, message: message, file: file, function: function, line: line)
    }

    /// Error 级别日誌（僅供 SDK 內部使用）
    internal static func error(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(level: .error, message: message, file: file, function: function, line: line)
    }

    // MARK: - 私有方法

    private static func log(level: DXPlayerLogLevel, message: String, file: String, function: String, line: Int) {
        // 检查是否启用
        guard isEnabled else { return }

        // 检查日誌级别
        guard level >= logLevel else { return }

        // 构建日誌消息
        var logMessage = ""

        // 添加时间戳
        if showTimestamp {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm:ss.SSS"
            logMessage += "[\(formatter.string(from: Date()))] "
        }

        // 添加级别
        logMessage += "[\(level.emoji) \(level.name)] "

        // 添加 SDK 标識
        logMessage += "[DXPlayerSDK] "

        // 添加文件信息
        if showFileInfo {
            let fileName = (file as NSString).lastPathComponent
            logMessage += "[\(fileName):\(line)] "
        }

        // 添加消息
        logMessage += message

        // 輸出
        print(logMessage)
    }
}

import Foundation

// MARK: - DanmakuDataSource 協定

/// 彈幕資料來源協定
public protocol DanmakuDataSource: AnyObject {
    /// 資料來源類型
    var sourceType: DanmakuSourceType { get }

    /// 設定代理
    var delegate: DanmakuDataSourceDelegate? { get set }

    /// 啟動資料來源
    /// - Parameter context: 上下文資訊（如影片 ID、房間 ID 等）
    func start(context: [String: Any])

    /// 停止資料來源
    func stop()

    /// 發送彈幕
    /// - Parameters:
    ///   - text: 彈幕文字
    ///   - completion: 完成回調
    func send(text: String, completion: @escaping (Result<Void, Error>) -> Void)

    /// 時間軸模式專用：獲取指定時間範圍的彈幕
    /// - Parameters:
    ///   - startTime: 開始時間（秒）
    ///   - endTime: 結束時間（秒）
    ///   - completion: 完成回調
    func fetchDanmaku(from startTime: TimeInterval, to endTime: TimeInterval, completion: @escaping (Result<[DanmakuItem], Error>) -> Void)
}

// MARK: - DanmakuSourceType

/// 資料來源類型
public enum DanmakuSourceType {
    case timeline       // 時間軸模式（VOD）
    case realtime       // 即時模式（直播）
    case hybrid         // 混合模式
    case local          // 本地模式（測試）
}

// MARK: - DanmakuDataSourceDelegate

/// 資料來源代理
public protocol DanmakuDataSourceDelegate: AnyObject {
    /// 接收到新彈幕
    func dataSource(_ dataSource: DanmakuDataSource, didReceive danmaku: DanmakuItem)

    /// 接收到多條彈幕
    func dataSource(_ dataSource: DanmakuDataSource, didReceive danmakus: [DanmakuItem])

    /// 發生錯誤
    func dataSource(_ dataSource: DanmakuDataSource, didFailWithError error: Error)

    /// 連線狀態變更（僅即時模式）
    func dataSource(_ dataSource: DanmakuDataSource, didChangeConnectionState state: DanmakuConnectionState)
}

// MARK: - DanmakuConnectionState

/// 連線狀態
public enum DanmakuConnectionState {
    case disconnected
    case connecting
    case connected
    case reconnecting
}

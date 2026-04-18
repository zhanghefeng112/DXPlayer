import Foundation

/// 用户弹幕设置服务
///
/// 对应接口：
///   - GET  /api/danmu/setting  — 获取设置
///   - POST /api/danmu/setting  — 更新设置
///
/// 使用示例：
/// ```swift
/// let service = DanmakuSettingService(baseURL: "http://example.com", token: "Bearer xxx")
/// service.fetchSetting { result in
///     if case .success(let setting) = result {
///         print(setting.color, setting.vipLevel)
///     }
/// }
/// ```
public class DanmakuSettingService {

    // MARK: - 属性

    private let baseURL: String
    private var token: String?

    // MARK: - 初始化

    public init(baseURL: String, token: String? = nil) {
        self.baseURL = baseURL
        self.token = token
    }

    /// 更新鉴权 Token（登录状态变化时调用）
    public func updateToken(_ token: String?) {
        self.token = token
    }

    // MARK: - 获取设置

    /// 获取用户弹幕设置（GET /api/danmu/setting）
    public func fetchSetting(completion: @escaping (Result<DanmakuUserSetting, Error>) -> Void) {
        guard let url = URL(string: "\(baseURL)/api/danmu/setting") else {
            completion(.failure(makeError(-1, "无效 URL")))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        if let token = token {
            request.setValue(token, forHTTPHeaderField: "X-Auth-Token")
        }

        URLSession.shared.dataTask(with: request) { [weak self] data, _, error in
            guard let self = self else { return }
            DispatchQueue.main.async {
                if let error = error {
                    completion(.failure(error))
                    return
                }
                guard let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let errno = json["errno"] as? Int else {
                    completion(.failure(self.makeError(-2, "响应解析失败")))
                    return
                }
                guard errno == 0 else {
                    let errmsg = json["errmsg"] as? String ?? "未知错误"
                    completion(.failure(self.makeError(errno, errmsg)))
                    return
                }
                guard let dataDict = json["data"] as? [String: Any] else {
                    completion(.failure(self.makeError(-3, "data 字段缺失")))
                    return
                }

                let rawColor = dataDict["color"] as? String ?? ""
                let setting = DanmakuUserSetting(
                    color: rawColor.isEmpty ? nil : rawColor,
                    vipLevel: dataDict["vip_level"] as? Int ?? 0,
                    isUper: (dataDict["is_uper"] as? Int ?? 0) == 1,
                    disturbKeywords: dataDict["disturb_kw"] as? [String] ?? [],
                    receiveLevel: dataDict["receive_level"] as? Int ?? 0
                )
                DXPlayerLogger.info("⚙️ [弹幕设置] 获取成功 - vip:\(setting.vipLevel) isUper:\(setting.isUper) color:\(setting.color ?? "nil")")
                completion(.success(setting))
            }
        }.resume()
    }

    // MARK: - 更新设置

    /// 更新用户弹幕设置（POST /api/danmu/setting）
    ///
    /// 只有非 nil 的字段会被发送到服务端，nil 字段表示不修改。
    /// 传 `color: ""` 可清除颜色设置。
    public func updateSetting(_ update: DanmakuUserSettingUpdate, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let url = URL(string: "\(baseURL)/api/danmu/setting") else {
            completion(.failure(makeError(-1, "无效 URL")))
            return
        }

        // 只将非 nil 字段写入请求体
        var body: [String: Any] = [:]
        if let color = update.color { body["color"] = color }
        if let keywords = update.disturbKeywords { body["disturb_kw"] = keywords }
        if let level = update.receiveLevel { body["receive_level"] = level }

        guard !body.isEmpty else {
            // 没有任何需要更新的字段，直接成功返回
            completion(.success(()))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = token {
            request.setValue(token, forHTTPHeaderField: "X-Auth-Token")
        }
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        URLSession.shared.dataTask(with: request) { [weak self] data, _, error in
            guard let self = self else { return }
            DispatchQueue.main.async {
                if let error = error {
                    completion(.failure(error))
                    return
                }
                guard let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let errno = json["errno"] as? Int else {
                    completion(.failure(self.makeError(-2, "响应解析失败")))
                    return
                }
                if errno == 0 {
                    DXPlayerLogger.info("⚙️ [弹幕设置] 更新成功")
                    completion(.success(()))
                } else {
                    let errmsg = json["errmsg"] as? String ?? "未知错误"
                    completion(.failure(self.makeError(errno, errmsg)))
                }
            }
        }.resume()
    }

    // MARK: - 私有辅助

    private func makeError(_ code: Int, _ message: String) -> NSError {
        NSError(domain: "DanmakuSettingService", code: code, userInfo: [NSLocalizedDescriptionKey: message])
    }
}

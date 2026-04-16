import Foundation
import Network

/// 代理播放管理器
/// 使用 Network.framework 实现本地 HTTP 代理服务器（纯 Swift 实现）
public class ProxyServer {

    // MARK: - 单例
    public static let shared = ProxyServer()

    // MARK: - 属性
    private var servers: [String: LocalProxyServer] = [:]  // 域名 -> 服务器映射
    private let proxyHost = "127.0.0.1"

    private init() {}

    // MARK: - 公开方法

    /// 为指定 URL 创建代理服务器
    /// - Parameter url: 原始视频 URL
    /// - Returns: 代理信息字典，包含 origin 和 localproxy
    public func createServer(for url: String) async -> [String: String] {
        guard let domain = extractDomain(from: url) else {
            DXPlayerLogger.warning("⚠️ [代理服务器] 无法提取域名: \(url)")
            return ["origin": "", "localproxy": ""]
        }

        // 检查是否已有该域名的代理服务器
        if let existingServer = servers[domain], existingServer.isRunning {
            let port = existingServer.port
            DXPlayerLogger.info("♻️ [代理服务器] 复用现有服务器 \(domain) -> http://\(proxyHost):\(port)")
            return ["origin": domain, "localproxy": "http://\(proxyHost):\(port)"]
        }

        // 创建新的代理服务器
        do {
            let server = try await startProxyServer(domain: domain)
            servers[domain] = server
            let port = server.port
            DXPlayerLogger.info("✅ [代理服务器] 新建代理 \(domain) -> http://\(proxyHost):\(port)")
            return ["origin": domain, "localproxy": "http://\(proxyHost):\(port)"]
        } catch {
            DXPlayerLogger.error("❌ [代理服务器] 启动失败: \(error)")
            return ["origin": "", "localproxy": ""]
        }
    }

    /// 停止所有代理服务器
    public func stopAll() {
        DXPlayerLogger.info("🛑 [代理服务器] 停止所有代理服务器")
        for (domain, server) in servers {
            server.stop()
            DXPlayerLogger.debug("  停止: \(domain)")
        }
        servers.removeAll()
    }

    /// 获取代理统计信息
    public func getProxyStats() -> String {
        var stats = "📊 代理服务器统计:\n"
        if servers.isEmpty {
            stats += "  无活动代理\n"
        } else {
            for (domain, server) in servers {
                let mbTransferred = Double(server.totalBytesTransferred) / 1024.0 / 1024.0
                stats += "  • \(domain):\(server.port)\n"
                stats += "    请求数: \(server.requestCount)\n"
                stats += "    传输量: \(String(format: "%.2f", mbTransferred)) MB\n"
            }
        }
        return stats
    }

    // MARK: - 私有方法

    /// 启动代理服务器
    private func startProxyServer(domain: String) async throws -> LocalProxyServer {
        let port = findAvailablePort()
        let server = LocalProxyServer(targetDomain: domain, port: port)
        try await server.start()
        return server
    }

    /// 提取域名
    private func extractDomain(from urlString: String) -> String? {
        guard let url = URL(string: urlString),
              let host = url.host else {
            return nil
        }
        return host
    }

    /// 查找可用端口
    private func findAvailablePort() -> UInt16 {
        return UInt16.random(in: 17000...65535)
    }
}

// MARK: - LocalProxyServer

/// 本地 HTTP 代理服务器（使用 Network.framework）
class LocalProxyServer {

    let targetDomain: String
    let port: UInt16
    var isRunning: Bool {
        return listener?.state == .ready
    }

    // 统计信息
    private(set) var requestCount: Int = 0
    private(set) var totalBytesTransferred: Int64 = 0

    private var listener: NWListener?
    private var connections: [NWConnection] = []
    private let queue = DispatchQueue(label: "com.dxplayer.proxyserver")

    init(targetDomain: String, port: UInt16) {
        self.targetDomain = targetDomain
        self.port = port
    }

    func start() async throws {
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true

        let listener = try NWListener(using: parameters, on: NWEndpoint.Port(rawValue: port)!)
        self.listener = listener

        listener.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            switch state {
            case .ready:
                DXPlayerLogger.debug("🟢 [LocalProxyServer] 监听端口 \(self.port)")
            case .failed(let error):
                DXPlayerLogger.error("❌ [LocalProxyServer] 失败: \(error)")
            case .cancelled:
                DXPlayerLogger.debug("⚪️ [LocalProxyServer] 已取消")
            default:
                break
            }
        }

        listener.newConnectionHandler = { [weak self] connection in
            self?.handleConnection(connection)
        }

        listener.start(queue: queue)

        // 等待服务器就绪
//        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
//            var resumed = false
//            listener.stateUpdateHandler = { state in
//                guard !resumed else { return }
//                switch state {
//                case .ready:
//                    resumed = true
//                    continuation.resume()
//                case .failed(let error):
//                    resumed = true
//                    continuation.resume(throwing: error)
//                default:
//                    break
//                }
//            }
//        }
        
        // 等待服务器就绪
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let resumState = ResumeState()   // ✅ 用 actor 管理 resumed 状态
            listener.stateUpdateHandler = { state in
                // 由于 stateUpdateHandler 可能在任意线程/队列回调， 我们在 Task 里用 await 调用 actor
                Task {
                    switch state {
                    case .ready:
                        if await resumState.tryResume() {   // ✅ 只会成功一次
                            continuation.resume()
                        }
                    case .failed(let error):
                        if await resumState.tryResume() {   // ✅ 只会成功一次
                            continuation.resume(throwing: error)
                        }
                    default:
                        break
                    }
                }
            }
        }

    }
    
    actor ResumeState {
        private var resumed = false

        /// 尝试标记为已 resume，返回是否是第一次
        func tryResume() -> Bool {
            if resumed { return false }
            resumed = true
            return true
        }
    }

    func stop() {
        listener?.cancel()
        connections.forEach { $0.cancel() }
        connections.removeAll()
    }

    private func handleConnection(_ connection: NWConnection) {
        connections.append(connection)
        connection.start(queue: queue)

        // 持续读取 HTTP 请求
        receiveRequest(connection: connection)
    }

    private func receiveRequest(connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self = self else {
                connection.cancel()
                return
            }

            if let error = error {
                DXPlayerLogger.error("❌ [连接] 接收错误: \(error)")
                connection.cancel()
                return
            }

            if let data = data, !data.isEmpty {
                self.processHTTPRequest(data, connection: connection)
            }

            // 如果连接未完成，继续接收
            if !isComplete {
                self.receiveRequest(connection: connection)
            } else {
                connection.cancel()
            }
        }
    }

    private func processHTTPRequest(_ data: Data, connection: NWConnection) {
        guard let requestString = String(data: data, encoding: .utf8) else {
            sendErrorResponse(connection, statusCode: 400)
            return
        }

        // 解析请求行和头部
        let lines = requestString.components(separatedBy: "\r\n")
        guard let requestLine = lines.first,
              let requestPath = parseRequestPath(from: requestLine) else {
            sendErrorResponse(connection, statusCode: 400)
            return
        }

        // 解析 Range 头部//
        var rangeHeader: String?
        for line in lines {
            if line.lowercased().hasPrefix("range:") {
                rangeHeader = line.replacingOccurrences(of: "(?i)range:\\s*", with: "", options: .regularExpression)
                break
            }
        }

        requestCount += 1
        DXPlayerLogger.info("🔍 [代理请求 #\(requestCount)] \(requestPath)" + (rangeHeader != nil ? " Range: \(rangeHeader!)" : ""))

        // 构建原始 URL
        let originalURL: URL
        if requestPath.hasPrefix("http://") || requestPath.hasPrefix("https://") {
            // 完整 URL
            guard let url = URL(string: requestPath) else {
                sendErrorResponse(connection, statusCode: 400)
                return
            }
            originalURL = url
        } else {
            // 相对路径
            guard let url = URL(string: "https://\(targetDomain)\(requestPath)") else {
                sendErrorResponse(connection, statusCode: 400)
                return
            }
            originalURL = url
        }

        let rangeHeaderStr = rangeHeader
        // 转发请求
        Task {
            await forwardRequest(to: originalURL, rangeHeader: rangeHeaderStr, connection: connection)
        }
    }

    private func parseRequestPath(from requestLine: String) -> String? {
        let parts = requestLine.components(separatedBy: " ")
        guard parts.count >= 2 else { return nil }
        return parts[1]
    }

    private func forwardRequest(to url: URL, rangeHeader: String?, connection: NWConnection) async {
        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 60

            // 添加 Range 头部
            if let range = rangeHeader {
                request.setValue(range, forHTTPHeaderField: "Range")
            }

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                sendErrorResponse(connection, statusCode: 500)
                return
            }

            // 检查是否为 M3U8
            let contentType = httpResponse.mimeType ?? ""
            let isM3U8 = contentType.contains("mpegurl") || url.pathExtension == "m3u8"

            let responseData: Data
            if isM3U8, let rewritten = rewriteM3U8(data, baseURL: url) {
                responseData = rewritten
                DXPlayerLogger.debug("📝 [代理] M3U8 重写完成")
            } else {
                responseData = data
            }

            // 统计数据
            totalBytesTransferred += Int64(responseData.count)

            // 发送响应（包含 Range 相关头部）
            sendHTTPResponse(connection,
                           statusCode: httpResponse.statusCode,
                           contentType: contentType,
                           data: responseData,
                           contentRange: httpResponse.allHeaderFields["Content-Range"] as? String)

            let mbTransferred = Double(totalBytesTransferred) / 1024.0 / 1024.0
            DXPlayerLogger.info("✅ [代理请求 #\(requestCount)] 完成 \(responseData.count) bytes, 状态: \(httpResponse.statusCode), 累计: \(String(format: "%.2f", mbTransferred)) MB")

        } catch {
            DXPlayerLogger.error("❌ [代理请求] 失败: \(error)")
            sendErrorResponse(connection, statusCode: 502)
        }
    }

    private func rewriteM3U8(_ data: Data, baseURL: URL) -> Data? {
        guard let content = String(data: data, encoding: .utf8) else {
            return nil
        }

        var lines = content.components(separatedBy: "\n")
        for i in 0..<lines.count {
            let line = lines[i].trimmingCharacters(in: .whitespacesAndNewlines)

            // 跳过注释和空行
            if line.isEmpty || line.hasPrefix("#") {
                continue
            }

            // 处理 URL 行
            if let absoluteURL = resolveURL(line, baseURL: baseURL) {
                // 将绝对 URL 重写为代理 URL
                let proxyURL = "http://127.0.0.1:\(port)\(absoluteURL.path)\(absoluteURL.query.map { "?\($0)" } ?? "")"
                lines[i] = proxyURL
            }
        }

        return lines.joined(separator: "\n").data(using: .utf8)
    }

    private func resolveURL(_ urlString: String, baseURL: URL) -> URL? {
        if urlString.hasPrefix("http://") || urlString.hasPrefix("https://") {
            return URL(string: urlString)
        } else {
            return URL(string: urlString, relativeTo: baseURL)?.absoluteURL
        }
    }

    private func sendHTTPResponse(_ connection: NWConnection, statusCode: Int, contentType: String, data: Data, contentRange: String? = nil) {
        // 构建 HTTP 响应头（注意：每行用 \r\n 结尾，最后用 \r\n\r\n 分隔）
        let statusText: String
        switch statusCode {
        case 200: statusText = "OK"
        case 206: statusText = "Partial Content"
        case 404: statusText = "Not Found"
        case 500: statusText = "Internal Server Error"
        case 502: statusText = "Bad Gateway"
        default: statusText = "Error"
        }

        var headers = "HTTP/1.1 \(statusCode) \(statusText)\r\n" +
                      "Content-Type: \(contentType)\r\n" +
                      "Content-Length: \(data.count)\r\n" +
                      "Access-Control-Allow-Origin: *\r\n" +
                      "Accept-Ranges: bytes\r\n"

        // 添加 Content-Range 头部（如果有）
        if let contentRange = contentRange {
            headers += "Content-Range: \(contentRange)\r\n"
        }

        headers += "Connection: keep-alive\r\n\r\n"

        guard let headerData = headers.data(using: .utf8) else {
            DXPlayerLogger.error("❌ [响应] 无法编码 HTTP 头")
            connection.cancel()
            return
        }

        var responseData = Data()
        responseData.append(headerData)
        responseData.append(data)

        connection.send(content: responseData, completion: .contentProcessed { error in
            if let error = error {
                DXPlayerLogger.error("❌ [发送响应] 失败: \(error)")
            }
            // 不立即关闭连接，让 FFmpeg 决定何时关闭
        })
    }

    private func sendErrorResponse(_ connection: NWConnection, statusCode: Int) {
        let errorHTML = "<html><body><h1>\(statusCode) Error</h1></body></html>"
        let errorData = errorHTML.data(using: .utf8) ?? Data()

        sendHTTPResponse(connection, statusCode: statusCode, contentType: "text/html", data: errorData)
    }
}

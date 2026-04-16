import UIKit
import CoreGraphics

/// 雪碧图元数据格式
public enum ThumbnailSpriteFormat {
    case webVTT    // WebVTT 格式（标准）
    case json      // JSON 格式（Bilibili 风格）
    case unknown
}

/// 缩略图元数据项
public struct ThumbnailMetadataItem {
    let startTime: TimeInterval
    let endTime: TimeInterval
    let spriteImageURL: URL
    let rect: CGRect  // 在雪碧图中的位置 (x, y, width, height)

    /// 检查时间是否在范围内
    func contains(time: TimeInterval) -> Bool {
        return time >= startTime && time < endTime
    }
}

/// 雪碧图解析器
/// 支持 WebVTT 和 JSON 两种格式
public class ThumbnailSpriteParser {

    // MARK: - Properties

    /// 解析后的元数据项列表
    public private(set) var metadataItems: [ThumbnailMetadataItem] = []

    /// 元数据格式
    private(set) var format: ThumbnailSpriteFormat = .unknown

    /// 雪碧图缓存（URL -> UIImage）
    private var spriteImageCache: [URL: UIImage] = [:]

    /// 访问队列（线程安全）
    private let accessQueue = DispatchQueue(label: "com.dxplayer.spriteparser", attributes: .concurrent)

    // MARK: - Initialization

    public init() {
        // 默认初始化
    }

    // MARK: - Public Methods

    /// 解析元数据文件
    /// - Parameters:
    ///   - data: 元数据文件内容
    ///   - baseURL: 基础 URL（用于解析相对路径）
    /// - Returns: 是否解析成功
    public func parse(data: Data, baseURL: URL) -> Bool {
        // 尝试解析为字符串
        guard let content = String(data: data, encoding: .utf8) else {
            DXPlayerLogger.error("❌ [雪碧图解析] 无法解析为字符串")
            return false
        }

        // 自动检测格式
        if content.hasPrefix("WEBVTT") {
            format = .webVTT
            return parseWebVTT(content: content, baseURL: baseURL)
        } else if content.hasPrefix("{") || content.hasPrefix("[") {
            format = .json
            return parseJSON(data: data, baseURL: baseURL)
        } else {
            DXPlayerLogger.error("❌ [雪碧图解析] 未知格式")
            return false
        }
    }

    /// 根据时间查找对应的缩略图元数据
    /// - Parameter time: 时间戳（秒）
    /// - Returns: 元数据项，如果找不到返回 nil
    func findMetadata(at time: TimeInterval) -> ThumbnailMetadataItem? {
        var result: ThumbnailMetadataItem?

        accessQueue.sync {
            // 二分查找（假设元数据按时间排序）
            result = metadataItems.first { $0.contains(time: time) }
        }

        return result
    }

    /// 从雪碧图裁剪缩略图
    /// - Parameters:
    ///   - metadata: 元数据项
    ///   - completion: 完成回调（主线程）
    func cropThumbnail(from metadata: ThumbnailMetadataItem, completion: @escaping (UIImage?) -> Void) {
        // 后台线程处理图片操作
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else {
                DispatchQueue.main.async { completion(nil) }
                return
            }

            // 检查缓存
            if let cachedImage = self.spriteImageCache[metadata.spriteImageURL] {
                let croppedImage = self.cropImage(cachedImage, rect: metadata.rect)
                DispatchQueue.main.async { completion(croppedImage) }
                return
            }

            // 下载雪碧图
            self.downloadSpriteImage(url: metadata.spriteImageURL) { spriteImage in
                guard let spriteImage = spriteImage else {
                    DispatchQueue.main.async { completion(nil) }
                    return
                }

                // 缓存雪碧图
                self.accessQueue.async(flags: .barrier) {
                    self.spriteImageCache[metadata.spriteImageURL] = spriteImage
                }

                // 裁剪图片
                let croppedImage = self.cropImage(spriteImage, rect: metadata.rect)
                DispatchQueue.main.async { completion(croppedImage) }
            }
        }
    }

    /// 预加载雪碧图图片
    /// - Parameters:
    ///   - image: 雪碧图图片
    ///   - url: 雪碧图 URL
    public func preloadSpriteImage(_ image: UIImage, for url: URL) {
        accessQueue.async(flags: .barrier) { [weak self] in
            self?.spriteImageCache[url] = image
            DXPlayerLogger.info("📦 [雪碧图解析] 已预加载雪碧图: \(url.lastPathComponent)")
        }
    }

    /// 清除缓存
    func clearCache() {
        accessQueue.async(flags: .barrier) { [weak self] in
            self?.spriteImageCache.removeAll()
            DXPlayerLogger.info("📦 [雪碧图解析] 已清除缓存")
        }
    }

    // MARK: - WebVTT Parsing

    /// 解析 WebVTT 格式
    /// - Parameters:
    ///   - content: 文件内容
    ///   - baseURL: 基础 URL
    /// - Returns: 是否解析成功
    private func parseWebVTT(content: String, baseURL: URL) -> Bool {
        let lines = content.components(separatedBy: .newlines)
        var items: [ThumbnailMetadataItem] = []

        var i = 0
        while i < lines.count {
            let line = lines[i].trimmingCharacters(in: .whitespaces)

            // 跳过 WEBVTT 头部和空行
            if line.isEmpty || line.hasPrefix("WEBVTT") || line.hasPrefix("NOTE") {
                i += 1
                continue
            }

            // 解析时间戳行：00:00:00.000 --> 00:00:02.000
            if line.contains("-->") {
                let times = line.components(separatedBy: "-->")
                guard times.count == 2 else {
                    i += 1
                    continue
                }

                let startTime = parseWebVTTTime(times[0].trimmingCharacters(in: .whitespaces))
                let endTime = parseWebVTTTime(times[1].trimmingCharacters(in: .whitespaces))

                // 下一行应该是 URL#xywh=x,y,w,h
                i += 1
                if i < lines.count {
                    let urlLine = lines[i].trimmingCharacters(in: .whitespaces)
                    if let item = parseWebVTTURL(urlLine, baseURL: baseURL, startTime: startTime, endTime: endTime) {
                        items.append(item)
                    }
                }
            }

            i += 1
        }

        metadataItems = items
        DXPlayerLogger.info("✅ [雪碧图解析] WebVTT 格式，解析了 \(items.count) 个缩略图")
        return !items.isEmpty
    }

    /// 解析 WebVTT 时间字符串
    /// - Parameter timeString: 时间字符串（HH:mm:ss.SSS 或 mm:ss.SSS）
    /// - Returns: 时间戳（秒）
    private func parseWebVTTTime(_ timeString: String) -> TimeInterval {
        let components = timeString.components(separatedBy: ":")
        var hours = 0.0
        var minutes = 0.0
        var seconds = 0.0

        if components.count == 3 {
            // HH:mm:ss.SSS
            hours = Double(components[0]) ?? 0
            minutes = Double(components[1]) ?? 0
            seconds = Double(components[2].replacingOccurrences(of: ",", with: ".")) ?? 0
        } else if components.count == 2 {
            // mm:ss.SSS
            minutes = Double(components[0]) ?? 0
            seconds = Double(components[1].replacingOccurrences(of: ",", with: ".")) ?? 0
        }

        return hours * 3600 + minutes * 60 + seconds
    }

    /// 解析 WebVTT URL 行
    /// - Parameters:
    ///   - urlLine: URL 行（例如：thumbnails.jpg#xywh=0,0,160,90）
    ///   - baseURL: 基础 URL
    ///   - startTime: 开始时间
    ///   - endTime: 结束时间
    /// - Returns: 元数据项
    private func parseWebVTTURL(_ urlLine: String, baseURL: URL, startTime: TimeInterval, endTime: TimeInterval) -> ThumbnailMetadataItem? {
        // 分离 URL 和坐标
        let parts = urlLine.components(separatedBy: "#xywh=")
        guard parts.count == 2 else { return nil }

        let imageURLString = parts[0]
        let coords = parts[1].components(separatedBy: ",").compactMap { Int($0) }
        guard coords.count == 4 else { return nil }

        // 构建完整 URL
        let imageURL = URL(string: imageURLString, relativeTo: baseURL)?.absoluteURL ?? URL(string: imageURLString)!

        let rect = CGRect(x: coords[0], y: coords[1], width: coords[2], height: coords[3])

        return ThumbnailMetadataItem(startTime: startTime, endTime: endTime, spriteImageURL: imageURL, rect: rect)
    }

    // MARK: - JSON Parsing (Bilibili Style)

    /// 解析 JSON 格式（Bilibili 风格）
    /// - Parameters:
    ///   - data: JSON 数据
    ///   - baseURL: 基础 URL
    /// - Returns: 是否解析成功
    private func parseJSON(data: Data, baseURL: URL) -> Bool {
        do {
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return false
            }

            let imgXLen = json["img_x_len"] as? Int ?? 10
            let imgYLen = json["img_y_len"] as? Int ?? 10
            let imgXSize = json["img_x_size"] as? Int ?? 160
            let imgYSize = json["img_y_size"] as? Int ?? 90
            let images = json["images"] as? [String] ?? []
            let interval = (json["interval"] as? Double) ?? 2.0  // 每个缩略图的时间间隔（秒）

            guard !images.isEmpty else { return false }

            var items: [ThumbnailMetadataItem] = []
            let totalThumbsPerImage = imgXLen * imgYLen

            for (imageIndex, imagePath) in images.enumerated() {
                // 构建完整 URL
                let imageURL = URL(string: imagePath, relativeTo: baseURL)?.absoluteURL ?? URL(string: imagePath)!

                for thumbIndex in 0..<totalThumbsPerImage {
                    let globalIndex = imageIndex * totalThumbsPerImage + thumbIndex

                    let startTime = Double(globalIndex) * interval
                    let endTime = startTime + interval

                    // 计算在雪碧图中的位置
                    let row = thumbIndex / imgXLen
                    let col = thumbIndex % imgXLen
                    let x = col * imgXSize
                    let y = row * imgYSize

                    let rect = CGRect(x: x, y: y, width: imgXSize, height: imgYSize)

                    let item = ThumbnailMetadataItem(startTime: startTime, endTime: endTime, spriteImageURL: imageURL, rect: rect)
                    items.append(item)
                }
            }

            metadataItems = items
            DXPlayerLogger.info("✅ [雪碧图解析] JSON 格式（Bilibili），解析了 \(items.count) 个缩略图")
            return true

        } catch {
            DXPlayerLogger.error("❌ [雪碧图解析] JSON 解析失败: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Image Operations

    /// 下载雪碧图
    /// - Parameters:
    ///   - url: 图片 URL
    ///   - completion: 完成回调
    private func downloadSpriteImage(url: URL, completion: @escaping (UIImage?) -> Void) {
        let task = URLSession.shared.dataTask(with: url) { data, response, error in
            if let error = error {
                DXPlayerLogger.error("❌ [雪碧图下载] 失败: \(error.localizedDescription)")
                completion(nil)
                return
            }

            guard let data = data, let image = UIImage(data: data) else {
                DXPlayerLogger.error("❌ [雪碧图下载] 无法解析图片数据")
                completion(nil)
                return
            }

            DXPlayerLogger.debug("✅ [雪碧图下载] 成功: \(url.lastPathComponent), 大小: \(data.count / 1024) KB")
            completion(image)
        }

        task.resume()
    }

    /// 裁剪图片
    /// - Parameters:
    ///   - image: 源图片
    ///   - rect: 裁剪区域
    /// - Returns: 裁剪后的图片
    private func cropImage(_ image: UIImage, rect: CGRect) -> UIImage? {
        guard let cgImage = image.cgImage else { return nil }

        // 考虑图片的 scale
        let scale = image.scale
        let scaledRect = CGRect(
            x: rect.origin.x * scale,
            y: rect.origin.y * scale,
            width: rect.size.width * scale,
            height: rect.size.height * scale
        )

        guard let croppedCGImage = cgImage.cropping(to: scaledRect) else { return nil }

        return UIImage(cgImage: croppedCGImage, scale: scale, orientation: image.imageOrientation)
    }
}

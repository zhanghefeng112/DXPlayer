import UIKit
import AVFoundation

/// 缩略图预览管理器
/// 支持雪碧图和实时生成两种模式
public class ThumbnailPreviewManager {

    // MARK: - Types

    /// 缩略图生成模式
    public enum GenerationMode {
        case spriteSheet    // 雪碧图模式（需要片源提供）
        case realtime       // 实时生成模式（从视频提取帧）
        case disabled       // 禁用模式（片源不支持微缩图）
    }

    /// 配置
    public struct Configuration {
        var mode: GenerationMode = .disabled
        var cacheSize: Int = 50
        var thumbnailSize: CGSize = CGSize(width: 160, height: 90)
        var maxConcurrentGenerations: Int = 3

        public init(mode: GenerationMode = .disabled, cacheSize: Int = 50) {
            self.mode = mode
            self.cacheSize = cacheSize
        }
    }

    // MARK: - Properties

    /// 配置
    public var configuration: Configuration

    /// 缓存管理器
    private let cache: ThumbnailCache

    /// 雪碧图解析器
    private var spriteParser: ThumbnailSpriteParser

    /// 视频 URL
    private var videoURL: URL?

    /// 视频 Asset
    private var videoAsset: AVURLAsset?

    /// 实时生成器
    private var imageGenerator: AVAssetImageGenerator?

    /// 元数据 URL
    private var metadataURL: URL?

    /// 是否已加载元数据
    private var isMetadataLoaded = false

    /// 微缩图功能是否可用（片源支持且已加载）
    public var isAvailable: Bool {
        return currentMode != .disabled && (currentMode == .realtime || isMetadataLoaded)
    }

    /// 当前生成模式
    private var currentMode: GenerationMode = .disabled

    /// 请求序列号（用于取消过期请求）
    private var requestSequence: Int = 0

    /// 访问队列
    private let accessQueue = DispatchQueue(label: "com.dxplayer.thumbnailmanager", attributes: .concurrent)

    /// 生成队列（限制并发数）
    private let generationQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 3
        queue.qualityOfService = .userInitiated
        return queue
    }()

    // MARK: - Initialization

    public init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
        self.cache = ThumbnailCache(maxSize: configuration.cacheSize)
        self.spriteParser = ThumbnailSpriteParser()
        self.currentMode = configuration.mode

        DXPlayerLogger.info("🖼️ [缩略图管理器] 初始化完成，模式: \(configuration.mode)")
    }

    deinit {
        imageGenerator?.cancelAllCGImageGeneration()
        generationQueue.cancelAllOperations()
        DXPlayerLogger.info("🖼️ [缩略图管理器] 已销毁")
    }

    // MARK: - Configuration

    /// 配置预览数据源
    /// - Parameters:
    ///   - videoURL: 视频 URL
    ///   - metadataURL: 元数据 URL（WebVTT 或 JSON，必须提供才能启用微缩图）
    public func configure(videoURL: URL, metadataURL: URL? = nil) {
        self.videoURL = videoURL
        self.metadataURL = metadataURL

        // 如果提供了元数据 URL，尝试加载雪碧图
        if let metadataURL = metadataURL {
            // 创建视频 Asset（用于备用的实时生成）
            let asset = AVURLAsset(url: videoURL)
            self.videoAsset = asset
            setupImageGenerator(asset: asset)

            loadMetadata(from: metadataURL)
        } else {
            // 没有提供元数据，禁用微缩图功能
            currentMode = .disabled
            DXPlayerLogger.info("🖼️ [缩略图管理器] 片源未提供微缩图资源，功能禁用")
        }
    }

    // MARK: - Public API

    /// 设置外部解析器（用于本地 VTT + Sprite 文件）
    /// - Parameter parser: 已解析好的雪碧图解析器
    public func setParser(_ parser: ThumbnailSpriteParser) {
        accessQueue.async(flags: .barrier) {
            // 替换解析器
            self.spriteParser = parser
            self.isMetadataLoaded = true
            self.currentMode = .spriteSheet

            DXPlayerLogger.info("🖼️ [缩略图管理器] 已设置外部解析器，共 \(parser.metadataItems.count) 个缩略图")
        }
    }

    /// 获取指定时间的缩略图
    /// - Parameters:
    ///   - time: 视频时间戳（秒）
    ///   - completion: 完成回调（主线程）
    public func getThumbnail(at time: TimeInterval, completion: @escaping (UIImage?) -> Void) {
        // 如果功能被禁用，直接返回 nil
        if currentMode == .disabled {
            DispatchQueue.main.async {
                completion(nil)
            }
            return
        }

        let cacheKey = thumbnailCacheKey(for: time)

        // 1. 检查缓存
        if let cachedImage = cache.get(cacheKey) {
            DispatchQueue.main.async {
                completion(cachedImage)
            }
            return
        }

        // 2. 根据模式生成
        if currentMode == .spriteSheet && isMetadataLoaded {
            // 雪碧图模式
            getThumbnailFromSprite(at: time, cacheKey: cacheKey, completion: completion)
        } else if currentMode == .realtime {
            // 实时生成模式（仅在显式指定时使用）
            getThumbnailFromGenerator(at: time, cacheKey: cacheKey, completion: completion)
        } else {
            // 未准备好或禁用
            DispatchQueue.main.async {
                completion(nil)
            }
        }
    }

    /// 预加载指定时间范围的缩略图
    /// - Parameters:
    ///   - startTime: 开始时间
    ///   - endTime: 结束时间
    public func preloadThumbnails(from startTime: TimeInterval, to endTime: TimeInterval) {
        DXPlayerLogger.info("🖼️ [预加载] 时间范围: \(String(format: "%.1f", startTime))s - \(String(format: "%.1f", endTime))s")

        // 计算时间间隔（根据视频长度动态调整）
        let duration = endTime - startTime
        let interval: TimeInterval
        if duration < 60 {
            interval = 2  // 短视频：每 2 秒
        } else if duration < 600 {
            interval = 5  // 中等视频：每 5 秒
        } else {
            interval = 10  // 长视频：每 10 秒
        }

        var currentTime = startTime
        while currentTime <= endTime {
            getThumbnail(at: currentTime) { _ in
                // 预加载，不需要处理结果
            }
            currentTime += interval
        }
    }

    /// 清除缓存
    public func clearCache() {
        cache.clear()
        spriteParser.clearCache()
        DXPlayerLogger.info("🖼️ [缩略图管理器] 已清除缓存")
    }

    /// 获取统计信息
    public func getStats() -> String {
        return cache.getStats()
    }

    // MARK: - Private Methods (Sprite Sheet Mode)

    /// 加载元数据文件
    /// - Parameter url: 元数据 URL
    private func loadMetadata(from url: URL) {
        DXPlayerLogger.info("🖼️ [加载元数据] URL: \(url)")

        let task = URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            guard let self = self else { return }

            if let error = error {
                DXPlayerLogger.error("❌ [加载元数据] 失败: \(error.localizedDescription)")
                // 加载失败，禁用微缩图功能
                self.currentMode = .disabled
                return
            }

            guard let data = data else {
                DXPlayerLogger.error("❌ [加载元数据] 无数据")
                self.currentMode = .disabled
                return
            }

            // 解析元数据
            if self.spriteParser.parse(data: data, baseURL: url.deletingLastPathComponent()) {
                self.isMetadataLoaded = true
                self.currentMode = .spriteSheet
                DXPlayerLogger.info("✅ [加载元数据] 成功，切换到雪碧图模式")
            } else {
                DXPlayerLogger.error("❌ [加载元数据] 解析失败")
                self.currentMode = .disabled
            }
        }

        task.resume()
    }

    /// 从雪碧图获取缩略图
    /// - Parameters:
    ///   - time: 时间戳
    ///   - cacheKey: 缓存 key
    ///   - completion: 完成回调
    private func getThumbnailFromSprite(at time: TimeInterval, cacheKey: String, completion: @escaping (UIImage?) -> Void) {
        guard let metadata = spriteParser.findMetadata(at: time) else {
            DXPlayerLogger.warning("⚠️ [雪碧图] 找不到时间 \(String(format: "%.1f", time))s 的元数据")
            DispatchQueue.main.async {
                completion(nil)
            }
            return
        }

        spriteParser.cropThumbnail(from: metadata) { [weak self] image in
            guard let self = self else { return }

            if let image = image {
                // 缓存结果
                self.cache.set(cacheKey, image: image)
                completion(image)
            } else {
                // 裁剪失败
                DXPlayerLogger.warning("⚠️ [雪碧图] 裁剪失败")
                DispatchQueue.main.async {
                    completion(nil)
                }
            }
        }
    }

    // MARK: - Private Methods (Realtime Generation Mode)

    /// 配置实时生成器
    /// - Parameter asset: 视频 Asset
    private func setupImageGenerator(asset: AVURLAsset) {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true

        // 关键优化：增加时间容差，允许使用附近的关键帧
        // 这样可以大幅提升生成速度（从几百毫秒降低到几十毫秒）
        let tolerance = CMTime(seconds: 0.5, preferredTimescale: 600)
        generator.requestedTimeToleranceBefore = tolerance
        generator.requestedTimeToleranceAfter = tolerance

        generator.maximumSize = configuration.thumbnailSize

        self.imageGenerator = generator

        DXPlayerLogger.debug("🖼️ [实时生成] 生成器已配置（时间容差: 0.5s）")
    }

    /// 从实时生成器获取缩略图
    /// - Parameters:
    ///   - time: 时间戳
    ///   - cacheKey: 缓存 key
    ///   - completion: 完成回调
    private func getThumbnailFromGenerator(at time: TimeInterval, cacheKey: String, completion: @escaping (UIImage?) -> Void) {
        guard let generator = imageGenerator else {
            DXPlayerLogger.error("❌ [实时生成] 生成器未初始化")
            DispatchQueue.main.async {
                completion(nil)
            }
            return
        }

        // 检查 Asset 是否可用
        guard let asset = videoAsset, asset.isReadable else {
            DXPlayerLogger.error("❌ [实时生成] 视频 Asset 不可读（可能是加密视频）")
            DispatchQueue.main.async {
                completion(nil)
            }
            return
        }

        // 增加序列号（用于取消过期请求）
        requestSequence += 1
        let currentSequence = requestSequence

        let cmTime = CMTime(seconds: time, preferredTimescale: 600)

        generationQueue.addOperation { [weak self] in
            guard let self = self else { return }

            // 检查是否已被取消
            if currentSequence != self.requestSequence {
                DXPlayerLogger.debug("🚫 [实时生成] 请求已过期，取消生成")
                return
            }

            // 使用异步方式生成缩略图，带超时处理
            var resultImage: UIImage?
            var generationError: Error?

            let semaphore = DispatchSemaphore(value: 0)
            let timeoutSeconds: Double = 3.0

            generator.generateCGImagesAsynchronously(forTimes: [NSValue(time: cmTime)]) { _, cgImage, _, result, error in
                if result == .succeeded, let cgImage = cgImage {
                    resultImage = UIImage(cgImage: cgImage)
                } else {
                    generationError = error
                }
                semaphore.signal()
            }

            let waitResult = semaphore.wait(timeout: .now() + timeoutSeconds)

            if waitResult == .timedOut {
                DXPlayerLogger.warning("⚠️ [实时生成] 超时（\(timeoutSeconds)s），时间: \(String(format: "%.1f", time))s")
                DispatchQueue.main.async {
                    completion(nil)
                }
                return
            }

            if let image = resultImage {
                // 缓存结果
                self.cache.set(cacheKey, image: image)

                DXPlayerLogger.debug("✅ [实时生成] 时间: \(String(format: "%.1f", time))s")

                DispatchQueue.main.async {
                    completion(image)
                }
            } else {
                if let error = generationError {
                    DXPlayerLogger.error("❌ [实时生成] 失败: \(error.localizedDescription)")
                } else {
                    DXPlayerLogger.error("❌ [实时生成] 失败: 未知错误")
                }

                DispatchQueue.main.async {
                    completion(nil)
                }
            }
        }
    }

    /// 生成缓存 key
    /// - Parameter time: 时间戳
    /// - Returns: 缓存 key
    private func thumbnailCacheKey(for time: TimeInterval) -> String {
        // 取整到最近的 0.5 秒（减少缓存 key 数量）
        let roundedTime = round(time * 2) / 2
        return "thumb_\(String(format: "%.1f", roundedTime))"
    }
}

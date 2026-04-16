import UIKit

/// 缩略图缓存管理器
/// 使用 LRU（Least Recently Used）策略，限制最多缓存 50 张图片
class ThumbnailCache {

    // MARK: - Properties

    /// 缓存节点
    private class CacheNode {
        let key: String
        var value: UIImage
        var prev: CacheNode?
        var next: CacheNode?
        var timestamp: TimeInterval

        init(key: String, value: UIImage, timestamp: TimeInterval) {
            self.key = key
            self.value = value
            self.timestamp = timestamp
        }
    }

    /// 最大缓存数量
    private let maxCacheSize: Int

    /// 缓存字典（key -> node）
    private var cache: [String: CacheNode] = [:]

    /// 双向链表头节点（最近使用）
    private var head: CacheNode?

    /// 双向链表尾节点（最久未使用）
    private var tail: CacheNode?

    /// 当前缓存数量
    private var currentSize: Int = 0

    /// 访问队列（线程安全）
    private let accessQueue = DispatchQueue(label: "com.dxplayer.thumbnailcache", attributes: .concurrent)

    /// 统计信息
    private(set) var hitCount: Int = 0
    private(set) var missCount: Int = 0

    // MARK: - Initialization

    init(maxSize: Int = 50) {
        self.maxCacheSize = maxSize

        // 监听内存警告
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMemoryWarning),
            name: UIApplication.didReceiveMemoryWarningNotification,
            object: nil
        )

        DXPlayerLogger.info("📦 [缩略图缓存] 初始化完成，最大容量: \(maxSize)")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        DXPlayerLogger.info("📦 [缩略图缓存] 已销毁")
    }

    // MARK: - Public Methods

    /// 获取缓存的图片
    /// - Parameter key: 缓存 key（通常是时间戳字符串）
    /// - Returns: 缓存的图片，如果不存在返回 nil
    func get(_ key: String) -> UIImage? {
        var result: UIImage?

        accessQueue.sync {
            if let node = cache[key] {
                // 命中缓存
                hitCount += 1

                // 移动到链表头部（标记为最近使用）
                moveToHead(node)

                result = node.value

                DXPlayerLogger.debug("📦 [缓存命中] key: \(key), 命中率: \(String(format: "%.1f%%", hitRate * 100))")
            } else {
                // 未命中
                missCount += 1

                DXPlayerLogger.debug("📦 [缓存未命中] key: \(key)")
            }
        }

        return result
    }

    /// 存入缓存
    /// - Parameters:
    ///   - key: 缓存 key
    ///   - image: 要缓存的图片
    func set(_ key: String, image: UIImage) {
        accessQueue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }

            // 如果已存在，更新并移到头部
            if let existingNode = self.cache[key] {
                existingNode.value = image
                existingNode.timestamp = Date().timeIntervalSince1970
                self.moveToHead(existingNode)

                DXPlayerLogger.debug("📦 [缓存更新] key: \(key)")
                return
            }

            // 创建新节点
            let newNode = CacheNode(key: key, value: image, timestamp: Date().timeIntervalSince1970)
            self.cache[key] = newNode
            self.addToHead(newNode)
            self.currentSize += 1

            DXPlayerLogger.debug("📦 [缓存新增] key: \(key), 当前大小: \(self.currentSize)/\(self.maxCacheSize)")

            // 如果超出容量，删除尾部节点
            if self.currentSize > self.maxCacheSize {
                if let removedNode = self.removeTail() {
                    self.cache.removeValue(forKey: removedNode.key)
                    self.currentSize -= 1

                    DXPlayerLogger.debug("📦 [缓存淘汰] key: \(removedNode.key)")
                }
            }
        }
    }

    /// 批量存入缓存
    /// - Parameter items: key-image 字典
    func setBatch(_ items: [String: UIImage]) {
        for (key, image) in items {
            set(key, image: image)
        }
    }

    /// 检查缓存是否存在
    /// - Parameter key: 缓存 key
    /// - Returns: 是否存在
    func contains(_ key: String) -> Bool {
        var result = false
        accessQueue.sync {
            result = cache[key] != nil
        }
        return result
    }

    /// 删除指定缓存
    /// - Parameter key: 缓存 key
    func remove(_ key: String) {
        accessQueue.async(flags: .barrier) { [weak self] in
            guard let self = self, let node = self.cache[key] else { return }

            self.removeNode(node)
            self.cache.removeValue(forKey: key)
            self.currentSize -= 1

            DXPlayerLogger.debug("📦 [缓存删除] key: \(key)")
        }
    }

    /// 清空所有缓存
    func clear() {
        accessQueue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }

            let previousSize = self.currentSize

            self.cache.removeAll()
            self.head = nil
            self.tail = nil
            self.currentSize = 0
            self.hitCount = 0
            self.missCount = 0

            DXPlayerLogger.info("📦 [缓存清空] 已清除 \(previousSize) 个缓存项")
        }
    }

    /// 获取缓存统计信息
    /// - Returns: 统计信息字符串
    func getStats() -> String {
        var stats = ""
        accessQueue.sync {
            stats = """
            缓存统计:
            - 当前大小: \(currentSize)/\(maxCacheSize)
            - 命中次数: \(hitCount)
            - 未命中次数: \(missCount)
            - 命中率: \(String(format: "%.1f%%", hitRate * 100))
            """
        }
        return stats
    }

    // MARK: - Private Methods

    /// 命中率
    private var hitRate: Double {
        let total = hitCount + missCount
        return total > 0 ? Double(hitCount) / Double(total) : 0.0
    }

    /// 将节点移到链表头部
    private func moveToHead(_ node: CacheNode) {
        removeNode(node)
        addToHead(node)
    }

    /// 添加节点到链表头部
    private func addToHead(_ node: CacheNode) {
        node.prev = nil
        node.next = head

        if let head = head {
            head.prev = node
        }

        head = node

        if tail == nil {
            tail = node
        }
    }

    /// 从链表中移除节点
    private func removeNode(_ node: CacheNode) {
        if let prev = node.prev {
            prev.next = node.next
        } else {
            head = node.next
        }

        if let next = node.next {
            next.prev = node.prev
        } else {
            tail = node.prev
        }

        node.prev = nil
        node.next = nil
    }

    /// 移除链表尾部节点（LRU）
    /// - Returns: 被移除的节点
    private func removeTail() -> CacheNode? {
        guard let tailNode = tail else { return nil }

        removeNode(tailNode)

        return tailNode
    }

    /// 处理内存警告
    @objc private func handleMemoryWarning() {
        DXPlayerLogger.warning("⚠️ [缩略图缓存] 收到内存警告，开始清理...")

        accessQueue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }

            let previousSize = self.currentSize

            // 保留最近使用的 10 个
            let keepCount = min(10, self.maxCacheSize / 5)
            var removedCount = 0

            // 从尾部开始删除（删除最久未使用的）
            while self.currentSize > keepCount, let tailNode = self.tail {
                self.removeNode(tailNode)
                self.cache.removeValue(forKey: tailNode.key)
                self.currentSize -= 1
                removedCount += 1
            }

            DXPlayerLogger.info("📦 [内存清理] 已清除 \(removedCount)/\(previousSize) 个缓存项，保留 \(self.currentSize) 个")
        }
    }
}

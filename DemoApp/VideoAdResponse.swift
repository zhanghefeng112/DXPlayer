import Foundation

// MARK: - API 视频+广告响应模型

/// API 响应顶层结构
struct VideoAdResponse: Codable {
    let code: Int
    let msg: String
    let data: VideoAdData
}

/// 视频+广告数据
struct VideoAdData: Codable {
    let ads: AdsPositionMap?     // 广告位配置（pos_1, pos_2, pos_3...）
    let videoUrl: String         // 主视频 URL
    let isEncryption: Int?       // 0=不加密可直接播放，1=m3u8加密需解密
    let thumbnail: ThumbnailInfo?  // 雪碧图缩略图（可选）

    enum CodingKeys: String, CodingKey {
        case ads
        case videoUrl = "video_url"
        case isEncryption = "is_encryption"
        case thumbnail
    }
}

/// 广告位映射（pos_1, pos_2, pos_3...）
struct AdsPositionMap: Codable {
    let positions: [String: [AdItem]]

    init(positions: [String: [AdItem]]) {
        self.positions = positions
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicCodingKeys.self)
        var result = [String: [AdItem]]()
        for key in container.allKeys {
            if let items = try? container.decode([AdItem].self, forKey: key) {
                result[key.stringValue] = items
            }
        }
        positions = result
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: DynamicCodingKeys.self)
        for (key, value) in positions {
            if let codingKey = DynamicCodingKeys(stringValue: key) {
                try container.encode(value, forKey: codingKey)
            }
        }
    }

    /// 所有广告平铺列表
    var allAds: [AdItem] {
        positions.values.flatMap { $0 }
    }

    /// 按位置取广告
    func getPosition(_ pos: String) -> [AdItem] {
        positions[pos] ?? []
    }

    private struct DynamicCodingKeys: CodingKey {
        var stringValue: String
        var intValue: Int?

        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }
}

/// 新版广告条目
struct AdItem: Codable {
    let adId: Int?
    let type: String?      // preroll / midroll / pause / overlay
    let format: String?    // gif / image / video
    let title: String?
    let src: String?       // 资源 URL（图片/GIF/视频）
    let duration: Int?     // 广告持续时间（秒）
    let at: Int?           // 中插/浮层广告触发秒数（可选）
    let skip: Bool?        // 是否允许跳过
    let allowSkipTime: Int? // 几秒后可跳过（0=随时）

    enum CodingKeys: String, CodingKey {
        case adId = "ad_id"
        case type, format, title, src, duration, at, skip
        case allowSkipTime = "allow_skip_time"
    }

    /// 转换为旧版 AdInfo（向下兼容）
    func toAdInfo() -> AdInfo {
        let isVideo = format == "video"
        return AdInfo(
            id: adId,
            imgUrlFull: isVideo ? nil : src,
            url: nil,
            mvM3u8: isVideo ? src : nil,
            adType: nil
        )
    }
}

// MARK: - 向下兼容便捷属性

extension VideoAdData {

    /// 第一个 preroll 类型的广告（片头广告）
    var prerollAd: AdItem? {
        ads?.allAds.first { $0.type == "preroll" }
    }

    /// 第一个 pause 类型的广告（暂停广告）
    var pauseAd: AdItem? {
        ads?.allAds.first { $0.type == "pause" }
    }

    /// 第一个 midroll 类型的广告（中插广告）
    var midrollAd: AdItem? {
        ads?.allAds.first { $0.type == "midroll" }
    }

    /// 所有 midroll 类型的广告（按 at 秒数排序）
    var midrollAds: [AdItem] {
        (ads?.allAds.filter { $0.type == "midroll" } ?? [])
            .sorted { ($0.at ?? 0) < ($1.at ?? 0) }
    }

    /// 第一个 overlay 类型的广告（浮层广告）
    var overlayAd: AdItem? {
        ads?.allAds.first { $0.type == "overlay" }
    }

    /// 所有 overlay 类型的广告
    var overlayAds: [AdItem] {
        ads?.allAds.filter { $0.type == "overlay" } ?? []
    }

    /// 兼容旧 adImg：取第一个 pause + image 格式的广告
    var adImg: [AdInfo]? {
        let items = ads?.allAds.filter { $0.type == "pause" && $0.format == "image" } ?? []
        return items.isEmpty ? nil : items.map { $0.toAdInfo() }
    }

    /// 兼容旧 adGif：取第一个 pause + gif 格式的广告
    var adGif: [AdInfo]? {
        let items = ads?.allAds.filter { $0.type == "pause" && $0.format == "gif" } ?? []
        return items.isEmpty ? nil : items.map { $0.toAdInfo() }
    }

    /// 兼容旧 adVideo：取第一个 preroll + video 格式的广告
    var adVideo: [AdInfo]? {
        let items = ads?.allAds.filter { $0.type == "preroll" && $0.format == "video" } ?? []
        return items.isEmpty ? nil : items.map { $0.toAdInfo() }
    }
}

/// 雪碧图缩略图信息
struct ThumbnailInfo: Codable {
    let vttUrl: String       // WebVTT 元数据文件 URL
    let spriteUrls: [String] // 雪碧图大图 URL 列表

    enum CodingKeys: String, CodingKey {
        case vttUrl = "vtt_url"
        case spriteUrls = "sprite_urls"
    }
}

/// 广告信息（旧版兼容，下游代码仍使用）
struct AdInfo: Codable {
    let id: Int?
    let imgUrlFull: String?   // 图片/GIF URL
    let url: String?          // 跳转链接
    let mvM3u8: String?       // 视频广告 m3u8 URL
    let adType: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case imgUrlFull = "img_url_full"
        case url
        case mvM3u8 = "mv_m3u8"
        case adType = "ad_type"
    }
}

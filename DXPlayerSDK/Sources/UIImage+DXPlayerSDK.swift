//
//  UIImage+DXPlayerSDK.swift
//  DXPlayerSDK
//
//  Created by DXPlayer Team
//

import UIKit

/// UIImage 扩展，用于从 DXPlayerSDK Framework Bundle 加载图片资源
extension UIImage {

    /// 从 DXPlayerSDK 的 Bundle 中加载图片
    /// - Parameter name: 图片名稱（不包含扩展名）
    /// - Returns: UIImage 实例，如果图片不存在则返回 nil
    static func dxPlayerImage(named name: String) -> UIImage? {
        // 获取 Framework 的 Bundle
        let frameworkBundle = Bundle(for: IJKPlayerContainerView.self)

        // 先尝试从 Asset Catalog 加载
        if let image = UIImage(named: name, in: frameworkBundle, compatibleWith: nil) {
            return image
        }

        // 如果 Asset Catalog 不可用，尝试从 Assets.xcassets 目錄直接加载图片文件
        let imagePath = frameworkBundle.path(forResource: name, ofType: "png", inDirectory: "Assets.xcassets/\(name).imageset")
        if let path = imagePath, let image = UIImage(contentsOfFile: path) {
            return image
        }

        DXPlayerLogger.warning("无法加载图片资源: \(name)")
        return nil
    }

    /// 从 DXPlayerSDK 的 Bundle 中加载图片并设置渲染模式
    /// - Parameters:
    ///   - name: 图片名稱
    ///   - renderingMode: 渲染模式
    /// - Returns: UIImage 实例
    static func dxPlayerImage(named name: String, renderingMode: UIImage.RenderingMode) -> UIImage? {
        return dxPlayerImage(named: name)?.withRenderingMode(renderingMode)
    }
}

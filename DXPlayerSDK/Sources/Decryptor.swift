//
//  Decryptor.swift
//  IJKPlayerDemo
//
//  Created by mac on 8/11/25.
//
//  依赖：
//   - CryptoKit（系统自带，用于 AES-GCM / ChaChaPoly / RSA 验签等场景）
//   - CommonCrypto（可选，用于 AES-CBC 等传统模式；Xcode 工程里可直接 import CommonCrypto）
//

import Foundation
#if canImport(CryptoKit)
import CryptoKit
#endif
#if canImport(Compression)
import Compression
#endif
#if canImport(CommonCrypto)
import CommonCrypto
#endif

public enum DecryptError: Error {
    case invalidInput
    case base64DecodeFailed
    case hexDecodeFailed
    case decryptFailed(String)
    case decompressFailed
    case encodingFailed
    case unsupportedEncryptionType(String)
    case invalidEncryptionHeader
}

// MARK: - 后端加密类型
/// 后端加密约定的类型标识
public enum JmEncryptionType: String {
    case base64 = "AA"
    case xor = "AB"
    case aesECB = "AC"
    case aesCBC = "AD"
    case aesCFB = "AE"
    case aesOFB = "AF"
}

/// 后端加密约定解析结果
public struct JmEncryptionHeader {
    public let type: JmEncryptionType
    public let key: Data
    public let iv: Data
}

public struct DecryptResult {
    public let data: Data
    public var utf8String: String? { String(data: data, encoding: .utf8) }
}

/// 解密/解码常用方法集合
public final class Decryptor {


    // MARK: - 单例入口
    public static let shared = Decryptor()

    // MARK: - 網路配置
    /// 預設重試次數
    private let maxRetryCount = 3
    /// 重試延遲（秒）
    private let retryDelay: TimeInterval = 1.0

    /// 配置超時的 URLSession
    private lazy var urlSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15  // 請求超時 15 秒
        config.timeoutIntervalForResource = 30 // 資源超時 30 秒
        config.waitsForConnectivity = true     // 等待網路連接
        return URLSession(configuration: config)
    }()

    // 禁止外部初始化
    private init() {}

    // MARK: - Base64
    /// 标准 Base64 解码
    public func base64Decode(_ base64: String) throws -> DecryptResult {
        guard let data = Data(base64Encoded: base64) else {
            throw DecryptError.base64DecodeFailed
        }
        return DecryptResult(data: data)
    }

    /// URL-Safe Base64 解码（将 '-' -> '+', '_' -> '/'，自动补齐'='）
    public func base64URLSafeDecode(_ base64URL: String) throws -> DecryptResult {
        var s = base64URL
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        // 补齐 padding
        let mod = s.count % 4
        if mod != 0 { s.append(String(repeating: "=", count: 4 - mod)) }
        return try base64Decode(s)
    }

    // MARK: - Hex
    public func hexDecode(_ hex: String) throws -> DecryptResult {
        let clean = hex.replacingOccurrences(of: " ", with: "").lowercased()
        guard clean.count % 2 == 0 else { throw DecryptError.hexDecodeFailed }
        var bytes = Data(capacity: clean.count / 2)
        var idx = clean.startIndex
        while idx < clean.endIndex {
            let next = clean.index(idx, offsetBy: 2)
            guard next <= clean.endIndex else { throw DecryptError.hexDecodeFailed }
            let byteStr = clean[idx..<next]
            guard let b = UInt8(byteStr, radix: 16) else { throw DecryptError.hexDecodeFailed }
            bytes.append(b)
            idx = next
        }
        return DecryptResult(data: bytes)
    }


    // MARK: - 压缩解包（很多 m3u8 元数据会先 base64 再压缩）
    /// 自动尝试 GZIP/DEFLATE（zlib）解压（失败则原样返回）
    public func tryDecompress(_ data: Data) -> DecryptResult {
        #if canImport(Compression)
        if let gunzipped = decompress(data, algorithm: COMPRESSION_ZLIB) { // 常见是 zlib/gzip 容器
            return DecryptResult(data: gunzipped)
        }
        if let deflated = decompress(data, algorithm: COMPRESSION_LZFSE) {
            return DecryptResult(data: deflated)
        }
        #endif
        return DecryptResult(data: data)
    }

    #if canImport(Compression)
    private func decompress(_ data: Data, algorithm: compression_algorithm) -> Data? {
        let dstCap = max(data.count * 4, 32 * 1024) // 预估输出
        return data.withUnsafeBytes { srcPtr in
            var out = Data(count: dstCap)
            let decodedSize = out.withUnsafeMutableBytes { dstPtr -> Int in
                let size = compression_decode_buffer(
                    dstPtr.bindMemory(to: UInt8.self).baseAddress!,
                    dstCap,
                    srcPtr.bindMemory(to: UInt8.self).baseAddress!,
                    data.count,
                    nil,
                    algorithm
                )
                return size
            }
            if decodedSize == 0 { return nil }
            out.removeSubrange(decodedSize..<out.count)
            return out
        }
    }
    #endif

    // MARK: - AES（推荐优先使用 GCM；如服务端是 CBC 就用 CBC）
    /// AES-GCM 解密（CryptoKit）
    /// - Parameters:
    ///   - key: 16/24/32字节
    ///   - nonce: 12字节（推荐）
    ///   - cipher: 密文 + 认证标签（合并在一起或分开传）
    ///   - tag: 可选，若密文未拼接 tag 则传此参数
    @available(iOS 13, macOS 10.15, *)
    public func aesGCMDecrypt(key: Data, nonce: Data, cipher: Data, tag: Data? = nil) throws -> DecryptResult {
        #if canImport(CryptoKit)
        let symKey = SymmetricKey(data: key)
        let sealedBox: AES.GCM.SealedBox
        if let tag = tag {
            sealedBox = try AES.GCM.SealedBox(nonce: AES.GCM.Nonce(data: nonce),
                                              ciphertext: cipher,
                                              tag: tag)
        } else {
            // 假设 cipher 已附带 tag（常见是 [cipher|tag]）
            // 若你确定是 [nonce|cipher|tag]，请自行拆分后传入
            sealedBox = try AES.GCM.SealedBox(combined: nonce + cipher) // 这里仅示例，不确定拼接格式的请手动构造
        }
        let out = try AES.GCM.open(sealedBox, using: symKey)
        return DecryptResult(data: out)
        #else
        throw DecryptError.decryptFailed("CryptoKit 不可用")
        #endif
    }

    /// AES-CBC-PKCS7 解密（CommonCrypto）
    public func aesCBCDecrypt(key: Data, iv: Data, cipher: Data) throws -> DecryptResult {
        #if canImport(CommonCrypto)
        let keyLen = key.count
        let valid = [kCCKeySizeAES128, kCCKeySizeAES192, kCCKeySizeAES256]
        guard valid.contains(keyLen), iv.count == kCCBlockSizeAES128 else {
            throw DecryptError.decryptFailed("AES-CBC 参数非法")
        }

        var out = Data(count: cipher.count + kCCBlockSizeAES128)
        let outCapacity = out.count
        var outLen: size_t = 0

        let status = out.withUnsafeMutableBytes { outPtr -> CCCryptorStatus in
            let o = outPtr.baseAddress
            return cipher.withUnsafeBytes { inPtr -> CCCryptorStatus in
                let c = inPtr.baseAddress
                return key.withUnsafeBytes { keyPtr -> CCCryptorStatus in
                    let k = keyPtr.baseAddress
                    return iv.withUnsafeBytes { ivPtr -> CCCryptorStatus in
                        let v = ivPtr.baseAddress
                        return CCCrypt(
                            CCOperation(kCCDecrypt),
                            CCAlgorithm(kCCAlgorithmAES),
                            CCOptions(kCCOptionPKCS7Padding),
                            k, keyLen,
                            v,
                            c, cipher.count,
                            o, outCapacity,   // ✅ 用提前保存的 outCapacity
                            &outLen
                        )
                    }
                }
            }
        }

        guard status == kCCSuccess else {
            throw DecryptError.decryptFailed("AES-CBC 解密失败, code=\(status)")
        }
        out.removeSubrange(outLen..<out.count)
        return DecryptResult(data: out)
        #else
        throw DecryptError.decryptFailed("需要 CommonCrypto 支持")
        #endif
    }


    // MARK: - ChaCha20-Poly1305（CryptoKit）
    @available(iOS 13, macOS 10.15, *)
    public func chachaPolyDecrypt(key: Data, nonce: Data, cipher: Data, tag: Data) throws -> DecryptResult {
        #if canImport(CryptoKit)
        let symKey = SymmetricKey(data: key)
        let sealed = try ChaChaPoly.SealedBox(nonce: try .init(data: nonce),
                                              ciphertext: cipher, tag: tag)
        let out = try ChaChaPoly.open(sealed, using: symKey)
        return DecryptResult(data: out)
        #else
        throw DecryptError.decryptFailed("CryptoKit 不可用")
        #endif
    }

    // MARK: - 便捷：从 URL 拉取 Base64 并转明文（m3u8 常见流程）
    /// 下载远端内容 -> 识别/清洗 Base64 -> 解码 -> 尝试解压 -> 以 UTF-8 返回
    /// 兼容 iOS 12（使用 completion handler）
    public func fetchAndDecodeBase64Text(from url: URL,
                                         isURLSafe: Bool = false,
                                         autoDecompress: Bool = true,
                                         trimWhitespace: Bool = true,
                                         completion: @escaping (Result<String, Error>) -> Void) {

        let task = urlSession.dataTask(with: url) { [weak self] data, response, error in
            guard let self = self else { return }

            if let error = error {
                completion(.failure(error))
                return
            }
            guard let data = data else {
                completion(.failure(DecryptError.invalidInput))
                return
            }

            var raw = String(data: data, encoding: .utf8) ?? data.base64EncodedString()

            if trimWhitespace {
                raw = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            // 去掉 dataURI 或 BOM
            if let range = raw.range(of: "base64,") {
                raw = String(raw[range.upperBound...])
            }

            //去掉BOM, \u{feff} 是 Unicode 字符 U+FEFF，也就是 UTF-8 的 BOM 标记。如果字符串开头有它，去掉即可。
            raw = raw.replacingOccurrences(of: "\u{FEFF}", with: "")

            do {
                let decoded: DecryptResult = isURLSafe
                    ? try self.base64URLSafeDecode(raw)
                    : try self.base64Decode(raw)

                let finalData = autoDecompress ? self.tryDecompress(decoded.data).data : decoded.data
                if let txt = String(data: finalData, encoding: .utf8) ?? self.guessString(finalData) {
                    completion(.success(txt))
                } else {
                    completion(.failure(DecryptError.encodingFailed))
                }
            } catch {
                completion(.failure(error))
            }
        }
        task.resume()
    }


    /// 简易编码猜测（UTF-8 优先，退回到 GBK/ShiftJIS 可按需扩展）
    private func guessString(_ data: Data) -> String? {
        // 若需要可接入 CFStringConvertEncodingToNSStringEncoding 做更多编码尝试
        return String(data: data, encoding: .utf8)
    }

    // MARK: - 后端加密格式解密 (JM 格式)

    /// 解析后端加密数据
    /// 数据格式: [加密内容] + [加密约定] + [加密约定长度(2位数字)]
    /// 加密约定格式: {加密类型(2字符)} + {key长度(2位数字)} + {key} + {iv长度(2位数字)} + {iv}
    ///
    /// - Parameter data: 加密后的原始数据（可以是 base64 解码后的 Data，或直接的二进制数据）
    /// - Returns: 解密后的数据
    public func decryptJmFormat(_ data: Data) throws -> DecryptResult {
        print("🔐 [JM解密] 开始解密，数据大小: \(data.count) 字节")

        // 显示末尾 60 字节用于调试
        if data.count > 60 {
            let tail = data.suffix(60)
            let tailHex = tail.map { String(format: "%02x", $0) }.joined(separator: " ")
            print("🔐 [JM解密] 末尾60字节 (hex): \(tailHex)")
            if let tailStr = String(data: tail, encoding: .utf8) {
                print("🔐 [JM解密] 末尾60字节 (utf8): \(tailStr)")
            }
        }

        // 1. 解析加密约定
        let (header, encryptedContent) = try parseJmEncryptionHeader(data)

        print("🔐 [JM解密] 类型: \(header.type.rawValue), key长度: \(header.key.count), iv长度: \(header.iv.count)")

        // 2. 根据加密类型解密内容
        let decryptedData: Data
        switch header.type {
        case .base64:
            // Base64 编码，支持标准和 URL-safe 两种格式
            guard let base64String = String(data: encryptedContent, encoding: .utf8) else {
                throw DecryptError.decryptFailed("无法将内容转换为 Base64 字符串")
            }

            // 先尝试标准 Base64
            var decoded: Data? = Data(base64Encoded: base64String)

            // 如果失败，尝试 URL-safe Base64
            if decoded == nil {
                var urlSafe = base64String
                    .replacingOccurrences(of: "-", with: "+")
                    .replacingOccurrences(of: "_", with: "/")
                let padding = (4 - urlSafe.count % 4) % 4
                urlSafe += String(repeating: "=", count: padding)
                decoded = Data(base64Encoded: urlSafe)
                if decoded != nil {
                    print("🔐 [JM解密] 使用 URL-safe Base64 解码成功")
                }
            }

            guard let firstDecode = decoded else {
                throw DecryptError.base64DecodeFailed
            }

            // 检查解码后是否还是 Base64 编码（双层编码）
            if let secondString = String(data: firstDecode, encoding: .utf8) {
                let trimmed = secondString.trimmingCharacters(in: .whitespacesAndNewlines)
                // 检查是否是有效的 m3u8（以 #EXT 开头）
                if trimmed.hasPrefix("#EXT") {
                    // 已经是 m3u8，直接使用
                    print("🔐 [JM解密] 第一次解码后已是 m3u8 格式")
                    decryptedData = firstDecode
                } else {
                    // 尝试二次 Base64 解码（支持标准和 URL-safe）
                    var secondDecode = Data(base64Encoded: trimmed)
                    if secondDecode == nil {
                        // 尝试 URL-safe Base64
                        var urlSafe = trimmed
                            .replacingOccurrences(of: "-", with: "+")
                            .replacingOccurrences(of: "_", with: "/")
                        let padding = (4 - urlSafe.count % 4) % 4
                        urlSafe += String(repeating: "=", count: padding)
                        secondDecode = Data(base64Encoded: urlSafe)
                    }

                    if let finalData = secondDecode {
                        print("🔐 [JM解密] 检测到双层 Base64 编码，已完成二次解码")
                        decryptedData = finalData
                    } else {
                        // 无法二次解码，使用第一次解码结果
                        print("🔐 [JM解密] 二次解码失败，使用第一次解码结果")
                        decryptedData = firstDecode
                    }
                }
            } else {
                decryptedData = firstDecode
            }

        case .xor:
            // XOR 解密：内容是 Base64 编码的，需要先解码再 XOR
            guard let base64String = String(data: encryptedContent, encoding: .utf8) else {
                throw DecryptError.decryptFailed("XOR: 无法将内容转换为字符串")
            }

            // Base64 解码（支持标准和 URL-safe）
            var base64Decoded = Data(base64Encoded: base64String)
            if base64Decoded == nil {
                var urlSafe = base64String
                    .replacingOccurrences(of: "-", with: "+")
                    .replacingOccurrences(of: "_", with: "/")
                let padding = (4 - urlSafe.count % 4) % 4
                urlSafe += String(repeating: "=", count: padding)
                base64Decoded = Data(base64Encoded: urlSafe)
            }

            guard let decodedData = base64Decoded else {
                throw DecryptError.decryptFailed("XOR: Base64 解码失败")
            }

            print("🔐 [JM解密] XOR: Base64 解码成功，大小 \(decodedData.count)")
            decryptedData = xorDecrypt(data: decodedData, key: header.key)

        case .aesECB, .aesCBC, .aesCFB, .aesOFB:
            // AES 解密：内容是 Base64 编码的，需要先解码
            guard let base64String = String(data: encryptedContent, encoding: .utf8) else {
                throw DecryptError.decryptFailed("AES: 无法将内容转换为字符串")
            }

            // Base64 解码（支持标准和 URL-safe）
            var base64Decoded = Data(base64Encoded: base64String)
            if base64Decoded == nil {
                var urlSafe = base64String
                    .replacingOccurrences(of: "-", with: "+")
                    .replacingOccurrences(of: "_", with: "/")
                let padding = (4 - urlSafe.count % 4) % 4
                urlSafe += String(repeating: "=", count: padding)
                base64Decoded = Data(base64Encoded: urlSafe)
            }

            guard let decodedCipher = base64Decoded else {
                throw DecryptError.decryptFailed("AES: Base64 解码失败")
            }

            print("🔐 [JM解密] AES: Base64 解码成功，大小 \(decodedCipher.count)")

            switch header.type {
            case .aesECB:
                decryptedData = try aesECBDecrypt(key: header.key, cipher: decodedCipher).data
            case .aesCBC:
                decryptedData = try aesCBCDecrypt(key: header.key, iv: header.iv, cipher: decodedCipher).data
            case .aesCFB:
                decryptedData = try aesCFBDecrypt(key: header.key, iv: header.iv, cipher: decodedCipher).data
            case .aesOFB:
                decryptedData = try aesOFBDecrypt(key: header.key, iv: header.iv, cipher: decodedCipher).data
            default:
                fatalError("Unexpected AES type")
            }
        }

        return DecryptResult(data: decryptedData)
    }

    /// 解析加密约定头部
    /// - Parameter data: 完整的加密数据
    /// - Returns: (加密约定, 加密内容)
    private func parseJmEncryptionHeader(_ data: Data) throws -> (JmEncryptionHeader, Data) {
        // 数据格式: [内容] + [加密约定] + [加密约定长度]
        // 加密约定格式: {类型(2字符)} + {key长度(2字符)} + {key} + {iv长度(2字符)} + {iv}
        // 注意：加密约定长度本身的位数不固定，需要从末尾动态读取
        guard data.count >= 2 else {
            throw DecryptError.invalidEncryptionHeader
        }

        // 1. 从末尾动态读取加密约定长度（连续的数字字符）
        let (headerLen, headerLenDigits) = try parseTrailingNumber(from: data)

        print("🔐 [解密] 加密约定长度: \(headerLen) (\(headerLenDigits)位数字)")

        // 2. 验证数据长度
        guard data.count >= headerLen + headerLenDigits else {
            throw DecryptError.invalidEncryptionHeader
        }

        // 3. 提取加密约定
        let headerStartIndex = data.count - headerLenDigits - headerLen
        let headerData = data[headerStartIndex..<(data.count - headerLenDigits)]

        // 4. 提取加密内容
        let encryptedContent = data.prefix(headerStartIndex)

        // 5. 解析加密约定: {类型(2)} + {key长度(2)} + {key} + {iv长度(2)} + {iv}
        // 注意：IV 可能是二进制数据，不能用 UTF-8 解码整个 header
        // 需要逐步解析，只对 ASCII 部分使用字符串解码

        let headerBytes = Array(headerData)
        var byteIndex = 0

        // 读取加密类型 (固定2字节 ASCII)
        guard headerBytes.count >= 2 else {
            print("❌ [解析] header 太短，无法读取加密类型")
            throw DecryptError.invalidEncryptionHeader
        }
        let typeBytes = Data(headerBytes[0..<2])
        guard let typeStr = String(data: typeBytes, encoding: .utf8) else {
            print("❌ [解析] 无法解码加密类型")
            throw DecryptError.invalidEncryptionHeader
        }
        guard let encryptionType = JmEncryptionType(rawValue: typeStr) else {
            print("❌ [解析] 未知加密类型: \(typeStr)")
            throw DecryptError.unsupportedEncryptionType(typeStr)
        }
        byteIndex = 2
        print("🔐 [解析] 加密类型: \(typeStr)")

        // 读取 key 长度 (固定2字节 ASCII)
        guard headerBytes.count >= byteIndex + 2 else {
            print("❌ [解析] header 太短，无法读取 key 长度")
            throw DecryptError.invalidEncryptionHeader
        }
        let keyLenBytes = Data(headerBytes[byteIndex..<byteIndex+2])
        guard let keyLenStr = String(data: keyLenBytes, encoding: .utf8),
              let keyLen = Int(keyLenStr) else {
            print("❌ [解析] 无法解码 key 长度")
            throw DecryptError.invalidEncryptionHeader
        }
        byteIndex += 2
        print("🔐 [解析] key 长度: \(keyLen)")

        // 读取 key (ASCII 字符串)
        guard headerBytes.count >= byteIndex + keyLen else {
            print("❌ [解析] header 太短，无法读取 key")
            throw DecryptError.invalidEncryptionHeader
        }
        let keyData = Data(headerBytes[byteIndex..<byteIndex+keyLen])
        byteIndex += keyLen
        if let keyStr = String(data: keyData, encoding: .utf8) {
            print("🔐 [解析] key: \(keyStr)")
        }

        // 读取 iv 长度 (固定2字节 ASCII)
        guard headerBytes.count >= byteIndex + 2 else {
            print("❌ [解析] header 太短，无法读取 iv 长度")
            throw DecryptError.invalidEncryptionHeader
        }
        let ivLenBytes = Data(headerBytes[byteIndex..<byteIndex+2])
        guard let ivLenStr = String(data: ivLenBytes, encoding: .utf8),
              let ivLen = Int(ivLenStr) else {
            print("❌ [解析] 无法解码 iv 长度")
            throw DecryptError.invalidEncryptionHeader
        }
        byteIndex += 2
        print("🔐 [解析] iv 长度: \(ivLen)")

        // 读取 iv (可能是二进制数据！)
        let ivData: Data
        if ivLen > 0 {
            guard headerBytes.count >= byteIndex + ivLen else {
                print("❌ [解析] header 太短，无法读取 iv")
                throw DecryptError.invalidEncryptionHeader
            }
            ivData = Data(headerBytes[byteIndex..<byteIndex+ivLen])
            print("🔐 [解析] iv (hex): \(ivData.map { String(format: "%02x", $0) }.joined())")
        } else {
            ivData = Data()
        }

        let tailLen = headerLen
        let bodyLen = encryptedContent.count
        let keyPreview = String(data: keyData.prefix(16), encoding: .utf8) ?? keyData.prefix(16).map { String(format: "%02x", $0) }.joined()
        let ivPreview = ivData.prefix(9).map { String(format: "%02x", $0) }.joined()
        print("🔐 [JM解密] 解析結果: {\"t\": \"\(typeStr)\", \"keyLen\": \(keyLen), \"ivLen\": \(ivLen), \"tailLen\": \(tailLen), \"bodyLen\": \(bodyLen), \"keyPreview\": \"\(keyPreview)\", \"ivPreview\": \"\(ivPreview)\"}")

        let header = JmEncryptionHeader(type: encryptionType, key: keyData, iv: ivData)
        return (header, Data(encryptedContent))
    }

    /// 从 Data 末尾解析连续的数字字符（用于加密约定长度，因为它在最末尾，后面没有其他内容）
    /// - Returns: (解析出的数字, 数字的位数)
    private func parseTrailingNumber(from data: Data) throws -> (Int, Int) {
        var digits: [UInt8] = []
        let bytes = Array(data)

        // 从末尾往前读取连续的 ASCII 数字 ('0'-'9' = 48-57)
        for i in stride(from: bytes.count - 1, through: 0, by: -1) {
            let byte = bytes[i]
            if byte >= 48 && byte <= 57 {
                digits.insert(byte, at: 0)
            } else {
                break
            }
        }

        print("🔐 [解析长度] 找到 \(digits.count) 个数字: \(String(bytes: digits, encoding: .utf8) ?? "无法解码")")

        guard !digits.isEmpty,
              let numStr = String(bytes: digits, encoding: .utf8),
              let num = Int(numStr) else {
            print("❌ [解析长度] 无法解析末尾数字")
            throw DecryptError.invalidEncryptionHeader
        }

        return (num, digits.count)
    }

    // MARK: - XOR 解密

    /// XOR 解密
    private func xorDecrypt(data: Data, key: Data) -> Data {
        guard !key.isEmpty else { return data }

        var result = Data(count: data.count)
        for i in 0..<data.count {
            result[i] = data[i] ^ key[i % key.count]
        }
        return result
    }

    // MARK: - AES-ECB 解密

    /// AES-ECB-PKCS7 解密
    public func aesECBDecrypt(key: Data, cipher: Data) throws -> DecryptResult {
        #if canImport(CommonCrypto)
        let keyLen = key.count
        let valid = [kCCKeySizeAES128, kCCKeySizeAES192, kCCKeySizeAES256]
        guard valid.contains(keyLen) else {
            throw DecryptError.decryptFailed("AES-ECB key 长度非法: \(keyLen)")
        }

        var out = Data(count: cipher.count + kCCBlockSizeAES128)
        let outCapacity = out.count
        var outLen: size_t = 0

        let status = out.withUnsafeMutableBytes { outPtr -> CCCryptorStatus in
            let o = outPtr.baseAddress
            return cipher.withUnsafeBytes { inPtr -> CCCryptorStatus in
                let c = inPtr.baseAddress
                return key.withUnsafeBytes { keyPtr -> CCCryptorStatus in
                    let k = keyPtr.baseAddress
                    return CCCrypt(
                        CCOperation(kCCDecrypt),
                        CCAlgorithm(kCCAlgorithmAES),
                        CCOptions(kCCOptionPKCS7Padding | kCCOptionECBMode),
                        k, keyLen,
                        nil, // ECB 模式不需要 IV
                        c, cipher.count,
                        o, outCapacity,
                        &outLen
                    )
                }
            }
        }

        guard status == kCCSuccess else {
            throw DecryptError.decryptFailed("AES-ECB 解密失败, code=\(status)")
        }
        out.removeSubrange(outLen..<out.count)
        return DecryptResult(data: out)
        #else
        throw DecryptError.decryptFailed("需要 CommonCrypto 支持")
        #endif
    }

    // MARK: - AES-CFB 解密

    /// AES-CFB 解密（使用 CommonCrypto 的流模式模拟）
    public func aesCFBDecrypt(key: Data, iv: Data, cipher: Data) throws -> DecryptResult {
        #if canImport(CommonCrypto)
        // CommonCrypto 不直接支持 CFB，这里使用 CCCryptorCreateWithMode
        let keyLen = key.count
        let valid = [kCCKeySizeAES128, kCCKeySizeAES192, kCCKeySizeAES256]
        guard valid.contains(keyLen), iv.count == kCCBlockSizeAES128 else {
            throw DecryptError.decryptFailed("AES-CFB 参数非法")
        }

        var cryptor: CCCryptorRef?
        var status = key.withUnsafeBytes { keyPtr -> CCCryptorStatus in
            let k = keyPtr.baseAddress
            return iv.withUnsafeBytes { ivPtr -> CCCryptorStatus in
                let v = ivPtr.baseAddress
                return CCCryptorCreateWithMode(
                    CCOperation(kCCDecrypt),
                    CCMode(kCCModeCFB),
                    CCAlgorithm(kCCAlgorithmAES),
                    CCPadding(ccNoPadding),
                    v, k, keyLen,
                    nil, 0, 0,
                    CCModeOptions(kCCModeOptionCTR_BE),
                    &cryptor
                )
            }
        }

        guard status == kCCSuccess, let c = cryptor else {
            throw DecryptError.decryptFailed("AES-CFB 创建解密器失败, code=\(status)")
        }

        defer { CCCryptorRelease(c) }

        var out = Data(count: cipher.count)
        var outLen: size_t = 0
        let outCapacity = out.count

        status = out.withUnsafeMutableBytes { outPtr -> CCCryptorStatus in
            let o = outPtr.baseAddress
            return cipher.withUnsafeBytes { inPtr -> CCCryptorStatus in
                let i = inPtr.baseAddress
                return CCCryptorUpdate(c, i, cipher.count, o, outCapacity, &outLen)
            }
        }

        guard status == kCCSuccess else {
            throw DecryptError.decryptFailed("AES-CFB 解密失败, code=\(status)")
        }

        out.removeSubrange(outLen..<out.count)
        return DecryptResult(data: out)
        #else
        throw DecryptError.decryptFailed("需要 CommonCrypto 支持")
        #endif
    }

    // MARK: - AES-OFB 解密

    /// AES-OFB 解密
    public func aesOFBDecrypt(key: Data, iv: Data, cipher: Data) throws -> DecryptResult {
        #if canImport(CommonCrypto)
        let keyLen = key.count
        let valid = [kCCKeySizeAES128, kCCKeySizeAES192, kCCKeySizeAES256]
        guard valid.contains(keyLen), iv.count == kCCBlockSizeAES128 else {
            throw DecryptError.decryptFailed("AES-OFB 参数非法")
        }

        var cryptor: CCCryptorRef?
        var status = key.withUnsafeBytes { keyPtr -> CCCryptorStatus in
            let k = keyPtr.baseAddress
            return iv.withUnsafeBytes { ivPtr -> CCCryptorStatus in
                let v = ivPtr.baseAddress
                return CCCryptorCreateWithMode(
                    CCOperation(kCCDecrypt),
                    CCMode(kCCModeOFB),
                    CCAlgorithm(kCCAlgorithmAES),
                    CCPadding(ccNoPadding),
                    v, k, keyLen,
                    nil, 0, 0,
                    0,
                    &cryptor
                )
            }
        }

        guard status == kCCSuccess, let c = cryptor else {
            throw DecryptError.decryptFailed("AES-OFB 创建解密器失败, code=\(status)")
        }

        defer { CCCryptorRelease(c) }

        var out = Data(count: cipher.count)
        var outLen: size_t = 0
        let outCapacity = out.count

        status = out.withUnsafeMutableBytes { outPtr -> CCCryptorStatus in
            let o = outPtr.baseAddress
            return cipher.withUnsafeBytes { inPtr -> CCCryptorStatus in
                let i = inPtr.baseAddress
                return CCCryptorUpdate(c, i, cipher.count, o, outCapacity, &outLen)
            }
        }

        guard status == kCCSuccess else {
            throw DecryptError.decryptFailed("AES-OFB 解密失败, code=\(status)")
        }

        out.removeSubrange(outLen..<out.count)
        return DecryptResult(data: out)
        #else
        throw DecryptError.decryptFailed("需要 CommonCrypto 支持")
        #endif
    }

    // MARK: - 便捷方法：从 URL 获取并解密 JM 格式数据

    /// 从 URL 获取数据并使用 JM 格式解密
    /// - Parameters:
    ///   - url: 数据 URL
    ///   - isBase64Response: 响应是否为 Base64 编码（true 则先 Base64 解码）
    ///   - completion: 完成回调
    public func fetchAndDecryptJmFormat(from url: URL,
                                        isBase64Response: Bool = true,
                                        completion: @escaping (Result<String, Error>) -> Void) {
        let task = urlSession.dataTask(with: url) { [weak self] data, response, error in
            guard let self = self else { return }

            if let error = error {
                completion(.failure(error))
                return
            }

            guard let data = data else {
                completion(.failure(DecryptError.invalidInput))
                return
            }

            do {
                let dataToDecrypt: Data
                if isBase64Response {
                    // 先 Base64 解码
                    var raw = String(data: data, encoding: .utf8) ?? ""
                    raw = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                    raw = raw.replacingOccurrences(of: "\u{FEFF}", with: "")

                    let decoded = try self.base64Decode(raw)
                    dataToDecrypt = decoded.data
                } else {
                    dataToDecrypt = data
                }

                // JM 格式解密
                let result = try self.decryptJmFormat(dataToDecrypt)

                if let text = result.utf8String {
                    completion(.success(text))
                } else {
                    completion(.failure(DecryptError.encodingFailed))
                }
            } catch {
                completion(.failure(error))
            }
        }
        task.resume()
    }

    /// 两步解密：先获取重定向 URL，再解密 JM 格式数据
    /// 适用于第一个 URL 返回纯文本重定向 URL，第二个 URL 返回加密 m3u8 的场景
    /// - Parameters:
    ///   - url: 初始 URL（返回重定向 URL 的纯文本）
    ///   - isBase64Response: 最终响应是否为 Base64 编码
    ///   - completion: 完成回调
    public func fetchRedirectAndDecryptJmFormat(from url: URL,
                                                 isBase64Response: Bool = true,
                                                 completion: @escaping (Result<String, Error>) -> Void) {
        print("🔐 [解密] 第一步：获取重定向 URL from \(url)")

        // 第一步：获取重定向 URL
        let task = urlSession.dataTask(with: url) { [weak self] data, response, error in
            guard let self = self else { return }

            if let error = error {
                print("❌ [解密] 第一步失败：\(error)")
                completion(.failure(error))
                return
            }

            guard let data = data,
                  let redirectURLString = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  let redirectURL = URL(string: redirectURLString) else {
                print("❌ [解密] 无法解析重定向 URL")
                completion(.failure(DecryptError.invalidInput))
                return
            }

            print("🔐 [解密] 第二步：获取加密 m3u8 from \(redirectURL)")

            // 第二步：获取并解密实际的 m3u8
            // 注意：JM 格式数据是 [加密内容] + [加密约定] + [长度]，不需要整体 Base64 解码
            // 加密约定中的类型（如 AA）决定了加密内容的解码方式
            self.fetchAndDecryptJmFormat(from: redirectURL, isBase64Response: false, completion: completion)
        }
        task.resume()
    }

    // MARK: - 两步解密（增强版，支持检测普通 m3u8）

    /// 解密结果详情
    public struct DecryptResultInfo {
        /// 解密后的内容（如果是普通 m3u8 则为 nil）
        public let decryptedContent: String?
        /// 是否为普通 m3u8（以 #EXTM3U 开头）
        public let isPlainM3u8: Bool
        /// 重定向 URL
        public let redirectURL: URL?
    }

    /// 两步解密（增强版）：先获取重定向 URL，再解密 JM 格式数据
    /// 适用于第一个 URL 返回纯文本重定向 URL，第二个 URL 返回加密/普通 m3u8 的场景
    /// - Parameters:
    ///   - url: 初始 URL（返回重定向 URL 的纯文本）
    ///   - completion: 完成回调，返回 DecryptResultInfo
    public func fetchRedirectAndDecryptJmFormatWithInfo(from url: URL,
                                                         completion: @escaping (Result<DecryptResultInfo, Error>) -> Void) {
        print("🔐 [解密] 第一步：获取重定向 URL from \(url)")

        // 第一步：获取重定向 URL
        let task = urlSession.dataTask(with: url) { [weak self] data, response, error in
            guard let self = self else { return }

            if let error = error {
                print("❌ [解密] 第一步失败：\(error)")
                completion(.failure(error))
                return
            }

            guard let data = data,
                  let redirectURLString = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !redirectURLString.isEmpty,
                  redirectURLString.hasPrefix("http"),
                  let redirectURL = URL(string: redirectURLString) else {
                print("❌ [解密] 无法解析重定向 URL")
                completion(.failure(DecryptError.invalidInput))
                return
            }

            print("🔐 [解密] 第二步：获取数据 from \(redirectURL)")

            // 第二步：获取数据
            let dataTask = self.urlSession.dataTask(with: redirectURL) { data, response, error in
                if let error = error {
                    print("❌ [解密] 第二步失败：\(error)")
                    completion(.failure(error))
                    return
                }

                guard let data = data else {
                    print("❌ [解密] 获取数据失败")
                    completion(.failure(DecryptError.invalidInput))
                    return
                }

                // 检查是否是普通 m3u8（以 #EXTM3U 开头）
                if data.count > 7 {
                    let headerBytes = data.prefix(7)
                    if let header = String(data: headerBytes, encoding: .utf8), header == "#EXTM3U" {
                        print("✅ [解密] 检测到普通 m3u8 格式，直接使用重定向 URL")
                        let result = DecryptResultInfo(decryptedContent: nil, isPlainM3u8: true, redirectURL: redirectURL)
                        completion(.success(result))
                        return
                    }
                }

                // JM 格式解密
                do {
                    let decrypted = try self.decryptJmFormat(data)
                    if let text = decrypted.utf8String {
                        let result = DecryptResultInfo(decryptedContent: text, isPlainM3u8: false, redirectURL: redirectURL)
                        completion(.success(result))
                    } else {
                        completion(.failure(DecryptError.encodingFailed))
                    }
                } catch {
                    print("❌ [解密] JM 格式解密失败：\(error)")
                    completion(.failure(error))
                }
            }
            dataTask.resume()
        }
        task.resume()
    }

    // MARK: - 直接解密（单步，适用于直接返回加密内容的 URL）

    /// 直接从 URL 获取并解密数据（单步解密）
    /// 适用于 URL 直接返回加密/普通 m3u8 的场景（不需要先获取重定向 URL）
    /// - Parameters:
    ///   - url: 直接返回加密数据或普通 m3u8 的 URL
    ///   - completion: 完成回调，返回 DecryptResultInfo
    public func fetchAndDecryptDirectly(from url: URL,
                                        completion: @escaping (Result<DecryptResultInfo, Error>) -> Void) {
        fetchAndDecryptDirectlyWithRetry(from: url, retryCount: 0, completion: completion)
    }

    /// 帶重試邏輯的直接解密內部方法
    private func fetchAndDecryptDirectlyWithRetry(from url: URL,
                                                   retryCount: Int,
                                                   completion: @escaping (Result<DecryptResultInfo, Error>) -> Void) {
        print("🔐 [直接解密] 获取数据 from \(url) (嘗試 \(retryCount + 1)/\(maxRetryCount + 1))")

        let task = urlSession.dataTask(with: url) { [weak self] data, response, error in
            guard let self = self else { return }

            // 處理網路錯誤，支援重試
            if let error = error {
                print("❌ [直接解密] 获取数据失败：\(error)")

                if retryCount < self.maxRetryCount {
                    print("🔄 [直接解密] 將在 \(self.retryDelay) 秒後重試...")
                    DispatchQueue.global().asyncAfter(deadline: .now() + self.retryDelay) {
                        self.fetchAndDecryptDirectlyWithRetry(from: url, retryCount: retryCount + 1, completion: completion)
                    }
                    return
                }

                completion(.failure(error))
                return
            }

            guard let data = data else {
                print("❌ [直接解密] 数据为空")

                if retryCount < self.maxRetryCount {
                    print("🔄 [直接解密] 數據為空，將在 \(self.retryDelay) 秒後重試...")
                    DispatchQueue.global().asyncAfter(deadline: .now() + self.retryDelay) {
                        self.fetchAndDecryptDirectlyWithRetry(from: url, retryCount: retryCount + 1, completion: completion)
                    }
                    return
                }

                completion(.failure(DecryptError.invalidInput))
                return
            }

            print("🔐 [直接解密] 获取到数据，大小: \(data.count) 字节")

            // 检查是否是普通 m3u8（以 #EXTM3U 开头，支持 BOM 和空白字符）
            if let text = String(data: data, encoding: .utf8) {
                // 去除 BOM 和前導空白
                var cleanText = text
                // UTF-8 BOM: EF BB BF
                if cleanText.hasPrefix("\u{FEFF}") {
                    cleanText = String(cleanText.dropFirst())
                }
                cleanText = cleanText.trimmingCharacters(in: .whitespacesAndNewlines)

                if cleanText.hasPrefix("#EXTM3U") {
                    print("✅ [直接解密] 检测到普通 m3u8 格式，直接使用原始 URL")
                    let result = DecryptResultInfo(decryptedContent: nil, isPlainM3u8: true, redirectURL: url)
                    completion(.success(result))
                    return
                } else {
                    let headerHex = data.prefix(10).map { String(format: "%02x", $0) }.joined(separator: " ")
                    print("🔐 [直接解密] 前10字节 (hex): \(headerHex)")
                    print("🔐 [直接解密] 前20字符: '\(String(cleanText.prefix(20)))'")
                }
            } else {
                let headerHex = data.prefix(10).map { String(format: "%02x", $0) }.joined(separator: " ")
                print("🔐 [直接解密] 无法解码为 UTF-8，前10字节 (hex): \(headerHex)")
            }

            // 检查是否是直接播放格式（通过文件魔数检测）
            // 这些格式不需要解密，应该直接播放
            if self.isDirectPlayFormat(data: data) {
                print("✅ [直接解密] 检测到直接播放格式（通过魔数），使用原始 URL")
                let result = DecryptResultInfo(decryptedContent: nil, isPlainM3u8: true, redirectURL: url)
                completion(.success(result))
                return
            }

            // 检查是否是嵌套重定向 URL（以 http 开头的短文本）
            if let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) {
                if text.hasPrefix("http") && text.count < 2000 && !text.contains("\n") {
                    // 處理可能包含多個 URL 的情況（用 <br> 分隔）
                    var urlString = text
                    if text.contains("<br>") {
                        let components = text.components(separatedBy: "<br>")
                        if let firstURL = components.first?.trimmingCharacters(in: .whitespacesAndNewlines),
                           !firstURL.isEmpty {
                            urlString = firstURL
                            print("🔐 [直接解密] 检测到多个 URL，使用第一个: \(urlString)")
                        }
                    }

                    if let nestedURL = URL(string: urlString) {
                        print("🔐 [直接解密] 检测到嵌套重定向 URL，继续获取: \(nestedURL)")
                        // 递归调用自己处理嵌套重定向（重置重试计数）
                        self.fetchAndDecryptDirectlyWithRetry(from: nestedURL, retryCount: 0, completion: completion)
                        return
                    }
                }
            }

            // 嘗試純 Base64 解碼（非 JM 格式，伺服器直接返回 Base64 編碼的 m3u8）
            print("🔐 [直接解密] 尝试 Base64 解码...")
            if let base64String = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) {
                print("🔐 [直接解密] Base64 字符串长度: \(base64String.count), 前20字符: \(String(base64String.prefix(20)))")

                // 嘗試標準 Base64 解碼
                var decodedData = Data(base64Encoded: base64String)

                // 如果標準解碼失敗，嘗試 URL-safe Base64
                if decodedData == nil {
                    let urlSafeString = base64String
                        .replacingOccurrences(of: "-", with: "+")
                        .replacingOccurrences(of: "_", with: "/")
                    // 添加 padding
                    let paddingNeeded = (4 - urlSafeString.count % 4) % 4
                    let paddedString = urlSafeString + String(repeating: "=", count: paddingNeeded)
                    decodedData = Data(base64Encoded: paddedString)
                    if decodedData != nil {
                        print("🔐 [直接解密] URL-safe Base64 解码成功")
                    }
                }

                if let decoded = decodedData, decoded.count > 7 {
                    let decodedHeader = decoded.prefix(7)
                    print("🔐 [直接解密] Base64 解码后前7字节: \(decodedHeader.map { String(format: "%02x", $0) }.joined())")
                    if let header = String(data: decodedHeader, encoding: .utf8) {
                        print("🔐 [直接解密] Base64 解码后前7字节 (utf8): '\(header)'")
                        if header == "#EXTM3U" {
                            print("✅ [直接解密] 检测到 Base64 编码的 m3u8，已解码")
                            if let decodedContent = String(data: decoded, encoding: .utf8) {
                                let result = DecryptResultInfo(decryptedContent: decodedContent, isPlainM3u8: false, redirectURL: url)
                                completion(.success(result))
                                return
                            }
                        }
                    }
                } else {
                    print("🔐 [直接解密] Base64 解码失败或数据太短")
                }
            }

            // JM 格式解密
            do {
                let decrypted = try self.decryptJmFormat(data)
                if let text = decrypted.utf8String {
                    print("✅ [直接解密] JM 格式解密成功")
                    let result = DecryptResultInfo(decryptedContent: text, isPlainM3u8: false, redirectURL: url)
                    completion(.success(result))
                } else {
                    completion(.failure(DecryptError.encodingFailed))
                }
            } catch {
                print("❌ [直接解密] JM 格式解密失败：\(error)")
                completion(.failure(error))
            }
        }
        task.resume()
    }

    // MARK: - 智能解密（自动判断是重定向 URL 还是直接内容）

    /// 智能解密：自动判断 URL 类型并选择合适的解密方式
    /// - 如果 URL 返回的是重定向 URL（纯文本 http 开头），则进行两步解密
    /// - 如果 URL 返回的是直接内容（m3u8 或加密数据），则进行单步解密
    /// - Parameters:
    ///   - url: 待解密的 URL
    ///   - completion: 完成回调
    public func smartDecrypt(from url: URL,
                             completion: @escaping (Result<DecryptResultInfo, Error>) -> Void) {
        smartDecryptWithRetry(from: url, retryCount: 0, completion: completion)
    }

    /// 帶重試邏輯的智能解密內部方法
    private func smartDecryptWithRetry(from url: URL,
                                       retryCount: Int,
                                       completion: @escaping (Result<DecryptResultInfo, Error>) -> Void) {
        print("🔐 [智能解密] 开始分析 URL: \(url) (嘗試 \(retryCount + 1)/\(maxRetryCount + 1))")

        let task = urlSession.dataTask(with: url) { [weak self] data, response, error in
            guard let self = self else { return }

            // 處理網路錯誤，支援重試
            if let error = error {
                print("❌ [智能解密] 获取数据失败：\(error)")

                // 檢查是否可以重試
                if retryCount < self.maxRetryCount {
                    print("🔄 [智能解密] 將在 \(self.retryDelay) 秒後重試...")
                    DispatchQueue.global().asyncAfter(deadline: .now() + self.retryDelay) {
                        self.smartDecryptWithRetry(from: url, retryCount: retryCount + 1, completion: completion)
                    }
                    return
                }

                completion(.failure(error))
                return
            }

            // 检查 HTTP 状态码
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
                let statusCode = httpResponse.statusCode
                print("❌ [智能解密] HTTP 错误: \(statusCode)")

                if statusCode >= 500 && retryCount < self.maxRetryCount {
                    print("🔄 [智能解密] 服务器错误，將在 \(self.retryDelay) 秒後重試...")
                    DispatchQueue.global().asyncAfter(deadline: .now() + self.retryDelay) {
                        self.smartDecryptWithRetry(from: url, retryCount: retryCount + 1, completion: completion)
                    }
                    return
                }

                let errorMsg = HTTPURLResponse.localizedString(forStatusCode: statusCode)
                completion(.failure(DecryptError.decryptFailed("HTTP \(statusCode): \(errorMsg)")))
                return
            }

            guard let data = data, !data.isEmpty else {
                print("❌ [智能解密] 数据为空")

                // 數據為空也嘗試重試
                if retryCount < self.maxRetryCount {
                    print("🔄 [智能解密] 數據為空，將在 \(self.retryDelay) 秒後重試...")
                    DispatchQueue.global().asyncAfter(deadline: .now() + self.retryDelay) {
                        self.smartDecryptWithRetry(from: url, retryCount: retryCount + 1, completion: completion)
                    }
                    return
                }

                completion(.failure(DecryptError.invalidInput))
                return
            }

            print("🔐 [智能解密] 获取到数据，大小: \(data.count) 字节")

            // Debug: 顯示前 100 字節
            let previewData = data.prefix(100)
            if let preview = String(data: previewData, encoding: .utf8) {
                print("🔐 [智能解密] 數據預覽: \(preview)")
            } else {
                print("🔐 [智能解密] 數據預覽 (hex): \(previewData.map { String(format: "%02x", $0) }.joined())")
            }

            // 检查是否是普通 m3u8（以 #EXTM3U 开头，支持 BOM 和空白字符）
            if let text = String(data: data, encoding: .utf8) {
                var cleanText = text
                // 去除 UTF-8 BOM
                if cleanText.hasPrefix("\u{FEFF}") {
                    cleanText = String(cleanText.dropFirst())
                }
                cleanText = cleanText.trimmingCharacters(in: .whitespacesAndNewlines)

                if cleanText.hasPrefix("#EXTM3U") {
                    print("✅ [智能解密] 检测到普通 m3u8 格式，直接使用原始 URL")
                    let result = DecryptResultInfo(decryptedContent: nil, isPlainM3u8: true, redirectURL: url)
                    completion(.success(result))
                    return
                }
            }

            // 检查是否是直接播放格式（通过文件魔数检测）
            if self.isDirectPlayFormat(data: data) {
                print("✅ [智能解密] 检测到直接播放格式（通过魔数），使用原始 URL")
                let result = DecryptResultInfo(decryptedContent: nil, isPlainM3u8: true, redirectURL: url)
                completion(.success(result))
                return
            }

            // 检查是否是重定向 URL（纯文本，以 http 开头，且内容较短）
            if let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) {
                print("🔐 [智能解密] UTF-8 解碼成功，長度: \(text.count)")
                print("🔐 [智能解密] 開頭: \(text.hasPrefix("http") ? "是 http" : "不是 http")")

                if text.hasPrefix("http") && text.count < 2000 {
                    // 處理可能包含多個 URL 的情況（用 <br> 或 <br><br> 分隔）
                    var urlString = text

                    // 如果包含 <br> 分隔符，取第一個 URL
                    if text.contains("<br>") {
                        let components = text.components(separatedBy: "<br>")
                        if let firstURL = components.first?.trimmingCharacters(in: .whitespacesAndNewlines),
                           !firstURL.isEmpty {
                            urlString = firstURL
                            print("🔐 [智能解密] 检测到多个 URL，使用第一个: \(urlString)")
                        }
                    }

                    // 如果不包含換行且可以解析為有效 URL
                    if !urlString.contains("\n") {
                        // 先嘗試直接解析
                        var redirectURL = URL(string: urlString)

                        // 如果解析失敗，嘗試 URL 編碼後再解析
                        if redirectURL == nil {
                            if let encoded = urlString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
                                redirectURL = URL(string: encoded)
                                print("🔐 [智能解密] 使用 URL 編碼: \(encoded.prefix(100))...")
                            }
                        }

                        if let finalURL = redirectURL {
                            print("🔐 [智能解密] 检测到重定向 URL，进行第二步解密: \(finalURL)")
                            // 进行第二步：获取并解密实际内容
                            self.fetchAndDecryptDirectly(from: finalURL, completion: completion)
                            return
                        } else {
                            print("❌ [智能解密] URL 解析失敗: \(urlString.prefix(100))...")
                        }
                    } else {
                        print("❌ [智能解密] URL 包含換行符")
                    }
                } else if !text.hasPrefix("http") {
                    print("🔐 [智能解密] 不是重定向 URL (不以 http 開頭)")
                } else {
                    print("🔐 [智能解密] 文本過長: \(text.count) 字符")
                }
            } else {
                print("❌ [智能解密] UTF-8 解碼失敗")
            }

            // 嘗試 JM 格式解密（直接內容）
            // 如果走到這裡，說明前面的重定向 URL 檢測失敗
            print("⚠️ [智能解密] 嘗試 JM 格式解密 (前面檢測未命中)")
            do {
                let decrypted = try self.decryptJmFormat(data)
                if let text = decrypted.utf8String {
                    print("✅ [智能解密] JM 格式解密成功")
                    let result = DecryptResultInfo(decryptedContent: text, isPlainM3u8: false, redirectURL: url)
                    completion(.success(result))
                } else {
                    completion(.failure(DecryptError.encodingFailed))
                }
            } catch {
                print("⚠️ [智能解密] JM 格式解密失败，尝试 Base64 解码...")

                // Fallback: 尝试纯 Base64 解码（如 baishitong.ai 返回的加密 m3u8）
                if let base64String = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) {
                    // 标准 Base64
                    var decodedData = Data(base64Encoded: base64String)

                    // URL-safe Base64 fallback
                    if decodedData == nil {
                        var urlSafe = base64String
                            .replacingOccurrences(of: "-", with: "+")
                            .replacingOccurrences(of: "_", with: "/")
                        let pad = (4 - urlSafe.count % 4) % 4
                        urlSafe.append(contentsOf: String(repeating: "=", count: pad))
                        decodedData = Data(base64Encoded: urlSafe)
                    }

                    if let decoded = decodedData,
                       let text = String(data: decoded, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                       text.hasPrefix("#EXTM3U") {
                        print("✅ [智能解密] Base64 解码成功，检测到 m3u8")
                        let result = DecryptResultInfo(decryptedContent: text, isPlainM3u8: false, redirectURL: url)
                        completion(.success(result))
                        return
                    }
                }

                print("❌ [智能解密] 所有解密方式均失败")
                completion(.failure(error))
            }
        }
        task.resume()
    }

    // MARK: - 媒体图片解密（固定 AES-128-CBC key/iv）

    /// 媒体图片 AES-128-CBC 固定密钥
    private static let mediaKeyBytes: [UInt8] = [102, 53, 100, 57, 54, 53, 100, 102, 55, 53, 51, 51, 54, 50, 55, 48]
    /// 媒体图片 AES-128-CBC 固定 IV
    private static let mediaIvBytes: [UInt8] = [57, 55, 98, 54, 48, 51, 57, 52, 97, 98, 99, 50, 102, 98, 101, 49]

    /// 解密媒体图片（使用固定 AES-128-CBC key/iv）
    /// - Parameter encryptedData: 加密后的图片数据
    /// - Returns: 解密后的图片数据
    public func decryptMediaImage(_ encryptedData: Data) throws -> Data {
        let key = Data(Self.mediaKeyBytes)
        let iv = Data(Self.mediaIvBytes)
        let result = try aesCBCDecrypt(key: key, iv: iv, cipher: encryptedData)
        return result.data
    }

    /// 从 URL 下载并解密媒体图片
    /// - Parameters:
    ///   - url: 图片 URL
    ///   - completion: 完成回调，返回解密后的图片数据
    public func fetchAndDecryptMediaImage(from url: URL, completion: @escaping (Result<Data, Error>) -> Void) {
        print("🖼️ [图片解密] 开始下载: \(url)")

        urlSession.dataTask(with: url) { [weak self] data, response, error in
            guard let self = self else { return }

            if let error = error {
                print("❌ [图片解密] 下载失败: \(error.localizedDescription)")
                completion(.failure(error))
                return
            }

            guard let data = data, !data.isEmpty else {
                print("❌ [图片解密] 数据为空")
                completion(.failure(DecryptError.invalidInput))
                return
            }

            // 先检查是否已经是有效图片（未加密）
            if Self.isImageData(data) {
                print("✅ [图片解密] 数据已是有效图片，无需解密")
                completion(.success(data))
                return
            }

            // 尝试 AES-CBC 解密
            do {
                let decrypted = try self.decryptMediaImage(data)
                if Self.isImageData(decrypted) {
                    print("✅ [图片解密] AES-CBC 解密成功，图片大小: \(decrypted.count) 字节")
                    completion(.success(decrypted))
                } else {
                    print("❌ [图片解密] 解密后数据不是有效图片")
                    completion(.failure(DecryptError.decryptFailed("解密后数据不是有效图片")))
                }
            } catch {
                print("❌ [图片解密] AES-CBC 解密失败: \(error)")
                completion(.failure(error))
            }
        }.resume()
    }

    /// 检查数据是否是有效的图片格式
    private static func isImageData(_ data: Data) -> Bool {
        guard data.count >= 8 else { return false }
        let bytes = Array(data.prefix(8))
        // PNG: 89 50 4E 47 0D 0A 1A 0A
        if bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47 {
            return true
        }
        // JPEG: FF D8 FF
        if bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF {
            return true
        }
        // GIF: 47 49 46 38
        if bytes[0] == 0x47 && bytes[1] == 0x49 && bytes[2] == 0x46 && bytes[3] == 0x38 {
            return true
        }
        // WebP: 52 49 46 46 ... 57 45 42 50
        if bytes[0] == 0x52 && bytes[1] == 0x49 && bytes[2] == 0x46 && bytes[3] == 0x46 && data.count >= 12 {
            let webp = Array(data[8..<12])
            if webp[0] == 0x57 && webp[1] == 0x45 && webp[2] == 0x42 && webp[3] == 0x50 {
                return true
            }
        }
        return false
    }

    // MARK: - 格式检测

    /// 检查数据是否是直接播放格式（通过文件魔数检测）
    /// 支持检测：MP4/MOV (ftyp), WebM (EBML), FLV, AVI, MKV, WMV/ASF
    /// - Parameter data: 文件数据
    /// - Returns: true 如果是直接播放格式
    private func isDirectPlayFormat(data: Data) -> Bool {
        guard data.count >= 12 else { return false }

        let bytes = Array(data.prefix(12))

        // MP4/MOV: 检查 ftyp box（通常在偏移 4 开始）
        // 格式: [4字节大小][ftyp][品牌]
        if bytes.count >= 8 {
            let ftypSignature = Data([0x66, 0x74, 0x79, 0x70]) // "ftyp"
            if data.count >= 8 && data[4..<8] == ftypSignature {
                print("🔐 [格式检测] 检测到 MP4/MOV 格式 (ftyp)")
                return true
            }
        }

        // WebM/MKV: EBML header (1A 45 DF A3)
        if bytes[0] == 0x1A && bytes[1] == 0x45 && bytes[2] == 0xDF && bytes[3] == 0xA3 {
            print("🔐 [格式检测] 检测到 WebM/MKV 格式 (EBML)")
            return true
        }

        // FLV: "FLV" (46 4C 56)
        if bytes[0] == 0x46 && bytes[1] == 0x4C && bytes[2] == 0x56 {
            print("🔐 [格式检测] 检测到 FLV 格式")
            return true
        }

        // AVI: "RIFF" + "AVI " (52 49 46 46 ... 41 56 49 20)
        if bytes[0] == 0x52 && bytes[1] == 0x49 && bytes[2] == 0x46 && bytes[3] == 0x46 {
            if data.count >= 12 && bytes[8] == 0x41 && bytes[9] == 0x56 && bytes[10] == 0x49 {
                print("🔐 [格式检测] 检测到 AVI 格式")
                return true
            }
        }

        // WMV/ASF: ASF header GUID (30 26 B2 75 8E 66 CF 11)
        if bytes[0] == 0x30 && bytes[1] == 0x26 && bytes[2] == 0xB2 && bytes[3] == 0x75 {
            print("🔐 [格式检测] 检测到 WMV/ASF 格式")
            return true
        }

        // MPEG-TS: 同步字节 (47) 每 188 字节重复
        if bytes[0] == 0x47 && data.count >= 188 {
            // 检查第二个同步字节
            if data.count >= 376 && data[188] == 0x47 {
                print("🔐 [格式检测] 检测到 MPEG-TS 格式")
                return true
            }
        }

        return false
    }
}

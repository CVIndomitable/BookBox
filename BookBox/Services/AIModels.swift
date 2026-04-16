import Foundation
import UIKit

/// AI 识别置信度
enum ConfidenceLevel: String, Codable {
    case high
    case medium
    case low

    /// 中文标签
    var label: String {
        switch self {
        case .high: "高置信"
        case .medium: "中置信"
        case .low: "低置信"
        }
    }

    /// 简短标签
    var shortLabel: String {
        switch self {
        case .high: "高"
        case .medium: "中"
        case .low: "低"
        }
    }
}

/// MiMo 多模态大模型识别结果
struct RecognizedBook: Codable, Identifiable {
    var id = UUID()
    var title: String
    var author: String?
    var confidence: ConfidenceLevel
    var category: String?   // AI 建议的分类

    enum CodingKeys: String, CodingKey {
        case id, title, author, confidence, category
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // 服务器返回不含 id，本地存储含 id，两种场景都兼容
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try container.decode(String.self, forKey: .title)
        author = try container.decodeIfPresent(String.self, forKey: .author)
        confidence = try container.decode(ConfidenceLevel.self, forKey: .confidence)
        category = try container.decodeIfPresent(String.self, forKey: .category)
    }

    /// 置信度映射到校验状态颜色
    var verifyStatus: VerifyStatus {
        switch confidence {
        case .high: .matched
        case .medium: .uncertain
        case .low: .notFound
        }
    }
}

/// 语音指令解析结果
struct VoiceCommandResult: Codable {
    var action: String       // move/query/edit/list
    var bookTitle: String?
    var bookId: Int?
    var target: VoiceTarget?
    var reply: String
    var cached: Bool?        // 是否来自服务器缓存
    var supplier: SupplierMeta?  // 本次调用使用的供应商（用于降级提醒）

    struct VoiceTarget: Codable {
        var type: String     // shelf/box
        var name: String
    }
}

/// 书库上下文（提供给服务器的结构化状态信息）
/// 服务器端据此构建 system prompt，客户端不再拼接提示词以防注入
struct LibraryContext: Codable {
    struct Room: Codable {
        var name: String
    }
    struct Shelf: Codable {
        var name: String
        var bookCount: Int
        var roomName: String?
    }
    struct Box: Codable {
        var name: String
        var uid: String
        var bookCount: Int
        var roomName: String?
    }

    var rooms: [Room]?
    var shelves: [Shelf]
    var boxes: [Box]
}

/// 压缩图片用于上传识别（长边不超过 1024px，JPEG quality 0.6）
func compressImageForRecognition(_ image: UIImage) -> Data? {
    // 1024px 足够 AI 识别书名，且能控制 base64 体积在 nginx 限制内
    let maxDimension: CGFloat = 1024
    let size = image.size

    if size.width <= maxDimension && size.height <= maxDimension {
        return image.jpegData(compressionQuality: 0.6)
    }

    let scale = maxDimension / max(size.width, size.height)
    let newSize = CGSize(width: size.width * scale, height: size.height * scale)

    let renderer = UIGraphicsImageRenderer(size: newSize)
    let resized = renderer.image { _ in
        image.draw(in: CGRect(origin: .zero, size: newSize))
    }

    return resized.jpegData(compressionQuality: 0.6)
}

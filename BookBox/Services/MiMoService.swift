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

    struct VoiceTarget: Codable {
        var type: String     // shelf/box
        var name: String
    }
}

/// 书库上下文（提供给 AI 的状态信息）
struct LibraryContext {
    var shelves: [(name: String, bookCount: Int)]
    var boxes: [(name: String, uid: String, bookCount: Int)]

    var systemPrompt: String {
        var parts = ["你是 BookBox 书库助手。用户通过语音管理自己的书库。"]
        parts.append("当前书库状态：")

        if !shelves.isEmpty {
            let shelfDesc = shelves.map { "\($0.name)（\($0.bookCount)本）" }.joined(separator: "、")
            parts.append("书架：\(shelfDesc)")
        }

        if !boxes.isEmpty {
            let boxDesc = boxes.map { "\($0.uid) \($0.name)（\($0.bookCount)本）" }.joined(separator: "、")
            parts.append("箱子（已归档）：\(boxDesc)")
        }

        parts.append("")
        parts.append("请根据用户指令返回 JSON：")
        parts.append(#"{"action": "move|query|edit|list", "bookTitle": "书名", "bookId": null, "target": {"type": "shelf|box", "name": "名称"}, "reply": "回复用户的话"}"#)
        parts.append("只返回 JSON。")

        return parts.joined(separator: "\n")
    }
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

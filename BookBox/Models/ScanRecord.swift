import Foundation

/// 扫描模式
enum ScanMode: String, Codable {
    case preclassify
    case boxing
}

/// 扫描记录
struct ScanRecord: Identifiable, Codable {
    let id: Int
    let mode: ScanMode
    var boxId: Int?
    var photoPath: String?
    var ocrResult: [String: Any]?
    var extractedTitles: [String]?
    var createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, mode
        case boxId = "box_id"
        case photoPath = "photo_path"
        case extractedTitles = "extracted_titles"
        case createdAt = "created_at"
    }

    // ocrResult 是 JSON 类型，需要自定义编解码
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        mode = try container.decode(ScanMode.self, forKey: .mode)
        boxId = try container.decodeIfPresent(Int.self, forKey: .boxId)
        photoPath = try container.decodeIfPresent(String.self, forKey: .photoPath)
        extractedTitles = try container.decodeIfPresent([String].self, forKey: .extractedTitles)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt)
        ocrResult = nil
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(mode, forKey: .mode)
        try container.encodeIfPresent(boxId, forKey: .boxId)
        try container.encodeIfPresent(photoPath, forKey: .photoPath)
        try container.encodeIfPresent(extractedTitles, forKey: .extractedTitles)
        try container.encodeIfPresent(createdAt, forKey: .createdAt)
    }
}

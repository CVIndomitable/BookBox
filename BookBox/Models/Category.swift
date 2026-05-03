import Foundation

/// 分类模型，支持多级分类
struct Category: Identifiable, Codable, Hashable {
    let id: Int
    var name: String
    var parentId: Int?
    var children: [Category]?
    var categoryType: String?  // "user" | "statutory"

    var isStatutory: Bool { categoryType == "statutory" }

    enum CodingKeys: String, CodingKey {
        case id, name, children
        case parentId = "parent_id"
        case categoryType = "category_type"
    }
}

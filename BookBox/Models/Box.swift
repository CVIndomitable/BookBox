import Foundation

/// 箱子模型
struct Box: Identifiable, Codable, Hashable {
    let id: Int
    let boxUid: String
    var name: String
    var description: String?
    var bookCount: Int
    var books: [Book]?
    var createdAt: Date?
    var updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, name, description, books
        case boxUid = "box_uid"
        case bookCount = "book_count"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

/// 新建/编辑箱子请求
struct BoxRequest: Codable {
    var name: String
    var description: String?
}

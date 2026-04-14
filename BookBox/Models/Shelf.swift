import Foundation

/// 书架模型
struct Shelf: Identifiable, Codable, Hashable {
    let id: Int
    var name: String
    var location: String?
    var description: String?
    var bookCount: Int
    var libraryId: Int?
    var books: [Book]?
    var createdAt: Date?
    var updatedAt: Date?
}

/// 新建/编辑书架请求
struct ShelfRequest: Codable {
    var name: String
    var location: String?
    var description: String?
    var libraryId: Int?
}

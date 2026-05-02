import Foundation

/// 书架模型
struct Shelf: Identifiable, Codable, Hashable {
    let id: Int
    var name: String
    var location: String?
    var description: String?
    var bookCount: Int
    var libraryId: Int?
    var roomId: Int?
    var books: [Book]?
    var createdAt: Date?
    var updatedAt: Date?
}

/// 新建/编辑书架请求
/// - 传 roomId 时 libraryId 会被服务器改为 room.libraryId
/// - 只传 libraryId 时会自动归入该书库的默认房间
struct ShelfRequest: Codable {
    var name: String
    var location: String?
    var description: String?
    var libraryId: Int?
    var roomId: Int?
}

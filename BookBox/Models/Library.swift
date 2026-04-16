import Foundation

/// 书库模型
struct Library: Identifiable, Codable, Hashable {
    let id: Int
    var name: String
    var location: String?
    var description: String?
    var bookCount: Int?
    var createdAt: Date?
    var updatedAt: Date?
}

/// 书库详情（含总览统计）
struct LibraryDetail: Codable {
    let id: Int
    let name: String
    let location: String?
    let description: String?
    let totalBooks: Int
    let unlocated: Int
    let rooms: [RoomSummary]?
    let shelves: [ShelfSummary]
    let boxes: [BoxSummary]
    let createdAt: Date?
    let updatedAt: Date?
}

/// 新建/编辑书库请求
struct LibraryRequest: Codable {
    var name: String
    var location: String?
    var description: String?
}

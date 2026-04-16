import Foundation

/// 房间模型：介于书库和书架/箱子之间
struct Room: Identifiable, Codable, Hashable {
    let id: Int
    var name: String
    var description: String?
    var isDefault: Bool
    var libraryId: Int
    var createdAt: Date?
    var updatedAt: Date?
}

/// 房间摘要（用于总览/详情嵌套返回）
struct RoomSummary: Identifiable, Codable, Hashable {
    let id: Int
    let name: String
    let isDefault: Bool
    let description: String?
}

/// 新建房间请求
struct RoomRequest: Codable {
    var name: String
    var description: String?
    var libraryId: Int
}

/// 更新房间请求（搬动箱子/书架不走这里，走 Shelf/Box 的 PUT）
struct RoomUpdateRequest: Codable {
    var name: String?
    var description: String?
}

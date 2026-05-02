import Foundation

/// 书库总览数据
struct LibraryOverview: Codable {
    let totalBooks: Int
    let unlocated: Int
    let rooms: [RoomSummary]?
    let shelves: [ShelfSummary]
    let boxes: [BoxSummary]
    let myRole: String?
}

/// 书架摘要（用于总览）
struct ShelfSummary: Identifiable, Codable, Hashable {
    let id: Int
    let name: String
    let location: String?
    let bookCount: Int
    let roomId: Int?
}

/// 箱子摘要（用于总览）
struct BoxSummary: Identifiable, Codable, Hashable {
    let id: Int
    let boxUid: String
    let name: String
    let bookCount: Int
    let roomId: Int?
}

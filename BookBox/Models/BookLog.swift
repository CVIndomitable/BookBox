import Foundation

/// 日志关联的书籍摘要（全局日志接口返回）
struct BookLogBook: Codable {
    let id: Int
    let title: String
    let author: String?
}

/// 操作日志模型
struct BookLog: Identifiable, Codable {
    let id: Int
    // 后端在书籍被删除后将 bookId 置空（onDelete: SetNull），故为可空
    var bookId: Int?
    var action: String
    var fromType: String?
    var fromId: Int?
    var toType: String?
    var toId: Int?
    var method: String
    var rawInput: String?
    var aiResponse: String?
    var note: String?
    var createdAt: Date?
    var book: BookLogBook?

    /// 操作描述
    var actionLabel: String {
        switch action {
        case "add": "入库"
        case "move": "移动"
        case "remove": "移出"
        case "edit": "编辑"
        case "verify": "校验"
        default: action
        }
    }
}

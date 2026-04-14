import Foundation

/// 校验状态
enum VerifyStatus: String, Codable, CaseIterable {
    case matched
    case uncertain
    case notFound = "not_found"
    case manual

    /// 对应的颜色名
    var colorName: String {
        switch self {
        case .matched: "green"
        case .uncertain: "orange"
        case .notFound, .manual: "red"
        }
    }

    /// 中文描述
    var label: String {
        switch self {
        case .matched: "已匹配"
        case .uncertain: "待确认"
        case .notFound: "未找到"
        case .manual: "手动录入"
        }
    }
}

/// 位置类型
enum LocationType: String, Codable {
    case shelf
    case box
    case none
}

/// 书籍模型
struct Book: Identifiable, Codable, Hashable {
    let id: Int
    var title: String
    var author: String?
    var isbn: String?
    var publisher: String?
    var coverUrl: String?
    var categoryId: Int?
    var verifyStatus: VerifyStatus?
    var verifySource: String?
    var rawOcrText: String?
    var locationType: LocationType?
    var locationId: Int?
    var libraryId: Int?
    var createdAt: Date?
    var updatedAt: Date?

    /// 位置描述文字
    var locationDescription: String {
        switch locationType {
        case .shelf: "书架"
        case .box: "箱子"
        default: "未归位"
        }
    }
}

/// 书籍校验结果
struct VerifyResult: Codable {
    let status: VerifyStatus
    let title: String
    let author: String?
    let isbn: String?
    let coverUrl: String?
    let source: String?
}

/// 批量新增书籍的请求体
struct BatchBooksRequest: Codable {
    let books: [NewBookRequest]
    let locationType: LocationType?
    let locationId: Int?
    let libraryId: Int?
}

/// 新增书籍请求
struct NewBookRequest: Codable {
    var title: String
    var author: String?
    var isbn: String?
    var publisher: String?
    var coverUrl: String?
    var categoryId: Int?
    var verifyStatus: VerifyStatus?
    var verifySource: String?
    var rawOcrText: String?
}

/// 移动书籍请求
struct MoveBookRequest: Codable {
    let toType: LocationType
    let toId: Int?
    let method: String?
    let rawInput: String?
}

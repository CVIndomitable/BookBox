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
    var createdAt: Date?
    var updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, title, author, isbn, publisher
        case coverUrl = "cover_url"
        case categoryId = "category_id"
        case verifyStatus = "verify_status"
        case verifySource = "verify_source"
        case rawOcrText = "raw_ocr_text"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
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

    enum CodingKeys: String, CodingKey {
        case status, title, author, isbn, source
        case coverUrl = "cover_url"
    }
}

/// 批量新增书籍的请求体
struct BatchBooksRequest: Codable {
    let books: [NewBookRequest]
    let boxId: Int?

    enum CodingKeys: String, CodingKey {
        case books
        case boxId = "box_id"
    }
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

    enum CodingKeys: String, CodingKey {
        case title, author, isbn, publisher
        case coverUrl = "cover_url"
        case categoryId = "category_id"
        case verifyStatus = "verify_status"
        case verifySource = "verify_source"
        case rawOcrText = "raw_ocr_text"
    }
}

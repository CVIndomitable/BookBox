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
    var edition: String?                                    // 版次
    var adaptation: String?                                 // 改编
    var translator: String?                                 // 译者
    var authorNationality: String?                          // 作者国籍
    var publisherPerson: String?                            // 出版人
    var responsibleEditor: String?                          // 责任编辑
    var responsiblePrinting: String?                        // 责任印制
    var coverDesign: String?                                // 封面设计
    var phone: String?                                      // 电话
    var address: String?                                    // 地址
    var postalCode: String?                                 // 邮编
    var printingHouse: String?                              // 印刷
    var impression: String?                                 // 印次
    var format: String?                                     // 开本
    var printedSheets: String?                              // 印张
    var wordCount: String?                                  // 字数
    // 定价：Prisma Decimal 序列化后是字符串（如 "29.80"），直接按 String 解码避免精度问题
    var price: String?
    var coverUrl: String?
    /// 构造可展示的封面 URL（绝对 URL 直接使用，相对路径拼接服务器地址）
    var coverDisplayUrl: URL? {
        guard let url = coverUrl else { return nil }
        if url.hasPrefix("http://") || url.hasPrefix("https://") {
            return URL(string: url)
        }
        let base = AppConfig.current
        let root = base.hasSuffix("/api") ? String(base.dropLast(4)) : base
        return URL(string: root + url)
    }
    var categoryId: Int?
    var verifyStatus: VerifyStatus?
    var verifySource: String?
    var rawOcrText: String?
    var locationType: LocationType?
    var locationId: Int?
    var libraryId: Int?
    var createdAt: Date?
    var updatedAt: Date?
    /// 回收站时间；null 表示未被删（仅 /books/trash 响应会带值）
    var deletedAt: Date?
    /// 图书馆缓存来源书籍 ID
    var cacheSourceBookId: Int?

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
    var edition: String?                                    // 版次
    var adaptation: String?                                 // 改编
    var translator: String?                                 // 译者
    var authorNationality: String?                          // 作者国籍
    var publisherPerson: String?                            // 出版人
    var responsibleEditor: String?                          // 责任编辑
    var responsiblePrinting: String?                        // 责任印制
    var coverDesign: String?                                // 封面设计
    var phone: String?                                      // 电话
    var address: String?                                    // 地址
    var postalCode: String?                                 // 邮编
    var printingHouse: String?                              // 印刷
    var impression: String?                                 // 印次
    var format: String?                                     // 开本
    var printedSheets: String?                              // 印张
    var wordCount: String?                                  // 字数
    // 发给服务器时也用字符串，服务端会解析 "29.8"/"¥29.8"/"29.80元" 等形式
    var price: String?
    var coverUrl: String?
    var categoryId: Int?
    var verifyStatus: VerifyStatus?
    var verifySource: String?
    var rawOcrText: String?
    var cacheSourceBookId: Int?  // 图书馆缓存来源
}

/// 从照片提取书籍详情的响应
struct ExtractBookDetailsResponse: Codable {
    let extracted: ExtractedBookDetails
    let match: Book?
    let matchReason: String?
    let candidates: [Book]
}

/// AI 从照片里读出的字段（任意一项可能为 nil）
struct ExtractedBookDetails: Codable {
    var title: String?
    var author: String?
    var isbn: String?
    var publisher: String?
    var edition: String?
    var price: Double?
    var adaptation: String?
    var translator: String?
    var authorNationality: String?
    var publisherPerson: String?
    var responsibleEditor: String?
    var responsiblePrinting: String?
    var coverDesign: String?
    var phone: String?
    var address: String?
    var postalCode: String?
    var printingHouse: String?
    var impression: String?
    var format: String?
    var printedSheets: String?
    var wordCount: String?
}

/// 移动书籍请求
struct MoveBookRequest: Codable {
    let toType: LocationType
    let toId: Int?
    let method: String?
    let rawInput: String?
}

/// 查重候选（请求体里带的一条待新增书）
struct DuplicateCheckCandidate: Codable {
    let title: String
    let publisher: String?
}

/// 查重命中项：index 是候选数组中的下标，existing 是库中已存在的那本
struct DuplicateHit: Codable {
    let index: Int
    let existing: ExistingBookRef

    struct ExistingBookRef: Codable {
        let id: Int
        let title: String
        let publisher: String?
        let author: String?
        let libraryId: Int?
        let locationType: LocationType?
        let locationId: Int?
    }
}

/// 全库查重分组：一组 title+publisher 完全一致的重复书
struct DuplicateGroup: Codable, Identifiable {
    let title: String
    let publisher: String?
    let count: Int
    let books: [Book]

    /// 用 title + publisher 作为分组标识
    var id: String { "\(title)\u{0000}\(publisher ?? "")" }
}

/// 全库查重响应
struct DuplicateLibraryResponse: Codable {
    let groups: [DuplicateGroup]
    let totalGroups: Int
    let totalDuplicateBooks: Int
}

/// 回收站响应：软删的书 + 保留天数（服务端固定，iOS 用于提示）
struct TrashResponse: Codable {
    let data: [Book]
    let retentionDays: Int
}

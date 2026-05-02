import Foundation

/// 扫描模式
enum ScanMode: String, Codable {
    case preclassify
    case boxing
}

/// 扫描记录
struct ScanRecord: Identifiable, Codable {
    let id: Int
    let mode: ScanMode
    var boxId: Int?
    var photoPath: String?
    var ocrResult: String?
    var extractedTitles: [String]?
    var createdAt: Date?
}

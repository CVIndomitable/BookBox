import Foundation

/// 地区模式
enum RegionMode: String, Codable {
    case mainland
    case overseas
}

/// 用户设置
struct UserSettings: Codable {
    var regionMode: RegionMode
    var llmProvider: String?
    var llmApiKey: String?
    var llmEndpoint: String?
    var llmModel: String?
    var llmSupportsSearch: Bool
    var hasLlmApiKey: Bool?

    /// 默认设置
    static let defaultSettings = UserSettings(
        regionMode: .mainland,
        llmProvider: "mimo",
        llmApiKey: nil,
        llmEndpoint: nil,
        llmModel: nil,
        llmSupportsSearch: false,
        hasLlmApiKey: false
    )
}

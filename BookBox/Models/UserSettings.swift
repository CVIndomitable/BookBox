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

    enum CodingKeys: String, CodingKey {
        case regionMode = "region_mode"
        case llmProvider = "llm_provider"
        case llmApiKey = "llm_api_key"
        case llmEndpoint = "llm_endpoint"
        case llmModel = "llm_model"
        case llmSupportsSearch = "llm_supports_search"
    }

    /// 默认设置
    static let defaultSettings = UserSettings(
        regionMode: .mainland,
        llmProvider: nil,
        llmApiKey: nil,
        llmEndpoint: nil,
        llmModel: nil,
        llmSupportsSearch: false
    )
}

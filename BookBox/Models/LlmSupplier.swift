import Foundation

/// AI 供应商（服务器下发，iOS 仅读取展示）
struct LlmSupplier: Codable, Identifiable, Equatable {
    var id: Int
    var name: String
    var protocolName: String
    var endpoint: String
    var apiKeyMasked: String?
    var hasApiKey: Bool
    var visionModel: String?
    var textModel: String?
    var priority: Int
    var enabled: Bool
    var timeoutMs: Int
    var note: String?
    var lastOkAt: Date?
    var lastFailAt: Date?
    var lastError: String?

    enum CodingKeys: String, CodingKey {
        case id, name
        case protocolName = "protocol"
        case endpoint, apiKeyMasked, hasApiKey
        case visionModel, textModel
        case priority, enabled, timeoutMs
        case note, lastOkAt, lastFailAt, lastError
    }
}

/// 服务器返回的调用元信息（来自 /llm/recognize、/llm/voice-command）
struct SupplierMeta: Codable, Equatable {
    var id: Int
    var name: String
    var priority: Int
    var degraded: Bool
    var topName: String
    var topPriority: Int
    var triedCount: Int

    /// 生成给用户看的降级提示
    var degradationMessage: String {
        "AI 顶级供应商 \(topName)（P\(topPriority)）不可用，已自动切换到 \(name)（P\(priority)）"
    }
}

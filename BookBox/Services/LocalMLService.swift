import Foundation

/// 本地 Core ML 服务 — 可选功能，用于离线书名提取和分类
/// 当前为占位实现，后续集成 Core ML 模型时填充
#warning("LocalMLService 为占位实现，需集成 Core ML 模型")
final class LocalMLService {
    static let shared = LocalMLService()
    private init() {}

    /// 本地模型是否可用
    var isAvailable: Bool {
        // TODO: 检查是否有已下载的 Core ML 模型
        false
    }

    /// 使用本地模型提取书名
    func extractTitles(from ocrText: String) async throws -> [ExtractedTitle] {
        guard isAvailable else {
            throw LocalMLError.modelNotAvailable
        }
        // TODO: 加载 Core ML 模型进行推理
        return []
    }

    /// 使用本地模型分类
    func classifyBook(title: String) async throws -> String {
        guard isAvailable else {
            throw LocalMLError.modelNotAvailable
        }
        // TODO: 加载 Core ML 模型进行推理
        return "未分类"
    }
}

enum LocalMLError: LocalizedError {
    case modelNotAvailable
    case predictionFailed(Error)

    var errorDescription: String? {
        switch self {
        case .modelNotAvailable:
            return "本地 AI 模型不可用"
        case .predictionFailed:
            return "本地模型推理失败"
        }
    }
}

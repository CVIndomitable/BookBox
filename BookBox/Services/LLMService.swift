import Foundation

/// 大模型服务 — 通过后端转发调用大模型 API
final class LLMService {
    static let shared = LLMService()
    private let network = NetworkService.shared
    private init() {}

    /// 用大模型从 OCR 文本中提取书名列表
    func extractTitles(from ocrText: String) async throws -> [ExtractedTitle] {
        let titles = try await network.llmExtractTitles(ocrText: ocrText)
        return titles.map { title in
            ExtractedTitle(
                title: title,
                confidence: 0.85,
                source: .llm
            )
        }
    }

    /// 用大模型对书籍进行分类
    func classifyBook(title: String) async throws -> String {
        try await network.llmClassify(title: title)
    }
}

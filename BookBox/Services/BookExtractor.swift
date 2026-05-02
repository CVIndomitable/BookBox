import Foundation

/// 从 OCR 文本中提取出的书名候选
struct ExtractedTitle: Identifiable {
    let id = UUID()
    let title: String
    let confidence: Double
    let source: ExtractionSource
}

/// 提取来源
enum ExtractionSource {
    case rule       // 规则提取
    case localML    // 本地模型
    case llm        // 大模型 API
}

/// 书名提取服务 — 从 OCR 识别结果中提取书名
final class BookExtractor {
    static let shared = BookExtractor()
    private init() {}

    // 常见出版社关键词，用于过滤非书名行
    private let publisherKeywords = [
        "出版社", "出版", "press", "publishing", "publisher",
        "书店", "书局", "书社", "印书馆", "文艺", "文学",
        "人民", "教育", "科学", "技术", "大学"
    ]

    // 常见作者标识
    private let authorKeywords = [
        "著", "编", "译", "编著", "主编", "编译", "校注",
        "author", "by", "编辑"
    ]

    /// 从 OCR 文本块中提取书名列表（规则式提取）
    func extractTitles(from blocks: [OCRTextBlock]) -> [ExtractedTitle] {
        var results: [ExtractedTitle] = []
        var seenTitles = Set<String>()

        for block in blocks {
            let lines = block.text
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }

            for line in lines {
                // 跳过太短的行（通常不是书名）
                guard line.count >= 2 else { continue }

                // 跳过出版社
                if isPublisherLine(line) { continue }

                // 跳过作者行
                if isAuthorLine(line) { continue }

                // 跳过纯数字行（ISBN、定价等）
                if isPureNumberLine(line) { continue }

                // 跳过价格行
                if isPriceLine(line) { continue }

                let cleaned = cleanTitle(line)
                guard !cleaned.isEmpty, cleaned.count >= 2 else { continue }

                // 去重
                let normalized = cleaned.lowercased()
                guard !seenTitles.contains(normalized) else { continue }
                seenTitles.insert(normalized)

                // 计算置信度：基于文本长度、OCR 置信度等
                let confidence = calculateConfidence(title: cleaned, block: block)
                results.append(ExtractedTitle(
                    title: cleaned,
                    confidence: confidence,
                    source: .rule
                ))
            }
        }

        // 按置信度降序排列
        return results.sorted { $0.confidence > $1.confidence }
    }

    /// 从纯文本中提取（当没有文本块信息时使用）
    func extractTitles(from text: String) -> [ExtractedTitle] {
        let blocks = text
            .components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .map { OCRTextBlock(text: $0, confidence: 0.8, boundingBox: .zero) }
        return extractTitles(from: blocks)
    }

    // MARK: - 私有方法

    private func isPublisherLine(_ line: String) -> Bool {
        let lower = line.lowercased()
        return publisherKeywords.contains { lower.contains($0) }
    }

    private func isAuthorLine(_ line: String) -> Bool {
        let lower = line.lowercased()
        return authorKeywords.contains { lower.hasSuffix($0) || lower.contains("[\($0)]") }
    }

    private func isPureNumberLine(_ line: String) -> Bool {
        let digits = line.filter(\.isNumber)
        return digits.count > line.count / 2 && line.count > 3
    }

    private func isPriceLine(_ line: String) -> Bool {
        let patterns = ["¥", "￥", "元", "USD", "$", "定价"]
        return patterns.contains { line.contains($0) }
    }

    private func cleanTitle(_ title: String) -> String {
        var result = title
        // 去除首尾标点
        result = result.trimmingCharacters(in: .punctuationCharacters)
        result = result.trimmingCharacters(in: .whitespaces)
        // 去除书名号
        result = result.replacingOccurrences(of: "《", with: "")
        result = result.replacingOccurrences(of: "》", with: "")
        return result
    }

    private func calculateConfidence(title: String, block: OCRTextBlock) -> Double {
        var score = Double(block.confidence)

        // 长度加分：2-30 字符的书名最合理
        if title.count >= 2 && title.count <= 30 {
            score += 0.1
        }
        // 包含中文字符加分
        if title.unicodeScalars.contains(where: { $0.value >= 0x4E00 && $0.value <= 0x9FFF }) {
            score += 0.05
        }

        return min(score, 1.0)
    }
}

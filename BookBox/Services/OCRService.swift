import Vision
import UIKit

/// OCR 识别结果中的单个文本块
struct OCRTextBlock: Identifiable {
    let id = UUID()
    let text: String
    let confidence: Float
    let boundingBox: CGRect
}

/// OCR 服务 — 封装 Apple Vision 框架的文字识别功能
final class OCRService {
    static let shared = OCRService()
    private init() {}

    /// 从图片中识别文字，返回文本块列表
    func recognizeText(from image: UIImage) async throws -> [OCRTextBlock] {
        guard let cgImage = image.cgImage else {
            throw OCRError.invalidImage
        }

        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: OCRError.recognitionFailed(error))
                    return
                }

                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(returning: [])
                    return
                }

                let blocks = observations.compactMap { observation -> OCRTextBlock? in
                    guard let candidate = observation.topCandidates(1).first else {
                        return nil
                    }
                    return OCRTextBlock(
                        text: candidate.string,
                        confidence: candidate.confidence,
                        boundingBox: observation.boundingBox
                    )
                }

                continuation.resume(returning: blocks)
            }

            // 设置识别语言：简体中文、繁体中文、英文
            request.recognitionLanguages = ["zh-Hans", "zh-Hant", "en"]
            // 精确模式
            request.recognitionLevel = .accurate
            // 启用语言纠正
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: OCRError.recognitionFailed(error))
            }
        }
    }

    /// 将所有文本块合并为完整文本
    func fullText(from blocks: [OCRTextBlock]) -> String {
        blocks.map(\.text).joined(separator: "\n")
    }
}

/// OCR 错误
enum OCRError: LocalizedError {
    case invalidImage
    case recognitionFailed(Error)

    var errorDescription: String? {
        switch self {
        case .invalidImage:
            return "图片无效，无法进行文字识别"
        case .recognitionFailed:
            return "文字识别失败"
        }
    }
}

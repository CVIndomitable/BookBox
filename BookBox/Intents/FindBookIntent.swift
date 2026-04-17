import AppIntents

/// Siri 快捷指令：查找书籍所在位置
/// 策略：当前书库跑 DB+AI；若没命中，再按顺序查其他书库（只跑 DB，避免每库都等 AI）
/// Siri 单次 perform 只能返回一次 dialog，所以路径信息会在最终对话里一次性叙述
struct FindBookIntent: AppIntent {
    static var title: LocalizedStringResource = "查找书籍"
    static var description = IntentDescription("根据书名查询书在哪个书架或箱子")

    @Parameter(title: "书名")
    var bookTitle: String

    func perform() async throws -> some IntentResult & ProvidesDialog {
        do {
            let stored = UserDefaults.standard.integer(forKey: "lastLibraryId")
            let currentLibraryId: Int? = stored > 0 ? stored : nil

            // 拉全部书库，按"当前库在前"的顺序依次尝试
            let allLibraries = (try? await NetworkService.shared.fetchLibraries()) ?? []
            guard !allLibraries.isEmpty else {
                return .result(dialog: "还没有建立任何书库")
            }

            var queue: [Library] = []
            if let cid = currentLibraryId, let cur = allLibraries.first(where: { $0.id == cid }) {
                queue.append(cur)
                queue.append(contentsOf: allLibraries.filter { $0.id != cid })
            } else {
                queue = allLibraries
            }

            var triedNames: [String] = []

            for (idx, lib) in queue.enumerated() {
                // 只对当前书库开启 AI 兜底；其他库仅跑严格+宽松（速度优先）
                let useAI = (idx == 0)
                let result = try await NetworkService.shared.findBookSmart(query: bookTitle, libraryId: lib.id, useAI: useAI)

                if let book = result.books.first {
                    let locDesc = await Self.locationDescription(for: book, libraryId: lib.id)
                    let tag: String
                    switch result.method {
                    case "ai": tag = "（AI 模糊匹配）"
                    case "loose": tag = "（近似匹配）"
                    default: tag = ""
                    }
                    let libPrefix: String
                    if triedNames.isEmpty {
                        libPrefix = ""
                    } else {
                        let priorList = triedNames.map { "《\($0)》" }.joined(separator: "、")
                        libPrefix = "在 \(priorList) 没找到，在《\(lib.name)》"
                    }
                    return .result(dialog: IntentDialog(stringLiteral: "\(libPrefix)\(locDesc)\(tag)"))
                }
                triedNames.append(lib.name)
            }

            // 全部库 DB 都没命中，最后做一次跨库 AI 兜底
            let finalResult = try await NetworkService.shared.findBookSmart(query: bookTitle, libraryId: nil, useAI: true)
            if let book = finalResult.books.first {
                let libName = allLibraries.first(where: { $0.id == book.libraryId })?.name ?? "其他书库"
                let locDesc = await Self.locationDescription(for: book, libraryId: book.libraryId)
                let priorList = triedNames.map { "《\($0)》" }.joined(separator: "、")
                return .result(dialog: IntentDialog(stringLiteral: "在 \(priorList) 都没严格匹配到，AI 在《\(libName)》给到最接近的一本：\(locDesc)"))
            }

            let priorList = triedNames.map { "《\($0)》" }.joined(separator: "、")
            return .result(dialog: IntentDialog(stringLiteral: "在 \(priorList) 都没有找到《\(bookTitle)》"))
        } catch {
            return .result(dialog: IntentDialog(stringLiteral: "查询失败：\(error.localizedDescription)"))
        }
    }

    /// 根据 book 的 locationType/locationId 生成"xxx 在书架/箱子「yyy」"描述
    private static func locationDescription(for book: Book, libraryId: Int?) async -> String {
        let title = "《\(book.title)》"
        switch book.locationType {
        case .shelf:
            let shelves = (try? await NetworkService.shared.fetchShelves(libraryId: libraryId)) ?? []
            let name = shelves.first(where: { $0.id == book.locationId })?.name ?? "未知书架"
            return "\(title)在书架「\(name)」"
        case .box:
            let boxes = (try? await NetworkService.shared.fetchBoxes(libraryId: libraryId)) ?? []
            let name = boxes.first(where: { $0.id == book.locationId })?.name ?? "未知箱子"
            return "\(title)在箱子「\(name)」"
        default:
            return "\(title)还未归位"
        }
    }
}

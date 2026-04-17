import AppIntents

/// Siri 快捷指令：把书移动到指定书架或箱子
/// 跨库语义：书和目标可以在不同书库；后端 /books/:id/move 会据目标容器的 libraryId
/// 同步更新 book.libraryId。书用 findBookSmart 全库级联搜索，目标 shelf/box 按名称
/// 包含匹配，范围是全部书库。
struct MoveBookIntent: AppIntent {
    static var title: LocalizedStringResource = "移动书籍"
    static var description = IntentDescription("将书移动到指定书架或箱子（支持跨书库）")

    @Parameter(title: "书名")
    var bookTitle: String

    @Parameter(title: "目标位置")
    var destination: String

    func perform() async throws -> some IntentResult & ProvidesDialog {
        do {
            // 1. 跨库找书（当前库 DB+AI，其他库 DB，最后跨库 AI 兜底）
            let stored = UserDefaults.standard.integer(forKey: "lastLibraryId")
            let currentLibraryId: Int? = stored > 0 ? stored : nil
            let libraries = (try? await NetworkService.shared.fetchLibraries()) ?? []

            var candidate: Book?
            var foundAt: String?
            var triedNames: [String] = []

            var queue: [Library] = []
            if let cid = currentLibraryId, let cur = libraries.first(where: { $0.id == cid }) {
                queue.append(cur)
                queue.append(contentsOf: libraries.filter { $0.id != cid })
            } else {
                queue = libraries
            }

            for (idx, lib) in queue.enumerated() {
                let useAI = (idx == 0)
                let r = try await NetworkService.shared.findBookSmart(query: bookTitle, libraryId: lib.id, useAI: useAI)
                if let b = r.books.first {
                    candidate = b
                    foundAt = lib.name
                    break
                }
                triedNames.append(lib.name)
            }

            if candidate == nil {
                let cross = try await NetworkService.shared.findBookSmart(query: bookTitle, libraryId: nil, useAI: true)
                if let b = cross.books.first {
                    candidate = b
                    foundAt = libraries.first(where: { $0.id == b.libraryId })?.name ?? "其他书库"
                }
            }

            guard let book = candidate else {
                return .result(dialog: IntentDialog(stringLiteral: "没有找到《\(bookTitle)》"))
            }

            // 2. 全局搜索目标书架/箱子（跨库）
            let shelves = (try? await NetworkService.shared.fetchShelves(libraryId: nil)) ?? []
            if let shelf = shelves.first(where: { $0.name.contains(destination) }) {
                let req = MoveBookRequest(toType: .shelf, toId: shelf.id, method: "siri", rawInput: "Siri: 移动\(bookTitle)到\(destination)")
                _ = try await NetworkService.shared.moveBook(id: book.id, request: req)
                let targetLibName = libraries.first(where: { $0.id == shelf.libraryId })?.name
                let suffix = crossMessage(bookLib: foundAt, targetLib: targetLibName)
                return .result(dialog: IntentDialog(stringLiteral: "已将《\(book.title)》移到书架「\(shelf.name)」\(suffix)"))
            }

            let boxes = (try? await NetworkService.shared.fetchBoxes(libraryId: nil)) ?? []
            if let box = boxes.first(where: { $0.name.contains(destination) }) {
                let req = MoveBookRequest(toType: .box, toId: box.id, method: "siri", rawInput: "Siri: 移动\(bookTitle)到\(destination)")
                _ = try await NetworkService.shared.moveBook(id: book.id, request: req)
                let targetLibName = libraries.first(where: { $0.id == box.libraryId })?.name
                let suffix = crossMessage(bookLib: foundAt, targetLib: targetLibName)
                return .result(dialog: IntentDialog(stringLiteral: "已将《\(book.title)》移到箱子「\(box.name)」\(suffix)"))
            }

            return .result(dialog: IntentDialog(stringLiteral: "没有找到名为「\(destination)」的书架或箱子"))
        } catch {
            return .result(dialog: IntentDialog(stringLiteral: "操作失败：\(error.localizedDescription)"))
        }
    }

    /// 跨书库时在结尾附上"（从《A》搬到《B》）"，同库则为空
    private func crossMessage(bookLib: String?, targetLib: String?) -> String {
        guard let b = bookLib, let t = targetLib, b != t else { return "" }
        return "（从《\(b)》搬到《\(t)》）"
    }
}

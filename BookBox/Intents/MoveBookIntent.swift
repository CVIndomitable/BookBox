import AppIntents

/// Siri 快捷指令：移动书籍到指定书架或箱子
struct MoveBookIntent: AppIntent {
    static var title: LocalizedStringResource = "移动书籍"
    static var description = IntentDescription("将书移动到指定书架或箱子")

    @Parameter(title: "书名")
    var bookTitle: String

    @Parameter(title: "目标位置")
    var destination: String

    func perform() async throws -> some IntentResult & ProvidesDialog {
        do {
            // 搜索书籍
            let searchResult = try await NetworkService.shared.fetchBooks(search: bookTitle)
            guard let book = searchResult.data.first else {
                return .result(dialog: "没有找到《\(bookTitle)》")
            }

            // 先搜索书架
            let shelves = try await NetworkService.shared.fetchShelves()
            if let shelf = shelves.first(where: { $0.name.contains(destination) }) {
                let req = MoveBookRequest(toType: .shelf, toId: shelf.id, method: "siri", rawInput: "Siri: 移动\(bookTitle)到\(destination)")
                _ = try await NetworkService.shared.moveBook(id: book.id, request: req)
                return .result(dialog: "已将《\(book.title)》移到书架「\(shelf.name)」")
            }

            // 再搜索箱子
            let boxes = try await NetworkService.shared.fetchBoxes()
            if let box = boxes.first(where: { $0.name.contains(destination) }) {
                let req = MoveBookRequest(toType: .box, toId: box.id, method: "siri", rawInput: "Siri: 移动\(bookTitle)到\(destination)")
                _ = try await NetworkService.shared.moveBook(id: book.id, request: req)
                return .result(dialog: "已将《\(book.title)》移到箱子「\(box.name)」")
            }

            return .result(dialog: "没有找到名为「\(destination)」的书架或箱子")
        } catch {
            return .result(dialog: "操作失败：\(error.localizedDescription)")
        }
    }
}

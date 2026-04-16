import AppIntents

/// Siri 快捷指令：查找书籍所在位置
struct FindBookIntent: AppIntent {
    static var title: LocalizedStringResource = "查找书籍"
    static var description = IntentDescription("根据书名查询书在哪个书架或箱子")

    @Parameter(title: "书名")
    var bookTitle: String

    func perform() async throws -> some IntentResult & ProvidesDialog {
        do {
            // 多书库下仅查当前书库
            let stored = UserDefaults.standard.integer(forKey: "lastLibraryId")
            let libraryId: Int? = stored > 0 ? stored : nil

            let result = try await NetworkService.shared.fetchBooks(pageSize: 5, search: bookTitle, libraryId: libraryId)
            let books = result.data

            guard !books.isEmpty else {
                return .result(dialog: "没有找到《\(bookTitle)》")
            }

            // 一次性拉取书架和箱子,避免 N+1
            async let shelvesTask = NetworkService.shared.fetchShelves(libraryId: libraryId)
            async let boxesTask = NetworkService.shared.fetchBoxes(libraryId: libraryId)
            let shelves = (try? await shelvesTask) ?? []
            let boxes = (try? await boxesTask) ?? []

            let describe: (Book) -> String = { book in
                switch book.locationType {
                case .shelf:
                    let name = shelves.first(where: { $0.id == book.locationId })?.name ?? "未知书架"
                    return "《\(book.title)》在书架「\(name)」"
                case .box:
                    let name = boxes.first(where: { $0.id == book.locationId })?.name ?? "未知箱子"
                    return "《\(book.title)》在箱子「\(name)」"
                default:
                    return "《\(book.title)》还未归位"
                }
            }

            if books.count == 1 {
                return .result(dialog: "\(describe(books[0]))")
            }

            let preview = books.prefix(3).map(describe).joined(separator: "；")
            let tail = books.count > 3 ? "，还有 \(books.count - 3) 本" : ""
            return .result(dialog: "找到 \(books.count) 本:\(preview)\(tail)")
        } catch {
            return .result(dialog: "查询失败:\(error.localizedDescription)")
        }
    }
}

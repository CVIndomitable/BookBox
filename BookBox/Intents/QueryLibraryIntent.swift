import AppIntents

/// Siri 快捷指令：查询书库概况
struct QueryLibraryIntent: AppIntent {
    static var title: LocalizedStringResource = "查询书库"
    static var description = IntentDescription("查看书库中的书籍数量和分布情况")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        do {
            // 多书库下仅查当前书库
            let stored = UserDefaults.standard.integer(forKey: "lastLibraryId")
            let libraryId: Int? = stored > 0 ? stored : nil
            let overview = try await NetworkService.shared.fetchLibraryOverview(libraryId: libraryId)

            var parts: [String] = []
            parts.append("书库共有 \(overview.totalBooks) 本书")

            if !overview.shelves.isEmpty {
                let shelfDesc = overview.shelves.map { "\($0.name) \($0.bookCount)本" }.joined(separator: "、")
                parts.append("书架：\(shelfDesc)")
            }

            if !overview.boxes.isEmpty {
                let boxDesc = overview.boxes.map { "\($0.name) \($0.bookCount)本" }.joined(separator: "、")
                parts.append("箱子：\(boxDesc)")
            }

            if overview.unlocated > 0 {
                parts.append("未归位 \(overview.unlocated) 本")
            }

            return .result(dialog: "\(parts.joined(separator: "，"))")
        } catch {
            return .result(dialog: "查询失败：\(error.localizedDescription)")
        }
    }
}

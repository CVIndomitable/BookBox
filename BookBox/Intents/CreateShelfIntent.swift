import AppIntents

/// Siri 快捷指令：新建书架
struct CreateShelfIntent: AppIntent {
    static var title: LocalizedStringResource = "新建书架"
    static var description = IntentDescription("在书库中创建一个新的书架")

    @Parameter(title: "书架名称")
    var shelfName: String

    @Parameter(title: "位置描述", default: nil)
    var location: String?

    func perform() async throws -> some IntentResult & ProvidesDialog {
        do {
            // 使用上次选择的书库
            let libraryId = UserDefaults.standard.integer(forKey: "lastLibraryId")
            let request = ShelfRequest(
                name: shelfName,
                location: location,
                libraryId: libraryId > 0 ? libraryId : nil
            )
            let shelf = try await NetworkService.shared.createShelf(request)
            return .result(dialog: "已创建书架「\(shelf.name)」")
        } catch {
            return .result(dialog: "创建失败：\(error.localizedDescription)")
        }
    }
}

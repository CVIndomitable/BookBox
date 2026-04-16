import AppIntents

/// 注册 Siri 快捷短语
struct BookBoxShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: MoveBookIntent(),
            phrases: [
                "在书库移动书籍",
                "书库移动书",
            ],
            shortTitle: "移动书籍",
            systemImageName: "arrow.right.circle"
        )
        AppShortcut(
            intent: QueryLibraryIntent(),
            phrases: [
                "查看书库",
                "书库有多少书",
            ],
            shortTitle: "查询书库",
            systemImageName: "books.vertical"
        )
        AppShortcut(
            intent: FindBookIntent(),
            phrases: [
                "在书库找书",
                "书库查找书籍",
                "书库这本书在哪",
            ],
            shortTitle: "查找书籍",
            systemImageName: "magnifyingglass"
        )
        AppShortcut(
            intent: CreateShelfIntent(),
            phrases: [
                "在书库新建书架",
                "书库创建书架",
            ],
            shortTitle: "新建书架",
            systemImageName: "plus.rectangle.on.rectangle"
        )
    }
}

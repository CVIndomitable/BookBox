import AppIntents

/// 注册 Siri 快捷短语
struct BookBoxShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: MoveBookIntent(),
            phrases: [
                "在\(.applicationName)移动书籍",
                "\(.applicationName)移动书",
            ],
            shortTitle: "移动书籍",
            systemImageName: "arrow.right.circle"
        )
        AppShortcut(
            intent: QueryLibraryIntent(),
            phrases: [
                "查看\(.applicationName)书库",
                "\(.applicationName)有多少书",
            ],
            shortTitle: "查询书库",
            systemImageName: "books.vertical"
        )
        AppShortcut(
            intent: FindBookIntent(),
            phrases: [
                "在\(.applicationName)找书",
                "\(.applicationName)查找书籍",
                "\(.applicationName)这本书在哪",
            ],
            shortTitle: "查找书籍",
            systemImageName: "magnifyingglass"
        )
        AppShortcut(
            intent: CreateShelfIntent(),
            phrases: [
                "在\(.applicationName)新建书架",
                "\(.applicationName)创建书架",
            ],
            shortTitle: "新建书架",
            systemImageName: "plus.rectangle.on.rectangle"
        )
    }
}

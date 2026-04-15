import SwiftUI

/// 全局操作日志
struct LogsView: View {
    @State private var logs: [BookLog] = []
    @State private var isLoading = true
    @State private var currentPage = 1
    @State private var hasMore = true
    @State private var selectedAction: String?
    @State private var selectedMethod: String?
    @State private var errorMessage: String?

    private let actions = ["add", "move", "remove", "edit", "verify"]
    private let methods = ["manual", "voice", "scan"]

    var body: some View {
        VStack(spacing: 0) {
            filterBar

            if isLoading && logs.isEmpty {
                ProgressView("加载中...")
                    .frame(maxHeight: .infinity)
            } else if logs.isEmpty {
                ContentUnavailableView("暂无操作记录", systemImage: "clock.arrow.circlepath")
            } else {
                List {
                    ForEach(logs) { log in
                        logRow(log)
                    }
                    if hasMore {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .onAppear { Task { await loadMore() } }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("操作日志")
        .task { await loadLogs() }
        .refreshable {
            currentPage = 1
            await loadLogs()
        }
        .alert("加载失败", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("确定") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: - 筛选栏

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Menu {
                    Button("全部操作") { selectedAction = nil; resetAndLoad() }
                    ForEach(actions, id: \.self) { action in
                        Button(actionLabel(action)) {
                            selectedAction = action
                            resetAndLoad()
                        }
                    }
                } label: {
                    Label(selectedAction.map { actionLabel($0) } ?? "操作类型",
                          systemImage: "line.3.horizontal.decrease.circle")
                        .font(.callout)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(selectedAction != nil ? Color.accentColor.opacity(0.15) : Color(.systemGray5))
                        .clipShape(Capsule())
                }

                Menu {
                    Button("全部方式") { selectedMethod = nil; resetAndLoad() }
                    ForEach(methods, id: \.self) { method in
                        Button(methodLabel(method)) {
                            selectedMethod = method
                            resetAndLoad()
                        }
                    }
                } label: {
                    Label(selectedMethod.map { methodLabel($0) } ?? "操作方式",
                          systemImage: "hand.tap")
                        .font(.callout)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(selectedMethod != nil ? Color.accentColor.opacity(0.15) : Color(.systemGray5))
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }

    // MARK: - 日志行

    private func logRow(_ log: BookLog) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: actionIcon(log.action))
                    .foregroundStyle(actionColor(log.action))
                Text(log.actionLabel)
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text(methodLabel(log.method))
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color(.systemGray5))
                    .clipShape(Capsule())
            }

            if let book = log.book {
                Text(book.title)
                    .font(.body)
                if let author = book.author {
                    Text(author)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let note = log.note, !note.isEmpty {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let date = log.createdAt {
                Text(date, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - 数据加载

    private func loadLogs() async {
        isLoading = true
        do {
            let response = try await NetworkService.shared.fetchAllLogs(
                page: currentPage,
                action: selectedAction,
                method: selectedMethod
            )
            if currentPage == 1 {
                logs = response.data
            } else {
                logs.append(contentsOf: response.data)
            }
            hasMore = logs.count < response.pagination.total
        } catch {
            errorMessage = error.chineseDescription
        }
        isLoading = false
    }

    private func loadMore() async {
        guard hasMore, !isLoading else { return }
        currentPage += 1
        await loadLogs()
    }

    private func resetAndLoad() {
        currentPage = 1
        logs = []
        Task { await loadLogs() }
    }

    // MARK: - 标签映射

    private func actionLabel(_ action: String) -> String {
        switch action {
        case "add": "入库"
        case "move": "移动"
        case "remove": "移出"
        case "edit": "编辑"
        case "verify": "校验"
        default: action
        }
    }

    private func methodLabel(_ method: String) -> String {
        switch method {
        case "manual": "手动"
        case "voice": "语音"
        case "scan": "扫描"
        default: method
        }
    }

    private func actionIcon(_ action: String) -> String {
        switch action {
        case "add": "plus.circle.fill"
        case "move": "arrow.right.circle.fill"
        case "remove": "minus.circle.fill"
        case "edit": "pencil.circle.fill"
        case "verify": "checkmark.circle.fill"
        default: "circle.fill"
        }
    }

    private func actionColor(_ action: String) -> Color {
        switch action {
        case "add": .green
        case "move": .blue
        case "remove": .red
        case "edit": .orange
        case "verify": .purple
        default: .gray
        }
    }
}

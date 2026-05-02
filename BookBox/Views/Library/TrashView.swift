import SwiftUI

/// 回收站 — 显示软删的书籍，支持还原 / 立即彻底删除
/// 服务端 30 天后自动物理删除；本页只展示，不做过期判断
struct TrashView: View {
    @State private var books: [Book] = []
    @State private var retentionDays: Int = 30
    @State private var isLoading = true
    @State private var hasLoaded = false
    @State private var errorMessage: String?
    @State private var pendingPurge: Book?
    @State private var processingId: Int?

    var body: some View {
        content
            .navigationTitle("回收站")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .task {
                if !hasLoaded { await load() }
            }
            .refreshable { await load() }
            .alert("操作失败", isPresented: errorAlertBinding) {
                Button("确定") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
            .confirmationDialog(
                pendingPurge.map { "彻底删除「\($0.title)」？" } ?? "",
                isPresented: purgeDialogBinding,
                titleVisibility: .visible
            ) {
                Button("彻底删除", role: .destructive) {
                    if let book = pendingPurge {
                        Task { await purge(book) }
                    }
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("此操作无法撤销。")
            }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading && books.isEmpty {
            ProgressView("加载回收站...")
                .frame(maxHeight: .infinity)
        } else if books.isEmpty && hasLoaded {
            ContentUnavailableView {
                Label("回收站是空的", systemImage: "trash.slash")
            } description: {
                Text("被删除的书会出现在这里，\(retentionDays) 天后彻底清除")
            }
        } else {
            List {
                Section {
                    ForEach(books) { book in
                        row(book)
                    }
                } footer: {
                    Text("保留 \(retentionDays) 天后自动彻底删除")
                }
            }
            .listStyle(.insetGrouped)
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                Task { await load() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .disabled(isLoading)
        }
    }

    private var errorAlertBinding: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    private var purgeDialogBinding: Binding<Bool> {
        Binding(
            get: { pendingPurge != nil },
            set: { if !$0 { pendingPurge = nil } }
        )
    }

    // MARK: - 行

    @ViewBuilder
    private func row(_ book: Book) -> some View {
        HStack(spacing: 12) {
            AsyncImage(url: book.coverDisplayUrl) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: .fill)
                default:
                    RoundedRectangle(cornerRadius: 4)
                        .fill(.quaternary)
                        .overlay {
                            Image(systemName: "book.closed")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                }
            }
            .frame(width: 40, height: 54)
            .clipShape(RoundedRectangle(cornerRadius: 4))

            VStack(alignment: .leading, spacing: 3) {
                Text(book.title)
                    .font(.body)
                    .lineLimit(2)
                if let author = book.author, !author.isEmpty {
                    Text(author)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if let deletedAt = book.deletedAt {
                    Text(deletedAtLabel(deletedAt))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer()
            if processingId == book.id {
                ProgressView()
            }
        }
        .padding(.vertical, 2)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                pendingPurge = book
            } label: {
                Label("彻底删除", systemImage: "trash.fill")
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button {
                Task { await restore(book) }
            } label: {
                Label("还原", systemImage: "arrow.uturn.backward")
            }
            .tint(.green)
        }
    }

    private func deletedAtLabel(_ date: Date) -> String {
        let df = DateFormatter()
        df.dateFormat = "M月d日 HH:mm"
        let deleted = df.string(from: date)
        let expire = Calendar.current.date(byAdding: .day, value: retentionDays, to: date) ?? date
        let days = Calendar.current.dateComponents([.day], from: Date(), to: expire).day ?? 0
        return "删除于 \(deleted) · \(max(0, days)) 天后清除"
    }

    // MARK: - 操作

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let resp = try await NetworkService.shared.fetchTrashedBooks()
            books = resp.data
            retentionDays = resp.retentionDays
            hasLoaded = true
        } catch {
            errorMessage = error.chineseDescription
        }
    }

    private func restore(_ book: Book) async {
        processingId = book.id
        defer { processingId = nil }
        do {
            _ = try await NetworkService.shared.restoreBook(id: book.id)
            books.removeAll { $0.id == book.id }
        } catch {
            errorMessage = "还原失败: \(error.chineseDescription)"
        }
    }

    private func purge(_ book: Book) async {
        processingId = book.id
        defer { processingId = nil }
        do {
            _ = try await NetworkService.shared.purgeBook(id: book.id)
            books.removeAll { $0.id == book.id }
        } catch {
            errorMessage = "删除失败: \(error.chineseDescription)"
        }
    }
}

#Preview {
    NavigationStack {
        TrashView()
    }
}

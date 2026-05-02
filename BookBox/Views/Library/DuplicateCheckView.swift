import SwiftUI

/// 全库查重页 — 扫描所有书，按「书名 + 出版社」分组显示重复书
struct DuplicateCheckView: View {
    @State private var groups: [DuplicateGroup] = []
    @State private var totalGroups = 0
    @State private var totalDuplicateBooks = 0
    @State private var libraryNames: [Int: String] = [:]
    @State private var shelfNames: [Int: String] = [:]
    @State private var boxNames: [Int: String] = [:]
    @State private var isLoading = false
    @State private var hasLoaded = false
    @State private var errorMessage: String?
    @State private var deletingBookId: Int?
    @State private var confirmDeleteBook: Book?

    var body: some View {
        NavigationStack {
            Group {
                if isLoading && groups.isEmpty {
                    ProgressView("扫描中...")
                        .frame(maxHeight: .infinity)
                } else if groups.isEmpty && hasLoaded {
                    ContentUnavailableView {
                        Label("没有重复书", systemImage: "checkmark.seal")
                    } description: {
                        Text("整个书库中没有「书名 + 出版社」完全一致的书籍")
                    } actions: {
                        Button("重新扫描") {
                            Task { await loadDuplicates() }
                        }
                    }
                } else {
                    List {
                        Section {
                            HStack {
                                Label("重复分组", systemImage: "rectangle.stack.badge.person.crop")
                                Spacer()
                                Text("\(totalGroups) 组")
                                    .foregroundStyle(.secondary)
                            }
                            HStack {
                                Label("重复书本", systemImage: "books.vertical")
                                Spacer()
                                Text("\(totalDuplicateBooks) 本")
                                    .foregroundStyle(.secondary)
                            }
                        } footer: {
                            Text("规则：「书名 + 出版社」完全一致视为重复；跨全部书库扫描。")
                        }

                        ForEach(groups) { group in
                            Section {
                                ForEach(group.books) { book in
                                    NavigationLink {
                                        LibraryBookDetailView(book: book)
                                    } label: {
                                        duplicateRow(book)
                                    }
                                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                        Button(role: .destructive) {
                                            confirmDeleteBook = book
                                        } label: {
                                            Label("移入回收站", systemImage: "trash")
                                        }
                                    }
                                }
                            } header: {
                                groupHeader(group)
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("查重")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await loadDuplicates() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(isLoading)
                }
            }
            .task {
                if !hasLoaded {
                    await loadDuplicates()
                }
            }
            .refreshable {
                await loadDuplicates()
            }
            .alert("加载失败", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("确定") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
            .confirmationDialog(
                confirmDeleteBook.map { "移入回收站：\($0.title)" } ?? "",
                isPresented: Binding(
                    get: { confirmDeleteBook != nil },
                    set: { if !$0 { confirmDeleteBook = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("移入回收站", role: .destructive) {
                    if let book = confirmDeleteBook {
                        Task { await deleteBook(book) }
                    }
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("30 天内可在回收站还原，过期后自动彻底删除。")
            }
        }
    }

    // MARK: - 删除

    private func deleteBook(_ book: Book) async {
        deletingBookId = book.id
        defer { deletingBookId = nil }
        do {
            _ = try await NetworkService.shared.deleteBook(id: book.id)
            // 从当前分组列表里就地剔除；若分组只剩 1 本就整组移除
            removeBookFromGroups(book.id)
        } catch {
            errorMessage = "删除失败: \(error.chineseDescription)"
        }
    }

    private func removeBookFromGroups(_ bookId: Int) {
        var newGroups: [DuplicateGroup] = []
        var removedCount = 0
        for group in groups {
            let remaining = group.books.filter { $0.id != bookId }
            removedCount += group.books.count - remaining.count
            // 组内只剩 1 本就不再算重复，整组去掉
            if remaining.count >= 2 {
                newGroups.append(DuplicateGroup(
                    title: group.title,
                    publisher: group.publisher,
                    count: remaining.count,
                    books: remaining
                ))
            }
        }
        groups = newGroups
        totalGroups = newGroups.count
        totalDuplicateBooks = max(0, totalDuplicateBooks - removedCount)
    }

    // MARK: - 子视图

    private func groupHeader(_ group: DuplicateGroup) -> some View {
        HStack(spacing: 6) {
            Text(group.title)
                .font(.callout.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
            Spacer()
            Text("× \(group.count)")
                .font(.caption)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.orange.opacity(0.2), in: Capsule())
                .foregroundStyle(.orange)
        }
        .textCase(nil)
        .padding(.bottom, 2)
        .overlay(alignment: .bottomLeading) {
            if let publisher = group.publisher, !publisher.isEmpty {
                Text(publisher)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .offset(y: 14)
            }
        }
    }

    private func duplicateRow(_ book: Book) -> some View {
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
                if let author = book.author, !author.isEmpty {
                    Text(author)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Text(locationDescription(for: book))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                Text("ID: \(book.id)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            if let status = book.verifyStatus {
                StatusBadge(status: status)
            }
        }
        .padding(.vertical, 2)
    }

    /// 拼接「书库 / 容器名」的位置描述
    private func locationDescription(for book: Book) -> String {
        var parts: [String] = []
        if let lid = book.libraryId, let lname = libraryNames[lid] {
            parts.append(lname)
        }

        switch book.locationType {
        case .shelf:
            if let id = book.locationId, let name = shelfNames[id] {
                parts.append("书架·\(name)")
            } else {
                parts.append("书架")
            }
        case .box:
            if let id = book.locationId, let name = boxNames[id] {
                parts.append("箱子·\(name)")
            } else {
                parts.append("箱子")
            }
        default:
            parts.append("未归位")
        }

        return parts.joined(separator: " · ")
    }

    // MARK: - 数据加载

    private func loadDuplicates() async {
        isLoading = true
        defer { isLoading = false }
        do {
            // 并发拉重复数据和各类容器的名称映射
            async let dupTask = NetworkService.shared.fetchLibraryDuplicates()
            async let librariesTask = NetworkService.shared.fetchLibraries()
            async let shelvesTask = NetworkService.shared.fetchShelves()
            async let boxesTask = NetworkService.shared.fetchBoxes()

            let resp = try await dupTask
            let libs = (try? await librariesTask) ?? []
            let shelves = (try? await shelvesTask) ?? []
            let boxes = (try? await boxesTask) ?? []

            libraryNames = Dictionary(uniqueKeysWithValues: libs.map { ($0.id, $0.name) })
            shelfNames = Dictionary(uniqueKeysWithValues: shelves.map { ($0.id, $0.name) })
            boxNames = Dictionary(uniqueKeysWithValues: boxes.map { ($0.id, $0.name) })

            groups = resp.groups
            totalGroups = resp.totalGroups
            totalDuplicateBooks = resp.totalDuplicateBooks
            hasLoaded = true
        } catch {
            errorMessage = error.chineseDescription
        }
    }
}

#Preview {
    DuplicateCheckView()
}

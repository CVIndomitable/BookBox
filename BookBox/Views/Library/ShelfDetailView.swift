import SwiftUI

/// 书架详情 — 展示书架上的所有书籍，支持编辑/删除书架、移除书籍
struct ShelfDetailView: View {
    let shelfId: Int
    let shelfName: String
    @Environment(\.dismiss) private var dismiss
    @State private var shelf: Shelf?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showEdit = false
    @State private var showDeleteConfirm = false
    @State private var editName = ""
    @State private var editLocation = ""
    @State private var editDescription = ""
    @State private var isSaving = false

    var body: some View {
        Group {
            if isLoading {
                ProgressView("加载中...")
                    .frame(maxHeight: .infinity)
            } else if let shelf {
                List {
                    Section {
                        LabeledContent("名称", value: shelf.name)
                        if let location = shelf.location, !location.isEmpty {
                            LabeledContent("位置", value: location)
                        }
                        LabeledContent("书籍数量", value: "\(shelf.bookCount) 本")
                        if let desc = shelf.description, !desc.isEmpty {
                            LabeledContent("备注", value: desc)
                        }
                    } header: {
                        Text("书架信息")
                    }

                    if let books = shelf.books, !books.isEmpty {
                        Section {
                            ForEach(books) { book in
                                NavigationLink(value: book) {
                                    BookRow(book: book)
                                }
                            }
                            .onDelete { offsets in
                                removeBooks(at: offsets, from: books)
                            }
                        } header: {
                            Text("书架上的书")
                        }
                    } else {
                        Section {
                            ContentUnavailableView("书架上暂无书籍", systemImage: "book.closed")
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .navigationDestination(for: Book.self) { book in
                    LibraryBookDetailView(book: book)
                }
            }
        }
        .navigationTitle(shelf?.name ?? shelfName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        editName = shelf?.name ?? shelfName
                        editLocation = shelf?.location ?? ""
                        editDescription = shelf?.description ?? ""
                        showEdit = true
                    } label: {
                        Label("编辑", systemImage: "pencil")
                    }
                    Button(role: .destructive) {
                        showDeleteConfirm = true
                    } label: {
                        Label("删除书架", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .task { await loadDetail() }
        .refreshable { await loadDetail() }
        .sheet(isPresented: $showEdit) {
            NavigationStack {
                Form {
                    Section("书架信息") {
                        TextField("书架名称", text: $editName)
                        TextField("位置（可选）", text: $editLocation)
                        TextField("备注（可选）", text: $editDescription, axis: .vertical)
                            .lineLimit(3...6)
                    }
                }
                .navigationTitle("编辑书架")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("取消") { showEdit = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("保存") { updateShelf() }
                            .disabled(editName.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                    }
                }
            }
        }
        .alert("确认删除", isPresented: $showDeleteConfirm) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) { deleteShelf() }
        } message: {
            Text("删除书架后，书架上的书籍不会被删除，但会变为未归位状态。")
        }
        .alert("操作失败", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("确定") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func loadDetail() async {
        isLoading = true
        do {
            shelf = try await NetworkService.shared.fetchShelf(id: shelfId)
        } catch {
            errorMessage = error.chineseDescription
        }
        isLoading = false
    }

    private func updateShelf() {
        isSaving = true
        Task {
            do {
                let updated = try await NetworkService.shared.updateShelf(
                    id: shelfId,
                    ShelfRequest(
                        name: editName.trimmingCharacters(in: .whitespaces),
                        location: editLocation.isEmpty ? nil : editLocation,
                        description: editDescription.isEmpty ? nil : editDescription,
                        libraryId: shelf?.libraryId
                    )
                )
                shelf = updated
                showEdit = false
            } catch {
                errorMessage = error.chineseDescription
            }
            isSaving = false
        }
    }

    private func deleteShelf() {
        Task {
            do {
                _ = try await NetworkService.shared.deleteShelf(id: shelfId)
                dismiss()
            } catch {
                errorMessage = error.chineseDescription
            }
        }
    }

    private func removeBooks(at offsets: IndexSet, from books: [Book]) {
        let booksToRemove = offsets.map { books[$0] }
        for book in booksToRemove {
            Task {
                do {
                    _ = try await NetworkService.shared.removeBookFromShelf(shelfId: shelfId, bookId: book.id)
                    await loadDetail()
                } catch {
                    errorMessage = error.chineseDescription
                }
            }
        }
    }
}

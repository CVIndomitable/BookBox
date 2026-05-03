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
    @State private var showAddBooks = false
    @State private var editName = ""
    @State private var editLocation = ""
    @State private var editDescription = ""
    @State private var isSaving = false

    @State private var editLibraries: [Library] = []
    @State private var editLibraryId: Int?
    @State private var isLoadingEditLibraries = false

    @State private var editRooms: [Room] = []
    @State private var editRoomId: Int?
    @State private var isLoadingEditRooms = false

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
                                NavigationLink {
                                    LibraryBookDetailView(book: book)
                                } label: {
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
            }
        }
        .navigationTitle(shelf?.name ?? shelfName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showAddBooks = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                }
                .disabled(shelf == nil)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        editName = shelf?.name ?? shelfName
                        editLocation = shelf?.location ?? ""
                        editDescription = shelf?.description ?? ""
                        editLibraryId = shelf?.libraryId
                        editRoomId = shelf?.roomId
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
        .sheet(isPresented: $showAddBooks) {
            ShelfAddBooksSheet(
                shelfId: shelfId,
                shelfName: shelf?.name ?? shelfName,
                libraryId: shelf?.libraryId,
                onCompleted: {
                    Task { await loadDetail() }
                }
            )
        }
        .sheet(isPresented: $showEdit) {
            editSheet
        }
        .alert("确认删除", isPresented: $showDeleteConfirm) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) { deleteShelf() }
        } message: {
            let count = shelf?.bookCount ?? 0
            if count > 0 {
                Text("删除书架后，书架上的 \(count) 本书不会被删除，但会变为未归位状态。")
            } else {
                Text("删除书架后，若有书籍将变为未归位状态。")
            }
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

    private var editSheet: some View {
        NavigationStack {
            Form {
                editInfoSection
                editPlacementSection
            }
            .navigationTitle("编辑书架")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { showEdit = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { updateShelf() }
                        .disabled(!canSaveEdit)
                }
            }
            .task { await loadEditOptions() }
            .onChange(of: editLibraryId) { _, newValue in
                editRoomId = nil
                editRooms = []
                if newValue != nil {
                    Task { await loadEditRooms(preferred: nil) }
                }
            }
        }
    }

    private var editInfoSection: some View {
        Section("书架信息") {
            TextField("书架名称", text: $editName)
            TextField("位置（可选）", text: $editLocation)
            TextField("备注（可选）", text: $editDescription, axis: .vertical)
                .lineLimit(3...6)
        }
    }

    @ViewBuilder
    private var editPlacementSection: some View {
        Section("归属") {
            editLibraryPicker
            if editLibraryId != nil {
                editRoomPicker
            }
        }
    }

    @ViewBuilder
    private var editLibraryPicker: some View {
        if isLoadingEditLibraries {
            ProgressView()
        } else if editLibraries.isEmpty {
            Text("暂无书库")
                .foregroundStyle(.secondary)
        } else {
            Picker("书库", selection: $editLibraryId) {
                Text("请选择书库").tag(Int?.none)
                ForEach(editLibraries) { lib in
                    Text(lib.name).tag(Int?(lib.id))
                }
            }
        }
    }

    @ViewBuilder
    private var editRoomPicker: some View {
        if isLoadingEditRooms {
            ProgressView()
        } else if editRooms.isEmpty {
            Text("该书库暂无房间")
                .foregroundStyle(.secondary)
        } else {
            Picker("房间", selection: $editRoomId) {
                Text("请选择房间").tag(Int?.none)
                ForEach(editRooms) { room in
                    Text(room.isDefault ? "\(room.name)（默认）" : room.name)
                        .tag(Int?(room.id))
                }
            }
        }
    }

    private var canSaveEdit: Bool {
        !editName.trimmingCharacters(in: .whitespaces).isEmpty
            && !isSaving
            && editLibraryId != nil
            && editRoomId != nil
    }

    private func loadEditOptions() async {
        isLoadingEditLibraries = true
        do {
            editLibraries = try await NetworkService.shared.fetchLibraries()
        } catch {
            errorMessage = error.chineseDescription
        }
        isLoadingEditLibraries = false

        if editLibraryId != nil {
            await loadEditRooms(preferred: editRoomId)
        }
    }

    private func loadEditRooms(preferred: Int?) async {
        guard let libId = editLibraryId else { return }
        isLoadingEditRooms = true
        do {
            let fetched = try await NetworkService.shared.fetchRooms(libraryId: libId)
            editRooms = fetched
            if let pre = preferred, fetched.contains(where: { $0.id == pre }) {
                editRoomId = pre
            } else if let def = fetched.first(where: { $0.isDefault }) {
                editRoomId = def.id
            } else {
                editRoomId = fetched.first?.id
            }
        } catch {
            errorMessage = error.chineseDescription
        }
        isLoadingEditRooms = false
    }

    private func loadDetail() async {
        isLoading = true
        defer { isLoading = false }
        do {
            shelf = try await NetworkService.shared.fetchShelf(id: shelfId)
        } catch {
            if (error as? URLError)?.code == .cancelled { return }
            errorMessage = error.chineseDescription
        }
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
                        libraryId: editLibraryId,
                        roomId: editRoomId
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

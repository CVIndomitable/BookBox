import SwiftUI

/// 箱子详情 — 展示箱内所有书籍，支持编辑/删除箱子、移除书籍
struct BoxDetailView: View {
    let box: Box
    @Environment(\.dismiss) private var dismiss
    @State private var detail: Box?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showEdit = false
    @State private var showDeleteConfirm = false
    @State private var showAddBooks = false
    @State private var editName = ""
    @State private var editDescription = ""
    @State private var isSaving = false

    @State private var editLibraries: [Library] = []
    @State private var editLibraryId: Int?
    @State private var isLoadingEditLibraries = false

    @State private var editRooms: [Room] = []
    @State private var editRoomId: Int?
    @State private var isLoadingEditRooms = false
    @State private var showCreateSunReminder = false

    var body: some View {
        Group {
            if isLoading {
                ProgressView("加载中...")
                    .frame(maxHeight: .infinity)
            } else if let detail {
                List {
                    Section {
                        LabeledContent("编号", value: detail.boxUid)
                        LabeledContent("书籍数量", value: "\(detail.bookCount) 本")
                        if let desc = detail.description, !desc.isEmpty {
                            LabeledContent("备注", value: desc)
                        }
                    } header: {
                        Text("箱子信息")
                    }

                    if let books = detail.books, !books.isEmpty {
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
                            Text("箱内书籍")
                        }
                    } else {
                        Section {
                            ContentUnavailableView("箱内暂无书籍", systemImage: "book.closed")
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle(detail?.name ?? box.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showAddBooks = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                }
                .disabled(detail == nil)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        editName = detail?.name ?? box.name
                        editDescription = detail?.description ?? box.description ?? ""
                        editLibraryId = detail?.libraryId ?? box.libraryId
                        editRoomId = detail?.roomId ?? box.roomId
                        showEdit = true
                    } label: {
                        Label("编辑", systemImage: "pencil")
                    }
                    Button {
                        showCreateSunReminder = true
                    } label: {
                        Label("设置晒书提醒", systemImage: "sun.max")
                    }
                    Button(role: .destructive) {
                        showDeleteConfirm = true
                    } label: {
                        Label("删除箱子", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .task { await loadDetail() }
        .refreshable { await loadDetail() }
        .sheet(isPresented: $showAddBooks) {
            BoxAddBooksSheet(
                boxId: box.id,
                boxName: detail?.name ?? box.name,
                libraryId: detail?.libraryId ?? box.libraryId,
                onCompleted: {
                    Task { await loadDetail() }
                }
            )
        }
        .sheet(isPresented: $showEdit) {
            editSheet
        }
        .sheet(isPresented: $showCreateSunReminder) {
            SunReminderCreateView(
                targetType: "box",
                targetId: box.id,
                targetName: detail?.name ?? box.name,
                onCreated: { showCreateSunReminder = false }
            )
        }
        .alert("确认删除", isPresented: $showDeleteConfirm) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) { deleteBox() }
        } message: {
            let count = detail?.bookCount ?? box.bookCount
            if count > 0 {
                Text("删除箱子后，箱内 \(count) 本书不会被删除，但会变为未归位状态。")
            } else {
                Text("删除箱子后，若有书籍将变为未归位状态。")
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
            .navigationTitle("编辑箱子")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { showEdit = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { updateBox() }
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
        Section("箱子信息") {
            TextField("箱子名称", text: $editName)
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
        do {
            detail = try await NetworkService.shared.fetchBox(id: box.id)
        } catch {
            errorMessage = error.chineseDescription
            detail = box
        }
        isLoading = false
    }

    private func updateBox() {
        isSaving = true
        Task {
            do {
                _ = try await NetworkService.shared.updateBox(
                    id: box.id,
                    BoxRequest(
                        name: editName.trimmingCharacters(in: .whitespaces),
                        description: editDescription.isEmpty ? nil : editDescription,
                        libraryId: editLibraryId,
                        roomId: editRoomId
                    )
                )
                showEdit = false
                await loadDetail()
            } catch {
                errorMessage = error.chineseDescription
            }
            isSaving = false
        }
    }

    private func deleteBox() {
        Task {
            do {
                _ = try await NetworkService.shared.deleteBox(id: box.id)
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
                    _ = try await NetworkService.shared.removeBookFromBox(boxId: box.id, bookId: book.id)
                    await loadDetail()
                } catch {
                    errorMessage = error.chineseDescription
                }
            }
        }
    }
}

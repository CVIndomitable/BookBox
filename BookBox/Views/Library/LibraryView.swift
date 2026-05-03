import SwiftUI

/// 书库总览 — 顶部书库切换 + 书架 + 箱子 + 全部书籍
struct LibraryView: View {
    @State private var libraries: [Library] = []
    @State private var selectedLibraryId: Int? = nil
    @AppStorage("lastLibraryId") private var lastLibraryId: Int = 0
    @State private var overview: LibraryOverview?
    @State private var books: [Book] = []
    @State private var searchText = ""
    @State private var isLoading = true
    @State private var isLoadingLibraries = true
    @State private var currentPage = 1
    @State private var totalBooks = 0
    @State private var hasMore = true
    @State private var isPaginating = false
    @State private var errorMessage: String?
    @State private var viewMode: ViewMode = .overview
    @State private var showLibraryCreate = false
    @State private var showLibraryEdit = false
    @State private var showDeleteConfirm = false
    @State private var editingLibrary: Library?
    @State private var editName = ""
    @State private var editLocation = ""
    @State private var editDescription = ""
    @State private var isSaving = false
    @State private var showLogs = false
    @State private var showCategories = false
    @State private var showScanHistory = false
    @State private var showDetailsScan = false
    @State private var showMemberManage = false
    @State private var showSunReminders = false
    @State private var showSunReminderCreate = false

    // 书籍多选
    @State private var selectedBookIds = Set<Int>()
    @State private var isBookMultiSelect = false
    @State private var showBookBatchDeleteConfirm = false
    @State private var showBookBatchMoveSheet = false
    @State private var isBatchOperating = false

    // 书架多选
    @State private var selectedShelfIds = Set<Int>()
    @State private var isShelfMultiSelect = false
    @State private var showShelfBatchDeleteConfirm = false

    // 箱子多选
    @State private var selectedBoxIds = Set<Int>()
    @State private var isBoxMultiSelect = false
    @State private var showBoxBatchDeleteConfirm = false

    enum ViewMode: String, CaseIterable {
        case overview = "总览"
        case books = "全部书籍"
    }

    /// 当前选中的书库
    private var selectedLibrary: Library? {
        libraries.first { $0.id == selectedLibraryId }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 书库选择器
                libraryPicker

                Picker("查看方式", selection: $viewMode) {
                    ForEach(ViewMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.bottom, 8)

                switch viewMode {
                case .overview:
                    overviewContent
                case .books:
                    bookListView
                }
            }
            .navigationTitle("书库")
            .toolbar {
                if viewMode == .books && isBookMultiSelect {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("取消") {
                            isBookMultiSelect = false
                            selectedBookIds.removeAll()
                        }
                    }
                } else if viewMode == .books && !isBookMultiSelect {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("选择") {
                            isBookMultiSelect = true
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { showDetailsScan = true } label: {
                            Label("拍照补详情", systemImage: "camera.viewfinder")
                        }
                        Button { showLogs = true } label: {
                            Label("操作日志", systemImage: "clock.arrow.circlepath")
                        }
                        Button { showCategories = true } label: {
                            Label("分类管理", systemImage: "tag")
                        }
                        Button { showScanHistory = true } label: {
                            Label("扫描历史", systemImage: "doc.text.magnifyingglass")
                        }
                        if selectedLibraryId != nil {
                            Button { showMemberManage = true } label: {
                                Label("成员管理", systemImage: "person.2")
                            }
                            Button { showSunReminderCreate = true } label: {
                                Label("设置晒书提醒", systemImage: "sun.max")
                            }
                        }
                        Button { showSunReminders = true } label: {
                            Label("晒书提醒列表", systemImage: "clock.arrow.circlepath")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .navigationDestination(isPresented: $showLogs) { LogsView() }
            .navigationDestination(isPresented: $showCategories) { CategoryManageView() }
            .navigationDestination(isPresented: $showScanHistory) { ScanHistoryView() }
            .sheet(isPresented: $showDetailsScan) {
                NavigationStack {
                    BookDetailsScanView(libraryId: selectedLibraryId) { updated in
                        // 若当前正在浏览书列表，把更新后的书直接替换掉旧的，省一次刷新
                        if let idx = books.firstIndex(where: { $0.id == updated.id }) {
                            books[idx] = updated
                        }
                    }
                }
            }
            .sheet(isPresented: $showMemberManage) {
                MemberManageView(libraryId: selectedLibraryId ?? 0) {
                    Task { await loadOverview() }
                }
            }
            .sheet(isPresented: $showSunReminders) {
                SunReminderView()
            }
            .sheet(isPresented: $showSunReminderCreate) {
                if let libraryId = selectedLibraryId, let name = selectedLibrary?.name {
                    SunReminderCreateView(
                        targetType: "library",
                        targetId: libraryId,
                        targetName: name,
                        onCreated: { showSunReminderCreate = false }
                    )
                }
            }
            .searchable(text: $searchText, prompt: "搜索书名或作者")
            .onChange(of: searchText) { _, _ in
                if viewMode == .books {
                    currentPage = 1
                    books = []
                    Task { await loadBooks() }
                }
            }
            .onChange(of: selectedLibraryId) { _, newId in
                // 切换书库时重新加载数据
                if let newId {
                    lastLibraryId = newId
                }
                overview = nil
                books = []
                currentPage = 1
                Task {
                    await loadOverview()
                    if viewMode == .books {
                        await loadBooks()
                    }
                }
            }
            .sheet(isPresented: $showLibraryCreate) {
                NavigationStack {
                    LibraryCreateView { newLibrary in
                        libraries.append(newLibrary)
                        selectedLibraryId = newLibrary.id
                    }
                }
            }
            .sheet(isPresented: $showLibraryEdit) {
                NavigationStack {
                    Form {
                        Section("书库信息") {
                            TextField("书库名称", text: $editName)
                            TextField("位置（可选）", text: $editLocation)
                            TextField("备注（可选）", text: $editDescription, axis: .vertical)
                                .lineLimit(3...6)
                        }
                    }
                    .navigationTitle("编辑书库")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("取消") {
                                showLibraryEdit = false
                            }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("保存") {
                                updateLibrary()
                            }
                            .disabled(editName.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                        }
                    }
                }
            }
            .alert("确认删除", isPresented: $showDeleteConfirm) {
                Button("取消", role: .cancel) { }
                Button("删除", role: .destructive) {
                    deleteLibrary()
                }
            } message: {
                Text("删除书库「\(editingLibrary?.name ?? "")」后，其中的书籍不会被删除，但会失去书库归属。")
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
    }

    // MARK: - 书库选择器

    private var libraryPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                // 新建书库按钮
                Button {
                    showLibraryCreate = true
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.title3)
                        Text("新建")
                            .font(.caption)
                    }
                    .frame(width: 66, height: 56)
                    .background(.quaternary)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }

                if isLoadingLibraries {
                    ProgressView()
                        .frame(width: 66, height: 56)
                } else {
                    ForEach(libraries) { library in
                        Button {
                            selectedLibraryId = library.id
                        } label: {
                            VStack(spacing: 4) {
                                Image(systemName: "building.columns")
                                    .font(.title3)
                                Text(library.name)
                                    .font(.caption)
                                    .lineLimit(1)
                            }
                            .frame(width: 66, height: 56)
                            .background(selectedLibraryId == library.id ? AnyShapeStyle(Color.accentColor.opacity(0.2)) : AnyShapeStyle(.quaternary))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(selectedLibraryId == library.id ? Color.accentColor : .clear, lineWidth: 2)
                            )
                        }
                        .tint(.primary)
                        .contextMenu {
                            Button {
                                editingLibrary = library
                                editName = library.name
                                editLocation = library.location ?? ""
                                editDescription = library.description ?? ""
                                showLibraryEdit = true
                            } label: {
                                Label("重命名", systemImage: "pencil")
                            }

                            Button(role: .destructive) {
                                editingLibrary = library
                                showDeleteConfirm = true
                            } label: {
                                Label("删除书库", systemImage: "trash")
                            }
                        }
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }

    // MARK: - 总览

    private var overviewContent: some View {
        Group {
            if selectedLibraryId == nil {
                ContentUnavailableView {
                    Label("请选择书库", systemImage: "building.columns")
                } description: {
                    Text("选择一个书库或新建书库开始管理")
                } actions: {
                    Button("新建书库") {
                        showLibraryCreate = true
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else if isLoading && overview == nil {
                ProgressView("加载中...")
                    .frame(maxHeight: .infinity)
            } else {
                List {
                    // 概要信息
                    if let ov = overview {
                        Section {
                            LabeledContent("总书籍数", value: "\(ov.totalBooks) 本")
                            if ov.unlocated > 0 {
                                LabeledContent("未归位", value: "\(ov.unlocated) 本")
                                    .foregroundStyle(.orange)
                            }
                        }
                    }

                    // 房间区域
                    Section {
                        if let rooms = overview?.rooms, !rooms.isEmpty {
                            ForEach(rooms) { room in
                                NavigationLink {
                                    RoomDetailView(roomId: room.id, roomName: room.name, libraryId: selectedLibraryId ?? 0)
                                } label: {
                                    roomRow(room)
                                }
                            }
                        } else {
                            Text("暂无房间")
                                .foregroundStyle(.secondary)
                        }
                        if let libraryId = selectedLibraryId {
                            NavigationLink {
                                RoomCreateView(libraryId: libraryId) { _ in
                                    Task { await loadOverview() }
                                }
                            } label: {
                                Label("新建房间", systemImage: "plus.circle")
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                    } header: {
                        Label("房间", systemImage: "square.grid.2x2")
                    }

                    // 书架区域（带房间标注）
                    Section {
                        if let shelves = overview?.shelves, !shelves.isEmpty {
                            ForEach(shelves) { shelf in
                                if isShelfMultiSelect {
                                    Button {
                                        toggleShelfSelection(shelf.id)
                                    } label: {
                                        HStack(spacing: 12) {
                                            Image(systemName: selectedShelfIds.contains(shelf.id) ? "checkmark.circle.fill" : "circle")
                                                .foregroundStyle(selectedShelfIds.contains(shelf.id) ? Color.accentColor : .secondary)
                                                .font(.title3)
                                            shelfRow(shelf)
                                        }
                                    }
                                    .buttonStyle(.plain)
                                } else {
                                    NavigationLink {
                                        ShelfDetailView(shelfId: shelf.id, shelfName: shelf.name)
                                    } label: {
                                        shelfRow(shelf)
                                    }
                                }
                            }

                            // 多选操作按钮
                            if isShelfMultiSelect && !selectedShelfIds.isEmpty {
                                HStack {
                                    Button {
                                        let visibleIds = Set(shelves.map(\.id))
                                        if visibleIds.isSubset(of: selectedShelfIds) {
                                            selectedShelfIds.removeAll()
                                        } else {
                                            selectedShelfIds = visibleIds
                                        }
                                    } label: {
                                        let visibleIds = Set(shelves.map(\.id))
                                        Text(visibleIds.isSubset(of: selectedShelfIds) && !selectedShelfIds.isEmpty ? "取消全选" : "全选")
                                            .font(.subheadline)
                                    }
                                    Spacer()
                                    Button(role: .destructive) {
                                        showShelfBatchDeleteConfirm = true
                                    } label: {
                                        Label("删除(\(selectedShelfIds.count))", systemImage: "trash")
                                    }
                                }
                            }
                        } else {
                            Text("暂无书架")
                                .foregroundStyle(.secondary)
                        }

                        if !isShelfMultiSelect {
                            NavigationLink {
                                ShelfCreateView(libraryId: selectedLibraryId)
                            } label: {
                                Label("新建书架", systemImage: "plus.circle")
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                    } header: {
                        HStack {
                            Label("书架", systemImage: "books.vertical")
                            Spacer()
                            if let shelves = overview?.shelves, !shelves.isEmpty {
                                if isShelfMultiSelect {
                                    Button("取消") {
                                        isShelfMultiSelect = false
                                        selectedShelfIds.removeAll()
                                    }
                                    .font(.caption)
                                } else {
                                    Button("选择") {
                                        isShelfMultiSelect = true
                                    }
                                    .font(.caption)
                                }
                            }
                        }
                    }

                    // 箱子区域（带房间标注）
                    Section {
                        if let boxes = overview?.boxes, !boxes.isEmpty {
                            ForEach(boxes) { box in
                                if isBoxMultiSelect {
                                    Button {
                                        toggleBoxSelection(box.id)
                                    } label: {
                                        HStack(spacing: 12) {
                                            Image(systemName: selectedBoxIds.contains(box.id) ? "checkmark.circle.fill" : "circle")
                                                .foregroundStyle(selectedBoxIds.contains(box.id) ? Color.accentColor : .secondary)
                                                .font(.title3)
                                            boxRow(box)
                                        }
                                    }
                                    .buttonStyle(.plain)
                                } else {
                                    NavigationLink {
                                        BoxDetailView(box: Box(
                                            id: box.id,
                                            boxUid: box.boxUid,
                                            name: box.name,
                                            bookCount: box.bookCount
                                        ))
                                    } label: {
                                        boxRow(box)
                                    }
                                }
                            }

                            // 多选操作按钮
                            if isBoxMultiSelect && !selectedBoxIds.isEmpty {
                                HStack {
                                    Button {
                                        let visibleIds = Set(boxes.map(\.id))
                                        if visibleIds.isSubset(of: selectedBoxIds) {
                                            selectedBoxIds.removeAll()
                                        } else {
                                            selectedBoxIds = visibleIds
                                        }
                                    } label: {
                                        let visibleIds = Set(boxes.map(\.id))
                                        Text(visibleIds.isSubset(of: selectedBoxIds) && !selectedBoxIds.isEmpty ? "取消全选" : "全选")
                                            .font(.subheadline)
                                    }
                                    Spacer()
                                    Button(role: .destructive) {
                                        showBoxBatchDeleteConfirm = true
                                    } label: {
                                        Label("删除(\(selectedBoxIds.count))", systemImage: "trash")
                                    }
                                }
                            }
                        } else {
                            Text("暂无箱子")
                                .foregroundStyle(.secondary)
                        }
                    } header: {
                        HStack {
                            Label("箱子（归档）", systemImage: "shippingbox")
                            Spacer()
                            if let boxes = overview?.boxes, !boxes.isEmpty {
                                if isBoxMultiSelect {
                                    Button("取消") {
                                        isBoxMultiSelect = false
                                        selectedBoxIds.removeAll()
                                    }
                                    .font(.caption)
                                } else {
                                    Button("选择") {
                                        isBoxMultiSelect = true
                                    }
                                    .font(.caption)
                                }
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .task {
            await loadLibraries()
        }
        .refreshable {
            await loadLibraries()
            await loadOverview()
        }
        .confirmationDialog("批量删除书架", isPresented: $showShelfBatchDeleteConfirm, titleVisibility: .visible) {
            Button("删除", role: .destructive) {
                batchDeleteSelectedShelves()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("确定要删除选中的 \(selectedShelfIds.count) 个书架吗？书架上的书会转移到默认房间。")
        }
        .confirmationDialog("批量删除箱子", isPresented: $showBoxBatchDeleteConfirm, titleVisibility: .visible) {
            Button("删除", role: .destructive) {
                batchDeleteSelectedBoxes()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("确定要删除选中的 \(selectedBoxIds.count) 个箱子吗？")
        }
    }

    /// 查找房间名（用于在书架/箱子行显示其所在房间）
    private func roomNameFor(_ roomId: Int?) -> String? {
        guard let roomId, let rooms = overview?.rooms else { return nil }
        return rooms.first(where: { $0.id == roomId })?.name
    }

    private func roomRow(_ room: RoomSummary) -> some View {
        let shelfCount = overview?.shelves.filter { $0.roomId == room.id }.count ?? 0
        let boxCount = overview?.boxes.filter { $0.roomId == room.id }.count ?? 0
        return HStack(spacing: 12) {
            Image(systemName: "square.grid.2x2.fill")
                .font(.title2)
                .foregroundStyle(.purple)
                .frame(width: 44, height: 44)
                .background(Color.purple.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(room.name)
                        .font(.body.weight(.medium))
                    if room.isDefault {
                        Text("默认")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.2))
                            .clipShape(Capsule())
                    }
                }
                Text("\(shelfCount) 书架 · \(boxCount) 箱子")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }

    private func shelfRow(_ shelf: ShelfSummary) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "books.vertical.fill")
                .font(.title2)
                .foregroundStyle(.blue)
                .frame(width: 44, height: 44)
                .background(Color.blue.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 4) {
                Text(shelf.name)
                    .font(.body.weight(.medium))
                HStack(spacing: 6) {
                    if let roomName = roomNameFor(shelf.roomId) {
                        Text(roomName)
                            .font(.caption)
                            .foregroundStyle(.purple)
                    }
                    if let location = shelf.location {
                        Text(location)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            Text("\(shelf.bookCount) 本")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private func boxRow(_ box: BoxSummary) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "shippingbox.fill")
                .font(.title2)
                .foregroundStyle(.brown)
                .frame(width: 44, height: 44)
                .background(Color.brown.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 4) {
                Text(box.name)
                    .font(.body.weight(.medium))
                HStack(spacing: 6) {
                    if let roomName = roomNameFor(box.roomId) {
                        Text(roomName)
                            .font(.caption)
                            .foregroundStyle(.purple)
                    }
                    Text(box.boxUid)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Text("\(box.bookCount) 本")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    // MARK: - 全部书籍

    private var bookListView: some View {
        Group {
            if selectedLibraryId == nil {
                ContentUnavailableView("请先选择书库", systemImage: "building.columns")
            } else if isLoading && books.isEmpty {
                ProgressView("加载中...")
                    .frame(maxHeight: .infinity)
            } else if books.isEmpty {
                ContentUnavailableView("暂无书籍", systemImage: "book.closed")
            } else {
                ZStack(alignment: .bottom) {
                    List {
                        ForEach(books) { book in
                            if isBookMultiSelect {
                                Button {
                                    toggleBookSelection(book.id)
                                } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: selectedBookIds.contains(book.id) ? "checkmark.circle.fill" : "circle")
                                            .foregroundStyle(selectedBookIds.contains(book.id) ? Color.accentColor : .secondary)
                                            .font(.title3)
                                        BookRow(book: book)
                                    }
                                }
                                .buttonStyle(.plain)
                            } else {
                                NavigationLink(value: book) {
                                    BookRow(book: book)
                                }
                            }
                        }
                        .onDelete { offsets in
                            if !isBookMultiSelect {
                                deleteBooks(at: offsets)
                            }
                        }

                        if hasMore && !isBookMultiSelect {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                                .onAppear {
                                    Task { await loadMore() }
                                }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .navigationDestination(for: Book.self) { book in
                        LibraryBookDetailView(book: book)
                    }

                    if isBookMultiSelect && !selectedBookIds.isEmpty {
                        bookMultiSelectBar
                    }
                }
            }
        }
        .task {
            if books.isEmpty && selectedLibraryId != nil {
                await loadBooks()
            }
        }
        .refreshable {
            currentPage = 1
            await loadBooks()
        }
        .confirmationDialog("批量删除", isPresented: $showBookBatchDeleteConfirm, titleVisibility: .visible) {
            Button("还给图书馆", role: .destructive) {
                batchDeleteBooks(returnToLibrary: true)
            }
            Button("移入回收站", role: .destructive) {
                batchDeleteBooks(returnToLibrary: false)
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("已选择 \(selectedBookIds.count) 本书")
        }
        .sheet(isPresented: $showBookBatchMoveSheet) {
            BatchMoveBooksSheet(
                bookIds: Array(selectedBookIds),
                onCompleted: {
                    isBookMultiSelect = false
                    selectedBookIds.removeAll()
                    currentPage = 1
                    Task { await loadBooks() }
                }
            )
        }
    }

    /// 多选底部操作栏（书籍）
    private var bookMultiSelectBar: some View {
        HStack {
            Button {
                let visibleIds = Set(books.map(\.id))
                if visibleIds.isSubset(of: selectedBookIds) {
                    selectedBookIds.removeAll()
                } else {
                    selectedBookIds = visibleIds
                }
            } label: {
                Text(Set(books.map(\.id)).isSubset(of: selectedBookIds) && !selectedBookIds.isEmpty ? "取消全选" : "全选")
                    .font(.subheadline)
            }
            Spacer()
            if isBatchOperating {
                ProgressView()
                    .padding(.horizontal)
            } else {
                Button {
                    showBookBatchDeleteConfirm = true
                } label: {
                    Text("删除(\(selectedBookIds.count))")
                        .font(.subheadline.weight(.medium))
                }
                .buttonStyle(.bordered)
                .tint(.red)
                Button {
                    showBookBatchMoveSheet = true
                } label: {
                    Text("移动(\(selectedBookIds.count))")
                        .font(.subheadline.weight(.medium))
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
        .background(.ultraThinMaterial)
    }

    // MARK: - 数据加载

    private func loadLibraries() async {
        isLoadingLibraries = true
        do {
            libraries = try await NetworkService.shared.fetchLibraries()

            // 恢复上次选择的书库
            if selectedLibraryId == nil {
                if lastLibraryId > 0, libraries.contains(where: { $0.id == lastLibraryId }) {
                    selectedLibraryId = lastLibraryId
                } else if let first = libraries.first {
                    selectedLibraryId = first.id
                }
            }
        } catch {
            if (error as? URLError)?.code == .cancelled { return }
            errorMessage = error.chineseDescription
        }
        isLoadingLibraries = false

        // 加载选中书库的总览
        if selectedLibraryId != nil {
            await loadOverview()
        }
    }

    private func loadOverview() async {
        guard let libraryId = selectedLibraryId else { return }
        isLoading = true
        do {
            overview = try await NetworkService.shared.fetchLibraryOverview(libraryId: libraryId)
        } catch {
            if (error as? URLError)?.code == .cancelled { return }
            errorMessage = error.chineseDescription
        }
        isLoading = false
    }

    private func loadBooks() async {
        guard let libraryId = selectedLibraryId else { return }
        isLoading = true
        do {
            let response = try await NetworkService.shared.fetchBooks(
                page: currentPage,
                search: searchText.isEmpty ? nil : searchText,
                libraryId: libraryId
            )
            if currentPage == 1 {
                books = response.data
            } else {
                books.append(contentsOf: response.data)
            }
            totalBooks = response.pagination.total
            hasMore = books.count < totalBooks
        } catch {
            if (error as? URLError)?.code == .cancelled { return }
            errorMessage = error.chineseDescription
        }
        isLoading = false
    }

    private func loadMore() async {
        guard hasMore, !isLoading, !isPaginating else { return }
        isPaginating = true
        currentPage += 1
        await loadBooks()
        isPaginating = false
    }

    // MARK: - 书籍删除

    private func deleteBooks(at offsets: IndexSet) {
        let booksToDelete = offsets.map { books[$0] }
        Task {
            var failed: [Book] = []
            // 先从 UI 移除（乐观更新）
            books.remove(atOffsets: offsets)
            for book in booksToDelete {
                do {
                    _ = try await NetworkService.shared.deleteBook(id: book.id)
                } catch {
                    failed.append(book)
                    errorMessage = error.chineseDescription
                }
            }
            // 删除失败的书籍恢复到列表
            if !failed.isEmpty {
                books.append(contentsOf: failed)
            }
        }
    }

    // MARK: - 书库编辑 / 删除

    private func updateLibrary() {
        guard let library = editingLibrary else { return }
        isSaving = true
        Task {
            do {
                let request = LibraryRequest(
                    name: editName.trimmingCharacters(in: .whitespaces),
                    location: editLocation.isEmpty ? nil : editLocation,
                    description: editDescription.isEmpty ? nil : editDescription
                )
                let updated = try await NetworkService.shared.updateLibrary(id: library.id, request)
                // 更新本地列表
                if let idx = libraries.firstIndex(where: { $0.id == library.id }) {
                    libraries[idx] = updated
                }
                showLibraryEdit = false
            } catch {
                errorMessage = error.chineseDescription
            }
            isSaving = false
        }
    }

    private func deleteLibrary() {
        guard let library = editingLibrary else { return }
        Task {
            do {
                // 先执行删除请求，成功后再更新 UI
                _ = try await NetworkService.shared.deleteLibrary(id: library.id)
                libraries.removeAll { $0.id == library.id }
                if selectedLibraryId == library.id {
                    selectedLibraryId = libraries.first?.id
                }
            } catch {
                errorMessage = error.chineseDescription
            }
        }
    }

    // MARK: - 多选操作

    private func toggleBookSelection(_ id: Int) {
        if selectedBookIds.contains(id) {
            selectedBookIds.remove(id)
        } else {
            selectedBookIds.insert(id)
        }
    }

    private func toggleShelfSelection(_ id: Int) {
        if selectedShelfIds.contains(id) {
            selectedShelfIds.remove(id)
        } else {
            selectedShelfIds.insert(id)
        }
    }

    private func toggleBoxSelection(_ id: Int) {
        if selectedBoxIds.contains(id) {
            selectedBoxIds.remove(id)
        } else {
            selectedBoxIds.insert(id)
        }
    }

    private func batchDeleteBooks(returnToLibrary: Bool) {
        guard !selectedBookIds.isEmpty else { return }
        isBatchOperating = true
        Task {
            defer { isBatchOperating = false }
            do {
                let response = try await NetworkService.shared.batchDeleteBooks(
                    ids: Array(selectedBookIds),
                    returnToLibrary: returnToLibrary
                )
                let processedCount = response.processed ?? selectedBookIds.count
                // 从本地列表中移除已处理的书籍
                books.removeAll { selectedBookIds.contains($0.id) }
                totalBooks = max(0, totalBooks - processedCount)
                hasMore = books.count < totalBooks
                selectedBookIds.removeAll()
                isBookMultiSelect = false
                // 刷新总览数据
                await loadOverview()
            } catch {
                errorMessage = error.chineseDescription
            }
        }
    }

    private func batchDeleteSelectedShelves() {
        guard !selectedShelfIds.isEmpty else { return }
        Task {
            do {
                _ = try await NetworkService.shared.batchDeleteShelves(ids: Array(selectedShelfIds))
                selectedShelfIds.removeAll()
                isShelfMultiSelect = false
                await loadOverview()
            } catch {
                errorMessage = error.chineseDescription
            }
        }
    }

    private func batchDeleteSelectedBoxes() {
        guard !selectedBoxIds.isEmpty else { return }
        Task {
            do {
                _ = try await NetworkService.shared.batchDeleteBoxes(ids: Array(selectedBoxIds))
                selectedBoxIds.removeAll()
                isBoxMultiSelect = false
                await loadOverview()
            } catch {
                errorMessage = error.chineseDescription
            }
        }
    }
}

/// 书库中的书籍详情页（含位置信息、操作日志、编辑/删除/移动）
struct LibraryBookDetailView: View {
    let book: Book
    @Environment(\.dismiss) private var dismiss
    @State private var detail: Book?
    @State private var logs: [BookLog] = []
    @State private var isLoading = true
    @State private var showEdit = false
    @State private var showMove = false
    @State private var showDeleteConfirm = false
    @State private var errorMessage: String?

    // 编辑状态
    @State private var editTitle = ""
    @State private var editAuthor = ""
    @State private var editIsbn = ""
    @State private var editPublisher = ""
    @State private var editEdition = ""
    @State private var editAdaptation = ""
    @State private var editTranslator = ""
    @State private var editAuthorNationality = ""
    @State private var editPublisherPerson = ""
    @State private var editResponsibleEditor = ""
    @State private var editResponsiblePrinting = ""
    @State private var editCoverDesign = ""
    @State private var editPhone = ""
    @State private var editAddress = ""
    @State private var editPostalCode = ""
    @State private var editPrintingHouse = ""
    @State private var editImpression = ""
    @State private var editFormat = ""
    @State private var editPrintedSheets = ""
    @State private var editWordCount = ""
    @State private var editPrice = ""
    @State private var isSaving = false
    @State private var isConfirmingStatus = false

    // 拍照识别详情
    @State private var showDetailCamera = false
    @State private var detailImage: UIImage?
    @State private var isExtractingDetails = false
    @State private var extractResult: ExtractBookDetailsResponse?
    @State private var showCandidatePicker = false
    @State private var showExtractedPreview = false

    // 封面上传
    @State private var showCoverPicker = false
    @State private var showCoverCamera = false
    @State private var showCoverScanner = false
    @State private var coverImage: UIImage?
    @State private var isUploadingCover = false

    var body: some View {
        detailContent
            .task {
                do {
                    async let fetchDetail = NetworkService.shared.fetchBook(id: book.id)
                    async let fetchLogs = NetworkService.shared.fetchBookLogs(bookId: book.id)
                    detail = try await fetchDetail
                    let logsResponse = try await fetchLogs
                    logs = logsResponse.data
                } catch {
                    detail = book
                }
                isLoading = false
            }
            .sheet(isPresented: $showEdit) {
                NavigationStack {
                    Form {
                        Section("基本信息") {
                            TextField("书名", text: $editTitle)
                            TextField("作者", text: $editAuthor)
                            TextField("改编", text: $editAdaptation)
                            TextField("译者", text: $editTranslator)
                            TextField("作者国籍", text: $editAuthorNationality)
                            TextField("ISBN", text: $editIsbn)
                                .keyboardType(.numbersAndPunctuation)
                            TextField("出版社", text: $editPublisher)
                            TextField("版次（如 2023年5月第1版）", text: $editEdition)
                            TextField("出版人", text: $editPublisherPerson)
                            TextField("责任编辑", text: $editResponsibleEditor)
                            TextField("责任印制", text: $editResponsiblePrinting)
                            TextField("封面设计", text: $editCoverDesign)
                            TextField("定价", text: $editPrice)
                                .keyboardType(.decimalPad)
                        }

                        Section("出版信息") {
                            TextField("印刷厂", text: $editPrintingHouse)
                            TextField("印次（如 2023年5月第2次印刷）", text: $editImpression)
                            TextField("开本（如 32开）", text: $editFormat)
                            TextField("印张", text: $editPrintedSheets)
                            TextField("字数（如 200千字）", text: $editWordCount)
                        }

                        Section("联系方式") {
                            TextField("电话", text: $editPhone)
                                .keyboardType(.phonePad)
                            TextField("地址", text: $editAddress)
                            TextField("邮编", text: $editPostalCode)
                        }
                    }
                    .navigationTitle("编辑书籍")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("取消") { showEdit = false }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("保存") { updateBook() }
                                .disabled(editTitle.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                        }
                    }
                }
            }
            .sheet(isPresented: $showMove) {
                MoveBookSheet(bookId: book.id) {
                    Task {
                        do {
                            detail = try await NetworkService.shared.fetchBook(id: book.id)
                        } catch {
                            errorMessage = "刷新书籍详情失败: \(error.chineseDescription)"
                        }
                    }
                }
            }
            .sheet(isPresented: $showDetailCamera) {
                CameraView(capturedImage: $detailImage)
                    .ignoresSafeArea()
            }
            .onChange(of: detailImage) { _, newValue in
                guard let img = newValue else { return }
                extractDetailsFromImage(img)
            }
            .sheet(isPresented: $showCoverPicker) {
                PhotoPickerView(selectedImage: $coverImage)
                    .ignoresSafeArea()
            }
            .sheet(isPresented: $showCoverCamera) {
                CameraView(capturedImage: $coverImage)
                    .ignoresSafeArea()
            }
            .sheet(isPresented: $showCoverScanner) {
                DocumentScannerView(scannedImage: $coverImage)
                    .ignoresSafeArea()
            }
            .onChange(of: coverImage) { _, newValue in
                guard let img = newValue else { return }
                isUploadingCover = true
                Task {
                    do {
                        guard let data = img.jpegData(compressionQuality: 0.8) else {
                            errorMessage = "图片压缩失败"
                            isUploadingCover = false
                            return
                        }
                        detail = try await NetworkService.shared.uploadCover(bookId: book.id, imageData: data)
                    } catch {
                        errorMessage = error.chineseDescription
                    }
                    isUploadingCover = false
                }
            }
            .sheet(isPresented: $showExtractedPreview) {
                if let extracted = extractResult?.extracted {
                    NavigationStack {
                        ExtractedDetailsPreviewView(
                            extracted: extracted,
                            onApply: { applyExtractedToCurrentBook(extracted) }
                        )
                    }
                }
            }
            .overlay {
                if isExtractingDetails {
                    ZStack {
                        Color.black.opacity(0.4).ignoresSafeArea()
                        VStack(spacing: 12) {
                            ProgressView()
                            Text("AI 识别中…")
                                .font(.caption)
                                .foregroundStyle(.white)
                        }
                        .padding()
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                    }
                }
            }
            .confirmationDialog("删除「\(detail?.title ?? book.title)」", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
                Button("还给图书馆") {
                    deleteBook(returnToLibrary: true)
                }
                Button("移入回收站", role: .destructive) {
                    deleteBook(returnToLibrary: false)
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("「还给图书馆」仅取消这本书与当前位置的关联。\n「移入回收站」会将书软删除，30 天后自动清除。")
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

    @ViewBuilder
    private var detailContent: some View {
        if isLoading {
            ProgressView()
        } else if let detail {
            detailList(detail: detail)
        }
    }

    private func detailList(detail: Book) -> some View {
        List {
            detailListSections(detail: detail)
        }
        .listStyle(.insetGrouped)
        .navigationTitle(book.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    editTitle = detail.title
                    editAuthor = detail.author ?? ""
                    editIsbn = detail.isbn ?? ""
                    editPublisher = detail.publisher ?? ""
                    editEdition = detail.edition ?? ""
                    editAdaptation = detail.adaptation ?? ""
                    editTranslator = detail.translator ?? ""
                    editAuthorNationality = detail.authorNationality ?? ""
                    editPublisherPerson = detail.publisherPerson ?? ""
                    editResponsibleEditor = detail.responsibleEditor ?? ""
                    editResponsiblePrinting = detail.responsiblePrinting ?? ""
                    editCoverDesign = detail.coverDesign ?? ""
                    editPhone = detail.phone ?? ""
                    editAddress = detail.address ?? ""
                    editPostalCode = detail.postalCode ?? ""
                    editPrintingHouse = detail.printingHouse ?? ""
                    editImpression = detail.impression ?? ""
                    editFormat = detail.format ?? ""
                    editPrintedSheets = detail.printedSheets ?? ""
                    editWordCount = detail.wordCount ?? ""
                    editPrice = detail.price ?? ""
                    showEdit = true
                } label: {
                    Text("编辑")
                }
            }
        }
    }

    @ViewBuilder
    private func detailListSections(detail: Book) -> some View {
        // 封面
        Section {
            VStack(spacing: 12) {
                if let url = detail.coverDisplayUrl {
                    AsyncImage(url: url) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxHeight: 200)
                    } placeholder: {
                        ProgressView()
                    }
                    .frame(maxWidth: .infinity)
                }

                if isUploadingCover {
                    ProgressView("上传中…")
                } else {
                    HStack(spacing: 16) {
                        Menu {
                            Button("拍照", systemImage: "camera") {
                                showCoverCamera = true
                            }
                            Button("从相册选取", systemImage: "photo") {
                                showCoverPicker = true
                            }
                            Button("扫描文档", systemImage: "doc.text.viewfinder") {
                                showCoverScanner = true
                            }
                        } label: {
                            Label(detail.coverUrl == nil ? "添加封面" : "更换封面",
                                  systemImage: "photo.badge.plus")
                        }
                        .buttonStyle(.bordered)

                        if detail.coverUrl != nil {
                            Button(role: .destructive) {
                                deleteCover()
                            } label: {
                                Label("删除封面", systemImage: "trash")
                            }
                            .buttonStyle(.bordered)
                            .tint(.red)
                        }
                    }
                }
            }
        } header: {
            Text("封面")
        }

        Section {
            LabeledContent("书名", value: detail.title)
            if let v = detail.author, !v.isEmpty { LabeledContent("作者", value: v) }
            if let v = detail.adaptation, !v.isEmpty { LabeledContent("改编", value: v) }
            if let v = detail.translator, !v.isEmpty { LabeledContent("译者", value: v) }
            if let v = detail.authorNationality, !v.isEmpty { LabeledContent("作者国籍", value: v) }
            if let v = detail.isbn, !v.isEmpty { LabeledContent("ISBN", value: v) }
            if let v = detail.publisher, !v.isEmpty { LabeledContent("出版社", value: v) }
            if let v = detail.edition, !v.isEmpty { LabeledContent("版次", value: v) }
            if let v = detail.publisherPerson, !v.isEmpty { LabeledContent("出版人", value: v) }
            if let v = detail.responsibleEditor, !v.isEmpty { LabeledContent("责任编辑", value: v) }
            if let v = detail.responsiblePrinting, !v.isEmpty { LabeledContent("责任印制", value: v) }
            if let v = detail.coverDesign, !v.isEmpty { LabeledContent("封面设计", value: v) }
            if let v = detail.price, !v.isEmpty { LabeledContent("定价", value: "¥\(v)") }
        } header: {
            Text("基本信息")
        }

        Section {
            if let v = detail.printingHouse, !v.isEmpty { LabeledContent("印刷", value: v) }
            if let v = detail.impression, !v.isEmpty { LabeledContent("印次", value: v) }
            if let v = detail.format, !v.isEmpty { LabeledContent("开本", value: v) }
            if let v = detail.printedSheets, !v.isEmpty { LabeledContent("印张", value: v) }
            if let v = detail.wordCount, !v.isEmpty { LabeledContent("字数", value: v) }
        } header: {
            Text("出版信息")
        }

        Section {
            if let v = detail.phone, !v.isEmpty { LabeledContent("电话", value: v) }
            if let v = detail.address, !v.isEmpty { LabeledContent("地址", value: v) }
            if let v = detail.postalCode, !v.isEmpty { LabeledContent("邮编", value: v) }
        } header: {
            Text("联系方式")
        } footer: {
            Button {
                detailImage = nil
                showDetailCamera = true
            } label: {
                Label("拍照补充详情", systemImage: "camera.viewfinder")
            }
            .buttonStyle(.bordered)
            .padding(.top, 4)
        }

        Section("位置") {
            LabeledContent("当前位置", value: detail.locationDescription)
            Button {
                showMove = true
            } label: {
                Label("移动到...", systemImage: "arrow.right.circle")
            }
        }

        Section {
            if let status = detail.verifyStatus {
                HStack {
                    Text("校验状态")
                    Spacer()
                    if isConfirmingStatus {
                        ProgressView()
                    } else {
                        StatusBadge(status: status)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    if status == .uncertain && !isConfirmingStatus {
                        confirmVerifyStatus()
                    }
                }
                .onLongPressGesture(minimumDuration: 0.5) {
                    if status == .matched && !isConfirmingStatus {
                        revertVerifyStatus()
                    }
                }
            }
            if let source = detail.verifySource {
                LabeledContent("校验来源", value: source)
            }
        } header: {
            Text("校验信息")
        } footer: {
            switch detail.verifyStatus {
            case .uncertain:
                Text("点击「待确认」可改为已匹配")
            case .matched:
                Text("长按「已匹配」可改回待确认")
            default:
                EmptyView()
            }
        }

        if let ocrText = detail.rawOcrText, !ocrText.isEmpty {
            Section("原始识别文本") {
                Text(ocrText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }

        if !logs.isEmpty {
            Section("操作记录") {
                ForEach(logs) { log in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(log.actionLabel)
                                .font(.subheadline.weight(.medium))
                            Spacer()
                            Text(log.method)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        if let date = log.createdAt {
                            Text(date, style: .relative)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }

        // 删除按钮
        Section {
            Button(role: .destructive) {
                showDeleteConfirm = true
            } label: {
                HStack {
                    Spacer()
                    Label("删除书籍", systemImage: "trash")
                    Spacer()
                }
            }
        }
    }

    private func updateBook() {
        isSaving = true
        Task {
            do {
                let request = NewBookRequest(
                    title: editTitle.trimmingCharacters(in: .whitespaces),
                    author: editAuthor.isEmpty ? nil : editAuthor,
                    isbn: editIsbn.isEmpty ? nil : editIsbn,
                    publisher: editPublisher.isEmpty ? nil : editPublisher,
                    edition: editEdition.isEmpty ? nil : editEdition,
                    adaptation: editAdaptation.isEmpty ? nil : editAdaptation,
                    translator: editTranslator.isEmpty ? nil : editTranslator,
                    authorNationality: editAuthorNationality.isEmpty ? nil : editAuthorNationality,
                    publisherPerson: editPublisherPerson.isEmpty ? nil : editPublisherPerson,
                    responsibleEditor: editResponsibleEditor.isEmpty ? nil : editResponsibleEditor,
                    responsiblePrinting: editResponsiblePrinting.isEmpty ? nil : editResponsiblePrinting,
                    coverDesign: editCoverDesign.isEmpty ? nil : editCoverDesign,
                    phone: editPhone.isEmpty ? nil : editPhone,
                    address: editAddress.isEmpty ? nil : editAddress,
                    postalCode: editPostalCode.isEmpty ? nil : editPostalCode,
                    printingHouse: editPrintingHouse.isEmpty ? nil : editPrintingHouse,
                    impression: editImpression.isEmpty ? nil : editImpression,
                    format: editFormat.isEmpty ? nil : editFormat,
                    printedSheets: editPrintedSheets.isEmpty ? nil : editPrintedSheets,
                    wordCount: editWordCount.isEmpty ? nil : editWordCount,
                    price: editPrice.isEmpty ? nil : editPrice,
                    coverUrl: detail?.coverUrl,
                    categoryId: detail?.categoryId,
                    verifyStatus: detail?.verifyStatus,
                    verifySource: detail?.verifySource,
                    rawOcrText: detail?.rawOcrText
                )
                detail = try await NetworkService.shared.updateBook(id: book.id, request)
                showEdit = false
            } catch {
                errorMessage = error.chineseDescription
            }
            isSaving = false
        }
    }

    private func deleteBook(returnToLibrary: Bool = false) {
        Task {
            do {
                _ = try await NetworkService.shared.deleteBook(id: book.id, returnToLibrary: returnToLibrary)
                dismiss()
            } catch {
                errorMessage = error.chineseDescription
            }
        }
    }

    private func deleteCover() {
        Task {
            do {
                detail = try await NetworkService.shared.deleteCover(bookId: book.id)
            } catch {
                errorMessage = error.chineseDescription
            }
        }
    }

    private func confirmVerifyStatus() {
        setVerifyStatus(.matched)
    }

    private func revertVerifyStatus() {
        setVerifyStatus(.uncertain)
    }

    /// 从拍到的照片里抽取详情。注意：本页面已锁定到当前书（book.id），
    /// 不走库内匹配逻辑，直接用抽取结果覆盖当前书的字段。
    private func extractDetailsFromImage(_ image: UIImage) {
        guard let data = image.jpegData(compressionQuality: 0.8) else {
            errorMessage = "照片压缩失败"
            return
        }
        isExtractingDetails = true
        Task {
            defer { isExtractingDetails = false }
            do {
                let resp = try await NetworkService.shared.extractBookDetails(imageData: data)
                extractResult = resp
                showExtractedPreview = true
            } catch {
                errorMessage = error.chineseDescription
            }
        }
    }

    /// 把抽取结果合并到当前书：空字段不覆盖，有值则写入
    private func applyExtractedToCurrentBook(_ e: ExtractedBookDetails) {
        guard let current = detail else { return }
        isSaving = true
        Task {
            defer { isSaving = false }
            do {
                let priceStr: String? = {
                    if let p = e.price { return String(p) }
                    return current.price
                }()
                let orDefault = { (extracted: String?, current: String?) -> String? in
                    (extracted?.isEmpty == false) ? extracted : current
                }
                let request = NewBookRequest(
                    title: (e.title?.isEmpty == false && e.title != "无法辨认") ? e.title! : current.title,
                    author: (e.author?.isEmpty == false) ? e.author : current.author,
                    isbn: (e.isbn?.isEmpty == false) ? e.isbn : current.isbn,
                    publisher: (e.publisher?.isEmpty == false) ? e.publisher : current.publisher,
                    edition: orDefault(e.edition, current.edition),
                    adaptation: orDefault(e.adaptation, current.adaptation),
                    translator: orDefault(e.translator, current.translator),
                    authorNationality: orDefault(e.authorNationality, current.authorNationality),
                    publisherPerson: orDefault(e.publisherPerson, current.publisherPerson),
                    responsibleEditor: orDefault(e.responsibleEditor, current.responsibleEditor),
                    responsiblePrinting: orDefault(e.responsiblePrinting, current.responsiblePrinting),
                    coverDesign: orDefault(e.coverDesign, current.coverDesign),
                    phone: orDefault(e.phone, current.phone),
                    address: orDefault(e.address, current.address),
                    postalCode: orDefault(e.postalCode, current.postalCode),
                    printingHouse: orDefault(e.printingHouse, current.printingHouse),
                    impression: orDefault(e.impression, current.impression),
                    format: orDefault(e.format, current.format),
                    printedSheets: orDefault(e.printedSheets, current.printedSheets),
                    wordCount: orDefault(e.wordCount, current.wordCount),
                    price: priceStr,
                    coverUrl: current.coverUrl,
                    categoryId: current.categoryId,
                    verifyStatus: current.verifyStatus,
                    verifySource: current.verifySource,
                    rawOcrText: current.rawOcrText
                )
                detail = try await NetworkService.shared.updateBook(id: book.id, request)
                showExtractedPreview = false
            } catch {
                errorMessage = error.chineseDescription
            }
        }
    }

    private func setVerifyStatus(_ newStatus: VerifyStatus) {
        guard let current = detail else { return }
        isConfirmingStatus = true
        Task {
            do {
                let request = NewBookRequest(
                    title: current.title,
                    author: current.author,
                    isbn: current.isbn,
                    publisher: current.publisher,
                    edition: current.edition,
                    adaptation: current.adaptation,
                    translator: current.translator,
                    authorNationality: current.authorNationality,
                    publisherPerson: current.publisherPerson,
                    responsibleEditor: current.responsibleEditor,
                    responsiblePrinting: current.responsiblePrinting,
                    coverDesign: current.coverDesign,
                    phone: current.phone,
                    address: current.address,
                    postalCode: current.postalCode,
                    printingHouse: current.printingHouse,
                    impression: current.impression,
                    format: current.format,
                    printedSheets: current.printedSheets,
                    wordCount: current.wordCount,
                    price: current.price,
                    coverUrl: current.coverUrl,
                    categoryId: current.categoryId,
                    verifyStatus: newStatus,
                    verifySource: current.verifySource,
                    rawOcrText: current.rawOcrText
                )
                detail = try await NetworkService.shared.updateBook(id: book.id, request)
            } catch {
                errorMessage = error.chineseDescription
            }
            isConfirmingStatus = false
        }
    }
}

/// 抽取结果预览：展示 AI 从照片里读到的字段，用户可确认是否应用
struct ExtractedDetailsPreviewView: View {
    let extracted: ExtractedBookDetails
    let onApply: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Section {
                row("书名", extracted.title)
                row("作者", extracted.author)
                row("改编", extracted.adaptation)
                row("译者", extracted.translator)
                row("作者国籍", extracted.authorNationality)
                row("ISBN", extracted.isbn)
                row("出版社", extracted.publisher)
                row("版次", extracted.edition)
                row("出版人", extracted.publisherPerson)
                row("责任编辑", extracted.responsibleEditor)
                row("责任印制", extracted.responsiblePrinting)
                row("封面设计", extracted.coverDesign)
                row("电话", extracted.phone)
                row("地址", extracted.address)
                row("邮编", extracted.postalCode)
                row("印刷", extracted.printingHouse)
                row("印次", extracted.impression)
                row("开本", extracted.format)
                row("印张", extracted.printedSheets)
                row("字数", extracted.wordCount)
                if let p = extracted.price {
                    LabeledContent("定价") {
                        Text(String(format: "¥%.2f", p))
                    }
                }
            } header: {
                Text("识别结果")
            } footer: {
                Text("空字段不会覆盖已有数据；非空字段会写入当前书。")
            }
        }
        .navigationTitle("识别到的详情")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("取消") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("写入") { onApply() }
                    .disabled(!hasAnyValue)
            }
        }
    }

    @ViewBuilder
    private func row(_ label: String, _ value: String?) -> some View {
        if let v = value, !v.isEmpty {
            LabeledContent(label, value: v)
        }
    }

    private var hasAnyValue: Bool {
        [extracted.title, extracted.author, extracted.isbn, extracted.publisher, extracted.edition,
         extracted.adaptation, extracted.translator, extracted.authorNationality,
         extracted.publisherPerson, extracted.responsibleEditor, extracted.responsiblePrinting,
         extracted.coverDesign, extracted.phone, extracted.address, extracted.postalCode,
         extracted.printingHouse, extracted.impression, extracted.format,
         extracted.printedSheets, extracted.wordCount]
            .contains { ($0?.isEmpty == false) && $0 != "无法辨认" }
        || extracted.price != nil
    }
}

/// 批量移动书籍的 Sheet：选择目标书架或箱子
struct BatchMoveBooksSheet: View {
    let bookIds: [Int]
    let onCompleted: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var shelves: [Shelf] = []
    @State private var boxes: [Box] = []
    @State private var isLoading = true
    @State private var isMoving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("加载中...")
                        .frame(maxHeight: .infinity)
                } else {
                    List {
                        Section {
                            Button {
                                moveTo(.none, id: nil)
                            } label: {
                                Label("取消归位 (\(bookIds.count))", systemImage: "xmark.circle")
                                    .foregroundStyle(.orange)
                            }
                        }

                        if !shelves.isEmpty {
                            Section("书架") {
                                ForEach(shelves) { shelf in
                                    Button {
                                        moveTo(.shelf, id: shelf.id)
                                    } label: {
                                        HStack {
                                            Label(shelf.name, systemImage: "books.vertical.fill")
                                            Spacer()
                                            Text("\(shelf.bookCount) 本")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            }
                        }

                        if !boxes.isEmpty {
                            Section("箱子") {
                                ForEach(boxes) { box in
                                    Button {
                                        moveTo(.box, id: box.id)
                                    } label: {
                                        HStack {
                                            Label(box.name, systemImage: "shippingbox.fill")
                                            Spacer()
                                            Text("\(box.bookCount) 本")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("移动到")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
            .task { await loadLocations() }
            .overlay {
                if isMoving {
                    ProgressView("移动中...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(.ultraThinMaterial)
                }
            }
            .alert("移动失败", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("确定") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private func loadLocations() async {
        do {
            async let s = NetworkService.shared.fetchShelves()
            async let b = NetworkService.shared.fetchBoxes()
            shelves = try await s
            boxes = try await b
        } catch {
            errorMessage = error.chineseDescription
        }
        isLoading = false
    }

    private func moveTo(_ type: LocationType, id: Int?) {
        guard !bookIds.isEmpty else { return }
        isMoving = true
        Task {
            do {
                _ = try await NetworkService.shared.batchMoveBooks(
                    ids: bookIds,
                    toType: type,
                    toId: id
                )
                onCompleted()
                dismiss()
            } catch {
                errorMessage = error.chineseDescription
            }
            isMoving = false
        }
    }
}

#Preview {
    LibraryView()
}

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
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { showLogs = true } label: {
                            Label("操作日志", systemImage: "clock.arrow.circlepath")
                        }
                        Button { showCategories = true } label: {
                            Label("分类管理", systemImage: "tag")
                        }
                        Button { showScanHistory = true } label: {
                            Label("扫描历史", systemImage: "doc.text.magnifyingglass")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .navigationDestination(isPresented: $showLogs) { LogsView() }
            .navigationDestination(isPresented: $showCategories) { CategoryManageView() }
            .navigationDestination(isPresented: $showScanHistory) { ScanHistoryView() }
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

                    // 书架区域
                    Section {
                        if let shelves = overview?.shelves, !shelves.isEmpty {
                            ForEach(shelves) { shelf in
                                NavigationLink {
                                    ShelfDetailView(shelfId: shelf.id, shelfName: shelf.name)
                                } label: {
                                    shelfRow(shelf)
                                }
                            }
                        } else {
                            Text("暂无书架")
                                .foregroundStyle(.secondary)
                        }

                        NavigationLink {
                            ShelfCreateView(libraryId: selectedLibraryId)
                        } label: {
                            Label("新建书架", systemImage: "plus.circle")
                                .foregroundStyle(Color.accentColor)
                        }
                    } header: {
                        Label("书架", systemImage: "books.vertical")
                    }

                    // 箱子区域
                    Section {
                        if let boxes = overview?.boxes, !boxes.isEmpty {
                            ForEach(boxes) { box in
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
                        } else {
                            Text("暂无箱子")
                                .foregroundStyle(.secondary)
                        }
                    } header: {
                        Label("箱子（归档）", systemImage: "shippingbox")
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
                if let location = shelf.location {
                    Text(location)
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
                Text(box.boxUid)
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
                List {
                    ForEach(books) { book in
                        NavigationLink(value: book) {
                            BookRow(book: book)
                        }
                    }
                    .onDelete { offsets in
                        deleteBooks(at: offsets)
                    }

                    if hasMore {
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
            errorMessage = error.chineseDescription
        }
        isLoading = false
    }

    private func loadMore() async {
        guard hasMore, !isLoading else { return }
        currentPage += 1
        await loadBooks()
    }

    // MARK: - 书籍删除

    private func deleteBooks(at offsets: IndexSet) {
        let booksToDelete = offsets.map { books[$0] }
        books.remove(atOffsets: offsets)
        for book in booksToDelete {
            Task {
                do {
                    _ = try await NetworkService.shared.deleteBook(id: book.id)
                } catch {
                    errorMessage = error.chineseDescription
                }
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
                _ = try await NetworkService.shared.deleteLibrary(id: library.id)
                libraries.removeAll { $0.id == library.id }
                // 如果删除的是当前选中的书库，切换到第一个
                if selectedLibraryId == library.id {
                    selectedLibraryId = libraries.first?.id
                }
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
    @State private var isSaving = false

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
            } else if let detail {
                List {
                    // 封面
                    if let coverUrl = detail.coverUrl, let url = URL(string: coverUrl) {
                        Section {
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
                    }

                    Section("基本信息") {
                        LabeledContent("书名", value: detail.title)
                        if let author = detail.author {
                            LabeledContent("作者", value: author)
                        }
                        if let isbn = detail.isbn {
                            LabeledContent("ISBN", value: isbn)
                        }
                        if let publisher = detail.publisher {
                            LabeledContent("出版社", value: publisher)
                        }
                    }

                    Section("位置") {
                        LabeledContent("当前位置", value: detail.locationDescription)
                        Button {
                            showMove = true
                        } label: {
                            Label("移动到...", systemImage: "arrow.right.circle")
                        }
                    }

                    Section("校验信息") {
                        if let status = detail.verifyStatus {
                            HStack {
                                Text("校验状态")
                                Spacer()
                                StatusBadge(status: status)
                            }
                        }
                        if let source = detail.verifySource {
                            LabeledContent("校验来源", value: source)
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
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle(book.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    editTitle = detail?.title ?? book.title
                    editAuthor = detail?.author ?? book.author ?? ""
                    editIsbn = detail?.isbn ?? book.isbn ?? ""
                    editPublisher = detail?.publisher ?? book.publisher ?? ""
                    showEdit = true
                } label: {
                    Text("编辑")
                }
            }
        }
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
                    Section("书籍信息") {
                        TextField("书名", text: $editTitle)
                        TextField("作者", text: $editAuthor)
                        TextField("ISBN", text: $editIsbn)
                        TextField("出版社", text: $editPublisher)
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
                    detail = try? await NetworkService.shared.fetchBook(id: book.id)
                }
            }
        }
        .alert("确认删除", isPresented: $showDeleteConfirm) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) { deleteBook() }
        } message: {
            Text("确定要删除「\(detail?.title ?? book.title)」吗？此操作不可撤销。")
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

    private func updateBook() {
        isSaving = true
        Task {
            do {
                let request = NewBookRequest(
                    title: editTitle.trimmingCharacters(in: .whitespaces),
                    author: editAuthor.isEmpty ? nil : editAuthor,
                    isbn: editIsbn.isEmpty ? nil : editIsbn,
                    publisher: editPublisher.isEmpty ? nil : editPublisher,
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

    private func deleteBook() {
        Task {
            do {
                _ = try await NetworkService.shared.deleteBook(id: book.id)
                dismiss()
            } catch {
                errorMessage = error.chineseDescription
            }
        }
    }
}

#Preview {
    LibraryView()
}

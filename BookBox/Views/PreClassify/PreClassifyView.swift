import SwiftUI

/// 预分类保存的列表
struct PreClassifySession: Codable, Identifiable {
    var id = UUID()
    var name: String
    var books: [RecognizedBook]
    var createdAt: Date
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, name, books, createdAt, updatedAt
    }
}

/// 预分类模式 — 拍照识别书籍，AI 自动建议分类，支持本地保存多个列表
struct PreClassifyView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var capturedImage: UIImage?
    @State private var showCamera = false
    @State private var showPhotoPicker = false
    @State private var recognizedBooks: [RecognizedBook] = []
    @State private var recognitionTasks: [RecognitionTask] = []
    @State private var errorMessage: String?

    // 分类筛选
    @State private var selectedCategory: String?

    // 本地保存
    @State private var savedSessions: [PreClassifySession] = []
    @State private var currentSessionId: UUID?
    @State private var showSessionList = false
    @State private var showSaveAlert = false
    @State private var newSessionName = ""

    private static let sessionsFileName = "preClassifySessions.json"

    private static var sessionsFileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(sessionsFileName)
    }

    private var filteredBooks: [RecognizedBook] {
        guard let category = selectedCategory else { return recognizedBooks }
        return recognizedBooks.filter { $0.category == category }
    }

    /// 从已识别书籍中提取所有分类（保持首次出现顺序）
    private var allCategories: [String] {
        var seen = Set<String>()
        return recognizedBooks.compactMap { $0.category }.filter { seen.insert($0).inserted }
    }

    private var currentSessionName: String? {
        guard let id = currentSessionId else { return nil }
        return savedSessions.first { $0.id == id }?.name
    }

    var body: some View {
        VStack(spacing: 0) {
            if !recognitionTasks.isEmpty {
                recognitionQueueStrip
                Divider()
            }

            if recognizedBooks.isEmpty && recognitionTasks.isEmpty {
                emptyStateView
            } else if recognizedBooks.isEmpty {
                recognizingPlaceholder
            } else {
                if !allCategories.isEmpty {
                    categoryFilterBar
                }
                bookListView
            }
        }
        .navigationTitle("预分类")
        .toolbar { toolbarContent }
        .sheet(isPresented: $showCamera) {
            CameraView(capturedImage: $capturedImage)
                .ignoresSafeArea()
        }
        .sheet(isPresented: $showPhotoPicker) {
            PhotoPickerView(selectedImage: $capturedImage)
                .ignoresSafeArea()
        }
        .onChange(of: capturedImage) { _, newImage in
            if let image = newImage {
                enqueueRecognition(image)
                capturedImage = nil
            }
        }
        .sheet(isPresented: $showSessionList) {
            SessionListView(
                sessions: $savedSessions,
                currentSessionId: $currentSessionId,
                onLoad: { session in
                    loadSession(session)
                    showSessionList = false
                },
                onDelete: deleteSessions,
                onDismiss: { showSessionList = false }
            )
        }
        .alert("保存列表", isPresented: $showSaveAlert) {
            TextField("列表名称", text: $newSessionName)
            Button("保存") { saveAsNewSession(name: newSessionName) }
            Button("取消", role: .cancel) {}
        } message: {
            Text("为当前预分类列表命名")
        }
        .alert("识别失败", isPresented: .init(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("确定") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .onAppear { loadSessions() }
    }

    // MARK: - 工具栏

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button("关闭") { dismiss() }
        }
        ToolbarItem(placement: .topBarTrailing) {
            sessionMenu
        }
        ToolbarItem(placement: .topBarTrailing) {
            cameraMenu
        }
    }

    private var sessionMenu: some View {
        Menu {
            if currentSessionId != nil {
                Button("保存", systemImage: "square.and.arrow.down") {
                    autoSaveCurrentSession()
                }
                .disabled(recognizedBooks.isEmpty)
            } else {
                Button("保存当前列表", systemImage: "square.and.arrow.down") {
                    newSessionName = "列表 \(savedSessions.count + 1)"
                    showSaveAlert = true
                }
                .disabled(recognizedBooks.isEmpty)
            }

            Button("载入已保存列表", systemImage: "list.bullet") {
                showSessionList = true
            }
            .disabled(savedSessions.isEmpty)

            Divider()

            Button("新建空白列表", systemImage: "doc.badge.plus") {
                recognizedBooks = []
                currentSessionId = nil
                selectedCategory = nil
            }
        } label: {
            Image(systemName: "folder")
        }
    }

    private var cameraMenu: some View {
        Menu {
            Button("拍照", systemImage: "camera") {
                showCamera = true
            }
            Button("从相册选取", systemImage: "photo") {
                showPhotoPicker = true
            }
        } label: {
            Image(systemName: "plus.circle.fill")
                .font(.title3)
        }
    }

    // MARK: - 空状态

    private var emptyStateView: some View {
        ContentUnavailableView {
            Label("拍摄书籍", systemImage: "text.viewfinder")
        } description: {
            VStack(spacing: 8) {
                Text("拍照后 AI 自动识别书名并建议分类")
                if !savedSessions.isEmpty {
                    Button("载入已保存的列表") {
                        showSessionList = true
                    }
                    .font(.callout)
                }
            }
        } actions: {
            Button("开始拍照") { showCamera = true }
                .buttonStyle(.borderedProminent)
        }
    }

    // MARK: - 识别队列（顶部横向缩略图）

    private var recognitionQueueStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(recognitionTasks) { task in
                    recognitionThumbnail(task)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(.thinMaterial)
    }

    @ViewBuilder
    private func recognitionThumbnail(_ task: RecognitionTask) -> some View {
        ZStack {
            Image(uiImage: task.thumbnail)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            switch task.status {
            case .recognizing:
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.black.opacity(0.35))
                    .frame(width: 64, height: 64)
                ProgressView()
                    .tint(.white)
            case .done(let count):
                VStack {
                    Spacer()
                    Text("\(count) 本")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.green.opacity(0.9))
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                        .padding(4)
                }
                .frame(width: 64, height: 64)
            case .failed:
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.red.opacity(0.35))
                    .frame(width: 64, height: 64)
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.white)
                    .font(.title3)
            }
        }
        .overlay(alignment: .topTrailing) {
            if task.status != .recognizing {
                Button {
                    recognitionTasks.removeAll { $0.id == task.id }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.white, .black.opacity(0.6))
                }
                .offset(x: 6, y: -6)
            }
        }
    }

    /// 队列中有任务但还没有结果时显示的占位
    private var recognizingPlaceholder: some View {
        VStack(spacing: 8) {
            Spacer()
            Text("正在识别中，可继续拍照")
                .foregroundStyle(.secondary)
                .font(.subheadline)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 分类筛选栏

    private var categoryFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                CategoryChip(title: "全部", count: recognizedBooks.count, isSelected: selectedCategory == nil) {
                    selectedCategory = nil
                }
                ForEach(allCategories, id: \.self) { category in
                    CategoryChip(
                        title: category,
                        count: recognizedBooks.filter { $0.category == category }.count,
                        isSelected: selectedCategory == category
                    ) {
                        selectedCategory = selectedCategory == category ? nil : category
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .background(Color(.systemGroupedBackground))
    }

    // MARK: - 书籍列表

    private var bookListView: some View {
        List {
            sessionInfoSection
            booksSection
        }
        .listStyle(.insetGrouped)
    }

    @ViewBuilder
    private var sessionInfoSection: some View {
        if let name = currentSessionName {
            Section {
                HStack {
                    Image(systemName: "folder.fill")
                        .foregroundStyle(.secondary)
                    Text(name)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("自动保存")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    private var booksSection: some View {
        Section {
            ForEach(filteredBooks, id: \.id) { book in
                BookRecognitionRow(book: book)
            }
            .onDelete(perform: deleteBooks)
        } header: {
            if let cat = selectedCategory {
                Text("\(cat) — \(filteredBooks.count) 本")
            } else {
                Text("共 \(recognizedBooks.count) 本")
            }
        }
    }

    // MARK: - 识别队列

    /// 拍完一张就入队，后台并发识别，完成后追加到书籍列表
    private func enqueueRecognition(_ image: UIImage) {
        let thumb = image.preparingThumbnail(of: CGSize(width: 160, height: 160)) ?? image
        let task = RecognitionTask(thumbnail: thumb, status: .recognizing)
        recognitionTasks.append(task)
        let taskId = task.id

        Task { @MainActor in
            guard let compressed = compressImageForRecognition(image) else {
                updateTask(taskId, status: .failed)
                errorMessage = "图片压缩失败，请重试"
                return
            }
            do {
                let books = try await NetworkService.shared.recognizeBooks(imageData: compressed)
                if books.isEmpty {
                    updateTask(taskId, status: .failed)
                    errorMessage = "未识别到书籍，请调整角度或距离后重试"
                } else {
                    recognizedBooks.append(contentsOf: books)
                    autoSaveCurrentSession()
                    updateTask(taskId, status: .done(books.count))
                    Task.detached {
                        try? await NetworkService.shared.saveScanRecord(
                            mode: .preclassify,
                            extractedTitles: books.map(\.title)
                        )
                    }
                }
            } catch {
                updateTask(taskId, status: .failed)
                errorMessage = "AI 识别失败: \(error.chineseDescription)"
            }
        }
    }

    private func updateTask(_ id: UUID, status: RecognitionTask.Status) {
        guard let idx = recognitionTasks.firstIndex(where: { $0.id == id }) else { return }
        recognitionTasks[idx].status = status
    }

    private func deleteBooks(at offsets: IndexSet) {
        if selectedCategory != nil {
            let idsToDelete = Set(offsets.map { filteredBooks[$0].id })
            recognizedBooks.removeAll { idsToDelete.contains($0.id) }
        } else {
            recognizedBooks.remove(atOffsets: offsets)
        }
        autoSaveCurrentSession()
    }

    // MARK: - 本地保存

    private func loadSessions() {
        do {
            let data = try Data(contentsOf: Self.sessionsFileURL)
            savedSessions = try JSONDecoder().decode([PreClassifySession].self, from: data)
        } catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError {
            // 文件不存在是正常情况（首次启动）
        } catch {
            #if DEBUG
            print("[PreClassify] 加载会话失败: \(error)")
            #endif
        }
    }

    private func persistSessions() {
        do {
            let data = try JSONEncoder().encode(savedSessions)
            try data.write(to: Self.sessionsFileURL, options: .atomic)
        } catch {
            #if DEBUG
            print("[PreClassify] 保存会话失败: \(error)")
            #endif
        }
    }

    private func saveAsNewSession(name: String) {
        let session = PreClassifySession(
            id: UUID(),
            name: name.isEmpty ? "列表 \(savedSessions.count + 1)" : name,
            books: recognizedBooks,
            createdAt: Date(),
            updatedAt: Date()
        )
        savedSessions.append(session)
        currentSessionId = session.id
        persistSessions()
    }

    private func autoSaveCurrentSession() {
        guard let id = currentSessionId,
              let index = savedSessions.firstIndex(where: { $0.id == id }) else { return }
        savedSessions[index].books = recognizedBooks
        savedSessions[index].updatedAt = Date()
        persistSessions()
    }

    private func loadSession(_ session: PreClassifySession) {
        recognizedBooks = session.books
        currentSessionId = session.id
        selectedCategory = nil
    }

    private func deleteSessions(at offsets: IndexSet) {
        let idsToDelete = Set(offsets.map { savedSessions[$0].id })
        if let currentId = currentSessionId, idsToDelete.contains(currentId) {
            currentSessionId = nil
        }
        savedSessions.remove(atOffsets: offsets)
        persistSessions()
    }
}

// MARK: - 书籍识别结果行

private struct BookRecognitionRow: View {
    let book: RecognizedBook

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(confidenceColor)
                .frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 3) {
                Text(book.title)
                    .font(.body)
                subtitleRow
            }
            Spacer()
            Text(confidenceLabel)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    @ViewBuilder
    private var subtitleRow: some View {
        HStack(spacing: 8) {
            if let author = book.author {
                Text(author)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let category = book.category {
                Text(category)
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.12))
                    .foregroundStyle(Color.accentColor)
                    .clipShape(Capsule())
            }
        }
    }

    private var confidenceColor: Color {
        switch book.confidence {
        case .high: .green
        case .medium: .orange
        case .low: .red
        }
    }

    private var confidenceLabel: String {
        book.confidence.shortLabel
    }
}

// MARK: - 分类标签

private struct CategoryChip: View {
    let title: String
    let count: Int
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(title)
                Text("\(count)")
                    .font(.caption2)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(isSelected ? Color.white.opacity(0.3) : Color.secondary.opacity(0.2))
                    .clipShape(Capsule())
            }
            .font(.callout)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isSelected ? Color.accentColor : Color(.systemGray5))
            .foregroundStyle(isSelected ? .white : .primary)
            .clipShape(Capsule())
        }
    }
}

// MARK: - 已保存列表管理

private struct SessionListView: View {
    @Binding var sessions: [PreClassifySession]
    @Binding var currentSessionId: UUID?
    let onLoad: (PreClassifySession) -> Void
    let onDelete: (IndexSet) -> Void
    let onDismiss: () -> Void

    var body: some View {
        NavigationStack {
            List {
                ForEach(sessions, id: \.id) { session in
                    sessionRow(session)
                }
                .onDelete(perform: onDelete)
            }
            .navigationTitle("已保存的列表")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    EditButton()
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { onDismiss() }
                }
            }
            .overlay {
                if sessions.isEmpty {
                    ContentUnavailableView("暂无保存的列表", systemImage: "folder")
                }
            }
        }
    }

    private func sessionRow(_ session: PreClassifySession) -> some View {
        Button {
            onLoad(session)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(session.name)
                        .font(.body)
                        .foregroundStyle(.primary)
                    Text("\(session.books.count) 本书 · \(session.updatedAt.formatted(.dateTime.month().day().hour().minute()))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if session.id == currentSessionId {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Color.accentColor)
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        PreClassifyView()
    }
}

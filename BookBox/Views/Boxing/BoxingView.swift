import SwiftUI

/// 装箱模式主界面 — 先选箱子 → 拍照（后台并发识别，队列显示缩略图）→ 入箱
struct BoxingView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedBox: Box?

    var body: some View {
        Group {
            if let box = selectedBox {
                BoxingSessionView(
                    box: box,
                    onSwitchBox: { selectedBox = nil },
                    onClose: { dismiss() }
                )
            } else {
                BoxPickerView(
                    onPicked: { selectedBox = $0 },
                    onCancel: { dismiss() }
                )
            }
        }
    }
}

// MARK: - 箱子选择页

/// 装箱前选箱子：列出所有箱子供选择，或新建一个
struct BoxPickerView: View {
    let onPicked: (Box) -> Void
    let onCancel: () -> Void

    @State private var boxes: [Box] = []
    @State private var isLoading = true
    @State private var showBoxCreate = false
    @State private var searchText = ""
    @State private var errorMessage: String?

    private var filteredBoxes: [Box] {
        let q = searchText.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return boxes }
        return boxes.filter { $0.name.localizedCaseInsensitiveContains(q) }
    }

    var body: some View {
        Group {
            if isLoading {
                ProgressView("加载箱子...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if boxes.isEmpty {
                ContentUnavailableView {
                    Label("还没有箱子", systemImage: "shippingbox")
                } description: {
                    Text("新建一个箱子后再开始装箱")
                } actions: {
                    Button("新建箱子") { showBoxCreate = true }
                        .buttonStyle(.borderedProminent)
                }
            } else {
                List {
                    Section {
                        Button {
                            showBoxCreate = true
                        } label: {
                            Label("新建箱子", systemImage: "plus.circle.fill")
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                    Section("选择已有箱子") {
                        ForEach(filteredBoxes) { box in
                            Button {
                                onPicked(box)
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "shippingbox")
                                        .foregroundStyle(Color.accentColor)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(box.name)
                                            .font(.body)
                                            .foregroundStyle(.primary)
                                        Text("\(box.bookCount) 本")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .searchable(text: $searchText, prompt: "搜索箱子")
            }
        }
        .navigationTitle("装箱")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("关闭") { onCancel() }
            }
        }
        .sheet(isPresented: $showBoxCreate) {
            NavigationStack {
                BoxCreateView { newBox in
                    onPicked(newBox)
                }
            }
        }
        .task { await load() }
        .alert("错误", isPresented: .init(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("确定") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func load() async {
        isLoading = true
        do {
            boxes = try await NetworkService.shared.fetchBoxes()
        } catch {
            errorMessage = "加载箱子列表失败: \(error.chineseDescription)"
        }
        isLoading = false
    }
}

// MARK: - 装箱会话

/// 已选箱子后的装箱界面：拍照 → 后台队列识别 → 结果归集入库
struct BoxingSessionView: View {
    let box: Box
    let onSwitchBox: () -> Void
    let onClose: () -> Void

    @State private var showCamera = false
    @State private var showPhotoPicker = false
    @State private var capturedImage: UIImage?
    @State private var scanResults: [ScanResultItem] = []
    @State private var recognitionTasks: [RecognitionTask] = []
    @State private var showPreClassifyImport = false
    @State private var showSwitchConfirm = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            if !recognitionTasks.isEmpty {
                recognitionQueueStrip
                Divider()
            }

            if scanResults.isEmpty && recognitionTasks.isEmpty {
                emptyStateView
            } else if scanResults.isEmpty {
                recognizingPlaceholder
            } else {
                ScanResultView(
                    results: $scanResults,
                    locationType: .box,
                    locationId: box.id
                )
            }
        }
        .navigationTitle("装箱：\(box.name)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("关闭") { onClose() }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("拍照", systemImage: "camera") { showCamera = true }
                    Button("从相册选取", systemImage: "photo") { showPhotoPicker = true }
                    Button("从预分类导入", systemImage: "list.clipboard") { showPreClassifyImport = true }
                    Divider()
                    Button("切换箱子", systemImage: "arrow.triangle.2.circlepath") {
                        if scanResults.isEmpty && !recognitionTasks.contains(where: { $0.status == .recognizing }) {
                            onSwitchBox()
                        } else {
                            showSwitchConfirm = true
                        }
                    }
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                }
            }
        }
        .sheet(isPresented: $showCamera) {
            CameraView(capturedImage: $capturedImage)
                .ignoresSafeArea()
        }
        .sheet(isPresented: $showPhotoPicker) {
            PhotoPickerView(selectedImage: $capturedImage)
                .ignoresSafeArea()
        }
        .sheet(isPresented: $showPreClassifyImport) {
            PreClassifyImportView { importedBooks in
                for book in importedBooks {
                    scanResults.append(ScanResultItem(
                        title: book.title,
                        author: book.author,
                        confidence: book.confidence,
                        isVerifying: false
                    ))
                }
            }
        }
        .onChange(of: capturedImage) { _, newImage in
            if let image = newImage {
                enqueueRecognition(image)
                capturedImage = nil
            }
        }
        .confirmationDialog("切换箱子", isPresented: $showSwitchConfirm, titleVisibility: .visible) {
            Button("放弃并切换", role: .destructive) {
                recognitionTasks.removeAll()
                scanResults.removeAll()
                onSwitchBox()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("当前有未入库的识别结果或仍在识别的照片，切换会全部丢弃")
        }
        .alert("错误", isPresented: .init(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("确定") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: - 子视图

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

    private var emptyStateView: some View {
        ContentUnavailableView {
            Label("拍摄书籍", systemImage: "camera.viewfinder")
        } description: {
            Text("拍照后 AI 在后台识别，可连续拍摄多张")
        } actions: {
            Button("开始拍照") { showCamera = true }
                .buttonStyle(.borderedProminent)
        }
    }

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

    // MARK: - 识别队列

    private func enqueueRecognition(_ image: UIImage) {
        let thumb = image.preparingThumbnail(of: CGSize(width: 160, height: 160)) ?? image
        let task = RecognitionTask(thumbnail: thumb, status: .recognizing)
        recognitionTasks.append(task)
        let taskId = task.id
        let capturedBoxId = box.id

        Task { @MainActor in
            guard let compressed = compressImageForRecognition(image) else {
                updateTask(taskId, status: .failed)
                errorMessage = "图片压缩失败，请重试"
                return
            }
            do {
                let recognized = try await NetworkService.shared.recognizeBooks(imageData: compressed)
                // 期间用户可能已切换箱子，此时当前 Session 不再有效
                guard capturedBoxId == box.id else { return }

                if recognized.isEmpty {
                    updateTask(taskId, status: .failed)
                    errorMessage = "未识别到书籍，请调整角度或距离"
                } else {
                    for item in recognized {
                        scanResults.append(ScanResultItem(
                            title: item.title,
                            author: item.author,
                            confidence: item.confidence,
                            isVerifying: false
                        ))
                    }
                    updateTask(taskId, status: .done(recognized.count))
                    Task {
                        try? await NetworkService.shared.saveScanRecord(
                            mode: .boxing,
                            boxId: capturedBoxId,
                            extractedTitles: recognized.map(\.title)
                        )
                    }
                }
            } catch {
                guard capturedBoxId == box.id else { return }
                updateTask(taskId, status: .failed)
                errorMessage = "AI 识别失败: \(error.chineseDescription)"
            }
        }
    }

    private func updateTask(_ id: UUID, status: RecognitionTask.Status) {
        guard let idx = recognitionTasks.firstIndex(where: { $0.id == id }) else { return }
        recognitionTasks[idx].status = status
    }
}

// MARK: - 识别任务

/// 后台识别任务 — 每一张照片对应一条，支持并发
struct RecognitionTask: Identifiable {
    let id = UUID()
    let thumbnail: UIImage
    var status: Status

    enum Status: Equatable {
        case recognizing
        case done(Int)
        case failed
    }
}

/// 扫描结果条目
struct ScanResultItem: Identifiable {
    let id = UUID()
    var title: String
    var author: String?
    var confidence: ConfidenceLevel?
    var verifyResult: VerifyResult?
    var isVerifying: Bool
    var isSelected = true
    var rawOcrText: String?

    /// 最终使用的书名
    var finalTitle: String {
        verifyResult?.title ?? title
    }

    /// 最终作者
    var finalAuthor: String? {
        verifyResult?.author ?? author
    }

    /// 校验状态（MiMo 置信度 → 三色）
    var status: VerifyStatus {
        if let result = verifyResult {
            return result.status
        }
        switch confidence {
        case .high: return .matched
        case .medium: return .uncertain
        default: return .notFound
        }
    }
}

// MARK: - 从预分类导入

/// 从预分类列表中选择书籍导入到装箱模式
struct PreClassifyImportView: View {
    @Environment(\.dismiss) private var dismiss
    let onImport: ([RecognizedBook]) -> Void

    @State private var sessions: [PreClassifySession] = []
    @State private var selectedSession: PreClassifySession?
    @State private var selectedBookIds: Set<UUID> = []

    var body: some View {
        NavigationStack {
            Group {
                if let session = selectedSession {
                    bookSelectionList(session)
                } else {
                    sessionList
                }
            }
            .navigationTitle(selectedSession != nil ? "选择书籍" : "选择预分类列表")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if selectedSession != nil {
                        Button("返回") {
                            selectedSession = nil
                            selectedBookIds = []
                        }
                    } else {
                        Button("取消") { dismiss() }
                    }
                }
                if selectedSession != nil {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("导入 (\(selectedBookIds.count))") {
                            importSelected()
                        }
                        .disabled(selectedBookIds.isEmpty)
                    }
                }
            }
            .onAppear { loadSessions() }
        }
    }

    // MARK: - 列表选择

    private var sessionList: some View {
        List {
            if sessions.isEmpty {
                ContentUnavailableView("暂无预分类列表", systemImage: "list.clipboard")
            } else {
                ForEach(sessions) { session in
                    Button {
                        selectedSession = session
                        selectedBookIds = Set(session.books.map(\.id))
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
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }
        }
    }

    // MARK: - 书籍选择

    private func bookSelectionList(_ session: PreClassifySession) -> some View {
        VStack(spacing: 0) {
            List {
                Section {
                    ForEach(session.books) { book in
                        Button {
                            toggleBook(book.id)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: selectedBookIds.contains(book.id) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selectedBookIds.contains(book.id) ? Color.accentColor : .secondary)

                                Circle()
                                    .fill(confidenceColor(book.confidence))
                                    .frame(width: 10, height: 10)

                                VStack(alignment: .leading, spacing: 3) {
                                    Text(book.title)
                                        .font(.body)
                                        .foregroundStyle(.primary)
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
                                Spacer()
                            }
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("\(session.name) · \(session.books.count) 本")
                }
            }
            .listStyle(.insetGrouped)

            // 底部全选栏
            HStack {
                Button {
                    if selectedBookIds.count == session.books.count {
                        selectedBookIds.removeAll()
                    } else {
                        selectedBookIds = Set(session.books.map(\.id))
                    }
                } label: {
                    Text(selectedBookIds.count == session.books.count ? "取消全选" : "全选")
                        .font(.subheadline)
                }
                Spacer()
            }
            .padding()
            .background(.ultraThinMaterial)
        }
    }

    // MARK: - 辅助方法

    private func toggleBook(_ id: UUID) {
        if selectedBookIds.contains(id) {
            selectedBookIds.remove(id)
        } else {
            selectedBookIds.insert(id)
        }
    }

    private func confidenceColor(_ confidence: ConfidenceLevel) -> Color {
        switch confidence {
        case .high: .green
        case .medium: .orange
        case .low: .red
        }
    }

    private func loadSessions() {
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("preClassifySessions.json")
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([PreClassifySession].self, from: data) else { return }
        sessions = decoded
    }

    private func importSelected() {
        guard let session = selectedSession else { return }
        let books = session.books.filter { selectedBookIds.contains($0.id) }
        onImport(books)
        dismiss()
    }
}

#Preview {
    NavigationStack {
        BoxingView()
    }
}

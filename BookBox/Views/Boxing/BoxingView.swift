import SwiftUI

/// 装箱模式主界面 — 选择箱子 → 拍照 → 识别校验 → 入箱
struct BoxingView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var boxes: [Box] = []
    @State private var selectedBox: Box?
    @State private var showBoxCreate = false
    @State private var showCamera = false
    @State private var showPhotoPicker = false
    @State private var capturedImage: UIImage?
    @State private var scanResults: [ScanResultItem] = []
    @State private var isProcessing = false
    @State private var isLoadingBoxes = true
    @State private var errorMessage: String?
    @State private var showPreClassifyImport = false

    var body: some View {
        VStack(spacing: 0) {
            // 箱子选择区域
            boxSelector

            Divider()

            // 扫描结果区域
            if scanResults.isEmpty && !isProcessing {
                emptyStateView
            } else if isProcessing {
                processingView
            } else {
                ScanResultView(
                    results: $scanResults,
                    locationType: .box,
                    locationId: selectedBox?.id
                )
            }
        }
        .navigationTitle("装箱")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("关闭") {
                    dismiss()
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("拍照", systemImage: "camera") {
                        showCamera = true
                    }
                    Button("从相册选取", systemImage: "photo") {
                        showPhotoPicker = true
                    }
                    Button("从预分类导入", systemImage: "list.clipboard") {
                        showPreClassifyImport = true
                    }
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                }
                .disabled(selectedBox == nil)
            }
        }
        .sheet(isPresented: $showBoxCreate) {
            NavigationStack {
                BoxCreateView { newBox in
                    boxes.append(newBox)
                    selectedBox = newBox
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
                    let item = ScanResultItem(
                        title: book.title,
                        author: book.author,
                        confidence: book.confidence,
                        isVerifying: false
                    )
                    scanResults.append(item)
                }
            }
        }
        .onChange(of: capturedImage) { _, newImage in
            if let image = newImage {
                processImage(image)
            }
        }
        .task {
            await loadBoxes()
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

    private var boxSelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                // 新建箱子按钮
                Button {
                    showBoxCreate = true
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.title3)
                        Text("新建")
                            .font(.caption)
                    }
                    .frame(width: 70, height: 60)
                    .background(.quaternary)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }

                if isLoadingBoxes {
                    ProgressView()
                        .frame(width: 70, height: 60)
                } else {
                    ForEach(boxes) { box in
                        Button {
                            selectedBox = box
                        } label: {
                            VStack(spacing: 4) {
                                Image(systemName: "shippingbox")
                                    .font(.title3)
                                Text(box.name)
                                    .font(.caption)
                                    .lineLimit(1)
                            }
                            .frame(width: 70, height: 60)
                            .background(selectedBox?.id == box.id ? AnyShapeStyle(Color.accentColor.opacity(0.2)) : AnyShapeStyle(.quaternary))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(selectedBox?.id == box.id ? Color.accentColor : .clear, lineWidth: 2)
                            )
                        }
                        .tint(.primary)
                    }
                }
            }
            .padding()
        }
    }

    private var emptyStateView: some View {
        ContentUnavailableView {
            Label(
                selectedBox == nil ? "请先选择箱子" : "拍摄书籍",
                systemImage: selectedBox == nil ? "shippingbox" : "camera.viewfinder"
            )
        } description: {
            Text(selectedBox == nil
                 ? "选择一个箱子或新建箱子后开始装箱"
                 : "拍照后 AI 自动识别书名")
        } actions: {
            if selectedBox == nil {
                Button("新建箱子") {
                    showBoxCreate = true
                }
                .buttonStyle(.borderedProminent)
            } else {
                Button("开始拍照") {
                    showCamera = true
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private var processingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)
            Text("AI 正在识别书籍...")
                .foregroundStyle(.secondary)
        }
        .frame(maxHeight: .infinity)
    }

    private func loadBoxes() async {
        isLoadingBoxes = true
        do {
            boxes = try await NetworkService.shared.fetchBoxes()
        } catch {
            errorMessage = "加载箱子列表失败: \(error.chineseDescription)"
        }
        isLoadingBoxes = false
    }

    private func processImage(_ image: UIImage) {
        guard selectedBox != nil else { return }
        isProcessing = true

        Task {
            defer {
                isProcessing = false
                capturedImage = nil
            }
            do {
                guard let compressed = compressImageForRecognition(image) else {
                    errorMessage = "图片压缩失败，请重试"
                    return
                }
                let recognized = try await NetworkService.shared.recognizeBooks(imageData: compressed)
                if recognized.isEmpty {
                    errorMessage = "未识别到书籍，请调整角度或距离后重试"
                } else {
                    for book in recognized {
                        let item = ScanResultItem(
                            title: book.title,
                            author: book.author,
                            confidence: book.confidence,
                            isVerifying: false
                        )
                        scanResults.append(item)
                    }
                    // 保存扫描记录
                    Task {
                        try? await NetworkService.shared.saveScanRecord(
                            mode: .boxing,
                            boxId: selectedBox?.id,
                            extractedTitles: recognized.map(\.title)
                        )
                    }
                }
            } catch {
                errorMessage = "AI 识别失败: \(error.chineseDescription)"
            }
        }
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

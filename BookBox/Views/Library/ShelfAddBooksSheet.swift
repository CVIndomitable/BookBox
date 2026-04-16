import SwiftUI

/// 书架加书面板 — 两种方式：拍照识别新书入架，或从当前书库的未归位书籍中挑选搬入
struct ShelfAddBooksSheet: View {
    let shelfId: Int
    let shelfName: String
    let libraryId: Int?
    let onCompleted: () -> Void

    @Environment(\.dismiss) private var dismiss

    enum Mode: String, CaseIterable, Identifiable {
        case scan = "拍照识别"
        case pick = "挑选已有书"
        var id: String { rawValue }
    }

    @State private var mode: Mode = .scan

    // 拍照识别状态
    @State private var showCamera = false
    @State private var showPhotoPicker = false
    @State private var capturedImage: UIImage?
    @State private var scanResults: [ScanResultItem] = []
    @State private var isProcessing = false

    // 挑选已有书状态
    @State private var availableBooks: [Book] = []
    @State private var selectedIds = Set<Int>()
    @State private var searchText = ""
    @State private var isLoadingBooks = false
    @State private var isAdding = false

    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("", selection: $mode) {
                    ForEach(Mode.allCases) { m in
                        Text(m.rawValue).tag(m)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.vertical, 8)

                Divider()

                Group {
                    switch mode {
                    case .scan: scanContent
                    case .pick: pickContent
                    }
                }
            }
            .navigationTitle(shelfName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("关闭") { dismiss() }
                }
                if mode == .scan {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button("拍照", systemImage: "camera") { showCamera = true }
                            Button("从相册选取", systemImage: "photo") { showPhotoPicker = true }
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.title3)
                        }
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
            .onChange(of: capturedImage) { _, newImage in
                if let image = newImage {
                    processImage(image)
                }
            }
            .task(id: mode) {
                if mode == .pick, availableBooks.isEmpty {
                    await loadAvailableBooks()
                }
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
    }

    // MARK: - 拍照识别

    @ViewBuilder
    private var scanContent: some View {
        if isProcessing {
            VStack(spacing: 16) {
                ProgressView().scaleEffect(1.5)
                Text("AI 正在识别书籍...")
                    .foregroundStyle(.secondary)
            }
            .frame(maxHeight: .infinity)
        } else if scanResults.isEmpty {
            ContentUnavailableView {
                Label("拍摄书籍", systemImage: "camera.viewfinder")
            } description: {
                Text("拍照后 AI 自动识别书名，确认后录入本书架")
            } actions: {
                Button("开始拍照") { showCamera = true }
                    .buttonStyle(.borderedProminent)
            }
        } else {
            ScanResultView(
                results: $scanResults,
                locationType: .shelf,
                locationId: shelfId,
                onSaved: {
                    onCompleted()
                    dismiss()
                }
            )
        }
    }

    private func processImage(_ image: UIImage) {
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
                }
            } catch {
                errorMessage = "AI 识别失败: \(error.chineseDescription)"
            }
        }
    }

    // MARK: - 挑选已有书

    private var filteredBooks: [Book] {
        let trimmed = searchText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return availableBooks }
        return availableBooks.filter { book in
            book.title.localizedCaseInsensitiveContains(trimmed)
                || (book.author?.localizedCaseInsensitiveContains(trimmed) ?? false)
        }
    }

    @ViewBuilder
    private var pickContent: some View {
        VStack(spacing: 0) {
            if isLoadingBooks {
                ProgressView("加载中...")
                    .frame(maxHeight: .infinity)
            } else if availableBooks.isEmpty {
                ContentUnavailableView {
                    Label("暂无可添加的书籍", systemImage: "book.closed")
                } description: {
                    Text("本书库没有未归位的书籍。可先通过装箱或拍照识别录入，再搬入书架。")
                }
            } else {
                List {
                    Section {
                        ForEach(filteredBooks) { book in
                            Button {
                                toggleBook(book.id)
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: selectedIds.contains(book.id) ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(selectedIds.contains(book.id) ? Color.accentColor : .secondary)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(book.title).font(.body).foregroundStyle(.primary)
                                        if let author = book.author, !author.isEmpty {
                                            Text(author).font(.caption).foregroundStyle(.secondary)
                                        }
                                    }
                                    Spacer()
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    } header: {
                        Text("未归位 · 共 \(availableBooks.count) 本")
                    }
                }
                .listStyle(.insetGrouped)
                .searchable(text: $searchText, prompt: "搜索书名或作者")

                HStack {
                    Button {
                        let visibleIds = Set(filteredBooks.map(\.id))
                        if visibleIds.isSubset(of: selectedIds) {
                            selectedIds.subtract(visibleIds)
                        } else {
                            selectedIds.formUnion(visibleIds)
                        }
                    } label: {
                        let visibleIds = Set(filteredBooks.map(\.id))
                        Text(visibleIds.isSubset(of: selectedIds) && !visibleIds.isEmpty ? "取消全选" : "全选")
                            .font(.subheadline)
                    }
                    Spacer()
                    Button {
                        addSelectedBooks()
                    } label: {
                        HStack {
                            if isAdding { ProgressView().tint(.white) }
                            Text("加入书架 (\(selectedIds.count))")
                        }
                        .font(.headline)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(selectedIds.isEmpty ? Color.gray : Color.accentColor)
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                    }
                    .disabled(selectedIds.isEmpty || isAdding)
                }
                .padding()
                .background(.ultraThinMaterial)
            }
        }
    }

    private func toggleBook(_ id: Int) {
        if selectedIds.contains(id) {
            selectedIds.remove(id)
        } else {
            selectedIds.insert(id)
        }
    }

    private func loadAvailableBooks() async {
        isLoadingBooks = true
        do {
            let response = try await NetworkService.shared.fetchBooks(
                page: 1,
                pageSize: 500,
                locationType: .none,
                libraryId: libraryId
            )
            availableBooks = response.data
        } catch {
            errorMessage = "加载未归位书籍失败: \(error.chineseDescription)"
        }
        isLoadingBooks = false
    }

    private func addSelectedBooks() {
        guard !selectedIds.isEmpty else { return }
        isAdding = true
        Task {
            defer { isAdding = false }
            do {
                _ = try await NetworkService.shared.addBooksToShelf(
                    shelfId: shelfId,
                    bookIds: Array(selectedIds)
                )
                onCompleted()
                dismiss()
            } catch {
                errorMessage = "加入书架失败: \(error.chineseDescription)"
            }
        }
    }
}

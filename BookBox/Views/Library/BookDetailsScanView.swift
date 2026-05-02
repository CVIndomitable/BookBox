import SwiftUI

/// 库级"拍照补详情"流程：
/// 用户拍一张书的照片 → 服务器抽取字段 + 尝试匹配库内已存在的书 →
///   - 唯一命中：显示匹配到的书，确认后把抽取详情写进这本书
///   - 多个候选：列出候选让用户选一本
///   - 无候选：弹书库列表让用户手动选一本
///
/// 写入规则：抽取结果中空字段不覆盖已有值，非空字段覆盖。
struct BookDetailsScanView: View {
    let libraryId: Int?
    var onComplete: ((Book) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var image: UIImage?
    @State private var showCamera = false
    @State private var isExtracting = false
    @State private var isSaving = false
    @State private var extractResult: ExtractBookDetailsResponse?
    @State private var selectedCandidate: Book?
    @State private var showBookPicker = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            if let image {
                Section("照片") {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 180)
                        .frame(maxWidth: .infinity)
                }
            } else {
                Section {
                    Button {
                        showCamera = true
                    } label: {
                        Label("拍照识别", systemImage: "camera")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                } footer: {
                    Text("拍封面、书脊、版权页或价签都可以。AI 会尽量读出书名、ISBN、出版社、出版时间、定价。")
                }
            }

            if isExtracting {
                Section {
                    HStack { ProgressView(); Text("AI 识别中…") }
                }
            }

            if let ex = extractResult?.extracted {
                Section("识别到的详情") {
                    row("书名", ex.title)
                    row("作者", ex.author)
                    row("ISBN", ex.isbn)
                    row("出版社", ex.publisher)
                    row("出版时间", ex.publishDate)
                    if let p = ex.price {
                        LabeledContent("定价") {
                            Text(String(format: "¥%.2f", p))
                        }
                    }
                }
            }

            if let match = extractResult?.match {
                Section {
                    bookCell(match, highlighted: true)
                    Button {
                        applyToBook(match)
                    } label: {
                        Label("写入这本书", systemImage: "checkmark.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isSaving)
                } header: {
                    Text("自动匹配到 1 本书（\(reasonLabel(extractResult?.matchReason))）")
                } footer: {
                    Text("如果不是这本，点击下方「换一本」从全部书籍里重新选")
                }

                Section {
                    Button {
                        showBookPicker = true
                    } label: {
                        Label("不是这本？换一本", systemImage: "arrow.triangle.2.circlepath")
                    }
                }
            } else if let candidates = extractResult?.candidates, !candidates.isEmpty {
                Section {
                    ForEach(candidates) { b in
                        Button {
                            applyToBook(b)
                        } label: {
                            bookCell(b, highlighted: selectedCandidate?.id == b.id)
                        }
                        .disabled(isSaving)
                    }
                } header: {
                    Text("疑似的 \(candidates.count) 本，选一本写入")
                }

                Section {
                    Button {
                        showBookPicker = true
                    } label: {
                        Label("都不是？从全部书籍里挑一本", systemImage: "books.vertical")
                    }
                }
            } else if extractResult != nil && !isExtracting {
                Section {
                    Button {
                        showBookPicker = true
                    } label: {
                        Label("从书库里挑这是哪本书", systemImage: "books.vertical")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                } footer: {
                    Text("AI 没能在库内匹配到对应的书，请手动选一本把这些详情写进去。")
                }
            }

            if image != nil {
                Section {
                    Button("重新拍一张") {
                        image = nil
                        extractResult = nil
                        showCamera = true
                    }
                }
            }
        }
        .navigationTitle("拍照补详情")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("关闭") { dismiss() }
            }
        }
        .sheet(isPresented: $showCamera) {
            CameraView(capturedImage: $image)
                .ignoresSafeArea()
        }
        .sheet(isPresented: $showBookPicker) {
            NavigationStack {
                BookPickerView(libraryId: libraryId) { picked in
                    applyToBook(picked)
                }
            }
        }
        .onChange(of: image) { _, newValue in
            if let img = newValue { extractFrom(img) }
        }
        .overlay {
            if isSaving {
                ZStack {
                    Color.black.opacity(0.3).ignoresSafeArea()
                    ProgressView("写入中…")
                        .padding()
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
        .alert("出错了", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("确定") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func reasonLabel(_ r: String?) -> String {
        switch r {
        case "isbn": "ISBN 精确匹配"
        case "title+author": "书名+作者匹配"
        case "title": "书名匹配"
        default: "匹配"
        }
    }

    @ViewBuilder
    private func row(_ label: String, _ value: String?) -> some View {
        if let v = value, !v.isEmpty {
            LabeledContent(label, value: v)
        }
    }

    @ViewBuilder
    private func bookCell(_ b: Book, highlighted: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(b.title).font(.body.weight(.medium))
            if let author = b.author, !author.isEmpty {
                Text(author).font(.caption).foregroundStyle(.secondary)
            }
            if let isbn = b.isbn, !isbn.isEmpty {
                Text("ISBN: \(isbn)").font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }

    private func extractFrom(_ image: UIImage) {
        guard let data = image.jpegData(compressionQuality: 0.8) else {
            errorMessage = "照片压缩失败"
            return
        }
        isExtracting = true
        extractResult = nil
        Task {
            defer { isExtracting = false }
            do {
                extractResult = try await NetworkService.shared.extractBookDetails(
                    imageData: data,
                    libraryId: libraryId
                )
            } catch {
                errorMessage = error.chineseDescription
            }
        }
    }

    private func applyToBook(_ b: Book) {
        guard let e = extractResult?.extracted else { return }
        selectedCandidate = b
        isSaving = true
        Task {
            defer { isSaving = false }
            do {
                // 先抓这本书的完整字段，再把抽取结果合并上去。
                // 空字段不覆盖已有值；price 转字符串（后端会正则解析）。
                let current = try await NetworkService.shared.fetchBook(id: b.id)
                let priceStr: String? = {
                    if let p = e.price { return String(p) }
                    return current.price
                }()
                let request = NewBookRequest(
                    title: (e.title?.isEmpty == false && e.title != "无法辨认") ? e.title! : current.title,
                    author: (e.author?.isEmpty == false) ? e.author : current.author,
                    isbn: (e.isbn?.isEmpty == false) ? e.isbn : current.isbn,
                    publisher: (e.publisher?.isEmpty == false) ? e.publisher : current.publisher,
                    publishDate: (e.publishDate?.isEmpty == false) ? e.publishDate : current.publishDate,
                    price: priceStr,
                    coverUrl: current.coverUrl,
                    categoryId: current.categoryId,
                    verifyStatus: current.verifyStatus,
                    verifySource: current.verifySource,
                    rawOcrText: current.rawOcrText
                )
                let updated = try await NetworkService.shared.updateBook(id: b.id, request)
                onComplete?(updated)
                dismiss()
            } catch {
                errorMessage = error.chineseDescription
            }
        }
    }
}

/// 从书库挑一本书的选择器（搜索 + 分页列表）
/// 用在：AI 没能匹配到时让用户手动指定这是哪本书
struct BookPickerView: View {
    let libraryId: Int?
    var onPick: (Book) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var books: [Book] = []
    @State private var searchText = ""
    @State private var isLoading = false
    @State private var currentPage = 1
    @State private var hasMore = true
    @State private var errorMessage: String?

    var body: some View {
        List {
            ForEach(books) { b in
                Button {
                    onPick(b)
                    dismiss()
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(b.title).font(.body)
                            .foregroundStyle(.primary)
                        HStack(spacing: 8) {
                            if let author = b.author, !author.isEmpty {
                                Text(author).font(.caption).foregroundStyle(.secondary)
                            }
                            if let isbn = b.isbn, !isbn.isEmpty {
                                Text(isbn).font(.caption2).foregroundStyle(.tertiary)
                            }
                        }
                    }
                }
            }
            if hasMore && !books.isEmpty {
                HStack {
                    Spacer()
                    if isLoading {
                        ProgressView()
                    } else {
                        Button("加载更多") {
                            Task { await loadMore() }
                        }
                    }
                    Spacer()
                }
            }
            if books.isEmpty && !isLoading {
                Text("没有匹配的书")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            }
        }
        .searchable(text: $searchText, prompt: "搜索书名或作者")
        .onChange(of: searchText) { _, _ in
            Task { await reload() }
        }
        .navigationTitle("选择书籍")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("取消") { dismiss() }
            }
        }
        .task {
            if books.isEmpty { await reload() }
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

    private func reload() async {
        currentPage = 1
        hasMore = true
        books = []
        await loadMore()
    }

    private func loadMore() async {
        if isLoading || !hasMore { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let resp = try await NetworkService.shared.fetchBooks(
                page: currentPage,
                pageSize: 30,
                search: searchText.isEmpty ? nil : searchText,
                libraryId: libraryId
            )
            books.append(contentsOf: resp.data)
            hasMore = currentPage < resp.pagination.totalPages
            currentPage += 1
        } catch {
            errorMessage = error.chineseDescription
        }
    }
}

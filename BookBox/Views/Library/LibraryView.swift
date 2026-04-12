import SwiftUI

/// 书库总览 — 按箱子或分类浏览所有书籍
struct LibraryView: View {
    @State private var books: [Book] = []
    @State private var searchText = ""
    @State private var isLoading = true
    @State private var currentPage = 1
    @State private var totalBooks = 0
    @State private var hasMore = true
    @State private var errorMessage: String?
    @State private var viewMode: ViewMode = .books

    enum ViewMode: String, CaseIterable {
        case books = "全部书籍"
        case boxes = "按箱子"
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 视图模式切换
                Picker("查看方式", selection: $viewMode) {
                    ForEach(ViewMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .padding()

                switch viewMode {
                case .books:
                    bookListView
                case .boxes:
                    BoxListView()
                }
            }
            .navigationTitle("书库")
            .searchable(text: $searchText, prompt: "搜索书名或作者")
            .onChange(of: searchText) { _, _ in
                currentPage = 1
                books = []
                Task { await loadBooks() }
            }
        }
    }

    private var bookListView: some View {
        Group {
            if isLoading && books.isEmpty {
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
            if books.isEmpty {
                await loadBooks()
            }
        }
        .refreshable {
            currentPage = 1
            await loadBooks()
        }
    }

    private func loadBooks() async {
        isLoading = true
        do {
            let response = try await NetworkService.shared.fetchBooks(
                page: currentPage,
                search: searchText.isEmpty ? nil : searchText
            )
            if currentPage == 1 {
                books = response.items
            } else {
                books.append(contentsOf: response.items)
            }
            totalBooks = response.total
            hasMore = books.count < totalBooks
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func loadMore() async {
        guard hasMore, !isLoading else { return }
        currentPage += 1
        await loadBooks()
    }
}

/// 书库中的书籍详情页（只读 + 编辑）
struct LibraryBookDetailView: View {
    let book: Book
    @State private var detail: Book?
    @State private var isLoading = true

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
            } else if let detail {
                Form {
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
                        Section("OCR 原始文本") {
                            Text(ocrText)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle(book.title)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            do {
                detail = try await NetworkService.shared.fetchBook(id: book.id)
            } catch {
                detail = book
            }
            isLoading = false
        }
    }
}

#Preview {
    LibraryView()
}

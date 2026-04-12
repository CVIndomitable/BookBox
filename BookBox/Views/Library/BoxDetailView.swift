import SwiftUI

/// 箱子详情 — 展示箱内所有书籍
struct BoxDetailView: View {
    let box: Box
    @State private var detail: Box?
    @State private var isLoading = true
    @State private var errorMessage: String?

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
                                BookRow(book: book)
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
        .navigationTitle(box.name)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadDetail()
        }
        .refreshable {
            await loadDetail()
        }
    }

    private func loadDetail() async {
        isLoading = true
        do {
            detail = try await NetworkService.shared.fetchBox(id: box.id)
        } catch {
            errorMessage = error.localizedDescription
            detail = box
        }
        isLoading = false
    }
}

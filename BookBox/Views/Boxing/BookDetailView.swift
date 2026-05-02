import SwiftUI

/// 书籍详情/编辑视图 — 可手动修正识别结果
struct BookDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let scanItem: ScanResultItem
    var onSave: ((ScanResultItem) -> Void)?

    @State private var title: String
    @State private var author: String
    @State private var isbn: String
    @State private var publisher: String
    @State private var isVerifying = false
    @State private var verifyResult: VerifyResult?
    @State private var errorMessage: String?

    init(scanItem: ScanResultItem, onSave: ((ScanResultItem) -> Void)? = nil) {
        self.scanItem = scanItem
        self.onSave = onSave
        _title = State(initialValue: scanItem.finalTitle)
        _author = State(initialValue: scanItem.finalAuthor ?? "")
        _isbn = State(initialValue: scanItem.verifyResult?.isbn ?? "")
        _publisher = State(initialValue: "")
    }

    var body: some View {
        Form {
            Section("书籍信息") {
                TextField("书名", text: $title)
                TextField("作者", text: $author)
                TextField("ISBN", text: $isbn)
                    .keyboardType(.numberPad)
                TextField("出版社", text: $publisher)
            }

            if let rawText = scanItem.rawOcrText {
                Section("原始识别文本") {
                    Text(rawText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("校验状态") {
                HStack {
                    StatusBadge(status: verifyResult?.status ?? scanItem.status)
                    Spacer()
                    if let source = verifyResult?.source ?? scanItem.verifyResult?.source {
                        Text("来源: \(source)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if let confidence = scanItem.confidence {
                        Text("AI 置信度: \(confidence)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Button {
                    reVerify()
                } label: {
                    HStack {
                        if isVerifying {
                            ProgressView()
                        }
                        Text("重新校验")
                    }
                }
                .disabled(title.isEmpty || isVerifying)
            }
        }
        .navigationTitle("编辑书籍")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("取消") {
                    dismiss()
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") {
                    save()
                }
                .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .alert("校验失败", isPresented: .init(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("确定") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func reVerify() {
        isVerifying = true
        Task {
            do {
                let result = try await NetworkService.shared.verifyBook(
                    title: title,
                    region: .mainland
                )
                verifyResult = result
                if let resultAuthor = result.author, !resultAuthor.isEmpty {
                    author = resultAuthor
                }
                if let resultIsbn = result.isbn, !resultIsbn.isEmpty {
                    isbn = resultIsbn
                }
            } catch {
                errorMessage = error.chineseDescription
            }
            isVerifying = false
        }
    }

    private func save() {
        var updated = scanItem
        let finalResult = VerifyResult(
            status: verifyResult?.status ?? (title != scanItem.title ? .manual : scanItem.status),
            title: title,
            author: author.isEmpty ? nil : author,
            isbn: isbn.isEmpty ? nil : isbn,
            coverUrl: verifyResult?.coverUrl ?? scanItem.verifyResult?.coverUrl,
            source: verifyResult?.source ?? (title != scanItem.title ? "manual" : scanItem.verifyResult?.source)
        )
        updated.verifyResult = finalResult
        onSave?(updated)
        dismiss()
    }
}

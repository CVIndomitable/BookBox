import SwiftUI

/// 扫描结果列表 — 展示三色标识，支持编辑和批量入库
struct ScanResultView: View {
    @Binding var results: [ScanResultItem]
    let locationType: LocationType
    let locationId: Int?
    @State private var editingItem: ScanResultItem?
    @State private var isSaving = false
    @State private var showSaveSuccess = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            // 结果列表
            List {
                Section {
                    ForEach(Array(results.enumerated()), id: \.element.id) { index, item in
                        resultRow(item: item, index: index)
                    }
                } header: {
                    HStack {
                        Text("识别结果")
                        Spacer()
                        statusSummary
                    }
                }
            }
            .listStyle(.insetGrouped)

            // 底部操作栏
            bottomBar
        }
        .sheet(item: $editingItem) { item in
            NavigationStack {
                BookDetailView(scanItem: item) { updated in
                    if let index = results.firstIndex(where: { $0.id == updated.id }) {
                        results[index] = updated
                    }
                }
            }
        }
        .alert("保存成功", isPresented: $showSaveSuccess) {
            Button("确定") {
                results.removeAll()
            }
        } message: {
            Text("已将 \(selectedCount) 本书录入\(locationType == .shelf ? "书架" : "箱子")")
        }
        .alert("保存失败", isPresented: .init(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("确定") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func resultRow(item: ScanResultItem, index: Int) -> some View {
        HStack(spacing: 12) {
            // 选中状态
            Button {
                results[index].isSelected.toggle()
            } label: {
                Image(systemName: item.isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(item.isSelected ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.plain)

            // 状态指示灯
            if item.isVerifying {
                ProgressView()
                    .frame(width: 12, height: 12)
            } else {
                Circle()
                    .fill(statusColor(for: item.status))
                    .frame(width: 12, height: 12)
            }

            // 书名和作者
            VStack(alignment: .leading, spacing: 2) {
                Text(item.finalTitle)
                    .font(.body)
                    .lineLimit(2)

                HStack(spacing: 8) {
                    if let author = item.finalAuthor {
                        Text(author)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let confidence = item.confidence {
                        Text(confidenceLabel(confidence))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    if let source = item.verifyResult?.source {
                        Text("via \(source)")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            Spacer()

            // 编辑按钮
            Button {
                editingItem = item
            } label: {
                Image(systemName: "pencil.circle")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 2)
    }

    private var statusSummary: some View {
        HStack(spacing: 8) {
            let matched = results.filter { $0.status == .matched }.count
            let uncertain = results.filter { $0.status == .uncertain }.count
            let notFound = results.filter { $0.status == .notFound }.count

            if matched > 0 {
                Label("\(matched)", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
            }
            if uncertain > 0 {
                Label("\(uncertain)", systemImage: "questionmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            if notFound > 0 {
                Label("\(notFound)", systemImage: "xmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    private var selectedCount: Int {
        results.filter(\.isSelected).count
    }

    private var bottomBar: some View {
        HStack {
            Button {
                let allSelected = results.allSatisfy(\.isSelected)
                for i in results.indices {
                    results[i].isSelected = !allSelected
                }
            } label: {
                Text(results.allSatisfy(\.isSelected) ? "取消全选" : "全选")
                    .font(.subheadline)
            }

            Spacer()

            Button {
                saveSelectedBooks()
            } label: {
                HStack {
                    if isSaving {
                        ProgressView()
                            .tint(.white)
                    }
                    Text("入库 (\(selectedCount))")
                }
                .font(.headline)
                .padding(.horizontal, 24)
                .padding(.vertical, 10)
                .background(selectedCount > 0 ? Color.accentColor : .gray)
                .foregroundStyle(.white)
                .clipShape(Capsule())
            }
            .disabled(selectedCount == 0 || isSaving)
        }
        .padding()
        .background(.ultraThinMaterial)
    }

    private func statusColor(for status: VerifyStatus) -> Color {
        switch status {
        case .matched: .green
        case .uncertain: .orange
        case .notFound, .manual: .red
        }
    }

    private func confidenceLabel(_ confidence: ConfidenceLevel) -> String {
        confidence.label
    }

    private func saveSelectedBooks() {
        guard locationId != nil else {
            errorMessage = "请先选择\(locationType == .shelf ? "书架" : "箱子")"
            return
        }
        isSaving = true

        Task {
            do {
                let books = results
                    .filter(\.isSelected)
                    .map { item in
                        NewBookRequest(
                            title: item.finalTitle,
                            author: item.finalAuthor,
                            isbn: item.verifyResult?.isbn,
                            publisher: nil,
                            coverUrl: item.verifyResult?.coverUrl,
                            categoryId: nil,
                            verifyStatus: item.verifyResult?.status ?? item.status,
                            verifySource: item.verifyResult?.source ?? (item.confidence != nil ? "mimo" : nil),
                            rawOcrText: item.rawOcrText ?? item.title
                        )
                    }
                let batch = BatchBooksRequest(
                    books: books,
                    locationType: locationType,
                    locationId: locationId,
                    libraryId: nil
                )
                _ = try await NetworkService.shared.createBooks(batch: batch)
                showSaveSuccess = true
            } catch {
                errorMessage = error.chineseDescription
            }
            isSaving = false
        }
    }
}

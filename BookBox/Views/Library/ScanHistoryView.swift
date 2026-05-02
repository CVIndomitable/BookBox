import SwiftUI

/// 扫描历史 — 展示所有扫描记录
struct ScanHistoryView: View {
    @State private var records: [ScanRecord] = []
    @State private var isLoading = true
    @State private var currentPage = 1
    @State private var hasMore = true
    @State private var selectedMode: ScanMode?
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            Picker("模式", selection: $selectedMode) {
                Text("全部").tag(nil as ScanMode?)
                Text("预分类").tag(ScanMode.preclassify as ScanMode?)
                Text("装箱").tag(ScanMode.boxing as ScanMode?)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 8)
            .onChange(of: selectedMode) { _, _ in
                currentPage = 1
                records = []
                Task { await loadRecords() }
            }

            if isLoading && records.isEmpty {
                ProgressView("加载中...")
                    .frame(maxHeight: .infinity)
            } else if records.isEmpty {
                ContentUnavailableView("暂无扫描记录", systemImage: "doc.text.magnifyingglass")
            } else {
                List {
                    ForEach(records) { record in
                        recordRow(record)
                    }
                    if hasMore {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .onAppear { Task { await loadMore() } }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("扫描历史")
        .task { await loadRecords() }
        .refreshable {
            currentPage = 1
            await loadRecords()
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

    private func recordRow(_ record: ScanRecord) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: record.mode == .preclassify ? "rectangle.split.3x1" : "shippingbox")
                    .foregroundStyle(record.mode == .preclassify ? .blue : .orange)
                Text(record.mode == .preclassify ? "预分类" : "装箱")
                    .font(.subheadline.weight(.medium))
                Spacer()
                if let date = record.createdAt {
                    Text(date, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            if let titles = record.extractedTitles, !titles.isEmpty {
                Text(titles.joined(separator: "、"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - 数据加载

    private func loadRecords() async {
        isLoading = true
        do {
            let response = try await NetworkService.shared.fetchScanRecords(
                page: currentPage,
                mode: selectedMode
            )
            if currentPage == 1 {
                records = response.data
            } else {
                records.append(contentsOf: response.data)
            }
            hasMore = records.count < response.pagination.total
        } catch {
            errorMessage = error.chineseDescription
        }
        isLoading = false
    }

    private func loadMore() async {
        guard hasMore, !isLoading else { return }
        currentPage += 1
        await loadRecords()
    }
}

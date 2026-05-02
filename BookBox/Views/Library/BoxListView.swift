import SwiftUI

/// 箱子列表视图
struct BoxListView: View {
    @State private var boxes: [Box] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    // 多选模式
    @State private var selectedBoxIds = Set<Int>()
    @State private var isMultiSelect = false
    @State private var isDeleting = false

    var body: some View {
        Group {
            if isLoading {
                ProgressView("加载中...")
                    .frame(maxHeight: .infinity)
            } else if boxes.isEmpty {
                ContentUnavailableView("暂无箱子", systemImage: "shippingbox")
            } else {
                ZStack(alignment: .bottom) {
                    List {
                        ForEach(boxes) { box in
                            if isMultiSelect {
                                Button {
                                    toggleBox(box.id)
                                } label: {
                                    boxRow(box, isSelected: selectedBoxIds.contains(box.id))
                                }
                                .buttonStyle(.plain)
                            } else {
                                NavigationLink(value: box) {
                                    boxRow(box)
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .navigationDestination(for: Box.self) { box in
                        BoxDetailView(box: box)
                    }

                    // 多选底部操作栏
                    if isMultiSelect {
                        multiSelectBottomBar
                    }
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if !boxes.isEmpty {
                    Button(isMultiSelect ? "完成" : "选择") {
                        isMultiSelect.toggle()
                        if !isMultiSelect {
                            selectedBoxIds.removeAll()
                        }
                    }
                }
            }
        }
        .task {
            await loadBoxes()
        }
        .refreshable {
            await loadBoxes()
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

    // MARK: - 多选底部栏

    private var multiSelectBottomBar: some View {
        HStack {
            Button {
                let allIds = Set(boxes.map(\.id))
                if allIds.isSubset(of: selectedBoxIds) {
                    selectedBoxIds.removeAll()
                } else {
                    selectedBoxIds = allIds
                }
            } label: {
                let allIds = Set(boxes.map(\.id))
                Text(allIds.isSubset(of: selectedBoxIds) ? "取消全选" : "全选")
                    .font(.subheadline)
            }
            Spacer()
            Button(role: .destructive) {
                deleteSelectedBoxes()
            } label: {
                HStack(spacing: 4) {
                    if isDeleting {
                        ProgressView().tint(.white)
                    }
                    Text("删除(\(selectedBoxIds.count))")
                }
                .font(.headline)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(selectedBoxIds.isEmpty ? Color.gray : Color.red)
                .foregroundStyle(.white)
                .clipShape(Capsule())
            }
            .disabled(selectedBoxIds.isEmpty || isDeleting)
        }
        .padding()
        .background(.ultraThinMaterial)
    }

    // MARK: - 行

    private func boxRow(_ box: Box, isSelected: Bool? = nil) -> some View {
        HStack(spacing: 12) {
            if let isSelected {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                    .font(.title3)
            }

            Image(systemName: "shippingbox.fill")
                .font(.title2)
                .foregroundStyle(Color.accentColor)
                .frame(width: 44, height: 44)
                .background(Color.accentColor.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 4) {
                Text(box.name)
                    .font(.body.weight(.medium))
                Text(box.boxUid)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text("\(box.bookCount) 本")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    // MARK: - 操作

    private func toggleBox(_ id: Int) {
        if selectedBoxIds.contains(id) {
            selectedBoxIds.remove(id)
        } else {
            selectedBoxIds.insert(id)
        }
    }

    private func deleteSelectedBoxes() {
        guard !selectedBoxIds.isEmpty else { return }
        isDeleting = true
        Task {
            defer { isDeleting = false }
            do {
                _ = try await NetworkService.shared.batchDeleteBoxes(ids: Array(selectedBoxIds))
                // 从本地列表移除已删除的箱子
                boxes.removeAll { selectedBoxIds.contains($0.id) }
                selectedBoxIds.removeAll()
                isMultiSelect = false
            } catch {
                errorMessage = "批量删除失败: \(error.chineseDescription)"
            }
        }
    }

    private func loadBoxes() async {
        isLoading = true
        do {
            boxes = try await NetworkService.shared.fetchBoxes()
        } catch {
            errorMessage = error.chineseDescription
        }
        isLoading = false
    }
}

#Preview {
    NavigationStack {
        BoxListView()
    }
}

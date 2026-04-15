import SwiftUI

/// 分类管理 — 查看、新建、编辑、删除分类
struct CategoryManageView: View {
    @State private var categories: [Category] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showCreateAlert = false
    @State private var newCategoryName = ""
    @State private var editingCategory: Category?
    @State private var editName = ""
    @State private var showEditAlert = false
    @State private var showDeleteConfirm = false
    @State private var deletingCategory: Category?

    var body: some View {
        Group {
            if isLoading {
                ProgressView("加载中...")
                    .frame(maxHeight: .infinity)
            } else if categories.isEmpty {
                ContentUnavailableView {
                    Label("暂无分类", systemImage: "tag")
                } actions: {
                    Button("新建分类") {
                        newCategoryName = ""
                        showCreateAlert = true
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else {
                List {
                    ForEach(categories) { category in
                        categoryRow(category)
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("分类管理")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    newCategoryName = ""
                    showCreateAlert = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .task { await loadCategories() }
        .refreshable { await loadCategories() }
        .alert("新建分类", isPresented: $showCreateAlert) {
            TextField("分类名称", text: $newCategoryName)
            Button("创建") { createCategory() }
            Button("取消", role: .cancel) {}
        }
        .alert("编辑分类", isPresented: $showEditAlert) {
            TextField("分类名称", text: $editName)
            Button("保存") { updateCategory() }
            Button("取消", role: .cancel) {}
        }
        .alert("确认删除", isPresented: $showDeleteConfirm) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) { deleteCategory() }
        } message: {
            Text("删除分类「\(deletingCategory?.name ?? "")」后，其下的子分类和书籍将解除关联。")
        }
        .alert("操作失败", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("确定") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func categoryRow(_ category: Category) -> some View {
        HStack {
            Image(systemName: "tag.fill")
                .foregroundStyle(Color.accentColor)
            Text(category.name)
            Spacer()
        }
        .contextMenu {
            Button {
                editingCategory = category
                editName = category.name
                showEditAlert = true
            } label: {
                Label("编辑", systemImage: "pencil")
            }
            Button(role: .destructive) {
                deletingCategory = category
                showDeleteConfirm = true
            } label: {
                Label("删除", systemImage: "trash")
            }
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                deletingCategory = category
                showDeleteConfirm = true
            } label: {
                Label("删除", systemImage: "trash")
            }
            Button {
                editingCategory = category
                editName = category.name
                showEditAlert = true
            } label: {
                Label("编辑", systemImage: "pencil")
            }
            .tint(.orange)
        }
    }

    // MARK: - 数据操作

    private func loadCategories() async {
        isLoading = true
        do {
            categories = try await NetworkService.shared.fetchCategories()
        } catch {
            errorMessage = error.chineseDescription
        }
        isLoading = false
    }

    private func createCategory() {
        let name = newCategoryName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        Task {
            do {
                let category = try await NetworkService.shared.createCategory(name: name)
                categories.append(category)
            } catch {
                errorMessage = error.chineseDescription
            }
        }
    }

    private func updateCategory() {
        guard let category = editingCategory else { return }
        let name = editName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        Task {
            do {
                let updated = try await NetworkService.shared.updateCategory(id: category.id, name: name)
                if let idx = categories.firstIndex(where: { $0.id == category.id }) {
                    categories[idx] = updated
                }
            } catch {
                errorMessage = error.chineseDescription
            }
        }
    }

    private func deleteCategory() {
        guard let category = deletingCategory else { return }
        Task {
            do {
                _ = try await NetworkService.shared.deleteCategory(id: category.id)
                categories.removeAll { $0.id == category.id }
            } catch {
                errorMessage = error.chineseDescription
            }
        }
    }
}

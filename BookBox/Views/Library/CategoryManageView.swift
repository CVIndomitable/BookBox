import SwiftUI

/// 分类管理 — 查看、新建、编辑、删除分类
struct CategoryManageView: View {
    @State private var allCategories: [Category] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showCreateAlert = false
    @State private var newCategoryName = ""
    @State private var editingCategory: Category?
    @State private var editName = ""
    @State private var showEditAlert = false
    @State private var showDeleteConfirm = false
    @State private var deletingCategory: Category?
    @State private var selectedType = "user"

    private var displayCategories: [Category] {
        allCategories.filter { $0.categoryType == selectedType }
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("分类类型", selection: $selectedType) {
                Text("用户分类").tag("user")
                Text("法定分类").tag("statutory")
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 8)

            if isLoading {
                ProgressView("加载中...")
                    .frame(maxHeight: .infinity)
            } else if displayCategories.isEmpty {
                ContentUnavailableView {
                    Label(selectedType == "user" ? "暂无用户分类" : "法定分类", systemImage: "tag")
                } actions: {
                    if selectedType == "user" {
                        Button("新建分类") {
                            newCategoryName = ""
                            showCreateAlert = true
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            } else {
                List {
                    ForEach(displayCategories) { category in
                        categoryRow(category)
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("分类管理")
        .toolbar {
            if selectedType == "user" {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        newCategoryName = ""
                        showCreateAlert = true
                    } label: {
                        Image(systemName: "plus")
                    }
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
            if category.isStatutory {
                Image(systemName: "lock.fill")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            } else {
                Image(systemName: "tag.fill")
                    .foregroundStyle(Color.accentColor)
            }
            Text(category.name)
            Spacer()
        }
        .contextMenu {
            if !category.isStatutory {
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
        }
        .swipeActions(edge: .trailing) {
            if !category.isStatutory {
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
    }

    // MARK: - 数据操作

    private func loadCategories() async {
        isLoading = true
        do {
            allCategories = try await NetworkService.shared.fetchCategories(type: "all")
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
                allCategories.append(category)
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
                if let idx = allCategories.firstIndex(where: { $0.id == category.id }) {
                    allCategories[idx] = updated
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
                allCategories.removeAll { $0.id == category.id }
            } catch {
                errorMessage = error.chineseDescription
            }
        }
    }
}

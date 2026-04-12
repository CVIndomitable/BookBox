import SwiftUI

/// 分类结果视图 — 展示识别出的书名，支持分类编辑
struct ClassifyResultView: View {
    @Binding var titles: [ExtractedTitle]
    @State private var categories: [Category] = []
    @State private var selectedCategory: [UUID: Int] = [:]
    @State private var isLoadingCategories = false

    var body: some View {
        List {
            Section {
                ForEach(titles) { title in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(title.title)
                                .font(.body)

                            Spacer()

                            // 置信度指示
                            Text("\(Int(title.confidence * 100))%")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.quaternary)
                                .clipShape(Capsule())
                        }

                        // 分类选择
                        if !categories.isEmpty {
                            Picker("分类", selection: categoryBinding(for: title.id)) {
                                Text("未分类").tag(0)
                                ForEach(categories) { category in
                                    Text(category.name).tag(category.id)
                                }
                            }
                            .pickerStyle(.menu)
                            .font(.caption)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .onDelete { indices in
                    titles.remove(atOffsets: indices)
                }
            } header: {
                Text("识别到 \(titles.count) 本书")
            }
        }
        .task {
            await loadCategories()
        }
    }

    private func categoryBinding(for id: UUID) -> Binding<Int> {
        Binding(
            get: { selectedCategory[id] ?? 0 },
            set: { selectedCategory[id] = $0 }
        )
    }

    private func loadCategories() async {
        isLoadingCategories = true
        do {
            categories = try await NetworkService.shared.fetchCategories()
        } catch {
            // 分类加载失败不阻塞使用
        }
        isLoadingCategories = false
    }
}

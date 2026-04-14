import SwiftUI

/// 新建书架视图
struct ShelfCreateView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var location = ""
    @State private var description = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    /// 所属书库 ID
    var libraryId: Int?
    var onCreated: ((Shelf) -> Void)?

    var body: some View {
        Form {
            Section("书架信息") {
                TextField("书架名称", text: $name)
                TextField("位置描述（可选）", text: $location)
                TextField("备注（可选）", text: $description, axis: .vertical)
                    .lineLimit(3...6)
            }
        }
        .navigationTitle("新建书架")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("取消") {
                    dismiss()
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("创建") {
                    createShelf()
                }
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
            }
        }
        .alert("创建失败", isPresented: .init(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("确定") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func createShelf() {
        isSaving = true
        Task {
            do {
                let request = ShelfRequest(
                    name: name.trimmingCharacters(in: .whitespaces),
                    location: location.isEmpty ? nil : location,
                    description: description.isEmpty ? nil : description,
                    libraryId: libraryId
                )
                let shelf = try await NetworkService.shared.createShelf(request)
                onCreated?(shelf)
                dismiss()
            } catch {
                errorMessage = error.chineseDescription
            }
            isSaving = false
        }
    }
}

#Preview {
    NavigationStack {
        ShelfCreateView()
    }
}

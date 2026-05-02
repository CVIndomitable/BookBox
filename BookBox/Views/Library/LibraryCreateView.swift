import SwiftUI

/// 新建书库视图
struct LibraryCreateView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var location = ""
    @State private var description = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    var onCreated: ((Library) -> Void)?

    var body: some View {
        Form {
            Section("书库信息") {
                TextField("书库名称", text: $name)
                TextField("位置（可选）", text: $location)
                TextField("备注（可选）", text: $description, axis: .vertical)
                    .lineLimit(3...6)
            }
        }
        .navigationTitle("新建书库")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("取消") {
                    dismiss()
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("创建") {
                    createLibrary()
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

    private func createLibrary() {
        isSaving = true
        Task {
            do {
                let request = LibraryRequest(
                    name: name.trimmingCharacters(in: .whitespaces),
                    location: location.isEmpty ? nil : location,
                    description: description.isEmpty ? nil : description
                )
                let library = try await NetworkService.shared.createLibrary(request)
                onCreated?(library)
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
        LibraryCreateView()
    }
}

import SwiftUI

/// 新建箱子视图
struct BoxCreateView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var description = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    var onCreated: ((Box) -> Void)?

    var body: some View {
        Form {
            Section("箱子信息") {
                TextField("箱子名称", text: $name)
                TextField("备注（可选）", text: $description, axis: .vertical)
                    .lineLimit(3...6)
            }

            Section {
                Text("编号将在创建后自动生成，格式：YYYYMMDD-NNN")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("新建箱子")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("取消") {
                    dismiss()
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("创建") {
                    createBox()
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

    private func createBox() {
        isSaving = true
        Task {
            do {
                let request = BoxRequest(
                    name: name.trimmingCharacters(in: .whitespaces),
                    description: description.isEmpty ? nil : description
                )
                let box = try await NetworkService.shared.createBox(request)
                onCreated?(box)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
            isSaving = false
        }
    }
}

#Preview {
    NavigationStack {
        BoxCreateView()
    }
}

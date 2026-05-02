import SwiftUI

/// 新建房间视图
struct RoomCreateView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var description = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    /// 所属书库 ID（必须）
    let libraryId: Int
    var onCreated: ((Room) -> Void)?

    var body: some View {
        Form {
            Section("房间信息") {
                TextField("房间名称", text: $name)
                TextField("备注（可选）", text: $description, axis: .vertical)
                    .lineLimit(3...6)
            }
        }
        .navigationTitle("新建房间")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("取消") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("创建") { createRoom() }
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

    private func createRoom() {
        isSaving = true
        Task {
            do {
                let req = RoomRequest(
                    name: name.trimmingCharacters(in: .whitespaces),
                    description: description.isEmpty ? nil : description,
                    libraryId: libraryId
                )
                let room = try await NetworkService.shared.createRoom(req)
                onCreated?(room)
                dismiss()
            } catch {
                errorMessage = error.chineseDescription
            }
            isSaving = false
        }
    }
}

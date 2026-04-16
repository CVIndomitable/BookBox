import SwiftUI

/// 新建书架视图
struct ShelfCreateView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var location = ""
    @State private var description = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    @State private var rooms: [Room] = []
    @State private var selectedRoomId: Int?
    @State private var isLoadingRooms = false

    /// 所属书库 ID
    var libraryId: Int?
    /// 预选房间 ID（可选）
    var preselectedRoomId: Int?
    var onCreated: ((Shelf) -> Void)?

    var body: some View {
        Form {
            Section("书架信息") {
                TextField("书架名称", text: $name)
                TextField("位置描述（可选）", text: $location)
                TextField("备注（可选）", text: $description, axis: .vertical)
                    .lineLimit(3...6)
            }

            if libraryId != nil {
                Section("所在房间") {
                    if isLoadingRooms {
                        ProgressView()
                    } else if rooms.isEmpty {
                        Text("该书库暂无房间")
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("房间", selection: $selectedRoomId) {
                            ForEach(rooms) { room in
                                Text(room.isDefault ? "\(room.name)（默认）" : room.name)
                                    .tag(Optional(room.id))
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("新建书架")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("取消") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("创建") { createShelf() }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
            }
        }
        .task { await loadRooms() }
        .alert("创建失败", isPresented: .init(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("确定") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func loadRooms() async {
        guard let libraryId else { return }
        isLoadingRooms = true
        do {
            let fetched = try await NetworkService.shared.fetchRooms(libraryId: libraryId)
            rooms = fetched
            // 优先预选，否则选默认房间，再次首选第一个
            if let pre = preselectedRoomId, fetched.contains(where: { $0.id == pre }) {
                selectedRoomId = pre
            } else if let def = fetched.first(where: { $0.isDefault }) {
                selectedRoomId = def.id
            } else {
                selectedRoomId = fetched.first?.id
            }
        } catch {
            errorMessage = error.chineseDescription
        }
        isLoadingRooms = false
    }

    private func createShelf() {
        isSaving = true
        Task {
            do {
                let request = ShelfRequest(
                    name: name.trimmingCharacters(in: .whitespaces),
                    location: location.isEmpty ? nil : location,
                    description: description.isEmpty ? nil : description,
                    libraryId: libraryId,
                    roomId: selectedRoomId
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

import SwiftUI

/// 新建箱子视图
struct BoxCreateView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var description = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    @State private var libraries: [Library] = []
    @State private var selectedLibraryId: Int?
    @State private var isLoadingLibraries = false

    @State private var rooms: [Room] = []
    @State private var selectedRoomId: Int?
    @State private var isLoadingRooms = false

    /// 所属书库 ID（外部传入则锁定为该书库，不显示书库选择器）
    var libraryId: Int?
    /// 预选房间 ID（可选）
    var preselectedRoomId: Int?
    var onCreated: ((Box) -> Void)?

    /// 当前实际使用的书库 ID：外部传入优先，否则用户选择
    private var effectiveLibraryId: Int? {
        libraryId ?? selectedLibraryId
    }

    /// 必须有归属（书库+房间）才能创建
    private var canCreate: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && !isSaving
            && effectiveLibraryId != nil
            && selectedRoomId != nil
    }

    var body: some View {
        Form {
            infoSection
            placementSection
            hintSection
        }
        .navigationTitle("新建箱子")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("取消") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("创建") { createBox() }
                    .disabled(!canCreate)
            }
        }
        .task { await initialLoad() }
        .onChange(of: selectedLibraryId) { _, newValue in
            guard libraryId == nil else { return }
            selectedRoomId = nil
            rooms = []
            if newValue != nil {
                Task { await loadRooms() }
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

    private var infoSection: some View {
        Section("箱子信息") {
            TextField("箱子名称", text: $name)
            TextField("备注（可选）", text: $description, axis: .vertical)
                .lineLimit(3...6)
        }
    }

    @ViewBuilder
    private var placementSection: some View {
        Section("归属（必选）") {
            if libraryId == nil {
                libraryPicker
            }
            if effectiveLibraryId != nil {
                roomPicker
            }
        }
    }

    @ViewBuilder
    private var libraryPicker: some View {
        if isLoadingLibraries {
            ProgressView()
        } else if libraries.isEmpty {
            Text("暂无书库，请先创建书库")
                .foregroundStyle(.secondary)
        } else {
            Picker("书库", selection: $selectedLibraryId) {
                Text("请选择书库").tag(Int?.none)
                ForEach(libraries) { lib in
                    Text(lib.name).tag(Int?(lib.id))
                }
            }
        }
    }

    @ViewBuilder
    private var roomPicker: some View {
        if isLoadingRooms {
            ProgressView()
        } else if rooms.isEmpty {
            Text("该书库暂无房间")
                .foregroundStyle(.secondary)
        } else {
            Picker("房间", selection: $selectedRoomId) {
                Text("请选择房间").tag(Int?.none)
                ForEach(rooms) { room in
                    Text(room.isDefault ? "\(room.name)（默认）" : room.name)
                        .tag(Int?(room.id))
                }
            }
        }
    }

    private var hintSection: some View {
        Section {
            Text("编号将在创建后自动生成，格式：YYYYMMDD-NNN")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func initialLoad() async {
        if libraryId != nil {
            await loadRooms()
        } else {
            await loadLibraries()
        }
    }

    private func loadLibraries() async {
        isLoadingLibraries = true
        do {
            libraries = try await NetworkService.shared.fetchLibraries()
        } catch {
            errorMessage = error.chineseDescription
        }
        isLoadingLibraries = false
    }

    private func loadRooms() async {
        guard let libId = effectiveLibraryId else { return }
        isLoadingRooms = true
        do {
            let fetched = try await NetworkService.shared.fetchRooms(libraryId: libId)
            rooms = fetched
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

    private func createBox() {
        isSaving = true
        Task {
            do {
                let request = BoxRequest(
                    name: name.trimmingCharacters(in: .whitespaces),
                    description: description.isEmpty ? nil : description,
                    libraryId: effectiveLibraryId,
                    roomId: selectedRoomId
                )
                let box = try await NetworkService.shared.createBox(request)
                onCreated?(box)
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
        BoxCreateView()
    }
}

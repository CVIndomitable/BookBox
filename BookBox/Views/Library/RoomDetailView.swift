import SwiftUI

/// 房间详情：展示该房间下的所有书架和箱子
struct RoomDetailView: View {
    let roomId: Int
    let roomName: String
    let libraryId: Int

    @State private var shelves: [Shelf] = []
    @State private var boxes: [Box] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showRename = false
    @State private var renameValue = ""
    @State private var showDeleteConfirm = false
    @State private var isDefault = false

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            Section {
                if shelves.isEmpty {
                    Text("暂无书架")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(shelves) { shelf in
                        NavigationLink {
                            ShelfDetailView(shelfId: shelf.id, shelfName: shelf.name)
                        } label: {
                            containerRow(icon: "books.vertical.fill", color: .blue, title: shelf.name, subtitle: shelf.location, count: shelf.bookCount)
                        }
                    }
                }
                NavigationLink {
                    ShelfCreateView(libraryId: libraryId, preselectedRoomId: roomId) { _ in
                        Task { await reload() }
                    }
                } label: {
                    Label("新建书架", systemImage: "plus.circle")
                        .foregroundStyle(Color.accentColor)
                }
            } header: {
                Label("书架", systemImage: "books.vertical")
            }

            Section {
                if boxes.isEmpty {
                    Text("暂无箱子")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(boxes) { box in
                        NavigationLink {
                            BoxDetailView(box: box)
                        } label: {
                            containerRow(icon: "shippingbox.fill", color: .brown, title: box.name, subtitle: box.boxUid, count: box.bookCount)
                        }
                    }
                }
                NavigationLink {
                    BoxCreateView(libraryId: libraryId, preselectedRoomId: roomId) { _ in
                        Task { await reload() }
                    }
                } label: {
                    Label("新建箱子", systemImage: "plus.circle")
                        .foregroundStyle(Color.accentColor)
                }
            } header: {
                Label("箱子", systemImage: "shippingbox")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(roomName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !isDefault {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            renameValue = roomName
                            showRename = true
                        } label: {
                            Label("重命名", systemImage: "pencil")
                        }
                        Button(role: .destructive) {
                            showDeleteConfirm = true
                        } label: {
                            Label("删除房间", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .task { await reload() }
        .refreshable { await reload() }
        .sheet(isPresented: $showRename) {
            NavigationStack {
                Form {
                    Section("房间名称") {
                        TextField("房间名称", text: $renameValue)
                    }
                }
                .navigationTitle("重命名房间")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("取消") { showRename = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("保存") { renameRoom() }
                            .disabled(renameValue.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
        }
        .alert("删除房间", isPresented: $showDeleteConfirm) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) { deleteRoom() }
        } message: {
            Text("删除后，房间内的书架/箱子将转移到默认房间。")
        }
        .alert("加载失败", isPresented: .init(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("确定") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func containerRow(icon: String, color: Color, title: String, subtitle: String?, count: Int) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)
                .frame(width: 44, height: 44)
                .background(color.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.body.weight(.medium))
                if let subtitle {
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text("\(count) 本")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private func reload() async {
        isLoading = true
        do {
            async let s = NetworkService.shared.fetchShelves(roomId: roomId)
            async let b = NetworkService.shared.fetchBoxes(roomId: roomId)
            async let rooms = NetworkService.shared.fetchRooms(libraryId: libraryId)
            shelves = try await s
            boxes = try await b
            let rs = try await rooms
            isDefault = rs.first(where: { $0.id == roomId })?.isDefault ?? false
        } catch {
            errorMessage = error.chineseDescription
        }
        isLoading = false
    }

    private func renameRoom() {
        Task {
            do {
                _ = try await NetworkService.shared.updateRoom(
                    id: roomId,
                    RoomUpdateRequest(name: renameValue.trimmingCharacters(in: .whitespaces), description: nil)
                )
                showRename = false
                await reload()
            } catch {
                errorMessage = error.chineseDescription
            }
        }
    }

    private func deleteRoom() {
        Task {
            do {
                _ = try await NetworkService.shared.deleteRoom(id: roomId)
                dismiss()
            } catch {
                errorMessage = error.chineseDescription
            }
        }
    }
}

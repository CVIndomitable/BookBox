import SwiftUI

/// 移动书籍到指定位置（书架/箱子/取消归位）
struct MoveBookSheet: View {
    let bookId: Int
    let onMoved: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var shelves: [Shelf] = []
    @State private var boxes: [Box] = []
    @State private var isLoading = true
    @State private var isMoving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("加载中...")
                        .frame(maxHeight: .infinity)
                } else {
                    List {
                        Section {
                            Button {
                                moveTo(.none, id: nil)
                            } label: {
                                Label("取消归位", systemImage: "xmark.circle")
                                    .foregroundStyle(.orange)
                            }
                        }

                        if !shelves.isEmpty {
                            Section("书架") {
                                ForEach(shelves) { shelf in
                                    Button { moveTo(.shelf, id: shelf.id) } label: {
                                        HStack {
                                            Label(shelf.name, systemImage: "books.vertical.fill")
                                            Spacer()
                                            Text("\(shelf.bookCount) 本")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            }
                        }

                        if !boxes.isEmpty {
                            Section("箱子") {
                                ForEach(boxes) { box in
                                    Button { moveTo(.box, id: box.id) } label: {
                                        HStack {
                                            Label(box.name, systemImage: "shippingbox.fill")
                                            Spacer()
                                            Text("\(box.bookCount) 本")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("移动到")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
            .task { await loadLocations() }
            .overlay {
                if isMoving {
                    ProgressView("移动中...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(.ultraThinMaterial)
                }
            }
            .alert("移动失败", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("确定") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private func loadLocations() async {
        do {
            async let s = NetworkService.shared.fetchShelves()
            async let b = NetworkService.shared.fetchBoxes()
            shelves = try await s
            boxes = try await b
        } catch {
            errorMessage = error.chineseDescription
        }
        isLoading = false
    }

    private func moveTo(_ type: LocationType, id: Int?) {
        isMoving = true
        Task {
            do {
                _ = try await NetworkService.shared.moveBook(
                    id: bookId,
                    request: MoveBookRequest(toType: type, toId: id, method: "manual", rawInput: nil)
                )
                onMoved()
                dismiss()
            } catch {
                errorMessage = error.chineseDescription
            }
            isMoving = false
        }
    }
}

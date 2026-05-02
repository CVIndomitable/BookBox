import SwiftUI

/// 创建晒书提醒 — 从书库或箱子详情页进入
struct SunReminderCreateView: View {
    let targetType: String  // "library" or "box"
    let targetId: Int
    let targetName: String
    var onCreated: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var sunDays: Int = 90
    @State private var isCreating = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Image(systemName: targetType == "library" ? "building.columns" : "shippingbox")
                            .foregroundStyle(.secondary)
                        Text(targetName)
                            .font(.body.weight(.medium))
                    }
                } header: {
                    Text("目标")
                }

                Section("晒书间隔") {
                    Stepper("每 \(sunDays) 天晒一次", value: $sunDays, in: 7...730, step: 7)
                    Text("建议根据书籍受潮程度设定间隔。默认 90 天（约每季度）。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if isCreating {
                    Section {
                        HStack {
                            Spacer()
                            ProgressView("创建中…")
                            Spacer()
                        }
                    }
                }
            }
            .navigationTitle("设置晒书提醒")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("创建") { create() }
                        .disabled(isCreating)
                }
            }
            .alert("操作失败", isPresented: .init(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("确定") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private func create() {
        isCreating = true
        Task {
            do {
                if targetType == "library" {
                    _ = try await NetworkService.shared.createLibrarySunReminder(libraryId: targetId, sunDays: sunDays)
                } else {
                    _ = try await NetworkService.shared.createBoxSunReminder(boxId: targetId, sunDays: sunDays)
                }
                onCreated?()
                dismiss()
            } catch {
                errorMessage = error.chineseDescription
            }
            isCreating = false
        }
    }
}

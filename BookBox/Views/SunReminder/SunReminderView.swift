import SwiftUI

/// 晒书提醒列表 — 查看/标记已晒/删除
struct SunReminderView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var reminders: [SunReminder] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showCreate = false
    @State private var editingReminder: SunReminder?
    @State private var editSunDays: Int = 90

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("加载中…")
                        .frame(maxHeight: .infinity)
                } else if reminders.isEmpty {
                    ContentUnavailableView(
                        "暂无晒书提醒",
                        systemImage: "sun.max",
                        description: Text("在书库或箱子中可以设置晒书提醒")
                    )
                } else {
                    List {
                        overdueSection
                        upcomingSection
                    }
                    .listStyle(.insetGrouped)
                    .refreshable { await loadReminders() }
                }
            }
            .navigationTitle("晒书提醒")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
            .task { await loadReminders() }
            .sheet(item: $editingReminder) { reminder in
                editSheet(reminder)
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

    // MARK: - 过期/即将到来

    private var overdueSection: some View {
        let overdue = reminders.filter { $0.nextSunAt <= Date() }
        if overdue.isEmpty { return AnyView(EmptyView()) }
        return AnyView(
            Section {
                ForEach(overdue) { reminder in
                    reminderRow(reminder, isOverdue: true)
                }
                .onDelete { deleteReminders(at: $0, from: overdue) }
            } header: {
                HStack {
                    Text("待晒书")
                    Spacer()
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }
        )
    }

    private var upcomingSection: some View {
        let upcoming = reminders.filter { $0.nextSunAt > Date() }
        if upcoming.isEmpty { return AnyView(EmptyView()) }
        return AnyView(
            Section {
                ForEach(upcoming) { reminder in
                    reminderRow(reminder, isOverdue: false)
                }
                .onDelete { deleteReminders(at: $0, from: upcoming) }
            } header: {
                Text("即将到来")
            }
        )
    }

    // MARK: - 行

    private func reminderRow(_ reminder: SunReminder, isOverdue: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: reminder.targetType == "library" ? "building.columns" : "shippingbox")
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(reminder.targetName)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                HStack(spacing: 4) {
                    if isOverdue {
                        Text("已逾期")
                            .font(.caption2)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(.orange, in: Capsule())
                    } else {
                        Text(reminder.nextSunAt, style: .relative)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text("· 每 \(reminder.sunDays) 天")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            if isOverdue {
                Button {
                    markSunned(reminder)
                } label: {
                    Label("已晒", systemImage: "checkmark.circle.fill")
                        .labelStyle(.iconOnly)
                        .font(.title3)
                        .foregroundStyle(.green)
                }
                .buttonStyle(.plain)
            }

            Button {
                editSunDays = reminder.sunDays
                editingReminder = reminder
            } label: {
                Image(systemName: "ellipsis")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
    }

    // MARK: - 编辑 sheet

    private func editSheet(_ reminder: SunReminder) -> some View {
        NavigationStack {
            Form {
                Section("晒书间隔") {
                    Stepper("每 \(editSunDays) 天", value: $editSunDays, in: 1...730)
                }
                Section {
                    Text("每次晒书后会重置计时器，按新间隔计算下次提醒时间。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("编辑提醒")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { editingReminder = nil }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        updateReminder(reminder)
                    }
                    .disabled(editSunDays == reminder.sunDays)
                }
            }
        }
    }

    // MARK: - Actions

    private func loadReminders() async {
        isLoading = true
        do {
            reminders = try await NetworkService.shared.fetchSunReminders()
        } catch {
            errorMessage = error.chineseDescription
        }
        isLoading = false
    }

    private func markSunned(_ reminder: SunReminder) {
        Task {
            do {
                let updated = try await NetworkService.shared.markSunReminderAsSunned(id: reminder.id)
                if let idx = reminders.firstIndex(where: { $0.id == reminder.id }) {
                    reminders[idx] = updated
                }
            } catch {
                errorMessage = error.chineseDescription
            }
        }
    }

    private func updateReminder(_ reminder: SunReminder) {
        Task {
            do {
                let updated = try await NetworkService.shared.updateSunReminder(id: reminder.id, sunDays: editSunDays)
                if let idx = reminders.firstIndex(where: { $0.id == reminder.id }) {
                    reminders[idx] = updated
                }
                editingReminder = nil
            } catch {
                errorMessage = error.chineseDescription
            }
        }
    }

    private func deleteReminders(at offsets: IndexSet, from section: [SunReminder]) {
        for index in offsets {
            let reminder = section[index]
            Task {
                do {
                    try await NetworkService.shared.deleteSunReminder(id: reminder.id)
                    reminders.removeAll { $0.id == reminder.id }
                } catch {
                    errorMessage = error.chineseDescription
                }
            }
        }
    }
}

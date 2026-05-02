import SwiftUI

/// 书库成员管理 — 列表/添加/改角色/移除/转让/退出
struct MemberManageView: View {
    let libraryId: Int
    var onChanged: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var members: [LibraryMember] = []
    @State private var myRole: String?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showAddMember = false
    @State private var addUsername = ""
    @State private var addRole: MemberRole = .member
    @State private var isAdding = false
    @State private var showTransfer = false
    @State private var transferUsername = ""
    @State private var isTransferring = false
    @State private var showLeaveConfirm = false
    @State private var roleChangeTarget: LibraryMember?

    private var currentUserId: Int? { AuthService.shared.user?.id }
    private var isOwner: Bool { myRole == "owner" }
    private var isAdmin: Bool { myRole == "admin" || isOwner }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("加载中…")
                        .frame(maxHeight: .infinity)
                } else {
                    List {
                        Section {
                            ForEach(members) { member in
                                HStack(spacing: 12) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack(spacing: 6) {
                                            Text(member.user.displayName ?? member.user.username)
                                                .font(.body.weight(.medium))
                                            if member.userId == currentUserId {
                                                Text("我")
                                                    .font(.caption2)
                                                    .foregroundStyle(.secondary)
                                                    .padding(.horizontal, 6)
                                                    .padding(.vertical, 2)
                                                    .background(.quaternary, in: Capsule())
                                            }
                                        }
                                        Text("@\(member.user.username)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }

                                    Spacer()

                                    if member.role == .owner {
                                        MemberRoleBadge(role: member.role)
                                    } else if isOwner && member.userId != currentUserId {
                                        Menu {
                                            ForEach([MemberRole.admin, MemberRole.member], id: \.self) { role in
                                                Button(role.label) {
                                                    changeRole(member, to: role)
                                                }
                                            }
                                        } label: {
                                            MemberRoleBadge(role: member.role)
                                        }
                                    } else {
                                        MemberRoleBadge(role: member.role)
                                    }
                                }
                                .swipeActions(edge: .trailing) {
                                    if canRemove(member) {
                                        Button("移除", role: .destructive) {
                                            removeMember(member)
                                        }
                                    }
                                }
                            }
                        } header: {
                            Text("成员 (\(members.count))")
                        }

                        if isOwner {
                            Section {
                                Button {
                                    showAddMember = true
                                } label: {
                                    Label("添加成员", systemImage: "person.badge.plus")
                                }

                                Button {
                                    transferUsername = ""
                                    showTransfer = true
                                } label: {
                                    Label("转让书库", systemImage: "arrow.right.square")
                                }
                            }
                        }

                        if myRole != "owner" {
                            Section {
                                Button(role: .destructive) {
                                    showLeaveConfirm = true
                                } label: {
                                    HStack {
                                        Spacer()
                                        Label("退出书库", systemImage: "door.left.hand.open")
                                        Spacer()
                                    }
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .refreshable { await loadMembers() }
                }
            }
            .navigationTitle("成员管理")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
            .task { await loadMembers() }
            .sheet(isPresented: $showAddMember) {
                addMemberSheet
            }
            .sheet(isPresented: $showTransfer) {
                transferSheet
            }
            .alert("退出书库", isPresented: $showLeaveConfirm) {
                Button("取消", role: .cancel) {}
                Button("退出", role: .destructive) { leaveLibrary() }
            } message: {
                Text("确定要退出该书库吗？退出后需要所有者重新邀请才能加入。")
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

    // MARK: - 添加成员

    private var addMemberSheet: some View {
        NavigationStack {
            Form {
                Section("用户名") {
                    TextField("输入要添加的用户名", text: $addUsername)
                        .autocapitalization(.none)
                        .autocorrectionDisabled()
                }
                Section("角色") {
                    Picker("角色", selection: $addRole) {
                        ForEach([MemberRole.admin, MemberRole.member], id: \.self) { role in
                            Text(role.label).tag(role)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }
            .navigationTitle("添加成员")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { showAddMember = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("添加") {
                        addMember()
                    }
                    .disabled(addUsername.trimmingCharacters(in: .whitespaces).isEmpty || isAdding)
                }
            }
        }
    }

    // MARK: - 转让书库

    private var transferSheet: some View {
        NavigationStack {
            Form {
                Section("转让给") {
                    TextField("输入目标成员用户名", text: $transferUsername)
                        .autocapitalization(.none)
                        .autocorrectionDisabled()
                }
                Section {
                    Text("转让后您将成为管理员，目标成员成为新的所有者。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("转让书库")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { showTransfer = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("确认转让") {
                        transferOwnership()
                    }
                    .disabled(transferUsername.trimmingCharacters(in: .whitespaces).isEmpty || isTransferring)
                }
            }
        }
    }

    // MARK: - Actions

    private func loadMembers() async {
        isLoading = true
        do {
            async let membersTask = NetworkService.shared.fetchMembers(libraryId: libraryId)
            async let overviewTask = NetworkService.shared.fetchLibraryOverview(libraryId: libraryId)
            members = try await membersTask
            myRole = try await overviewTask.myRole
        } catch {
            errorMessage = error.chineseDescription
        }
        isLoading = false
    }

    private func addMember() {
        let name = addUsername.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        isAdding = true
        Task {
            do {
                _ = try await NetworkService.shared.addMember(libraryId: libraryId, username: name, role: addRole)
                showAddMember = false
                addUsername = ""
                await loadMembers()
            } catch {
                errorMessage = error.chineseDescription
            }
            isAdding = false
        }
    }

    private func removeMember(_ member: LibraryMember) {
        Task {
            do {
                try await NetworkService.shared.removeMember(libraryId: libraryId, userId: member.userId)
                await loadMembers()
            } catch {
                errorMessage = error.chineseDescription
            }
        }
    }

    private func changeRole(_ member: LibraryMember, to role: MemberRole) {
        Task {
            do {
                _ = try await NetworkService.shared.updateMemberRole(libraryId: libraryId, userId: member.userId, role: role)
                await loadMembers()
            } catch {
                errorMessage = error.chineseDescription
            }
        }
    }

    private func transferOwnership() {
        let name = transferUsername.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        isTransferring = true
        Task {
            do {
                try await NetworkService.shared.transferOwnership(libraryId: libraryId, to: name)
                showTransfer = false
                myRole = "admin"
                await loadMembers()
                onChanged?()
            } catch {
                errorMessage = error.chineseDescription
            }
            isTransferring = false
        }
    }

    private func leaveLibrary() {
        Task {
            do {
                try await NetworkService.shared.leaveLibrary(libraryId: libraryId)
                onChanged?()
                dismiss()
            } catch {
                errorMessage = error.chineseDescription
            }
        }
    }

    private func canRemove(_ member: LibraryMember) -> Bool {
        guard member.userId != currentUserId else { return false }
        if member.role == .owner { return false }
        if isOwner { return true }
        if isAdmin && member.role == .member { return true }
        return false
    }
}

/// 成员角色标签
struct MemberRoleBadge: View {
    let role: MemberRole

    var body: some View {
        Text(role.label)
            .font(.caption2.weight(.medium))
            .foregroundStyle(role == .owner ? .yellow : role == .admin ? .blue : .secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                (role == .owner ? Color.yellow : role == .admin ? Color.blue : Color.gray)
                    .opacity(0.12),
                in: Capsule()
            )
    }
}

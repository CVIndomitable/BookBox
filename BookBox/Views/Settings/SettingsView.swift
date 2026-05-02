import SwiftUI

/// 设置页 — 地区 / 语音开关 / 连接测试 / 供应商池状态。
/// AI 供应商配置全部在服务器端（中途岛）管理，iOS 仅读取展示。
struct SettingsView: View {
    @AppStorage("assistantMode") private var assistantModeRaw: String = AssistantMode.off.rawValue
    @AppStorage("duplicateCheckEnabled") private var duplicateCheckEnabled: Bool = false
    @AppStorage("duplicateTabEnabled") private var duplicateTabEnabled: Bool = false
    @AppStorage("recentBoxCount") private var recentBoxCount: Int = 3
    @State private var regionMode: RegionMode = .mainland
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var showSaveSuccess = false
    @State private var errorMessage: String?
    @State private var cacheStats: CacheStats?
    @State private var isLoadingCache = false
    @State private var isResettingCache = false
    @State private var isCheckingHealth = false
    @State private var healthResult: HealthCheckResult?
    @State private var healthError: String?
    @State private var suppliers: [LlmSupplier] = []
    @State private var isLoadingSuppliers = false
    @State private var suppliersError: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("服务器地址", value: AppConfig.current)
                    if let username = AuthService.shared.user?.username {
                        LabeledContent("当前用户", value: username)
                    }
                    Button("退出登录", role: .destructive) {
                        AuthService.shared.clear()
                    }
                        .font(.caption)
                } header: {
                    Text("服务器")
                } footer: {
                    Text("服务器地址已内置，无需手动配置")
                }

                Section {
                    Button {
                        checkHealth()
                    } label: {
                        HStack {
                            Spacer()
                            if isCheckingHealth {
                                ProgressView()
                                    .padding(.trailing, 4)
                                Text("检测中...")
                            } else {
                                Text("测试连接")
                            }
                            Spacer()
                        }
                    }
                    .disabled(isCheckingHealth)

                    if let result = healthResult {
                        healthStatusRow("服务器", status: result.server)
                        healthStatusRow("数据库", status: result.database)
                        healthStatusRow("AI 服务", status: result.ai)

                        if let pool = result.suppliers, !pool.isEmpty {
                            DisclosureGroup("供应商明细（\(pool.count)）") {
                                ForEach(pool, id: \.name) { s in
                                    HStack {
                                        Image(systemName: s.status == "ok" ? "checkmark.circle.fill" : "xmark.circle.fill")
                                            .foregroundStyle(s.status == "ok" ? .green : .red)
                                        Text(s.name)
                                            .font(.callout)
                                        Text("P\(s.priority)")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                        Spacer()
                                        if let msg = s.message {
                                            Text(msg)
                                                .font(.caption2)
                                                .foregroundStyle(.red)
                                                .lineLimit(1)
                                        }
                                    }
                                }
                            }
                        }
                    }

                    if let error = healthError {
                        Label(error, systemImage: "xmark.circle.fill")
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                } header: {
                    Text("连接测试")
                }

                Section {
                    if isLoadingSuppliers && suppliers.isEmpty {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                    } else if let err = suppliersError {
                        Label(err, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .font(.caption)
                    } else if suppliers.isEmpty {
                        Text("尚未配置任何供应商")
                            .foregroundStyle(.secondary)
                            .font(.callout)
                    } else {
                        ForEach(suppliers) { s in
                            supplierRow(s)
                        }

                        Button {
                            loadSuppliers()
                        } label: {
                            HStack {
                                Spacer()
                                Text("刷新")
                                    .font(.caption)
                                Spacer()
                            }
                        }
                    }
                } header: {
                    Text("AI 供应商池")
                } footer: {
                    Text("供应商及优先级由服务器统一管理。数字越小优先级越高，高优先级不可用时自动降级到下一级并在顶部提醒。")
                }

                Section {
                    Picker("地区模式", selection: $regionMode) {
                        Text("中国大陆").tag(RegionMode.mainland)
                        Text("海外").tag(RegionMode.overseas)
                    }
                } header: {
                    Text("搜索设置")
                } footer: {
                    Text(regionMode == .mainland
                         ? "优先使用豆瓣搜索中文书籍"
                         : "优先使用 Google Books 搜索")
                }

                Section {
                    Button {
                        saveSettings()
                    } label: {
                        HStack {
                            Spacer()
                            if isSaving {
                                ProgressView()
                            } else {
                                Text("保存设置")
                            }
                            Spacer()
                        }
                    }
                    .disabled(isSaving)
                }

                Section {
                    Picker("助手功能", selection: Binding(
                        get: { AssistantMode(rawValue: assistantModeRaw) ?? .off },
                        set: { assistantModeRaw = $0.rawValue }
                    )) {
                        ForEach(AssistantMode.allCases) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                } header: {
                    Text("应用内助手")
                } footer: {
                    Text("开启后在底部显示「助手」Tab，支持文字输入和语音输入/输出。关闭后仍可通过 Siri 快捷指令使用语音功能。")
                }

                Section {
                    Toggle("加书时查重", isOn: $duplicateCheckEnabled)
                    Toggle("显示「查重」Tab", isOn: $duplicateTabEnabled)
                } header: {
                    Text("查重")
                } footer: {
                    Text("加书时查重：添加书籍时若已存在书名与出版社完全一致的书将提醒。\n显示「查重」Tab：在底部增加「查重」模块，一键扫描已录入书库的全部重复书。两项均默认关闭。")
                }

                Section {
                    NavigationLink {
                        TrashView()
                    } label: {
                        Label("回收站", systemImage: "trash")
                    }
                } footer: {
                    Text("删除的书先进入回收站，30 天内可还原，过期后自动彻底删除。")
                }

                Section {
                    Stepper(value: $recentBoxCount, in: 1...5) {
                        LabeledContent("最近使用的箱子数量", value: "\(recentBoxCount)")
                    }
                } header: {
                    Text("装箱")
                } footer: {
                    Text("装箱模式的选箱子页顶部会显示最近选过的箱子，可在 1～5 个之间调整，默认 3 个。")
                }

                Section {
                    DisclosureGroup("AI 缓存统计") {
                        if let stats = cacheStats {
                            LabeledContent("命中次数", value: "\(stats.hits)")
                            LabeledContent("未命中次数", value: "\(stats.misses)")
                            LabeledContent("命中率", value: stats.hitRate)
                            LabeledContent("缓存条目", value: "\(stats.activeEntries)/\(stats.maxSize)")

                            Button(role: .destructive) {
                                resetCacheStats()
                            } label: {
                                HStack {
                                    Spacer()
                                    if isResettingCache {
                                        ProgressView()
                                    } else {
                                        Text("重置统计")
                                    }
                                    Spacer()
                                }
                            }
                            .disabled(isResettingCache)
                        } else if isLoadingCache {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        } else {
                            Text("暂无缓存数据")
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("AI 性能")
                }

                Section("关于") {
                    LabeledContent("版本", value: "2.0.0")
                }
            }
            .navigationTitle("设置")
            .task {
                await loadRemoteSettings()
                await loadCacheStats()
                loadSuppliers()
            }
            .alert("已保存", isPresented: $showSaveSuccess) {
                Button("确定") {}
            }
            .alert("保存失败", isPresented: .init(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("确定") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    @ViewBuilder
    private func supplierRow(_ s: LlmSupplier) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(s.name)
                    .font(.callout.weight(.semibold))
                Text("P\(s.priority)")
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.orange.opacity(0.2), in: Capsule())
                    .foregroundStyle(.orange)
                Spacer()
                if s.enabled {
                    Text("已启用")
                        .font(.caption2)
                        .foregroundStyle(.green)
                } else {
                    Text("已禁用")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Text("\(s.protocolName) · \(s.endpoint)")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            let vm = (s.visionModel?.isEmpty == false) ? s.visionModel! : "—"
            let tm = (s.textModel?.isEmpty == false) ? s.textModel! : "—"
            if vm != "—" || tm != "—" {
                Text("视觉：\(vm)   文本：\(tm)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if let err = s.lastError, s.lastFailAt != nil {
                Text("最近错误：\(err)")
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 2)
    }

    private func loadRemoteSettings() async {
        isLoading = true
        do {
            let settings = try await NetworkService.shared.fetchSettings()
            regionMode = settings.regionMode
        } catch {
            // 远程设置加载失败不阻塞使用
        }
        isLoading = false
    }

    private func loadSuppliers() {
        isLoadingSuppliers = true
        suppliersError = nil
        Task {
            do {
                suppliers = try await NetworkService.shared.fetchSuppliers()
            } catch {
                suppliersError = "无法加载供应商列表"
            }
            isLoadingSuppliers = false
        }
    }

    private func loadCacheStats() async {
        isLoadingCache = true
        do {
            cacheStats = try await NetworkService.shared.fetchCacheStats()
        } catch {
            // 缓存统计加载失败不阻塞
        }
        isLoadingCache = false
    }

    private func resetCacheStats() {
        isResettingCache = true
        Task {
            do {
                _ = try await NetworkService.shared.resetCacheStats()
                cacheStats = try await NetworkService.shared.fetchCacheStats()
            } catch {
                errorMessage = error.chineseDescription
            }
            isResettingCache = false
        }
    }

    @ViewBuilder
    private func healthStatusRow(_ title: String, status: ServiceStatus) -> some View {
        HStack {
            Text(title)
            Spacer()
            let isOk = status.status == "ok"
            let isDegraded = status.status == "degraded"
            let isNotConfigured = status.status == "not_configured"
            Image(systemName: isOk ? "checkmark.circle.fill" :
                              isDegraded ? "exclamationmark.triangle.fill" :
                              isNotConfigured ? "exclamationmark.triangle.fill" :
                              "xmark.circle.fill")
                .foregroundStyle(isOk ? .green :
                                 (isDegraded || isNotConfigured) ? .orange :
                                 .red)
            Text(isOk ? "正常" : (status.message ?? "异常"))
                .foregroundStyle(.secondary)
                .font(.caption)
        }
    }

    private func checkHealth() {
        isCheckingHealth = true
        healthResult = nil
        healthError = nil

        Task {
            do {
                healthResult = try await NetworkService.shared.checkHealth()
            } catch {
                healthError = error.chineseDescription
            }
            isCheckingHealth = false
        }
    }

    private func saveSettings() {
        isSaving = true

        Task {
            do {
                let settings = UserSettings(
                    regionMode: regionMode,
                    llmProvider: nil,
                    llmApiKey: nil,
                    llmEndpoint: nil,
                    llmModel: nil,
                    llmSupportsSearch: false,
                    hasLlmApiKey: nil
                )
                _ = try await NetworkService.shared.updateSettings(settings)
                showSaveSuccess = true
            } catch {
                errorMessage = error.chineseDescription
            }
            isSaving = false
        }
    }
}

#Preview {
    SettingsView()
}

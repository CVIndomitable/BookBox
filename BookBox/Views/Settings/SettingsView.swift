import SwiftUI

/// 设置页面 — 服务器配置、地区模式、大模型 API 设置
struct SettingsView: View {
    @State private var serverURL: String = ""
    @State private var apiToken: String = ""
    @State private var regionMode: RegionMode = .mainland
    @State private var llmProvider: String = ""
    @State private var llmApiKey: String = ""
    @State private var llmEndpoint: String = ""
    @State private var llmModel: String = ""
    @State private var llmSupportsSearch = false
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var showSaveSuccess = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("服务器") {
                    TextField("服务器地址", text: $serverURL)
                        .keyboardType(.URL)
                        .textContentType(.URL)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)

                    SecureField("API Token", text: $apiToken)
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
                    TextField("服务商（openai/claude/other）", text: $llmProvider)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    SecureField("API Key", text: $llmApiKey)
                    TextField("API 地址（可选）", text: $llmEndpoint)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    TextField("模型名称", text: $llmModel)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    Toggle("支持联网搜索", isOn: $llmSupportsSearch)
                } header: {
                    Text("大模型配置")
                } footer: {
                    Text("配置后可用于书名提取、分类和联网搜索")
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

                Section("关于") {
                    LabeledContent("版本", value: "1.0.0")
                    LabeledContent("本地 AI 模型") {
                        Text(LocalMLService.shared.isAvailable ? "已安装" : "未安装")
                            .foregroundStyle(LocalMLService.shared.isAvailable ? .green : .secondary)
                    }
                }
            }
            .navigationTitle("设置")
            .task {
                loadLocalSettings()
                await loadRemoteSettings()
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

    private func loadLocalSettings() {
        serverURL = NetworkService.shared.baseURL
        apiToken = NetworkService.shared.apiToken
    }

    private func loadRemoteSettings() async {
        isLoading = true
        do {
            let settings = try await NetworkService.shared.fetchSettings()
            regionMode = settings.regionMode
            llmProvider = settings.llmProvider ?? ""
            llmApiKey = settings.llmApiKey ?? ""
            llmEndpoint = settings.llmEndpoint ?? ""
            llmModel = settings.llmModel ?? ""
            llmSupportsSearch = settings.llmSupportsSearch
        } catch {
            // 远程设置加载失败不阻塞使用
        }
        isLoading = false
    }

    private func saveSettings() {
        isSaving = true

        // 保存本地设置
        NetworkService.shared.baseURL = serverURL
        NetworkService.shared.apiToken = apiToken

        // 保存远程设置
        Task {
            do {
                let settings = UserSettings(
                    regionMode: regionMode,
                    llmProvider: llmProvider.isEmpty ? nil : llmProvider,
                    llmApiKey: llmApiKey.isEmpty ? nil : llmApiKey,
                    llmEndpoint: llmEndpoint.isEmpty ? nil : llmEndpoint,
                    llmModel: llmModel.isEmpty ? nil : llmModel,
                    llmSupportsSearch: llmSupportsSearch
                )
                _ = try await NetworkService.shared.updateSettings(settings)
                showSaveSuccess = true
            } catch {
                errorMessage = error.localizedDescription
            }
            isSaving = false
        }
    }
}

#Preview {
    SettingsView()
}

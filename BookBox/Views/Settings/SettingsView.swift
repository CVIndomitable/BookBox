import SwiftUI

/// 设置页面 — AI 配置、地区模式（所有配置保存在服务器）
struct SettingsView: View {
    @AppStorage("voiceControlEnabled") private var voiceControlEnabled = false
    @State private var regionMode: RegionMode = .mainland
    @State private var mimoApiKey: String = ""
    @State private var mimoEndpoint: String = ""
    @State private var mimoVisionModel: String = ""
    @State private var hasExistingKey = false
    @State private var apiKeyModified = false
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var showSaveSuccess = false
    @State private var showAdvanced = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("服务器地址", value: AppConfig.serverBaseURL)
                        .font(.caption)
                } header: {
                    Text("服务器")
                } footer: {
                    Text("服务器地址已内置，无需手动配置")
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
                    SecureField(hasExistingKey ? "已配置（输入新值可更换）" : "输入 API Key", text: $mimoApiKey)
                        .textContentType(.password)
                        .onChange(of: mimoApiKey) { _, _ in
                            apiKeyModified = true
                        }
                } header: {
                    Text("AI 识别配置")
                } footer: {
                    Text("配置 API Key 后可使用 AI 识别书籍和语音助手。未配置时使用本地 OCR 识别。API Key 保存在服务器端，不存储在手机上。")
                }

                Section {
                    Toggle("高级设置", isOn: $showAdvanced)

                    if showAdvanced {
                        TextField("API 端点", text: $mimoEndpoint)
                            .keyboardType(.URL)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)

                        TextField("视觉模型", text: $mimoVisionModel)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                    }
                } header: {
                    if showAdvanced {
                        Text("模型配置")
                    }
                } footer: {
                    if showAdvanced {
                        Text("一般无需修改。默认端点和模型已内置在服务器端。")
                    }
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
                    Toggle("应用内语音控制", isOn: $voiceControlEnabled)
                } header: {
                    Text("语音助手")
                } footer: {
                    Text("开启后在主界面显示悬浮麦克风按钮，可通过语音管理书库。关闭后仍可通过 Siri 使用语音指令。")
                }

                Section("关于") {
                    LabeledContent("版本", value: "2.0.0")
                }
            }
            .navigationTitle("设置")
            .task {
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

    private func loadRemoteSettings() async {
        isLoading = true
        do {
            let settings = try await NetworkService.shared.fetchSettings()
            regionMode = settings.regionMode
            hasExistingKey = settings.hasLlmApiKey ?? false
            mimoEndpoint = settings.llmEndpoint ?? ""
            mimoVisionModel = settings.llmModel ?? ""
        } catch {
            // 远程设置加载失败不阻塞使用
        }
        isLoading = false
    }

    private func saveSettings() {
        isSaving = true

        Task {
            do {
                let settings = UserSettings(
                    regionMode: regionMode,
                    llmProvider: "mimo",
                    llmApiKey: apiKeyModified && !mimoApiKey.isEmpty ? mimoApiKey : nil,
                    llmEndpoint: mimoEndpoint.isEmpty ? nil : mimoEndpoint,
                    llmModel: mimoVisionModel.isEmpty ? nil : mimoVisionModel,
                    llmSupportsSearch: false,
                    hasLlmApiKey: nil
                )
                _ = try await NetworkService.shared.updateSettings(settings)
                if apiKeyModified && !mimoApiKey.isEmpty {
                    hasExistingKey = true
                }
                mimoApiKey = ""
                apiKeyModified = false
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

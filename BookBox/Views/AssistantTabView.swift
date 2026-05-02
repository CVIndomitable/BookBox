import SwiftUI

/// 助手 Tab — 支持文字和语音输入/输出
struct AssistantTabView: View {
    @StateObject private var engine = AssistantEngine()
    @StateObject private var speechService = SpeechService()
    @StateObject private var ttsService = TextToSpeechService()
    @State private var input: String = ""
    @State private var autoPlayVoiceResponse = true
    @State private var showAuthAlert = false
    @FocusState private var isInputFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                replyArea

                Divider()

                if speechService.isRecording {
                    voiceRecordingIndicator
                }

                inputBar
            }
            .navigationTitle("助手")
            .navigationBarTitleDisplayMode(.inline)
            .onDisappear {
                engine.cancel()
                speechService.stopRecording()
                ttsService.stop()
            }
            .alert("需要语音识别权限", isPresented: $showAuthAlert) {
                Button("去设置") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("请在系统设置中允许 BookBox 访问语音识别功能")
            }
        }
    }

    private var replyArea: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if engine.reply.isEmpty && !engine.isProcessing && engine.errorMessage == nil {
                        placeholderHint
                    }

                    if !engine.reply.isEmpty {
                        Text(engine.reply)
                            .font(.body)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.accentColor.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .id("reply")
                    }

                    if engine.isProcessing {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("AI 处理中…")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 4)
                    }

                    if let err = engine.errorMessage {
                        Label(err, systemImage: "xmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
                .padding()
            }
            .onChange(of: engine.reply) { _, _ in
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo("reply", anchor: .bottom)
                }
            }
        }
    }

    private var placeholderHint: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("可以这样说", systemImage: "lightbulb")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("• 把《三体》放到客厅书架")
            Text("• 《解忧杂货店》在哪")
            Text("• 搬家 01 号箱有哪些书")
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var voiceRecordingIndicator: some View {
        HStack(spacing: 8) {
            Image(systemName: "waveform")
                .foregroundStyle(.red)
            Text(speechService.recognizedText.isEmpty ? "正在录音..." : speechService.recognizedText)
                .font(.callout)
                .foregroundStyle(.primary)
                .lineLimit(2)
            Spacer()
            Button("停止") {
                stopVoiceInput()
            }
            .font(.caption)
            .buttonStyle(.bordered)
            .tint(.red)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.red.opacity(0.1))
    }

    private var inputBar: some View {
        HStack(spacing: 8) {
            // 麦克风按钮
            Button {
                toggleVoiceInput()
            } label: {
                Image(systemName: speechService.isRecording ? "waveform.circle.fill" : "mic.circle")
                    .font(.system(size: 28))
                    .foregroundStyle(speechService.isRecording ? .red : .blue)
            }
            .disabled(engine.isProcessing)

            // 文本输入框
            TextField("输入指令，例如：找《三体》", text: $input, axis: .vertical)
                .lineLimit(1...4)
                .textFieldStyle(.roundedBorder)
                .focused($isInputFocused)
                .submitLabel(.send)
                .onSubmit {
                    submitText()
                }
                .disabled(speechService.isRecording)

            // 扬声器按钮
            Button {
                autoPlayVoiceResponse.toggle()
            } label: {
                Image(systemName: autoPlayVoiceResponse ? "speaker.wave.2.fill" : "speaker.slash.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(autoPlayVoiceResponse ? .blue : .secondary)
            }

            // 发送按钮
            Button {
                submitText()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(canSubmit ? Color.accentColor : Color.secondary)
            }
            .disabled(!canSubmit)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private var canSubmit: Bool {
        !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !engine.isProcessing &&
        !speechService.isRecording
    }

    private func toggleVoiceInput() {
        if speechService.isRecording {
            stopVoiceInput()
        } else {
            startVoiceInput()
        }
    }

    private func startVoiceInput() {
        // 检查权限
        speechService.requestAuthorization()

        // 等待权限状态更新
        Task {
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1秒

            guard speechService.isAuthorized else {
                showAuthAlert = true
                return
            }

            // 停止任何正在播放的语音
            ttsService.stop()

            // 清空输入和回复
            input = ""
            engine.reset()

            // 开始录音
            do {
                try speechService.startRecording()
            } catch {
                engine.errorMessage = "录音启动失败: \(error.localizedDescription)"
            }
        }
    }

    private func stopVoiceInput() {
        speechService.stopRecording()

        let text = speechService.recognizedText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty {
            submitVoiceInput(text: text)
        }
    }

    private func submitText() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        // 停止任何正在播放的语音
        ttsService.stop()

        engine.submit(text: text, rawInput: "Text: \(text)")
        input = ""
        isInputFocused = false

        // 文字输入时，只有手动开启扬声器才播放
        if autoPlayVoiceResponse {
            observeEngineCompletion()
        }
    }

    private func submitVoiceInput(text: String) {
        engine.submit(text: text, rawInput: "Voice: \(text)")

        // 语音输入时，如果开启了自动播放，等待 AI 回复完成后播放
        if autoPlayVoiceResponse {
            observeEngineCompletion()
        }
    }

    private func observeEngineCompletion() {
        Task {
            // 等待 AI 处理完成
            while engine.isProcessing {
                try? await Task.sleep(nanoseconds: 100_000_000) // 0.1秒
            }

            // 如果有回复且无错误，播放语音
            if !engine.reply.isEmpty && engine.errorMessage == nil {
                ttsService.speak(text: engine.reply)
            }
        }
    }
}

#Preview {
    AssistantTabView()
}

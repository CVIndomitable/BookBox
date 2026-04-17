import SwiftUI

/// 全局悬浮麦克风按钮 + 语音交互面板
/// 实际的指令解析和执行由 AssistantEngine 负责（和文字输入的"助手"Tab 共用）
struct VoiceAssistantButton: View {
    @StateObject private var speechService = SpeechService()
    @StateObject private var engine = AssistantEngine()
    @State private var isExpanded = false
    @GestureState private var dragOffset = CGSize.zero
    @State private var baseOffset = CGSize.zero

    var body: some View {
        VStack(spacing: 0) {
            if isExpanded {
                expandedPanel
            }

            Button {
                if isExpanded && !speechService.isRecording && !engine.isProcessing {
                    isExpanded = false
                    engine.reset()
                } else if !isExpanded {
                    isExpanded = true
                    speechService.requestAuthorization()
                }
            } label: {
                Image(systemName: speechService.isRecording ? "waveform.circle.fill" : "mic.circle.fill")
                    .font(.system(size: 52))
                    .foregroundStyle(speechService.isRecording ? .red : .accentColor)
                    .background(Circle().fill(.ultraThickMaterial).frame(width: 56, height: 56))
                    .shadow(radius: 4)
            }
            .accessibilityLabel(speechService.isRecording ? "停止录音" : "语音助手")
            .accessibilityHint(isExpanded ? "点击关闭语音面板" : "点击打开语音助手")
        }
        .offset(x: baseOffset.width + dragOffset.width, y: baseOffset.height + dragOffset.height)
        .gesture(
            DragGesture()
                .updating($dragOffset) { value, state, _ in
                    state = value.translation
                }
                .onEnded { value in
                    baseOffset.width += value.translation.width
                    baseOffset.height += value.translation.height
                }
        )
        .onDisappear {
            engine.cancel()
        }
    }

    private var expandedPanel: some View {
        VStack(spacing: 12) {
            if !speechService.recognizedText.isEmpty {
                Text(speechService.recognizedText)
                    .font(.body)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }

            if !engine.reply.isEmpty {
                ScrollView {
                    Text(engine.reply)
                        .font(.body)
                        .foregroundStyle(Color.accentColor)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 200)
                .padding(10)
                .background(Color.accentColor.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }

            if engine.isProcessing {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("AI 处理中…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let error = engine.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack(spacing: 16) {
                if speechService.isAuthorized {
                    Button {
                        if speechService.isRecording {
                            speechService.stopRecording()
                            let text = speechService.recognizedText
                            if !text.isEmpty {
                                engine.submit(text: text, rawInput: text)
                            }
                        } else {
                            engine.reset()
                            do {
                                try speechService.startRecording()
                            } catch {
                                engine.errorMessage = "录音启动失败: \(error.chineseDescription)"
                            }
                        }
                    } label: {
                        Label(
                            speechService.isRecording ? "停止" : "开始说话",
                            systemImage: speechService.isRecording ? "stop.circle.fill" : "mic.fill"
                        )
                        .font(.subheadline.weight(.medium))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(speechService.isRecording ? Color.red : Color.accentColor)
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                    }
                } else {
                    Text("请授权语音识别权限")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Button("授权") {
                        speechService.requestAuthorization()
                    }
                    .font(.caption)
                }
            }
        }
        .padding()
        .frame(width: 300)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(radius: 8)
        .padding(.bottom, 8)
    }
}

#Preview {
    VoiceAssistantButton()
}

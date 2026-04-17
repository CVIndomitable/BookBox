import SwiftUI

/// 助手 Tab — 文字输入模式下的入口
/// 跟悬浮麦克风面板共用 AssistantEngine，但输入走键盘而不是语音识别
struct AssistantTabView: View {
    @StateObject private var engine = AssistantEngine()
    @State private var input: String = ""
    @FocusState private var isInputFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                replyArea

                Divider()

                inputBar
            }
            .navigationTitle("助手")
            .navigationBarTitleDisplayMode(.inline)
            .onDisappear {
                engine.cancel()
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

    private var inputBar: some View {
        HStack(spacing: 8) {
            TextField("输入指令，例如：找《三体》", text: $input, axis: .vertical)
                .lineLimit(1...4)
                .textFieldStyle(.roundedBorder)
                .focused($isInputFocused)
                .submitLabel(.send)
                .onSubmit {
                    submit()
                }

            Button {
                submit()
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
        !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !engine.isProcessing
    }

    private func submit() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        engine.submit(text: text, rawInput: "Text: \(text)")
        input = ""
        isInputFocused = false
    }
}

#Preview {
    AssistantTabView()
}

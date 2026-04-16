import SwiftUI

/// 全局悬浮麦克风按钮 + 语音交互面板
struct VoiceAssistantButton: View {
    @StateObject private var speechService = SpeechService()
    @State private var isExpanded = false
    @State private var isProcessing = false
    @State private var aiReply = ""
    @State private var errorMessage: String?
    @GestureState private var dragOffset = CGSize.zero
    @State private var baseOffset = CGSize.zero
    @State private var processingTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            if isExpanded {
                expandedPanel
            }

            // 悬浮按钮
            Button {
                if isExpanded && !speechService.isRecording && !isProcessing {
                    isExpanded = false
                    aiReply = ""
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
            processingTask?.cancel()
            processingTask = nil
        }
    }

    private var expandedPanel: some View {
        VStack(spacing: 12) {
            // 识别文字展示
            if !speechService.recognizedText.isEmpty {
                Text(speechService.recognizedText)
                    .font(.body)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }

            // AI 回复
            if !aiReply.isEmpty {
                Text(aiReply)
                    .font(.body)
                    .foregroundStyle(Color.accentColor)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.accentColor.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }

            // 处理中
            if isProcessing {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("AI 思考中...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // 错误提示
            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            // 录音按钮
            HStack(spacing: 16) {
                if speechService.isAuthorized {
                    Button {
                        if speechService.isRecording {
                            speechService.stopRecording()
                            processVoiceCommand()
                        } else {
                            aiReply = ""
                            errorMessage = nil
                            do {
                                try speechService.startRecording()
                            } catch {
                                errorMessage = "录音启动失败: \(error.chineseDescription)"
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
        .frame(width: 280)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(radius: 8)
        .padding(.bottom, 8)
    }

    private func processVoiceCommand() {
        let text = speechService.recognizedText
        guard !text.isEmpty else { return }

        isProcessing = true
        errorMessage = nil

        processingTask?.cancel()
        processingTask = Task {
            do {
                // 获取当前书库状态作为上下文（多书库下按 lastLibraryId 过滤）
                let lastLibraryId = UserDefaults.standard.integer(forKey: "lastLibraryId")
                let libraryId: Int? = lastLibraryId > 0 ? lastLibraryId : nil
                let overview = try await NetworkService.shared.fetchLibraryOverview(libraryId: libraryId)

                // 构建房间名索引，供书架/箱子附带房间信息
                let roomName: (Int?) -> String? = { rid in
                    guard let rid, let rooms = overview.rooms else { return nil }
                    return rooms.first(where: { $0.id == rid })?.name
                }
                let context = LibraryContext(
                    rooms: overview.rooms?.map { .init(name: $0.name) },
                    shelves: overview.shelves.map { .init(name: $0.name, bookCount: $0.bookCount, roomName: roomName($0.roomId)) },
                    boxes: overview.boxes.map { .init(name: $0.name, uid: $0.boxUid, bookCount: $0.bookCount, roomName: roomName($0.roomId)) }
                )

                let result = try await NetworkService.shared.processVoiceCommand(text: text, context: context)
                aiReply = (result.cached == true ? "⚡ " : "") + result.reply

                // 执行指令
                try await executeCommand(result)
            } catch {
                errorMessage = error.chineseDescription
            }
            isProcessing = false
        }
    }

    private func executeCommand(_ result: VoiceCommandResult) async throws {
        let stored = UserDefaults.standard.integer(forKey: "lastLibraryId")
        let libraryId: Int? = stored > 0 ? stored : nil

        switch result.action {
        case "move":
            guard let bookTitle = result.bookTitle, let target = result.target else { return }
            // 在当前书库范围搜索书籍
            let searchResult = try await NetworkService.shared.fetchBooks(search: bookTitle, libraryId: libraryId)
            guard let book = searchResult.data.first else { return }

            // 查找目标（限定在当前书库）
            if target.type == "shelf" {
                let shelves = try await NetworkService.shared.fetchShelves(libraryId: libraryId)
                if let shelf = shelves.first(where: { $0.name.contains(target.name) }) {
                    let req = MoveBookRequest(toType: .shelf, toId: shelf.id, method: "voice", rawInput: speechService.recognizedText)
                    _ = try await NetworkService.shared.moveBook(id: book.id, request: req)
                }
            } else if target.type == "box" {
                let boxes = try await NetworkService.shared.fetchBoxes(libraryId: libraryId)
                if let box = boxes.first(where: { $0.name.contains(target.name) }) {
                    let req = MoveBookRequest(toType: .box, toId: box.id, method: "voice", rawInput: speechService.recognizedText)
                    _ = try await NetworkService.shared.moveBook(id: book.id, request: req)
                }
            }

        case "query":
            // 查询类指令，AI 回复已包含信息，无需额外操作
            break

        default:
            break
        }
    }
}

#Preview {
    VoiceAssistantButton()
}

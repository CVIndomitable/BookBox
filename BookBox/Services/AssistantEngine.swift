import Foundation
import SwiftUI

/// 助手交互模式
/// - off：完全关闭，没有悬浮按钮、没有助手 Tab
/// - voice：右下角悬浮麦克风（原行为）
/// - text：底部多一个"助手"Tab，键盘输入，不显示悬浮按钮
enum AssistantMode: String, CaseIterable, Identifiable {
    case off
    case voice
    case text

    var id: String { rawValue }

    var label: String {
        switch self {
        case .off: "关闭"
        case .voice: "语音悬浮"
        case .text: "文字输入"
        }
    }
}

/// 助手执行引擎 — 被悬浮麦克风按钮和"助手"文字 Tab 共用
/// 负责：
/// 1. 把输入文本发给服务器端 LLM 解析意图（move/query/edit/list）
/// 2. 执行指令，跨书库查找书籍和目标容器
/// 3. 把每一步的进度写到 reply，让用户看到 AI 在做什么
@MainActor
final class AssistantEngine: ObservableObject {
    @Published var reply: String = ""
    @Published var isProcessing: Bool = false
    @Published var errorMessage: String?
    @Published var supplier: SupplierMeta?

    private var task: Task<Void, Never>?

    /// 清空状态，准备新一轮输入
    func reset() {
        reply = ""
        errorMessage = nil
        supplier = nil
    }

    /// 取消当前执行（页面消失时调用）
    func cancel() {
        task?.cancel()
        task = nil
    }

    /// 提交一段文本，走 LLM 解析 + 执行 + 级联反馈
    /// rawInput 会写到 book_logs 的 raw_input，便于溯源（语音 or 文字）
    func submit(text: String, rawInput: String? = nil) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        task?.cancel()
        reply = ""
        errorMessage = nil
        isProcessing = true

        task = Task { [weak self] in
            guard let self else { return }
            defer { self.isProcessing = false }

            do {
                // 构建书库上下文（当前 lastLibraryId）
                let stored = UserDefaults.standard.integer(forKey: "lastLibraryId")
                let libraryId: Int? = stored > 0 ? stored : nil
                let overview = try await NetworkService.shared.fetchLibraryOverview(libraryId: libraryId)

                let roomName: (Int?) -> String? = { rid in
                    guard let rid, let rooms = overview.rooms else { return nil }
                    return rooms.first(where: { $0.id == rid })?.name
                }
                let context = LibraryContext(
                    rooms: overview.rooms?.map { .init(name: $0.name) },
                    shelves: overview.shelves.map { .init(name: $0.name, bookCount: $0.bookCount, roomName: roomName($0.roomId)) },
                    boxes: overview.boxes.map { .init(name: $0.name, uid: $0.boxUid, bookCount: $0.bookCount, roomName: roomName($0.roomId)) }
                )

                let result = try await NetworkService.shared.processVoiceCommand(text: trimmed, context: context)
                self.supplier = result.supplier
                self.reply = (result.cached == true ? "⚡ " : "") + result.reply

                try await self.execute(result: result, rawInput: rawInput ?? trimmed)
            } catch {
                self.errorMessage = error.chineseDescription
            }
        }
    }

    // MARK: - 执行指令

    private func execute(result: VoiceCommandResult, rawInput: String) async throws {
        switch result.action {
        case "move":
            guard let bookTitle = result.bookTitle, let target = result.target else { return }
            await streamingMove(bookTitle: bookTitle, target: target, rawInput: rawInput)

        case "query":
            if let bookTitle = result.bookTitle, !bookTitle.isEmpty {
                await streamingFindBook(bookTitle: bookTitle, fallbackReply: result.reply)
            }

        default:
            break
        }
    }

    // MARK: - 查书：级联 + 每步反馈

    /// 当前库 DB → 当前库 AI → 其他库 DB → 跨库 AI 兜底
    private func streamingFindBook(bookTitle: String, fallbackReply: String) async {
        let stored = UserDefaults.standard.integer(forKey: "lastLibraryId")
        let currentLibraryId: Int? = stored > 0 ? stored : nil
        let libraries = (try? await NetworkService.shared.fetchLibraries()) ?? []
        guard !libraries.isEmpty else {
            appendLine("还没有建立任何书库")
            return
        }

        var queue: [Library] = []
        if let cid = currentLibraryId, let cur = libraries.first(where: { $0.id == cid }) {
            queue.append(cur)
            queue.append(contentsOf: libraries.filter { $0.id != cid })
        } else {
            queue = libraries
        }

        for (idx, lib) in queue.enumerated() {
            appendLine("🔍 在《\(lib.name)》查找…")
            do {
                let dbOnly = try await NetworkService.shared.findBookSmart(query: bookTitle, libraryId: lib.id, useAI: false)
                if let book = dbOnly.books.first {
                    let loc = await Self.locationDescription(for: book, libraryId: lib.id)
                    let tag = dbOnly.method == "loose" ? "（近似匹配）" : ""
                    appendLine("✅ \(loc)\(tag)")
                    return
                }
                if idx == 0 {
                    appendLine("当前书库精确/近似都没找到，尝试 AI 模糊匹配…")
                    let ai = try await NetworkService.shared.findBookSmart(query: bookTitle, libraryId: lib.id, useAI: true)
                    if let book = ai.books.first {
                        let loc = await Self.locationDescription(for: book, libraryId: lib.id)
                        appendLine("✅ AI 模糊匹配到：\(loc)")
                        return
                    }
                    appendLine("当前书库没有这本书，继续去其他书库找…")
                }
            } catch {
                appendLine("《\(lib.name)》查询失败：\(error.chineseDescription)")
            }
        }

        appendLine("所有书库 DB 都没找到，做最后一次跨库 AI 匹配…")
        do {
            let cross = try await NetworkService.shared.findBookSmart(query: bookTitle, libraryId: nil, useAI: true)
            if let book = cross.books.first {
                let libName = libraries.first(where: { $0.id == book.libraryId })?.name ?? "其他书库"
                let loc = await Self.locationDescription(for: book, libraryId: book.libraryId)
                appendLine("✅ AI 在《\(libName)》找到最接近的一本：\(loc)")
                return
            }
        } catch {
            appendLine("跨库 AI 查询失败：\(error.chineseDescription)")
        }

        appendLine("😕 所有书库都没找到《\(bookTitle)》")
        if !fallbackReply.isEmpty {
            appendLine(fallbackReply)
        }
    }

    // MARK: - 移书：跨库

    /// 先找书（任何书库），再找目标容器（任何书库），最后移动
    /// 后端 /books/:id/move 会根据目标容器的 libraryId 同步更新 book.libraryId
    private func streamingMove(bookTitle: String, target: VoiceCommandResult.VoiceTarget, rawInput: String) async {
        appendLine("🔍 定位书籍《\(bookTitle)》…")
        let book: Book
        do {
            let r = try await NetworkService.shared.findBookSmart(query: bookTitle, libraryId: nil, useAI: true)
            guard let b = r.books.first else {
                appendLine("😕 所有书库都没找到《\(bookTitle)》，无法移动")
                return
            }
            book = b
            let libName: String
            if let lid = b.libraryId {
                let libs = (try? await NetworkService.shared.fetchLibraries()) ?? []
                libName = libs.first(where: { $0.id == lid })?.name ?? "未知书库"
            } else {
                libName = "无归属书库"
            }
            appendLine("✅ 找到《\(b.title)》（在《\(libName)》）")
        } catch {
            appendLine("查找书籍失败：\(error.chineseDescription)")
            return
        }

        appendLine("🔍 定位目标「\(target.name)」…")
        switch target.type {
        case "shelf":
            do {
                let shelves = try await NetworkService.shared.fetchShelves(libraryId: nil)
                guard let shelf = shelves.first(where: { $0.name.contains(target.name) }) else {
                    appendLine("😕 没有找到名为「\(target.name)」的书架")
                    return
                }
                let req = MoveBookRequest(toType: .shelf, toId: shelf.id, method: "voice", rawInput: rawInput)
                _ = try await NetworkService.shared.moveBook(id: book.id, request: req)
                appendLine("✅ 已把《\(book.title)》移到书架「\(shelf.name)」")
            } catch {
                appendLine("移动失败：\(error.chineseDescription)")
            }
        case "box":
            do {
                let boxes = try await NetworkService.shared.fetchBoxes(libraryId: nil)
                guard let box = boxes.first(where: { $0.name.contains(target.name) }) else {
                    appendLine("😕 没有找到名为「\(target.name)」的箱子")
                    return
                }
                let req = MoveBookRequest(toType: .box, toId: box.id, method: "voice", rawInput: rawInput)
                _ = try await NetworkService.shared.moveBook(id: book.id, request: req)
                appendLine("✅ 已把《\(book.title)》移到箱子「\(box.name)」")
            } catch {
                appendLine("移动失败：\(error.chineseDescription)")
            }
        default:
            appendLine("暂不支持的目标类型：\(target.type)")
        }
    }

    // MARK: - Helpers

    private func appendLine(_ line: String) {
        if reply.isEmpty {
            reply = line
        } else {
            reply = reply + "\n" + line
        }
    }

    private static func locationDescription(for book: Book, libraryId: Int?) async -> String {
        let title = "《\(book.title)》"
        switch book.locationType {
        case .shelf:
            let shelves = (try? await NetworkService.shared.fetchShelves(libraryId: libraryId)) ?? []
            let name = shelves.first(where: { $0.id == book.locationId })?.name ?? "未知书架"
            return "\(title)在书架「\(name)」"
        case .box:
            let boxes = (try? await NetworkService.shared.fetchBoxes(libraryId: libraryId)) ?? []
            let name = boxes.first(where: { $0.id == book.locationId })?.name ?? "未知箱子"
            return "\(title)在箱子「\(name)」"
        default:
            return "\(title)还未归位"
        }
    }
}

import SwiftUI

@main
struct BookBoxApp: App {
    var body: some Scene {
        WindowGroup {
            HomeView()
                .overlay(alignment: .top) {
                    SupplierDegradationBanner()
                }
                .withVoiceAssistant()
        }
    }
}

/// 语音助手悬浮按钮修饰器
///
/// SwiftUI 的 `.overlay` 只会覆盖自身视图，`.fullScreenCover` 呈现的全屏模态会盖住根
/// 视图上的 overlay，因此需要在每个可能全屏展示的场景（如扫描入口的两个 cover）内部
/// 也应用一次此修饰器，保证悬浮按钮在任何场景都可见。
struct VoiceAssistantOverlay: ViewModifier {
    @AppStorage("assistantMode") private var assistantModeRaw: String = AssistantMode.off.rawValue

    func body(content: Content) -> some View {
        content.overlay(alignment: .bottomTrailing) {
            // 仅在"语音悬浮"模式显示悬浮按钮；"文字输入"模式走底部 Tab，不在这里显示
            if AssistantMode(rawValue: assistantModeRaw) == .voice {
                VoiceAssistantButton()
                    .padding()
            }
        }
    }
}

extension View {
    func withVoiceAssistant() -> some View {
        modifier(VoiceAssistantOverlay())
    }
}

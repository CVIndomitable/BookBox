import SwiftUI

@main
struct BookBoxApp: App {
    @AppStorage("voiceControlEnabled") private var voiceControlEnabled = false

    var body: some Scene {
        WindowGroup {
            HomeView()
                .overlay(alignment: .bottomTrailing) {
                    if voiceControlEnabled {
                        VoiceAssistantButton()
                            .padding()
                    }
                }
        }
    }
}

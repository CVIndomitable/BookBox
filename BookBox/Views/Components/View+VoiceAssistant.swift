import SwiftUI

extension View {
    func withVoiceAssistant() -> some View {
        self.overlay(alignment: .bottomTrailing) {
            VoiceAssistantButton()
                .padding(.trailing, 12)
                .padding(.bottom, 60)
        }
    }
}

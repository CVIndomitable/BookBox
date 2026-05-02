import SwiftUI

@main
struct BookBoxApp: App {
    @StateObject private var auth = AuthService.shared

    var body: some Scene {
        WindowGroup {
            Group {
                if auth.isLoggedIn {
                    HomeView()
                        .overlay(alignment: .top) {
                            SupplierDegradationBanner()
                        }
                        .withVoiceAssistant()
                } else {
                    LoginView()
                }
            }
        }
    }
}

import SwiftUI

@main
struct BookBoxApp: App {
    var body: some Scene {
        WindowGroup {
            HomeView()
                .overlay(alignment: .top) {
                    SupplierDegradationBanner()
                }
        }
    }
}

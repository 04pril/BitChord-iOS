import SwiftUI

/// Uses the existing app-local tunnel core. No Network Extension entitlement.
struct ProxySettingsScreen: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> YTMUWGSettingsController {
        YTMUWGSettingsController()
    }
    func updateUIViewController(_ controller: YTMUWGSettingsController, context: Context) {}
}

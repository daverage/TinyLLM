import SwiftUI

@main
struct TinyLLMApp: App {
    @NSApplicationDelegateAdaptor(TinyLLMAppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            SettingsHubView()
                .environmentObject(appDelegate.manager)
        }
    }
}

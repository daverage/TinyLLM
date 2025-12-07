import SwiftUI

struct SettingsHubView: View {
    var body: some View {
        TabView {
            ModelManagerView()
                .tabItem {
                    Label("Models", systemImage: "square.stack.3d.down.forward")
                }

            AdvancedSettingsView()
                .tabItem {
                    Label("Advanced", systemImage: "slider.horizontal.3")
                }

            BuildPanelView()
                .tabItem {
                    Label("Build", systemImage: "hammer")
                }
        }
        .tabViewStyle(.automatic)
        .frame(minWidth: 720, minHeight: 550)
    }
}

struct SettingsWindow: Scene {
    let manager: LLMManager

    var body: some Scene {
        Settings {
            SettingsHubView()
                .environmentObject(manager)
        }
    }
}

import SwiftUI

enum SidebarSection: String, CaseIterable, Identifiable {
    case home = "Home"
    case models = "Models"
    case advanced = "Advanced"
    case logs = "Logs"
    case build = "Build"

    var id: String { rawValue }

    var iconName: String {
        switch self {
        case .home: return "house"
        case .models: return "square.stack.3d.down.forward"
        case .advanced: return "slider.horizontal.3"
        case .logs: return "scroll"
        case .build: return "hammer"
        }
    }
}

struct AppSidebar: View {
    @EnvironmentObject var manager: LLMManager
    @State private var selection: SidebarSection = .home
    @State private var showDiagnostics = false

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            content
        }
        .frame(minWidth: 950, minHeight: 650)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("TinyLLM")
                .font(.title2.weight(.bold))
                .padding(.vertical, 12)

            ForEach(SidebarSection.allCases) { section in
                Button {
                    selection = section
                } label: {
                    HStack {
                        Image(systemName: section.iconName)
                        Text(section.rawValue)
                    }
                    .foregroundColor(selection == section ? .primary : .secondary)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(selection == section ? Color(NSColor.controlAccentColor).opacity(0.18) : Color.clear)
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }

            Spacer()

            Button {
                withAnimation { showDiagnostics.toggle() }
            } label: {
                Label("Diagnostics", systemImage: "waveform.path.ecg")
            }
            .buttonStyle(.bordered)

            Button("Refresh Metrics") {
                manager.requestRuntimeUpdate()
            }
            .buttonStyle(.bordered)

        }
        .padding(12)
        .frame(width: 220)
        .background(Color(NSColor.windowBackgroundColor))
    }

    @ViewBuilder
    private var content: some View {
        ZStack(alignment: .topTrailing) {
            switch selection {
            case .home:
                MainWindowView()
            case .models:
                ModelManagerView()
            case .advanced:
                AdvancedSettingsView()
            case .logs:
                LogsPaneView()
            case .build:
                BuildPanelView()
            }
            DiagnosticsOverlay(isVisible: $showDiagnostics)
                .padding()
        }
    }
}

struct AppSidebar_Previews: PreviewProvider {
    static var previews: some View {
        AppSidebar()
            .environmentObject(LLMManager())
    }
}

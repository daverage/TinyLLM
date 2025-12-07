import SwiftUI

struct BuildPanelView: View {
    @EnvironmentObject var manager: LLMManager
    @State private var autoStart = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
            Text("Build llama.cpp")
                .font(.title2)
                .fontWeight(.semibold)

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                infoRow(label: "Hardware", value: manager.hardwareSummary)
                infoRow(label: "Last build duration", value: lastBuildDurationText)
                infoRow(label: "Status", value: manager.statusText)
                infoRow(label: "Health", value: manager.healthNote)
            }

            Toggle("Start server automatically after rebuild", isOn: $autoStart)

            Button(action: {
                manager.rebuildLlamaCPP(autoStartAfter: autoStart)
            }) {
                Text("Rebuild llama.cpp")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Divider()

            Text("Build log")
                .font(.headline)

            ScrollView {
                Text(trimmedLog)
                    .font(.system(.caption, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
            }
            .frame(minHeight: 200)
            .background(Color(NSColor.textBackgroundColor))
            .cornerRadius(10)
            }
            .padding()
        }
    }

    private func infoRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.body)
                .multilineTextAlignment(.trailing)
        }
    }

    private var lastBuildDurationText: String {
        if let duration = manager.lastBuildDurationSeconds {
            return String(format: "%.1fs", duration)
        }
        return "Not built yet"
    }

    private var trimmedLog: String {
        manager.logTail
            .components(separatedBy: "\n")
            .filter { !$0.isEmpty }
            .suffix(20)
            .joined(separator: "\n")
    }
}

struct BuildPanelView_Previews: PreviewProvider {
    static var previews: some View {
        BuildPanelView()
            .environmentObject(LLMManager())
    }
}

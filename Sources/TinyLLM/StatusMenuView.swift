import SwiftUI
import AppKit

struct StatusMenuView: View {
    @EnvironmentObject var manager: LLMManager
    let onShowMainWindow: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            serverSummary
            SafeguardBadgesView(manager: manager)
            controlButtons
            Divider()
            modelPicker
            Divider()
            showMainButton
            quitButton
        }
        .padding(12)
        .frame(minWidth: 280)
    }

    private var serverSummary: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("Server Control", systemImage: "bolt.horizontal.circle")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text(manager.healthState.rawValue.capitalized)
                    .font(.caption2)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.12))
                    .foregroundColor(Color.accentColor)
                    .clipShape(Capsule())
            }
            Text("CPU \(manager.runtimeMetrics.llmCPUDisplay) · Memory \(manager.runtimeMetrics.memorySummary)")
                .font(.caption2)
                .foregroundColor(.secondary)
            Text(manager.statusText)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var controlButtons: some View {
        HStack {
            Button("Start") { manager.startServer() }
                .controlSize(.small)
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .disabled(manager.isRunning)

            Button("Stop") { manager.stopServer() }
                .controlSize(.small)
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(!manager.isRunning)
        }
    }

    private var modelPicker: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Model")
                .font(.caption)
                .foregroundColor(.secondary)
            Picker("Model", selection: $manager.selectedModel) {
                ForEach(manager.availableModels) { model in
                    Text(model.filename).tag(Optional(model))
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
        }
    }

    private var showMainButton: some View {
        Button {
            onShowMainWindow()
        } label: {
            Text("Show Main Window")
                .frame(maxWidth: .infinity)
        }
        .controlSize(.small)
        .buttonStyle(.bordered)
    }

    private var quitButton: some View {
        Button("Quit TinyLLM") {
            onDismiss()
            NSApplication.shared.terminate(nil)
        }
        .controlSize(.small)
        .buttonStyle(.bordered)
        .tint(.red.opacity(0.8))
    }
}

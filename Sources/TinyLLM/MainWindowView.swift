import SwiftUI

struct MainWindowView: View {
    @EnvironmentObject var manager: LLMManager

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
            
            // MARK: - Header + Health Indicator
            headerSection
            
            Divider()
            
            // MARK: - Model Selection
            modelSelection
            
            Divider()
            
            // MARK: - Settings Summary
            recommendedSettingsSection
            
            Divider()
            
            // MARK: - Live Metrics
            metricsSection
            
            Divider()
            
            // MARK: - Server Controls
            controlButtons
            
            Divider()
            
            // MARK: - Logs
            logViewer
            
            }
            .padding()
            .frame(minWidth: 650)
        }
        .frame(minHeight: 650)
    }
}

// MARK: - Header Section
private extension MainWindowView {
    var headerSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("TinyLLM Host")
                    .font(.title)
                    .fontWeight(.semibold)
                
                Text(manager.hardwareSummary)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text("GPU: \(manager.gpuSummary)")
                    .font(.caption2)
                    .foregroundColor(.secondary)

                SafeguardBadgesView(manager: manager)
                    .padding(.top, 6)
            }
            
            Spacer()
            
            VStack(alignment: .trailing) {
                Text(manager.healthNote)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(healthColor.opacity(0.2))
                    .foregroundColor(healthColor)
                    .cornerRadius(4)
                
                Text("Status: \(manager.statusText)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    var healthColor: Color {
        switch manager.healthState {
        case .healthy: return .green
        case .starting: return .orange
        case .degraded: return .yellow
        case .crashed: return .red
        case .stopped: return .secondary
        }
    }
}

// MARK: - Model Selection
private extension MainWindowView {
    var modelSelection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Model")
                .font(.headline)
            
            HStack {
                Picker("Model", selection: $manager.selectedModel) {
                    ForEach(manager.availableModels) { model in
                        Text(model.filename).tag(Optional(model))
                    }
                }
                
                Button("Refresh") {
                    manager.refreshModels()
                }
            }
            
            if let model = manager.selectedModel {
                Text("Selected: \(model.filename)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                Text("No model selected")
                    .font(.caption)
                    .foregroundColor(.red)
            }
        }
    }
}

// MARK: - Recommended Settings Section
private extension MainWindowView {
    var recommendedSettingsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Recommended Settings")
                .font(.headline)
            
            Text(manager.recommendedSummary)
                .font(.caption)
                .foregroundColor(.secondary)
            
            if let warn = manager.contextWarning {
                Text("⚠️ \(warn)")
                    .font(.caption)
                    .foregroundColor(.orange)
            }
        }
    }
}

// MARK: - Metrics Section
private extension MainWindowView {
    var metricsSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Live Metrics")
                .font(.headline)
            
            HStack(spacing: 20) {
                metricBox(title: "CPU", value: manager.cpuPercent)
                metricBox(title: "Memory", value: manager.memPercent)
                metricBox(title: "Context", value: "\(manager.effectiveCtxSize)")
                metricBox(title: "Threads", value: "\(manager.threadCount)")
            }
        }
    }
    
    func metricBox(title: String, value: String) -> some View {
        VStack {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.system(size: 16, weight: .semibold))
        }
        .frame(maxWidth: .infinity)
        .padding(6)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }
}

// MARK: - Control Buttons
private extension MainWindowView {
    var controlButtons: some View {
        HStack(spacing: 12) {
            Button("Start") {
                manager.startServer()
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
            .controlSize(.large)
            .disabled(manager.isRunning)

            Button("Stop") {
                manager.stopServer()
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .controlSize(.large)
            .disabled(!manager.isRunning)

            Spacer()

            Button("Apply Recommended") {
                manager.applyRecommendedSettings()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }
}

// MARK: - Logs
private extension MainWindowView {
    var logViewer: some View {
        VStack(alignment: .leading) {
            Text("Logs")
                .font(.headline)
            
            ScrollView {
                Text(manager.logTail)
                    .font(.system(.caption, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
            }
            .frame(minHeight: 200)
            .background(Color(NSColor.textBackgroundColor))
            .cornerRadius(8)
        }
    }
}

import SwiftUI

struct AdvancedSettingsView: View {
    
    @EnvironmentObject var manager: LLMManager
    
    private let gridColumns = [GridItem(.adaptive(minimum: 340, maximum: 420), spacing: 20, alignment: .top)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
            LazyVGrid(columns: gridColumns, spacing: 20) {
                contextSection
                performanceProfileSection
                gpuSection
                kvCacheSection
                ropeScalingSection
                extraArgsSection
                    autoMemorySection
                    recommendedSection
                    debugSection
                }
                HStack {
                    Spacer()
                    Button("Close") {
                        NSApplication.shared.keyWindow?.close()
                    }
                    .buttonStyle(.bordered)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
    }
}

// MARK: - Header

private extension AdvancedSettingsView {
    var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Advanced Settings")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Fine-tune llama.cpp runtime behaviour. These settings are applied the next time the server starts.")
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Context / Batch / Threads

private extension AdvancedSettingsView {
    var contextSection: some View {
        settingsCard(title: "Context & Performance", icon: "speedometer") {
            VStack(alignment: .leading, spacing: 12) {
                
                Toggle("Manual Context Override", isOn: $manager.manualContextOverride)
                    .font(.subheadline)
                
                HStack {
                    Text("Context Size")
                    Spacer()
                    Text("\(manager.ctxSize)")
                }
                Slider(value: Binding(
                    get: { Double(manager.ctxSize) },
                    set: { manager.ctxSize = Int($0) }
                ), in: 1024...65536, step: 1024)
                
                HStack {
                    Text("Batch Size")
                    Spacer()
                    Text("\(manager.batchSize)")
                }
                Slider(value: Binding(
                    get: { Double(manager.batchSize) },
                    set: { manager.batchSize = Int($0) }
                ), in: 64...2048, step: 64)
                
                HStack {
                    Text("Threads")
                    Spacer()
                    Text("\(manager.threadCount)")
                }
                Slider(value: Binding(
                    get: { Double(manager.threadCount) },
                    set: { manager.threadCount = Int($0) }
                ), in: 1...Double(manager.maxThreadCount), step: 1)
                
                if let warning = manager.contextWarning {
                    Text("⚠️ \(warning)")
                        .font(.caption)
                        .foregroundColor(.orange)
                        .padding(.top, 4)
                }
                }
                .padding(.top, 4)
        }
    }

    var performanceProfileSection: some View {
        settingsCard(title: "Performance Profile", icon: "dial.max") {
            VStack(alignment: .leading, spacing: 12) {
                Picker("Performance Profile", selection: $manager.hostPerformanceProfile) {
                    ForEach(HostPerformanceProfile.allCases) { profile in
                        Text(profile.label).tag(profile)
                    }
                }
                .pickerStyle(.segmented)

                Text(manager.hostPerformanceProfile.detail)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 4)
        }
    }
}

// MARK: - Auto Memory Safeguards

private extension AdvancedSettingsView {
    var autoMemorySection: some View {
        settingsCard(title: "Auto Memory Safeguards", icon: "thermometer") {
            VStack(alignment: .leading, spacing: 10) {
                Toggle("Stop server on sustained high memory pressure", isOn: $manager.autoThrottleMemory)
                Toggle("Throttle context/batch automatically when memory pressure spikes", isOn: $manager.autoReduceRuntimeOnPressure)
                Toggle("Switch to a smaller quant variant when needed", isOn: $manager.autoSwitchQuantOnPressure)
                Text("These options hook into the memory monitor; when the pressure reaches the 'High' threshold, the selected safeguards run automatically.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 4)
        }
    }
}

// MARK: - GPU Settings

private extension AdvancedSettingsView {
    var gpuSection: some View {
        settingsCard(title: "GPU Acceleration", icon: "bolt.circle") {
            VStack(alignment: .leading, spacing: 12) {
                Picker("Aggressiveness", selection: $manager.gpuAggressiveness) {
                    ForEach(GPUAggressiveness.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                HStack {
                    Text("GPU Layers")
                    Spacer()
                    Text("\(manager.nGpuLayers)")
                }
                Slider(value: Binding(
                    get: { Double(manager.nGpuLayers) },
                    set: { manager.nGpuLayers = Int($0) }
                ), in: 0...999, step: 1)

                Text("Recommended base: \(manager.recommendedGpuLayerBase) layers")
                    .font(.caption2)
                    .foregroundColor(.secondary)

                Toggle("Flash Attention (Metal-optimized)", isOn: $manager.enableFlashAttention)
                    .disabled(!manager.flashAttentionSupported)
                
                if !manager.flashAttentionSupported {
                    Text("Flash Attention not available on this build.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                
            }
            .padding(.top, 4)
        }
    }
}

// MARK: - KV Cache Types

private extension AdvancedSettingsView {
    var kvCacheSection: some View {
        settingsCard(title: "KV Cache Quantization", icon: "memorychip") {
            VStack(alignment: .leading, spacing: 12) {
                
                HStack {
                    Picker("K Cache", selection: $manager.cacheTypeK) {
                        Text("q4_0").tag("q4_0")
                        Text("q4_1").tag("q4_1")
                        Text("q5_0").tag("q5_0")
                        Text("q5_1").tag("q5_1")
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity)

                    Picker("V Cache", selection: $manager.cacheTypeV) {
                        Text("q4_0").tag("q4_0")
                        Text("q4_1").tag("q4_1")
                        Text("q5_0").tag("q5_0")
                        Text("q5_1").tag("q5_1")
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity)
                }
                
                Toggle("Auto-adjust KV Cache (Host may override)", isOn: $manager.enableAutoKV)
                
            }
            .padding(.top, 4)
        }
    }
}

// MARK: - Rope Scaling

private extension AdvancedSettingsView {
    var ropeScalingSection: some View {
        settingsCard(title: "RoPE Scaling", icon: "chart.bar") {
            VStack(alignment: .leading, spacing: 12) {
                
                Toggle("Enable RoPE Scaling", isOn: $manager.enableRopeScaling)
                
                if manager.enableRopeScaling {
                    HStack {
                        Text("Scale")
                        Spacer()
                        Text(String(format: "%.1f", manager.ropeScalingValue))
                    }
                    Slider(value: $manager.ropeScalingValue, in: 0.5...4.0, step: 0.1)
                }
                
                Text("RoPE scaling helps preserve attention range at high context sizes.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.top, 2)
            }
            .padding(.top, 4)
        }
    }
}

// MARK: - Extra Args

private extension AdvancedSettingsView {
    var extraArgsSection: some View {
        settingsCard(title: "Raw Extra Arguments", icon: "terminal") {
            VStack(alignment: .leading, spacing: 10) {
                TextEditor(text: $manager.extraArgsRaw)
                    .font(.system(.caption, design: .monospaced))
                    .frame(minHeight: 80)
                    .border(Color.gray.opacity(0.3), width: 1)
                
                Text("These are appended as-is to llama-server’s launch arguments.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

// MARK: - Recommended Settings

private extension AdvancedSettingsView {
    var recommendedSection: some View {
        settingsCard(title: "Recommended Tuning", icon: "slider.horizontal.3") {
            VStack(alignment: .leading, spacing: 10) {
                
                Toggle("Auto-apply Recommended Settings", isOn: $manager.autoApplyRecommended)
                
                Text(manager.recommendedSummary)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.bottom, 4)
                
                Button("Apply Recommended Now") {
                    manager.applyRecommendedSettings()
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    var debugSection: some View {
        settingsCard(title: "Diagnostics", icon: "ant") {
            Toggle("Enable Debug Logging", isOn: $manager.debugMode)
                .font(.subheadline)
        }
    }
}

// MARK: - Shared Card Styling

private extension AdvancedSettingsView {
    func settingsCard<Content: View>(title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundColor(.accentColor)
                Text(title)
                    .font(.headline)
                Spacer()
            }
            Divider()
                .padding(.vertical, 2)
            content()
        }
        .padding(16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.primary.opacity(0.08))
        )
    }
}

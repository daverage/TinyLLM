import SwiftUI

struct ModelManagerView: View {
    @EnvironmentObject var manager: LLMManager

    private static let bytesFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        return formatter
    }()

    private static let relativeDateFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 12) {
                    headerRow
                    statusRow
                    profileButtonsSection
                }

                modelLibrarySection

                huggingFaceLink

                presetDownloadsSection

                customDownloadSection
            }
            .padding()
        }
    }

    private var huggingFaceURL: URL {
        URL(string: "https://huggingface.co/models")!
    }

    private var huggingFaceLink: some View {
        Link(destination: huggingFaceURL) {
            HStack(spacing: 4) {
                Image(systemName: "link")
                Text("Browse Hugging Face models")
            }
            .font(.caption)
            .foregroundColor(.accentColor)
        }
    }

    private var headerRow: some View {
        HStack {
            Text("Model Manager")
                .font(.title2)
                .fontWeight(.semibold)
            Spacer()
            Button {
                manager.benchmarkSelectedModel()
            } label: {
                Label("Benchmark Selected", systemImage: "gauge")
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var statusRow: some View {
        HStack {
            Text(manager.statusText)
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            Text(manager.healthState.rawValue.capitalized)
                .font(.caption2)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(6)
        }
    }

    private var profileButtonsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Profile", selection: $manager.profile) {
                ForEach(LLMProfile.allCases) { profile in
                    Text(profile.label).tag(profile)
                }
            }
            .pickerStyle(.segmented)
            Text(manager.profileDetail)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private var modelLibrarySection: some View {
        GroupBox(label: headerLabel("Model Library")) {
            VStack(alignment: .leading, spacing: 12) {
                if manager.availableModels.isEmpty {
                    Text("No models detected yet. Download or refresh to populate the list.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    ForEach(manager.availableModels) { model in
                        modelRow(for: model)
                    }
                }
            }
            .padding(.vertical, 4)
        }
        .animation(.default, value: manager.availableModels.count)
    }

    private func modelRow(for model: LLMModel) -> some View {
        let record = manager.modelRecord(for: model)
        return Button {
            manager.selectedModel = model
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.filename)
                        .font(.headline)

                    HStack(spacing: 12) {
                        Text(Self.bytesFormatter.string(fromByteCount: record?.sizeBytes ?? 0))
                        separator
                        Text(String(format: "%.1fB params", record?.approxBillions ?? 0))
                        separator
                        Text("Last seen \(formatted(date: record?.lastSeen))")
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing) {
                    if manager.selectedModel == model {
                        Label("Selected", systemImage: "checkmark.circle.fill")
                            .labelStyle(.iconOnly)
                            .foregroundColor(.accentColor)
                    }
                    Text("TPS \(formatted(tps: record?.lastTPS))")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(manager.selectedModel == model ? Color.accentColor : Color(NSColor.separatorColor))
            )
        }
                .buttonStyle(.plain)
    }

    private var presetDownloadsSection: some View {
        GroupBox(label: headerLabel("Preset Downloads")) {
            VStack(spacing: 8) {
                ForEach(manager.presets) { preset in
                    Button {
                        manager.downloadPreset(preset)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(preset.label)
                                .font(.headline)
                            Text(preset.filename)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.bordered)
                }
            }

            Button("Rescan Models") {
                manager.refreshModels()
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var customDownloadSection: some View {
        GroupBox(label: headerLabel("Custom Download")) {
            VStack(alignment: .leading, spacing: 12) {
                TextField("Model URL", text: $manager.customURL)
                    .textFieldStyle(.roundedBorder)
                TextField("Filename.gguf", text: $manager.customFilename)
                    .textFieldStyle(.roundedBorder)

                Button("Download Custom Model") {
                    manager.downloadCustom()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.vertical, 4)
        }
    }

    private func formatted(date: Date?) -> String {
        guard let date = date else { return "unknown" }
        return Self.relativeDateFormatter.localizedString(for: date, relativeTo: Date())
    }

    private func formatted(tps: Double?) -> String {
        guard let tps = tps else { return "—" }
        return String(format: "%.1f", tps)
    }

    private var separator: some View {
        Text("•")
    }

    private func headerLabel(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(.headline)
            Spacer()
        }
    }

    private let profileOptions: [(LLMProfile, String)] = [
        (.coding, "Coder"),
        (.creative, "Creative"),
        (.balanced, "Conversation")
    ]
}

struct ModelManagerView_Previews: PreviewProvider {
    static var previews: some View {
        ModelManagerView()
            .environmentObject(LLMManager())
    }
}

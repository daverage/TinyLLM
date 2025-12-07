import SwiftUI

struct DiagnosticsOverlay: View {
    @Binding var isVisible: Bool
    @EnvironmentObject var manager: LLMManager

    var body: some View {
        if isVisible {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Diagnostics")
                        .font(.headline)
                    Spacer()
                    Button(action: { isVisible = false }) {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                }

                HStack(spacing: 12) {
                    pulse
                    VStack(alignment: .leading, spacing: 6) {
                        statRow(label: "CPU", value: manager.cpuPercent)
                        statRow(label: "Memory", value: manager.memPercent)
                        statRow(label: "Health", value: manager.healthState.rawValue.capitalized)
                        statRow(label: "Model", value: manager.selectedModel?.filename ?? "None")
                        statRow(label: "Temp State", value: manager.thermalState.rawValue.capitalized)
                    }
                }
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor).opacity(0.9))
            .cornerRadius(16)
            .shadow(radius: 10)
            .frame(maxWidth: 280)
            .transition(.move(edge: .trailing).combined(with: .opacity))
        }
    }

    private func statRow(label: String, value: String) -> some View {
        HStack {
            Text("\(label):")
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.caption)
                .fontWeight(.semibold)
        }
    }

    private var pulse: some View {
        Circle()
            .fill(pulseColor)
            .frame(width: 16, height: 16)
            .shadow(color: pulseColor.opacity(0.6), radius: 6, x: 0, y: 0)
    }

    private var pulseColor: Color {
        switch manager.thermalState {
        case .nominal: return .green
        case .moderate: return .yellow
        case .heavy: return .orange
        case .hotspot: return .red
        }
    }
}

struct DiagnosticsOverlay_Previews: PreviewProvider {
    struct Wrapper: View {
        @State var visible = true
        var body: some View {
            DiagnosticsOverlay(isVisible: $visible)
        }
    }

    static var previews: some View {
        Wrapper()
            .environmentObject(LLMManager())
    }
}

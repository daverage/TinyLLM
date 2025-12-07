import SwiftUI

struct SafeguardBadgesView: View {
    @ObservedObject var manager: LLMManager

    var body: some View {
        if badgeItems.isEmpty {
            Text("Auto safeguards are off")
                .font(.caption2)
                .foregroundColor(.secondary)
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(badgeItems) { badge in
                        Text(badge.label)
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .padding(.vertical, 2)
                            .padding(.horizontal, 8)
                            .background(badge.color.opacity(0.18))
                            .foregroundColor(badge.color)
                            .clipShape(Capsule())
                    }
                }
            }
        }
    }

    private var badgeItems: [SafeguardBadgeItem] {
        var items: [SafeguardBadgeItem] = []

        if manager.autoThrottleMemory {
            items.append(.init(label: "Stop on memory pressure", color: .red))
        }
        if manager.autoReduceRuntimeOnPressure {
            items.append(.init(label: "Auto throttle ctx/batch", color: .orange))
        }
        if manager.autoSwitchQuantOnPressure {
            items.append(.init(label: "Auto switch quant", color: .green))
        }

        return items
    }
}

private struct SafeguardBadgeItem: Identifiable {
    let id = UUID()
    let label: String
    let color: Color
}

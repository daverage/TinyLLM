import SwiftUI

struct LogsPaneView: View {
    @EnvironmentObject var manager: LLMManager

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Logs")
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
                Text(manager.healthState.rawValue.capitalized)
                    .font(.caption)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(6)
            }

            ScrollView {
                Text(manager.logTail)
                    .font(.system(.caption, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
            }
            .background(Color(NSColor.textBackgroundColor))
            .cornerRadius(10)
            .shadow(color: Color.black.opacity(0.08), radius: 4, x: 0, y: 2)
        }
        .padding()
    }
}

struct LogsPaneView_Previews: PreviewProvider {
    static var previews: some View {
        LogsPaneView()
            .environmentObject(LLMManager())
    }
}

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

                Button("Clear Logs") {
                    manager.clearLogs()
                }
                .buttonStyle(.bordered)

                Text(manager.healthState.rawValue.capitalized)
                    .font(.caption)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(6)
            }

            Picker("Log Source", selection: $manager.logDisplayMode) {
                ForEach(LogDisplayMode.allCases) { source in
                    Text(source.label).tag(source)
                }
            }
            .pickerStyle(.segmented)

            LogViewerComponent(logText: manager.logTail, minHeight: nil, padding: 10, isSelectable: true)
                .cornerRadius(10)
                .shadow(color: Color.black.opacity(0.08), radius: 4, x: 0, y: 2)
        }
        .padding()
    }
}

// MARK: - Shared Log Viewer Component

struct LogViewerComponent: View {
    let logText: String
    var minHeight: CGFloat? = 200
    var padding: CGFloat = 8
    var isSelectable: Bool = false

    var body: some View {
        if isSelectable {
            SelectableTextView(text: logText)
                .modifier(ConditionalMinHeight(minHeight: minHeight))
                .background(Color(NSColor.textBackgroundColor))
                .cornerRadius(8)
        } else {
            ScrollView {
                Text(logText)
                    .font(.system(.caption, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(padding)
            }
            .modifier(ConditionalMinHeight(minHeight: minHeight))
            .background(Color(NSColor.textBackgroundColor))
            .cornerRadius(8)
        }
    }
}

// MARK: - Selectable Text View (using NSTextView)

struct SelectableTextView: NSViewRepresentable {
    let text: String

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        let textView = scrollView.documentView as! NSTextView

        textView.isEditable = false
        textView.isSelectable = true
        textView.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        textView.textColor = .labelColor
        textView.backgroundColor = .textBackgroundColor
        textView.textContainerInset = NSSize(width: 10, height: 10)
        textView.autoresizingMask = [.width, .height]

        // Set initial text
        textView.string = text

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        if textView.string != text {
            textView.string = text
            // Auto-scroll to bottom
            textView.scrollToEndOfDocument(nil)
        }
    }
}

private struct ConditionalMinHeight: ViewModifier {
    let minHeight: CGFloat?

    func body(content: Content) -> some View {
        if let minHeight = minHeight {
            content.frame(minHeight: minHeight)
        } else {
            content
        }
    }
}

struct LogsPaneView_Previews: PreviewProvider {
    static var previews: some View {
        LogsPaneView()
            .environmentObject(LLMManager())
    }
}

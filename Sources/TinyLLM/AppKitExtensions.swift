import AppKit

extension NSApplication {
    /// Provide a simple implementation that matches the old AppKit selector.
    @objc func showAllWindows(_ sender: Any?) {
        for window in windows {
            window.orderFront(sender)
        }
    }
}

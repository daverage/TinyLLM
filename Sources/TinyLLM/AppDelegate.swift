import SwiftUI
import AppKit

@MainActor
final class TinyLLMAppDelegate: NSObject, NSApplicationDelegate {

    let manager = LLMManager()

    private var windowController: NSWindowController?
    private var statusItemController: StatusItemController?
    private var metricsTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.regular)
        configureStatusItem()
        startMetricsTimer()
        Task { @MainActor in
            manager.updateMetrics()
            manager.refreshThermalState()
        }
        showMainWindow()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showMainWindow()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        manager.stopServerBlocking(statusNote: "Shutting down")
        metricsTimer?.invalidate()
        metricsTimer = nil
    }

    @objc func showMainWindow(_ sender: Any? = nil) {
        if windowController == nil {
            windowController = makeWindowController()
        }
        guard let controller = windowController else { return }
        controller.showWindow(sender)
        controller.window?.makeKeyAndOrderFront(sender)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    private func configureStatusItem() {
        statusItemController = StatusItemController(
            manager: manager,
            showMainWindow: { [weak self] in
                self?.showMainWindow()
            }
        )
    }

    private func startMetricsTimer() {
        metricsTimer?.invalidate()
        metricsTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.manager.updateMetrics()
                self.manager.refreshThermalState()
            }
        }
        if let timer = metricsTimer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    private func makeWindowController() -> NSWindowController {
        let rootView = AppSidebar()
            .environmentObject(manager)
        let hosting = NSHostingController(rootView: rootView)

        let window = NSWindow(contentViewController: hosting)
        window.setContentSize(NSSize(width: 1000, height: 700))
        window.center()
        window.title = "TinyLLM"
        window.isReleasedWhenClosed = false

        let controller = NSWindowController(window: window)
        controller.windowFrameAutosaveName = "TinyLLMMainWindow"
        return controller
    }
}

// MARK: - Status Item Controller

@MainActor
final class StatusItemController {
    private let manager: LLMManager
    private let showMainWindow: () -> Void
    private let statusItem: NSStatusItem
    private let popover = NSPopover()

    init(manager: LLMManager, showMainWindow: @escaping () -> Void) {
        self.manager = manager
        self.showMainWindow = showMainWindow
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        configureStatusItem()
    }

    private func configureStatusItem() {
        popover.behavior = .transient
        popover.animates = true

        guard let button = statusItem.button else { return }
        button.image = NSImage(systemSymbolName: "brain.head.profile", accessibilityDescription: "TinyLLM")
        button.target = self
        button.action = #selector(togglePopover(_:))
    }

    @objc private func togglePopover(_ sender: Any?) {
        if popover.isShown {
            hidePopover()
        } else {
            showPopover()
        }
    }

    private func showPopover() {
        guard let button = statusItem.button else { return }
        let content = StatusMenuView(
            onShowMainWindow: { [weak self] in
                self?.showMainWindow()
                self?.hidePopover()
            },
            onDismiss: { [weak self] in
                self?.hidePopover()
            }
        )
        .environmentObject(manager)

        let hosting = NSHostingController(rootView: content)
        popover.contentViewController = hosting
        popover.contentSize = NSSize(width: 300, height: 360)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }

    private func hidePopover() {
        popover.performClose(nil)
        popover.contentViewController = nil
    }
}

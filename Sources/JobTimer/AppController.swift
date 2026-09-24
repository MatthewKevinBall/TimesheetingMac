import AppKit
import Carbon
import SwiftUI
import UserNotifications

/// Borderless panel that can take keyboard focus (for the quick switcher).
final class KeyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// Lets buttons in the floating timer respond to the first click even when the app isn't active.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

@MainActor
final class AppController: NSObject, NSWindowDelegate, UNUserNotificationCenterDelegate {
    static let shared = AppController()

    let store = Store.shared
    private var floatingPanel: NSPanel?
    private var switcherPanel: KeyPanel?
    private var mainWindow: NSWindow?
    private var hotKey: HotKey?
    private var idleMonitor: IdleMonitor?
    private var defaultsObserver: NSObjectProtocol?

    private var notificationsAvailable: Bool { Bundle.main.bundleIdentifier != nil }

    func launch() {
        Prefs.registerDefaults()
        store.recoverAfterLaunch()
        applySettings()

        hotKey = HotKey(keyCode: kVK_ANSI_T, modifiers: cmdKey | optionKey, id: 1) { [weak self] in
            self?.toggleQuickSwitcher()
        }

        idleMonitor = IdleMonitor(store: store)
        idleMonitor?.start()

        if notificationsAvailable {
            let center = UNUserNotificationCenter.current()
            center.delegate = self
            center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
        }

        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.applySettings() }
        }

        if store.jobs.isEmpty { showMainWindow(tab: .jobs) }
    }

    func terminate() {
        store.prepareForQuit()
    }

    /// Idempotent — called whenever UserDefaults change.
    func applySettings() {
        let policy: NSApplication.ActivationPolicy = Prefs.showInDock ? .regular : .accessory
        if NSApp.activationPolicy() != policy {
            NSApp.setActivationPolicy(policy)
            if policy == .accessory, mainWindow?.isVisible == true {
                DispatchQueue.main.async { NSApp.activate(ignoringOtherApps: true) }
            }
        }
        if Prefs.showFloating {
            showFloatingPanel()
        } else if floatingPanel?.isVisible == true {
            floatingPanel?.orderOut(nil)
        }
    }

    // MARK: - Floating timer

    private func showFloatingPanel() {
        if floatingPanel == nil { floatingPanel = makeFloatingPanel() }
        if let p = floatingPanel, !p.isVisible { p.orderFrontRegardless() }
    }

    private func makeFloatingPanel() -> NSPanel {
        let size = NSSize(width: FloatingTimerView.width, height: FloatingTimerView.height)
        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: size),
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        panel.contentView = FirstMouseHostingView(rootView: FloatingTimerView())

        if !panel.setFrameUsingName("FloatingTimer"), let screen = NSScreen.main {
            let vf = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: vf.maxX - size.width - 20, y: vf.maxY - size.height - 12))
        }
        panel.setFrameAutosaveName("FloatingTimer")
        return panel
    }

    // MARK: - Quick switcher

    func toggleQuickSwitcher() {
        if let p = switcherPanel, p.isVisible { closeQuickSwitcher() } else { showQuickSwitcher() }
    }

    func showQuickSwitcher() {
        let panel = switcherPanel ?? makeSwitcherPanel()
        switcherPanel = panel
        // Fresh view each time so the search field starts empty.
        panel.contentView = NSHostingView(rootView: QuickSwitcherView { [weak self] in self?.closeQuickSwitcher() })

        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        if let vf = screen?.visibleFrame {
            let size = panel.frame.size
            panel.setFrameOrigin(NSPoint(x: vf.midX - size.width / 2, y: vf.minY + vf.height * 0.62 - size.height / 2))
        }
        panel.makeKeyAndOrderFront(nil)
    }

    func closeQuickSwitcher() {
        switcherPanel?.orderOut(nil)
    }

    private func makeSwitcherPanel() -> KeyPanel {
        let panel = KeyPanel(contentRect: NSRect(x: 0, y: 0, width: QuickSwitcherView.width, height: QuickSwitcherView.height),
                             styleMask: [.borderless, .nonactivatingPanel],
                             backing: .buffered, defer: false)
        panel.level = .modalPanel
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.delegate = self
        return panel
    }

    func windowDidResignKey(_ notification: Notification) {
        if (notification.object as? NSWindow) === switcherPanel { closeQuickSwitcher() }
    }

    // MARK: - Main window

    func showMainWindow(tab: MainTab? = nil) {
        if let tab { store.mainTab = tab }
        if mainWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 620),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable],
                                  backing: .buffered, defer: false)
            window.title = "Job Timer"
            window.isReleasedWhenClosed = false
            let host = NSHostingController(rootView: MainView())
            host.sizingOptions = []
            window.contentViewController = host
            window.setContentSize(NSSize(width: 900, height: 620))
            if !window.setFrameUsingName("MainWindow") { window.center() }
            window.setFrameAutosaveName("MainWindow")
            mainWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        mainWindow?.makeKeyAndOrderFront(nil)
    }

    // MARK: - URL scheme

    /// jobtimer://switch, jobtimer://stop, jobtimer://timesheet, jobtimer://start?job=4521
    func handle(_ url: URL) {
        guard url.scheme == "jobtimer" else { return }
        switch url.host {
        case "switch":
            showQuickSwitcher()
        case "stop":
            store.stop()
        case "timesheet":
            showMainWindow(tab: .timesheet)
        case "start":
            let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first { $0.name == "job" }?.value ?? ""
            if let job = store.filteredJobs(query).first, !query.isEmpty {
                store.start(job)
            } else {
                showQuickSwitcher()
            }
        default:
            break
        }
    }

    // MARK: - Notifications

    func notify(id: String, title: String, body: String, action: String) {
        guard notificationsAvailable else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.userInfo = ["action": action]
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        let action = response.notification.request.content.userInfo["action"] as? String
        Task { @MainActor in
            if action == "timesheet" {
                AppController.shared.showMainWindow(tab: .timesheet)
            } else {
                AppController.shared.showQuickSwitcher()
            }
        }
        completionHandler()
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}

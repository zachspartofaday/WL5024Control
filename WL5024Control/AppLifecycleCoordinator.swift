import AppKit
import CoreServices

@MainActor
final class AppLifecycleCoordinator {
    enum WindowID: String {
        case settings
        case diagnostics
    }

    static let shared = AppLifecycleCoordinator()

    private var forceLoginLaunch = false
    private var didFinishLaunching = false
    private var isLoginLaunch = false
    private var didHandleInitialLaunch = false
    private var openWindow: ((WindowID) -> Void)?
    private var visibleWindows: Set<WindowID> = []

    func configure(arguments: [String]) {
        forceLoginLaunch = arguments.contains("--ui-login-launch")
    }

    func installWindowOpener(_ opener: @escaping (WindowID) -> Void) {
        openWindow = opener
        handleInitialLaunchIfReady()
    }

    func completeLaunch(loginItemEvent: Bool) {
        didFinishLaunching = true
        isLoginLaunch = forceLoginLaunch || loginItemEvent
        handleInitialLaunchIfReady()
    }

    func show(_ window: WindowID) {
        guard let openWindow else { return }
        NSApp.setActivationPolicy(.regular)
        openWindow(window)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowAppeared(_ window: WindowID) {
        visibleWindows.insert(window)
        if NSApp.activationPolicy() != .regular {
            NSApp.setActivationPolicy(.regular)
        }
    }

    func windowDisappeared(_ window: WindowID) {
        visibleWindows.remove(window)
        Task { @MainActor in
            guard self.visibleWindows.isEmpty else { return }
            NSApp.setActivationPolicy(.accessory)
        }
    }

    private func handleInitialLaunchIfReady() {
        guard didFinishLaunching, openWindow != nil, !didHandleInitialLaunch else { return }
        didHandleInitialLaunch = true
        if !isLoginLaunch { show(.settings) }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppLifecycleCoordinator.shared.completeLaunch(loginItemEvent: launchedAsLoginItem)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        AppLifecycleCoordinator.shared.show(.settings)
        return false
    }

    private var launchedAsLoginItem: Bool {
        guard let event = NSAppleEventManager.shared().currentAppleEvent,
              let descriptor = event.paramDescriptor(forKeyword: AEKeyword(keyAEPropData)) else {
            return false
        }
        return descriptor.typeCodeValue == OSType(keyAELaunchedAsLogInItem)
    }
}

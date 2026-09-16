import SwiftUI
import WL5024ControlFeature

@main
struct WL5024ControlApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model: HeadsetModel
    @State private var launchAtLogin: LaunchAtLoginModel
    private let profile: LaunchProfile
    private let lifecycle = AppLifecycleCoordinator.shared

    init() {
        let profile = LaunchProfile(arguments: ProcessInfo.processInfo.arguments)
        self.profile = profile
        _model = State(initialValue: profile.makeModel())
        _launchAtLogin = State(initialValue: profile.makeLaunchAtLoginModel())
        AppLifecycleCoordinator.shared.configure(arguments: ProcessInfo.processInfo.arguments)
    }

    var body: some Scene {
        Window("WL5024 Control", id: AppLifecycleCoordinator.WindowID.settings.rawValue) {
            SettingsWindowRoot(
                model: model,
                launchAtLogin: launchAtLogin,
                profile: profile,
                lifecycle: lifecycle
            )
        }
        .defaultSize(
            width: profile.minimumWindow ? 640 : 720,
            height: 520
        )
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)
        .windowToolbarStyle(.unified)

        Window("Diagnostics", id: AppLifecycleCoordinator.WindowID.diagnostics.rawValue) {
            DiagnosticsWindowRoot(model: model, profile: profile, lifecycle: lifecycle)
        }
        .defaultSize(width: 880, height: 620)
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)
        .windowToolbarStyle(.unified)

        MenuBarExtra {
            MenuBarContent(model: model, lifecycle: lifecycle)
        } label: {
            MenuBarSceneLabel(model: model, lifecycle: lifecycle)
        }
        .menuBarExtraStyle(.menu)
    }
}

private struct SettingsWindowRoot: View {
    @Environment(\.openWindow) private var openWindow
    let model: HeadsetModel
    let launchAtLogin: LaunchAtLoginModel
    let profile: LaunchProfile
    let lifecycle: AppLifecycleCoordinator

    var body: some View {
        HeadsetSettingsView(
            model: model,
            launchAtLogin: launchAtLogin,
            openDiagnostics: { lifecycle.show(.diagnostics) }
        )
        .preferredColorScheme(profile.colorScheme)
        .onAppear {
            installWindowOpener()
            lifecycle.windowAppeared(.settings)
        }
        .onDisappear { lifecycle.windowDisappeared(.settings) }
        .task { await model.start() }
    }

    private func installWindowOpener() {
        lifecycle.installWindowOpener { id in openWindow(id: id.rawValue) }
    }
}

private struct DiagnosticsWindowRoot: View {
    @Environment(\.openWindow) private var openWindow
    let model: HeadsetModel
    let profile: LaunchProfile
    let lifecycle: AppLifecycleCoordinator

    var body: some View {
        HeadsetDiagnosticsView(model: model)
            .navigationTitle("Diagnostics")
            .preferredColorScheme(profile.colorScheme)
            .frame(minWidth: 720, minHeight: 500)
            .onAppear {
                lifecycle.installWindowOpener { id in openWindow(id: id.rawValue) }
                lifecycle.windowAppeared(.diagnostics)
            }
            .onDisappear { lifecycle.windowDisappeared(.diagnostics) }
            .task { await model.start() }
    }
}

private struct MenuBarContent: View {
    @Environment(\.openWindow) private var openWindow
    let model: HeadsetModel
    let lifecycle: AppLifecycleCoordinator

    var body: some View {
        HeadsetMenuBarView(
            model: model,
            openSettings: { lifecycle.show(.settings) },
            openDiagnostics: { lifecycle.show(.diagnostics) }
        )
        .onAppear { installWindowOpener() }
        .task { await model.start() }
    }

    private func installWindowOpener() {
        lifecycle.installWindowOpener { id in openWindow(id: id.rawValue) }
    }
}

private struct MenuBarSceneLabel: View {
    @Environment(\.openWindow) private var openWindow
    let model: HeadsetModel
    let lifecycle: AppLifecycleCoordinator

    var body: some View {
        MenuBarLabel(model: model)
            .onAppear {
                lifecycle.installWindowOpener { id in openWindow(id: id.rawValue) }
            }
            .task { await model.start() }
    }
}

struct LaunchProfile {
    let demoMode: Bool
    let readOnlyMode: Bool
    let experimentalMode: Bool
    let bluetoothPermissionDenied: Bool
    let minimumWindow: Bool
    let colorScheme: ColorScheme?
    let fastDiscovery: Bool
    let loginItemState: LaunchAtLoginState?

    init(arguments: [String]) {
        demoMode = arguments.contains("--demo")
        readOnlyMode = arguments.contains("--read-only")
        experimentalMode = arguments.contains("--experimental")
        bluetoothPermissionDenied = arguments.contains("--ui-bluetooth-denied")
        minimumWindow = arguments.contains("--ui-minimum")
        fastDiscovery = arguments.contains("--ui-fast-discovery")
        colorScheme = arguments.contains("--appearance-light")
            ? .light
            : arguments.contains("--appearance-dark") ? .dark : nil
        if arguments.contains("--ui-login-enabled") {
            loginItemState = .enabled
        } else if arguments.contains("--ui-login-approval") {
            loginItemState = .requiresApproval
        } else if arguments.contains("--ui-login-disabled") || arguments.contains("--ui-login-launch") {
            loginItemState = .disabled
        } else {
            loginItemState = nil
        }
    }

    @MainActor
    func makeLaunchAtLoginModel() -> LaunchAtLoginModel {
        if let loginItemState { return LaunchAtLoginModel(mockState: loginItemState) }
        return LaunchAtLoginModel()
    }

    @MainActor
    func makeModel() -> HeadsetModel {
        if bluetoothPermissionDenied {
            return HeadsetModel(demoMode: false, controller: MockHeadsetController(
                snapshot: HeadsetSnapshot(connection: .bluetoothPermissionDenied)
            ))
        }
        if experimentalMode { return makeExperimentalModel() }
        guard readOnlyMode else {
            guard demoMode else { return HeadsetModel() }
            return HeadsetModel(
                demoMode: true,
                controller: MockHeadsetController(discoveryStepDelay: mockDiscoveryDelay)
            )
        }
        let capabilities = Set(HeadsetSettingKey.allCases)
        let snapshot = HeadsetSnapshot(
            connection: .connected(.bluetooth),
            device: .init(
                headsetFirmware: "Unverified",
                batteryPercent: 82,
                transport: .bluetooth
            ),
            capabilities: capabilities,
            values: Dictionary(uniqueKeysWithValues: capabilities.map { ($0, $0.defaultValue) }),
            readiness: Dictionary(uniqueKeysWithValues: capabilities.map { key in
                (key, CapabilityCatalog.configurableSettings.contains(key) ? .readOnly : .validationPending)
            }),
            valueConfidence: Dictionary(uniqueKeysWithValues: capabilities.map { ($0, .simulated) })
        )
        return HeadsetModel(
            demoMode: false,
            controller: MockHeadsetController(snapshot: snapshot, discoveryStepDelay: mockDiscoveryDelay)
        )
    }

    @MainActor
    private func makeExperimentalModel() -> HeadsetModel {
        let capabilities = Set(HeadsetSettingKey.allCases)
        let experimentalKeys = Set(CapabilityCatalog.experimentalSettings)
        let readOnlyKeys = Set(CapabilityCatalog.readOnlySettings)
        let snapshot = HeadsetSnapshot(
            connection: .connected(.bluetooth),
            device: .init(
                headsetFirmware: "Unverified",
                batteryPercent: 82,
                transport: .bluetooth
            ),
            capabilities: capabilities,
            values: [:],
            readiness: Dictionary(uniqueKeysWithValues: capabilities.map { key in
                if experimentalKeys.contains(key) { return (key, .experimental) }
                if readOnlyKeys.contains(key) { return (key, .readOnly) }
                return (key, .validationPending)
            })
        )
        return HeadsetModel(
            demoMode: false,
            controller: MockHeadsetController(snapshot: snapshot, discoveryStepDelay: mockDiscoveryDelay)
        )
    }

    private var mockDiscoveryDelay: Duration {
        fastDiscovery ? .milliseconds(1) : .milliseconds(100)
    }
}

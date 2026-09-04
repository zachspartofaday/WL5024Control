import SwiftUI
import WL5024ControlFeature

@main
struct WL5024ControlApp: App {
    @State private var model: HeadsetModel
    private let profile: LaunchProfile

    init() {
        let profile = LaunchProfile(arguments: ProcessInfo.processInfo.arguments)
        self.profile = profile
        _model = State(initialValue: profile.makeModel())
    }

    var body: some Scene {
        Window("WL5024 Control", id: "settings") {
            HeadsetSettingsView(model: model)
                .preferredColorScheme(profile.colorScheme)
                .frame(
                    width: profile.minimumWindow ? 720 : nil,
                    height: profile.minimumWindow ? 500 : nil
                )
                .task {
                    await model.start()
                }
        }
        .defaultSize(
            width: profile.minimumWindow ? 720 : 880,
            height: profile.minimumWindow ? 500 : 620
        )

        MenuBarExtra {
            HeadsetMenuBarView(model: model)
                .task {
                    await model.start()
                }
        } label: {
            MenuBarLabel(model: model)
        }
        .menuBarExtraStyle(.menu)
    }
}

private struct LaunchProfile {
    let demoMode: Bool
    let readOnlyMode: Bool
    let experimentalMode: Bool
    let minimumWindow: Bool
    let colorScheme: ColorScheme?
    let fastDiscovery: Bool

    init(arguments: [String]) {
        demoMode = arguments.contains("--demo")
        readOnlyMode = arguments.contains("--read-only")
        experimentalMode = arguments.contains("--experimental")
        minimumWindow = arguments.contains("--ui-minimum")
        fastDiscovery = arguments.contains("--ui-fast-discovery")
        colorScheme = arguments.contains("--appearance-light")
            ? .light
            : arguments.contains("--appearance-dark") ? .dark : nil
    }

    @MainActor
    func makeModel() -> HeadsetModel {
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
                (key, key == .automaticMedia ? .readOnly : .validationPending)
            }),
            valueConfidence: Dictionary(uniqueKeysWithValues: capabilities.map { ($0, .simulated) })
        )
        return HeadsetModel(
            demoMode: false,
            controller: MockHeadsetController(
                snapshot: snapshot,
                discoveryStepDelay: mockDiscoveryDelay
            )
        )
    }

    @MainActor
    private func makeExperimentalModel() -> HeadsetModel {
        let capabilities = Set(HeadsetSettingKey.allCases)
        let experimentalKeys = Set(CapabilityCatalog.experimentalSettings)
        let readOnlyKeys = Set(CapabilityCatalog.interactiveSettings).subtracting(experimentalKeys)
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
            controller: MockHeadsetController(
                snapshot: snapshot,
                discoveryStepDelay: mockDiscoveryDelay
            )
        )
    }

    private var mockDiscoveryDelay: Duration {
        fastDiscovery ? .milliseconds(1) : .milliseconds(100)
    }
}

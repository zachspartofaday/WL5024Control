import Foundation
import Observation

@MainActor
@Observable
public final class HeadsetModel {
    public private(set) var snapshot: HeadsetSnapshot
    public var selectedPage: SettingsPage? = .overview
    public private(set) var pendingSettings: Set<HeadsetSettingKey> = []
    public var errorMessage: String?
    public private(set) var didStart = false
    public let demoMode: Bool

    private let controller: any HeadsetController
    private var eventTask: Task<Void, Never>?

    public init(demoMode: Bool = false) {
        self.demoMode = demoMode
        controller = demoMode ? MockHeadsetController() : LiveHeadsetController()
        snapshot = demoMode
            ? .demo()
            : HeadsetSnapshot(
                connection: .idle,
                capabilities: Set(HeadsetSettingKey.allCases),
                values: Dictionary(uniqueKeysWithValues: HeadsetSettingKey.allCases.map { ($0, $0.defaultValue) })
            )
    }

    public func start() async {
        guard !didStart else { return }
        didStart = true
        let events = await controller.events()
        eventTask = Task { @MainActor [weak self] in
            for await event in events {
                guard let self else { return }
                switch event {
                case .snapshot(let newSnapshot): snapshot = newSnapshot
                case .error(let error): errorMessage = error.localizedDescription
                }
            }
        }
        await controller.start()
    }

    public func refresh() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                snapshot = try await controller.refresh()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    public func set(_ key: HeadsetSettingKey, to value: SettingValue) {
        guard !pendingSettings.contains(key) else { return }
        pendingSettings.insert(key)
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { pendingSettings.remove(key) }
            do {
                snapshot = try await controller.set(key, value: value)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    public func perform(_ key: HeadsetSettingKey) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                snapshot = try await controller.perform(key)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    public func value(for key: HeadsetSettingKey) -> SettingValue {
        snapshot.values[key] ?? key.defaultValue
    }

    public func dismissError() {
        errorMessage = nil
    }

    public func collectDiagnosticReport() async throws -> Data {
        if case .connected = snapshot.connection {
            do {
                snapshot = try await controller.refresh()
            } catch {
                DiagnosticRecorder.shared.record(
                    "capture",
                    "Safe automatic-media query failed",
                    details: ["error": error.localizedDescription]
                )
            }
        }
        DiagnosticRecorder.shared.record(
            "capture",
            "Diagnostic report requested",
            details: ["demoMode": demoMode.description]
        )
        return try DiagnosticRecorder.shared.encodedReport(snapshot: snapshot)
    }
}

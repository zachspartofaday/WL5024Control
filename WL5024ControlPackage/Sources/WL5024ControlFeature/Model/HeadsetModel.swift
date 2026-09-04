import Foundation
import Observation

@MainActor
@Observable
public final class HeadsetModel {
    public private(set) var snapshot: HeadsetSnapshot
    public var selectedPage: SettingsPage? = .overview
    public private(set) var pendingSettings: Set<HeadsetSettingKey> = []
    public private(set) var failure: HeadsetFailure?
    public private(set) var isCommandInFlight = false
    public private(set) var discoveryState: ReadOnlyDiscoveryState = .idle
    public private(set) var discoveryProgress: ReadOnlyDiscoveryProgress?
    public private(set) var lastDiscoverySummary: ReadOnlyDiscoverySummary?
    public private(set) var didStart = false
    public let demoMode: Bool

    private let controller: any HeadsetController
    private var eventTask: Task<Void, Never>?
    private var commandTask: Task<Void, Never>?
    private var queuedCommands: [QueuedCommand] = []
    private var activeCommand: QueuedCommand?
    private var retryCommand: QueuedCommand?
    private var lastAppliedRevision: UInt64 = 0

    public convenience init(demoMode: Bool = false) {
        self.init(
            demoMode: demoMode,
            controller: demoMode ? MockHeadsetController() : LiveHeadsetController()
        )
    }

    public init(demoMode: Bool, controller: any HeadsetController) {
        self.demoMode = demoMode
        self.controller = controller
        snapshot = demoMode
            ? .demo()
            : HeadsetSnapshot(
                connection: .idle,
                capabilities: Set(HeadsetSettingKey.allCases),
                readiness: Dictionary(
                    uniqueKeysWithValues: HeadsetSettingKey.allCases.map { ($0, .unavailable) }
                )
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
                case .snapshot(let update):
                    apply(update)
                case .error(let error):
                    present(error, retrying: .reconnect)
                }
            }
        }
        apply(await controller.start())
    }

    public func stop() async {
        eventTask?.cancel()
        eventTask = nil
        commandTask?.cancel()
        commandTask = nil
        queuedCommands.removeAll()
        pendingSettings.removeAll()
        isCommandInFlight = false
        discoveryState = .idle
        discoveryProgress = nil
        lastDiscoverySummary = nil
        apply(await controller.stop())
        didStart = false
    }

    @discardableResult
    public func refresh() -> Task<Void, Never> {
        enqueue(.refresh)
    }

    @discardableResult
    public func set(_ key: HeadsetSettingKey, to value: SettingValue) -> Task<Void, Never> {
        guard snapshot.readiness(for: key).allowsWrite else {
            present(.unsupported(key), retrying: nil)
            return Task {}
        }
        return enqueue(.set(key, value))
    }

    @discardableResult
    public func perform(_ key: HeadsetSettingKey) -> Task<Void, Never> {
        guard snapshot.readiness(for: key).allowsWrite else {
            present(.unsupported(key), retrying: nil)
            return Task {}
        }
        return enqueue(.action(key))
    }

    public func value(for key: HeadsetSettingKey) -> SettingValue? {
        snapshot.values[key]
    }

    public func readiness(for key: HeadsetSettingKey) -> CapabilityReadiness {
        snapshot.readiness(for: key)
    }

    public func dismissFailure() {
        failure = nil
    }

    public func retryLastAction() {
        guard let retryCommand else { return }
        failure = nil
        enqueue(retryCommand)
    }

    @discardableResult
    public func reconnect() -> Task<Void, Never> {
        failure = nil
        return enqueue(.reconnect)
    }

    @discardableResult
    public func runReadOnlyDiscovery() -> Task<Void, Never> {
        guard discoveryState != .running else { return commandTask ?? Task {} }
        discoveryState = .running
        discoveryProgress = nil
        lastDiscoverySummary = nil
        return enqueue(.discovery)
    }

    public func cancelReadOnlyDiscovery() {
        guard discoveryState == .running else { return }
        if let activeCommand, activeCommand.isDiscovery {
            queuedCommands.removeAll()
            commandTask?.cancel()
        } else {
            queuedCommands.removeAll(where: \.isDiscovery)
            discoveryState = .cancelled
            discoveryProgress = nil
        }
    }

    public func collectDiagnosticReport() async throws -> DiagnosticReport {
        if case .connected = snapshot.connection {
            await refresh().value
        }
        DiagnosticRecorder.shared.record(
            "capture",
            "Diagnostic report requested",
            details: ["demoMode": demoMode.description]
        )
        return DiagnosticRecorder.shared.report(snapshot: snapshot)
    }

    @discardableResult
    private func enqueue(_ command: QueuedCommand) -> Task<Void, Never> {
        if case .set(let key, _) = command,
           let existingIndex = queuedCommands.lastIndex(where: { $0.settingKey == key }) {
            queuedCommands[existingIndex] = command
        } else {
            queuedCommands.append(command)
        }
        updatePendingSettings()

        if let commandTask { return commandTask }
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await drainCommandQueue()
        }
        commandTask = task
        return task
    }

    private func drainCommandQueue() async {
        while !queuedCommands.isEmpty {
            guard !Task.isCancelled else { break }
            let command = queuedCommands.removeFirst()
            activeCommand = command
            isCommandInFlight = true
            updatePendingSettings(active: command.settingKey)

            do {
                try await execute(command)
                retryCommand = nil
            } catch is CancellationError {
                if command.isDiscovery {
                    discoveryState = .cancelled
                    discoveryProgress = nil
                }
                break
            } catch {
                let headsetError = error as? HeadsetError ?? .transport(error.localizedDescription)
                DiagnosticRecorder.shared.record(
                    "command",
                    "Headset command failed",
                    details: [
                        "command": command.name,
                        "error": error.localizedDescription,
                    ]
                )
                if command.isDiscovery {
                    discoveryState = .failed(error.localizedDescription)
                    discoveryProgress = nil
                } else {
                    retryCommand = command
                    present(headsetError, retrying: command)
                }
            }
            updatePendingSettings()
        }

        isCommandInFlight = false
        pendingSettings.removeAll()
        activeCommand = nil
        commandTask = nil
    }

    private func execute(_ command: QueuedCommand) async throws {
        switch command {
        case .refresh:
            apply(try await controller.refresh())
        case .set(let key, let value):
            apply(try await controller.set(key, value: value))
        case .action(let key):
            apply(try await controller.perform(key))
        case .reconnect:
            apply(await controller.stop())
            apply(await controller.start())
        case .discovery:
            let result = try await controller.discoverReadOnly { [weak self] progress in
                self?.discoveryProgress = progress
            }
            apply(result.update)
            lastDiscoverySummary = result.summary
            discoveryState = .completed
            discoveryProgress = nil
        }
    }

    func apply(_ update: HeadsetStateUpdate) {
        guard update.revision > lastAppliedRevision else { return }
        lastAppliedRevision = update.revision
        snapshot = update.snapshot
    }

    private func updatePendingSettings(active: HeadsetSettingKey? = nil) {
        pendingSettings = Set(queuedCommands.compactMap(\.settingKey))
        if let active { pendingSettings.insert(active) }
    }

    private func present(_ error: HeadsetError, retrying command: QueuedCommand?) {
        let recovery: RecoveryAction
        let message: String
        switch error {
        case .disconnected:
            recovery = .reconnect
            message = "Turn on the headset, then reconnect and try again."
        case .timeout:
            recovery = .retry
            message = "Keep the headset nearby, then try the command again."
        case .malformedResponse, .readbackMismatch:
            recovery = .retry
            message = "Try again. If the problem continues, export a Diagnostics log."
        case .busy:
            recovery = .retry
            message = "Wait for the current command to finish, then try again."
        case .unsupported:
            recovery = .dismiss
            message = "This setting stays disabled until a physical capture validates its command."
        case .invalidValue:
            recovery = .dismiss
            message = "Choose one of the available values and try again."
        case .transport:
            recovery = .reconnect
            message = "Reconnect the headset. Technical details were added to Diagnostics."
        }

        failure = HeadsetFailure(
            title: LocalizedStringResource("Unable to update the headset", bundle: #bundle),
            message: message,
            technicalDetails: error.localizedDescription,
            primaryAction: recovery
        )
        if let command { retryCommand = command }
    }
}

private enum QueuedCommand {
    case refresh
    case set(HeadsetSettingKey, SettingValue)
    case action(HeadsetSettingKey)
    case reconnect
    case discovery

    var settingKey: HeadsetSettingKey? {
        switch self {
        case .set(let key, _), .action(let key): key
        case .refresh, .reconnect, .discovery: nil
        }
    }

    var isDiscovery: Bool {
        if case .discovery = self { true } else { false }
    }

    var name: String {
        switch self {
        case .refresh: "refresh"
        case .set(let key, _): "set.\(key.rawValue)"
        case .action(let key): "action.\(key.rawValue)"
        case .reconnect: "reconnect"
        case .discovery: "read-only-discovery"
        }
    }
}

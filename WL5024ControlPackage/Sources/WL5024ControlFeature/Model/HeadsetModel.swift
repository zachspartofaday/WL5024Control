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
        retryCommand = nil
        failure = nil
        discoveryState = .idle
        discoveryProgress = nil
        lastDiscoverySummary = nil
        apply(await controller.stop())
        didStart = false
    }

    @discardableResult
    public func refresh() -> Task<Void, Never> {
        guard !rejectWhileAwaitingRecovery(command: "refresh") else { return Task {} }
        guard discoveryState != .running else {
            rejectDuringDiscovery(command: "refresh")
            return Task {}
        }
        return enqueue(.refresh)
    }

    @discardableResult
    public func set(_ key: HeadsetSettingKey, to value: SettingValue) -> Task<Void, Never> {
        guard !rejectWhileAwaitingRecovery(command: "set.\(key.rawValue)") else { return Task {} }
        guard discoveryState != .running else {
            rejectDuringDiscovery(command: "set.\(key.rawValue)")
            return Task {}
        }
        guard snapshot.readiness(for: key).allowsWrite else {
            present(.unsupported(key), retrying: nil)
            return Task {}
        }
        return enqueue(.set(key, value))
    }

    @discardableResult
    public func perform(_ key: HeadsetSettingKey) -> Task<Void, Never> {
        guard !rejectWhileAwaitingRecovery(command: "action.\(key.rawValue)") else { return Task {} }
        guard discoveryState != .running else {
            rejectDuringDiscovery(command: "action.\(key.rawValue)")
            return Task {}
        }
        guard snapshot.readiness(for: key).allowsWrite else {
            present(.unsupported(key), retrying: nil)
            return Task {}
        }
        return enqueue(.action(key))
    }

    private func rejectDuringDiscovery(command: String) {
        DiagnosticRecorder.shared.record(
            "command",
            "Discovery exclusive rejection",
            details: ["command": command]
        )
        present(.busy, retrying: nil)
    }

    private func rejectWhileAwaitingRecovery(command: String) -> Bool {
        guard retryCommand != nil else { return false }
        DiagnosticRecorder.shared.record(
            "command",
            "Command rejected while recovery is pending",
            details: ["command": command]
        )
        return true
    }

    public func value(for key: HeadsetSettingKey) -> SettingValue? {
        snapshot.values[key]
    }

    public func readiness(for key: HeadsetSettingKey) -> CapabilityReadiness {
        snapshot.readiness(for: key)
    }

    public func dismissFailure() {
        failure = nil
        // Dismissing abandons the retry; resume any commands halted behind it.
        retryCommand = nil
        restartDrainIfIdle()
    }

    public func retryLastAction() {
        guard let retryCommand else { return }
        guard discoveryState != .running else {
            rejectDuringDiscovery(command: "retry.\(retryCommand.name)")
            return
        }
        failure = nil
        // Re-run the exact failing command first; keep retryCommand until it
        // succeeds so a later unrelated success cannot clear a live retry.
        queuedCommands.insert(retryCommand, at: 0)
        updatePendingSettings()
        restartDrainIfIdle()
    }

    @discardableResult
    public func reconnect() -> Task<Void, Never> {
        guard discoveryState != .running else {
            rejectDuringDiscovery(command: "reconnect")
            return Task {}
        }
        failure = nil
        // Reconnect is an explicit recovery choice that abandons the exact
        // failed command while preserving work that was queued behind it.
        retryCommand = nil
        // Recovery must run before work preserved behind the command that
        // failed, otherwise that work immediately retries the broken link.
        if activeCommand?.isReconnect == true, let commandTask {
            return commandTask
        }
        queuedCommands.removeAll(where: \.isReconnect)
        queuedCommands.insert(.reconnect, at: 0)
        updatePendingSettings()

        if let commandTask { return commandTask }
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await drainCommandQueue()
        }
        commandTask = task
        return task
    }

    @discardableResult
    public func runReadOnlyDiscovery() -> Task<Void, Never> {
        guard !rejectWhileAwaitingRecovery(command: "read-only-discovery") else { return Task {} }
        guard discoveryState != .running else { return commandTask ?? Task {} }
        discoveryState = .running
        discoveryProgress = nil
        lastDiscoverySummary = nil
        return enqueue(.discovery)
    }

    public func cancelReadOnlyDiscovery() {
        guard discoveryState == .running else { return }
        if let activeCommand, activeCommand.isDiscovery {
            // Drop only discovery work; settings actions are disabled during
            // discovery (see set/perform/refresh guards), but preserve any
            // non-discovery commands against races instead of discarding them.
            queuedCommands.removeAll(where: \.isDiscovery)
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
        guard retryCommand == nil || command.isReconnect else {
            DiagnosticRecorder.shared.record(
                "command",
                "Queue intake blocked while recovery is pending",
                details: ["command": command.name]
            )
            return commandTask ?? Task {}
        }
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
        // When a user-visible command fails, halt with remaining work
        // preserved; retry/dismiss explicitly resumes (AUD-006).
        var requiresRecovery = false
        while !queuedCommands.isEmpty {
            guard !Task.isCancelled else { break }
            if requiresRecovery { break }
            let command = queuedCommands.removeFirst()
            activeCommand = command
            isCommandInFlight = true
            updatePendingSettings(active: command.settingKey)

            do {
                try await execute(command)
                // Clear retry only when its own command succeeds.
                if retryCommand == command {
                    retryCommand = nil
                }
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
                    requiresRecovery = true
                }
            }
            updatePendingSettings()
        }

        isCommandInFlight = false
        pendingSettings.removeAll()
        activeCommand = nil
        commandTask = nil
        // Restart only for cancellation-preserved work, never past a failure
        // that still needs user recovery.
        if !queuedCommands.isEmpty, !requiresRecovery {
            updatePendingSettings()
            let task = Task { @MainActor [weak self] in
                guard let self else { return }
                await self.drainCommandQueue()
            }
            commandTask = task
        } else if !queuedCommands.isEmpty {
            updatePendingSettings()
        }
    }

    private func restartDrainIfIdle() {
        guard commandTask == nil, !queuedCommands.isEmpty else { return }
        updatePendingSettings()
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.drainCommandQueue()
        }
        commandTask = task
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
        var recovery: RecoveryAction
        let message: String
        switch error {
        case .disconnected:
            recovery = .reconnect
            message = "Turn on the headset, then reconnect and try again."
        case .timeout:
            recovery = .retry
            message = "Keep the headset nearby, then try the command again."
        case .commandRejected, .malformedResponse, .readbackMismatch:
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

        // A Retry button is valid only when there is an exact command to
        // replay. Busy rejections during exclusive discovery deliberately do
        // not enqueue work, so their only honest recovery is dismissal.
        if recovery == .retry, command == nil {
            recovery = .dismiss
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

private enum QueuedCommand: Equatable {
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

    var isReconnect: Bool {
        if case .reconnect = self { true } else { false }
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

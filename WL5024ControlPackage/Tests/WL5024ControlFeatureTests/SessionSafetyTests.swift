import Foundation
import Testing
@testable import WL5024ControlFeature

// Regression schedules use fake transports; no Bluetooth or HID device is opened.
@MainActor
struct SessionSafetyTests {
    @Test(arguments: CommandBoundary.allCases, SuspendedOutcome.allCases)
    func expiredWriteCannotMutateReplacementSession(
        boundary: CommandBoundary, outcome: SuspendedOutcome
    ) async throws {
        let transport = SuspendedSessionTransport(boundary: boundary)
        let controller = LiveHeadsetController(transport: transport)
        _ = await controller.start()
        let oldCommand = Task { try await controller.set(.automaticMedia, value: .boolean(true)) }
        await transport.waitUntilSuspended()

        // Stop/start deliberately reconnects to the same peripheral UUID.
        _ = await controller.stop()
        _ = await controller.start()
        let fresh = try await controller.set(.automaticMedia, value: .boolean(true)).snapshot
        let transactionCount = transport.transactionCount
        transport.resume(outcome)

        await #expect(throws: HeadsetError.disconnected) { try await oldCommand.value }
        #expect(transport.transactionCount == transactionCount)
        #expect(controller.currentSnapshot == fresh)
    }

    @Test func discoveryCannotRestoreValuesFromAnExpiredSession() async {
        let transport = SessionChangingTransport(reconnect: false)
        let controller = LiveHeadsetController(transport: transport)
        _ = await controller.start()
        await #expect(throws: HeadsetError.disconnected) {
            try await controller.discoverReadOnly { _ in }
        }
        #expect(controller.currentSnapshot.values.isEmpty)
        #expect(controller.currentSnapshot.lastUpdated == nil)
    }

    @Test(arguments: [false, true])
    func aWriteMustNotContinueAfterItsPreparationSessionChanges(samePeripheral: Bool) async throws {
        let transport = SessionChangingTransport(reconnect: true, samePeripheral: samePeripheral)
        let controller = LiveHeadsetController(transport: transport)
        _ = await controller.start()
        do {
            _ = try await controller.set(.automaticMedia, value: .boolean(true))
        } catch {
            // Ending the command when its source session expires is correct.
        }
        #expect(transport.writes.isEmpty,
                "Old-session preparation must never produce a setter in the replacement session")
        if let write = transport.writes.first {
            #expect(write.session == transport.originalSession,
                    "Observed a write against the replacement session")
        }
    }

    @Test func refreshMustNotRestoreConfirmedValuesAfterDisconnect() async throws {
        let transport = SessionChangingTransport(reconnect: false)
        let controller = LiveHeadsetController(transport: transport)
        _ = await controller.start()
        do { _ = try await controller.refresh() } catch {}
        #expect(controller.currentSnapshot.connection == .searching)
        #expect(controller.currentSnapshot.values.isEmpty,
                "A completed old-session reply must not repopulate disconnected state")
        #expect(controller.currentSnapshot.lastUpdated == nil,
                "A disconnected refresh must not stamp old-session values as fresh")
    }

    @Test func unavailableMustInvalidateEveryConnectionLayer() async {
        let source = AuditBluetoothSource()
        let bluetooth = BLETransport(source: source)
        let coordinator = TransportCoordinator(bluetooth: bluetooth, hidMonitor: AuditHIDMonitor())
        let controller = LiveHeadsetController(transport: coordinator)
        _ = await controller.start()
        source.emit(.ready(.init(name: "WL5024", identifier: UUID(), diagnosticDetails: [:])))
        #expect(controller.currentSnapshot.connection == .connected(.bluetooth))
        source.emit(.unavailable)
        #expect(!bluetooth.isReady)
        #expect(coordinator.activeKind == nil,
                "Unavailable Bluetooth must not retain an active transport")
        #expect(controller.currentSnapshot.connection == .unavailable,
                "Unavailable Bluetooth must not remain connected in the UI")
        #expect(!controller.currentSnapshot.readiness(for: .automaticMedia).allowsWrite)
        _ = await controller.stop()
    }

    @Test func retryingFailureMustNotKeepThePreviousDisconnectIdentity() async {
        let source = AuditBluetoothSource()
        let bluetooth = BLETransport(source: source)
        let coordinator = TransportCoordinator(bluetooth: bluetooth, hidMonitor: AuditHIDMonitor())
        let controller = LiveHeadsetController(transport: coordinator)
        _ = await controller.start()
        let previous = UUID()
        let next = UUID()
        source.emit(.ready(.init(name: "WL5024 A", identifier: previous, diagnosticDetails: [:])))
        source.emit(.failed(message: "Notification setup lost", willRetry: true))
        source.emit(.ready(.init(name: "WL5024 B", identifier: next, diagnosticDetails: [:])))
        source.emit(.disconnected(identifier: next))
        #expect(coordinator.activeKind == nil,
                "Disconnect from the current peripheral must clear active transport")
        #expect(controller.currentSnapshot.connection == .searching,
                "Disconnect from the current peripheral must reach the controller")
        _ = await controller.stop()
    }
}

enum CommandBoundary: CaseIterable, Sendable {
    case preparation, acknowledgement, readBack, recovery

    var transactionIndex: Int {
        switch self {
        case .preparation: 1
        case .acknowledgement: 2
        case .readBack, .recovery: 3
        }
    }
}

enum SuspendedOutcome: CaseIterable, Sendable {
    case response, cancellation, failure
}

@MainActor
private final class SuspendedSessionTransport: HeadsetTransporting {
    private let identifier = UUID()
    private let boundary: CommandBoundary
    private let suspended = AsyncStream.makeStream(of: Void.self, bufferingPolicy: .bufferingNewest(1))
    private var pending: CheckedContinuation<Data, any Error>?
    private var pendingResponse = Data()
    private(set) var transactionCount = 0
    private(set) var activeKind: TransportKind?

    init(boundary: CommandBoundary) { self.boundary = boundary }

    func start(updateHandler: @escaping @Sendable (TransportUpdate) -> Void) {
        activeKind = .bluetooth
        updateHandler(.connectedBluetooth(name: "Fixture", identifier: identifier))
    }

    func stop() { activeKind = nil }

    func transact(_ transaction: TransportTransaction, timeout: Duration) async throws -> Data {
        transactionCount += 1
        if boundary == .recovery, transactionCount == 2 {
            throw DispatchedTransactionError(underlying: HeadsetError.timeout, gattWriteAcknowledged: true)
        }
        let request = try RaceFrame(decoding: transaction.request)
        let response = RaceFrame(
            packetType: .response, opcode: request.opcode,
            payload: request.opcode == 0x0021 ? Data([0, 2, 0]) : Data([0])
        ).encoded
        if transactionCount == boundary.transactionIndex {
            pendingResponse = response
            return try await withCheckedThrowingContinuation { continuation in
                pending = continuation
                suspended.continuation.yield()
            }
        }
        return response
    }

    func waitUntilSuspended() async {
        for await _ in suspended.stream { return }
    }

    func resume(_ outcome: SuspendedOutcome) {
        switch outcome {
        case .response: pending?.resume(returning: pendingResponse)
        case .cancellation: pending?.resume(throwing: CancellationError())
        case .failure:
            pending?.resume(throwing: DispatchedTransactionError(
                underlying: HeadsetError.timeout, gattWriteAcknowledged: true
            ))
        }
        pending = nil
    }
}

@MainActor
private final class SessionChangingTransport: HeadsetTransporting {
    struct Write {
        let session: UUID
        let request: Data
    }
    let originalSession = UUID()
    private let replacementSession: UUID
    private let reconnect: Bool
    private var currentSession: UUID?
    private var handler: (@Sendable (TransportUpdate) -> Void)?
    private var readCount = 0
    private(set) var writes: [Write] = []
    var activeKind: TransportKind? { currentSession == nil ? nil : .bluetooth }

    init(reconnect: Bool, samePeripheral: Bool = false) {
        self.reconnect = reconnect
        replacementSession = samePeripheral ? originalSession : UUID()
    }
    func start(updateHandler: @escaping @Sendable (TransportUpdate) -> Void) {
        handler = updateHandler
        currentSession = originalSession
        updateHandler(.connectedBluetooth(name: "Original", identifier: originalSession))
    }
    func stop() { currentSession = nil; handler = nil }
    func transact(_ transaction: TransportTransaction, timeout: Duration) async throws -> Data {
        readCount += 1
        if readCount == 1 {
            // Represents a reply completing just before the disconnect callback
            // runs, with the awaiting command resuming after lifecycle events.
            let completedReply = RaceFrame(packetType: .response, opcode: 0x0021,
                                           payload: Data([0, 0, 0xA5])).encoded
            currentSession = nil
            handler?(.bluetoothDisconnected(identifier: originalSession))
            if reconnect {
                currentSession = replacementSession
                handler?(.connectedBluetooth(name: "Replacement", identifier: replacementSession))
            }
            return completedReply
        }
        guard currentSession != nil else { throw HeadsetError.disconnected }
        return RaceFrame(packetType: .response, opcode: 0x0021,
                         payload: Data([0, 2, 0xA5])).encoded
    }
    func transactWrite(_ transaction: TransportTransaction, timeout: Duration) async throws -> Data {
        guard let currentSession else { throw HeadsetError.disconnected }
        writes.append(Write(session: currentSession, request: transaction.request))
        return RaceFrame(packetType: .response, opcode: 0x0020, payload: Data([0])).encoded
    }
}

@MainActor
private final class AuditBluetoothSource: BluetoothEventSourcing {
    private(set) var isReady = false
    private var handler: (@MainActor (BluetoothAdapterEvent) -> Void)?
    func start(eventHandler: @escaping @MainActor (BluetoothAdapterEvent) -> Void) { handler = eventHandler }
    func stop() { isReady = false; handler = nil }
    func write(_ data: Data) throws { throw HeadsetError.disconnected }
    func emit(_ event: BluetoothAdapterEvent) {
        switch event {
        case .ready: isReady = true
        case .disconnected, .unavailable, .permissionDenied, .failed: isReady = false
        default: break
        }
        handler?(event)
    }
}

@MainActor
private final class AuditHIDMonitor: HIDMonitoring {
    func start(updateHandler: @escaping @Sendable (TransportUpdate) -> Void) {}
    func stop() {}
}

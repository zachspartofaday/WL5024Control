import Foundation
@preconcurrency import IOKit.hid
import Testing
@testable import WL5024ControlFeature

@MainActor
struct TransportAdapterTests {
    @Test func stalePeripheralDisconnectCannotEndTheCurrentTransaction() async throws {
        let source = FakeBluetoothEventSource()
        let transport = BLETransport(source: source)
        transport.start()
        source.emit(.ready(.init(name: "Current", identifier: UUID(), diagnosticDetails: [:])))
        let task = Task {
            try await transport.transact(WL5024Command.getWearDetection.transaction, timeout: .seconds(1))
        }
        await source.waitForWrite()
        source.emit(.disconnected(identifier: UUID()))
        #expect(transport.isReady)
        #expect(transport.lifecycle == .ready)
        let response = RaceFrame(packetType: .response, opcode: 0x0021, payload: Data([0, 2, 0])).encoded
        source.emit(.received(response))
        #expect(try await task.value == response)
        transport.stop()
    }

    @Test(arguments: ["unavailable", "denied", "retry", "terminal", "replacement"], [false, true])
    func connectionLossImmediatelyFailsPendingTransaction(event: String, isWrite: Bool) async {
        let source = FakeBluetoothEventSource()
        let recorder = DiagnosticRecorder(maximumEntries: 2)
        let transport = BLETransport(source: source, recorder: recorder)
        transport.start()
        let metadata = BluetoothConnectionMetadata(name: "Fixture", identifier: UUID(), diagnosticDetails: ["notify": "fixture"])
        source.emit(.ready(metadata))
        recorder.record("fixture", "overflow 1")
        recorder.record("fixture", "overflow 2")
        recorder.record("fixture", "overflow 3")
        #expect(recorder.report(snapshot: .demo()).inventory.bluetooth?.identifier == metadata.identifier.uuidString)

        let task = Task {
            if isWrite {
                return try await transport.transactWrite(WL5024Command.getWearDetection.transaction, timeout: .seconds(60))
            }
            return try await transport.transact(WL5024Command.getWearDetection.transaction, timeout: .seconds(60))
        }
        await source.waitForWrite()
        switch event {
        case "unavailable": source.emit(.unavailable)
        case "denied": source.emit(.permissionDenied)
        case "retry": source.emit(.failed(message: "resetting", willRetry: true))
        case "terminal": source.emit(.failed(message: "lost notifications", willRetry: false))
        default: source.emit(.ready(metadata))
        }
        do {
            _ = try await task.value
            Issue.record("The pending transaction must fail on session loss")
        } catch let error as DispatchedTransactionError {
            #expect(isWrite)
            #expect(!error.gattWriteAcknowledged)
        } catch {
            #expect(!isWrite)
        }
        #expect(transport.isReady == (event == "replacement"))
        #expect(transport.lifecycle == (event == "replacement" ? .ready : event == "retry" ? .retrying : .stopped))
        if event != "replacement" {
            #expect(recorder.report(snapshot: .demo()).inventory.bluetooth == nil)
        }
        transport.stop()
        #expect(recorder.report(snapshot: .demo()).inventory.bluetooth == nil)
    }

    @Test func cancelledTaskNeverDispatchesAWrite() async {
        let source = FakeBluetoothEventSource()
        let transport = BLETransport(source: source)
        transport.start()
        source.emit(.ready(.init(name: "Fixture", identifier: UUID(), diagnosticDetails: [:])))
        let task = Task {
            try await transport.transactWrite(WL5024Command.getWearDetection.transaction, timeout: .seconds(60))
        }
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(source.writes.isEmpty)
        transport.stop()
    }

    @Test func bluetoothDiscoveryAcceptsOnlyKnownServiceOrWL5024Name() {
        let service = BluetoothDiscoveryPolicy.controlServiceIdentifier
        #expect(BluetoothDiscoveryPolicy.isCandidate(
            peripheralName: nil,
            advertisedName: nil,
            advertisedServiceIdentifiers: [service.lowercased()]
        ))
        #expect(BluetoothDiscoveryPolicy.isCandidate(
            peripheralName: "Dell WL5024",
            advertisedName: nil,
            advertisedServiceIdentifiers: []
        ))
        #expect(BluetoothDiscoveryPolicy.isCandidate(
            peripheralName: nil,
            advertisedName: "WL 5024 Headset",
            advertisedServiceIdentifiers: []
        ))
        #expect(!BluetoothDiscoveryPolicy.isCandidate(
            peripheralName: "Dell Keyboard",
            advertisedName: "Dell Peripheral",
            advertisedServiceIdentifiers: []
        ))
        #expect(!BluetoothDiscoveryPolicy.isCandidate(
            peripheralName: "WL5025",
            advertisedName: nil,
            advertisedServiceIdentifiers: []
        ))
    }

    @Test func bluetoothAdapterRoutesMatchedAndUnsolicitedResponses() async throws {
        let source = FakeBluetoothEventSource()
        let transport = BLETransport(source: source)
        let collector = TransportUpdateCollector()
        transport.configure { update in
            MainActor.assumeIsolated { collector.updates.append(update) }
        }
        transport.start()
        let identifier = UUID()
        source.emit(.ready(BluetoothConnectionMetadata(
            name: "WL5024",
            identifier: identifier,
            diagnosticDetails: [:]
        )))

        let transaction = WL5024Command.getWearDetection.transaction
        let responseTask = Task { try await transport.transact(transaction, timeout: .seconds(1)) }
        await Task.yield()
        #expect(source.writes == [transaction.request])

        let unsolicited = Data([0xAA])
        source.emit(.received(unsolicited))
        let matching = RaceFrame(
            packetType: .response,
            opcode: 0x0021,
            payload: Data([0x00, 0x67, 0x00])
        ).encoded
        source.emit(.writeAcknowledged(characteristic: "fixture-write-characteristic"))
        source.emit(.received(matching))

        #expect(try await responseTask.value == matching)
        #expect(collector.updates.contains(.unsolicitedBluetooth(unsolicited)))
        #expect(collector.updates.contains(.connectedBluetooth(name: "WL5024", identifier: identifier)))
    }

    @Test func bluetoothAdapterPropagatesRetryAndCancellation() async {
        let source = FakeBluetoothEventSource()
        let transport = BLETransport(source: source)
        let collector = TransportUpdateCollector()
        transport.configure { update in
            MainActor.assumeIsolated { collector.updates.append(update) }
        }
        transport.start()
        source.emit(.ready(BluetoothConnectionMetadata(
            name: "WL5024",
            identifier: UUID(),
            diagnosticDetails: [:]
        )))

        let responseTask = Task {
            try await transport.transact(
                WL5024Command.getWearDetection.transaction,
                timeout: .seconds(10)
            )
        }
        await Task.yield()
        responseTask.cancel()
        do {
            _ = try await responseTask.value
            Issue.record("Expected cancellation")
        } catch is CancellationError {
            // Read transactions preserve ordinary cancellation semantics.
        } catch {
            Issue.record("Expected cancellation, got \(error)")
        }

        source.emit(.lifecycle(.setupFailed))
        source.emit(.failed(message: "fixture setup failure", willRetry: true))
        #expect(transport.lifecycle == .retrying)
        #expect(collector.updates.contains(.failed(
            source: .bluetooth,
            message: "fixture setup failure",
            willRetry: true
        )))
    }

    @Test func bluetoothAdapterQuarantinesTimedOutMatcherUntilLateReplyDrains() async throws {
        let source = FakeBluetoothEventSource()
        let transport = BLETransport(source: source)
        let collector = TransportUpdateCollector()
        transport.configure { update in
            MainActor.assumeIsolated { collector.updates.append(update) }
        }
        transport.start()
        source.emit(.ready(BluetoothConnectionMetadata(
            name: "WL5024",
            identifier: UUID(),
            diagnosticDetails: [:]
        )))

        let wearTransaction = WL5024Command.getWearDetection.transaction
        await #expect(throws: HeadsetError.timeout) {
            try await transport.transact(wearTransaction, timeout: .milliseconds(1))
        }
        #expect(source.writes == [wearTransaction.request])

        await #expect(throws: HeadsetError.transport(
            "A previous request may still reply. Reconnect the headset before retrying this command."
        )) {
            try await transport.transact(wearTransaction, timeout: .seconds(1))
        }
        #expect(source.writes == [wearTransaction.request])

        // A non-conflicting request may proceed while the timed-out matcher is
        // quarantined. Its pending transaction must not consume the late wear
        // response, which instead drains the quarantine as unsolicited data.
        let preferenceTransaction = WL5024Command.getPreference(module: 1).transaction
        let preferenceTask = Task {
            try await transport.transact(preferenceTransaction, timeout: .seconds(1))
        }
        await Task.yield()
        let lateWearResponse = RaceFrame(
            packetType: .response,
            opcode: 0x0021,
            payload: Data([0, 0x01, 0x00])
        ).encoded
        source.emit(.received(lateWearResponse))
        let preferenceResponse = RaceFrame(
            packetType: .response,
            opcode: 0x2C83,
            payload: Data([0, 1, 0, 1])
        ).encoded
        source.emit(.received(preferenceResponse))

        #expect(try await preferenceTask.value == preferenceResponse)
        #expect(collector.updates.contains(.unsolicitedBluetooth(lateWearResponse)))

        let retryTask = Task {
            try await transport.transact(wearTransaction, timeout: .seconds(1))
        }
        await Task.yield()
        let freshWearResponse = RaceFrame(
            packetType: .response,
            opcode: 0x0021,
            payload: Data([0, 0x02, 0x00])
        ).encoded
        source.emit(.received(freshWearResponse))
        #expect(try await retryTask.value == freshWearResponse)
        #expect(source.writes == [
            wearTransaction.request,
            preferenceTransaction.request,
            wearTransaction.request,
        ])
    }

    @Test func bluetoothAdapterPreservesDispatchedFailureState() async {
        let source = FakeBluetoothEventSource()
        let transport = BLETransport(source: source)
        transport.configure { _ in }
        transport.start()
        source.emit(.ready(BluetoothConnectionMetadata(
            name: "WL5024",
            identifier: UUID(),
            diagnosticDetails: [:]
        )))

        let responseTask = Task {
            try await transport.transactWrite(
                WL5024Command.getWearDetection.transaction,
                timeout: .seconds(10)
            )
        }
        await Task.yield()
        source.emit(.writeAcknowledged(characteristic: "fixture-write-characteristic"))
        source.emit(.writeFailed("fixture write failed"))

        do {
            _ = try await responseTask.value
            Issue.record("Expected a dispatched transaction failure")
        } catch let error as DispatchedTransactionError {
            #expect(!error.isCancellation)
            #expect(error.gattWriteAcknowledged)
            #expect(error.localizedDescription == "fixture write failed")
        } catch {
            Issue.record("Expected dispatched transaction failure, got \(error)")
        }
    }

    @Test func bluetoothAdapterPreservesDispatchedWriteCancellation() async {
        let source = FakeBluetoothEventSource()
        let transport = BLETransport(source: source)
        transport.configure { _ in }
        transport.start()
        source.emit(.ready(BluetoothConnectionMetadata(
            name: "WL5024",
            identifier: UUID(),
            diagnosticDetails: [:]
        )))

        let responseTask = Task {
            try await transport.transactWrite(
                WL5024Command.getWearDetection.transaction,
                timeout: .seconds(10)
            )
        }
        await Task.yield()
        responseTask.cancel()

        do {
            _ = try await responseTask.value
            Issue.record("Expected dispatched write cancellation")
        } catch let error as DispatchedTransactionError {
            #expect(error.isCancellation)
            #expect(!error.gattWriteAcknowledged)
        } catch {
            Issue.record("Expected dispatched write cancellation, got \(error)")
        }
    }

    @Test func hidRetainsTwoInterfacesRecordsBothAndRemovesOnlyAfterLast() {
        let source = FakeHIDEventSource()
        let recorder = DiagnosticRecorder(maximumEntries: 20)
        let monitor = HIDMonitor(source: source, recorder: recorder)
        let collector = TransportUpdateCollector()
        monitor.start { update in
            MainActor.assumeIsolated { collector.updates.append(update) }
        }
        let first = descriptor(registryID: 101, product: "Dell WL5024")
        let second = descriptor(registryID: 202, product: "Dell HR024")

        source.emit(.matched(first))
        source.emit(.matched(second))
        source.emit(.matched(first))
        source.emit(.input(input(for: first.identity, value: 11)))
        source.emit(.input(input(for: second.identity, value: 22)))

        #expect(monitor.retainedInterfaceCount == 2)
        #expect(collector.updates.filter { if case .receiverFound = $0 { true } else { false } }.count == 2)
        #expect(recorder.entries.filter { $0.category == "hid-input" }.count == 2)
        for _ in 0..<30 { source.emit(.input(input(for: first.identity, value: 1))) }
        #expect(recorder.report(snapshot: .demo()).inventory.receiverInterfaces.map(\.identifier) == [
            first.identity.description, second.identity.description,
        ])

        source.emit(.removed(first.identity))
        #expect(monitor.retainedInterfaceCount == 1)
        #expect(!collector.updates.contains(.receiverRemoved))
        #expect(recorder.report(snapshot: .demo()).inventory.receiverInterfaces.map(\.identifier) == [second.identity.description])

        source.emit(.removed(second.identity))
        #expect(monitor.retainedInterfaceCount == 0)
        #expect(collector.updates.last == .receiverRemoved)
        #expect(recorder.report(snapshot: .demo()).inventory.receiverInterfaces.isEmpty)
        source.emit(.matched(first))
        monitor.stop()
        #expect(recorder.report(snapshot: .demo()).inventory.receiverInterfaces.isEmpty)
    }

    @Test func hidManagerOpenFailureIsRecordedAndEmitted() {
        let source = FakeHIDEventSource(startResult: kIOReturnNotOpen)
        let recorder = DiagnosticRecorder(maximumEntries: 10)
        let monitor = HIDMonitor(source: source, recorder: recorder)
        let collector = TransportUpdateCollector()

        monitor.start { update in
            MainActor.assumeIsolated { collector.updates.append(update) }
        }

        #expect(source.stopCount == 1)
        #expect(recorder.entries.last?.details["ioReturn"] != nil)
        guard case .failed(source: .receiver, _, willRetry: false) = collector.updates.last else {
            Issue.record("Expected a receiver-source failure")
            return
        }
    }

    @Test func hidCandidateFilterUsesDellAndUpdaterVendorIdentities() {
        #expect(HIDMonitor.isWL5024Candidate(summary(vendorID: 0x413C, productID: 1, product: "WL5024")))
        #expect(HIDMonitor.isWL5024Candidate(summary(vendorID: 0x0E8D, productID: 0x0808, product: "Updater")))
        #expect(!HIDMonitor.isWL5024Candidate(summary(vendorID: 0x1234, productID: 1, product: "WL5024")))
        #expect(!HIDMonitor.isWL5024Candidate(summary(vendorID: 0x413C, productID: 1, product: "Keyboard")))
    }

    @Test func coordinatorRoutesTransactionsAndHonorsDisconnectIdentity() async throws {
        let bluetooth = FakeRawTransport()
        let hid = FakeHIDMonitor()
        let coordinator = TransportCoordinator(bluetooth: bluetooth, hidMonitor: hid)
        let collector = TransportUpdateCollector()
        coordinator.start { update in
            MainActor.assumeIsolated { collector.updates.append(update) }
        }
        let activeIdentifier = UUID()
        bluetooth.emit(.connectedBluetooth(name: "WL5024", identifier: activeIdentifier))

        let transaction = WL5024Command.getWearDetection.transaction
        let response = try await coordinator.transact(transaction, timeout: .seconds(1))
        #expect(response == bluetooth.response)
        #expect(bluetooth.transactions == [transaction])
        #expect(coordinator.activeKind == .bluetooth)

        bluetooth.emit(.bluetoothDisconnected(identifier: UUID()))
        #expect(coordinator.activeKind == .bluetooth)
        bluetooth.emit(.unsolicitedBluetooth(Data([0xAA])))
        #expect(collector.updates.contains(.unsolicitedBluetooth(Data([0xAA]))))

        bluetooth.emit(.bluetoothDisconnected(identifier: activeIdentifier))
        #expect(coordinator.activeKind == nil)
    }

    @Test func coordinatorPropagatesTransactionCancellationAndStopsBothSources() async {
        let bluetooth = FakeRawTransport(error: CancellationError())
        let hid = FakeHIDMonitor()
        let coordinator = TransportCoordinator(bluetooth: bluetooth, hidMonitor: hid)
        coordinator.start { _ in }
        bluetooth.emit(.connectedBluetooth(name: "WL5024", identifier: UUID()))

        await #expect(throws: CancellationError.self) {
            try await coordinator.transact(WL5024Command.getWearDetection.transaction)
        }
        coordinator.stop()
        #expect(bluetooth.stopCount == 1)
        #expect(hid.stopCount == 1)
    }
}

@MainActor
private final class TransportUpdateCollector {
    var updates: [TransportUpdate] = []
}

@MainActor
private final class FakeHIDEventSource: HIDEventSourcing {
    let startResult: IOReturn
    private var handler: (@Sendable (HIDSourceEvent) -> Void)?
    private(set) var stopCount = 0

    init(startResult: IOReturn = kIOReturnSuccess) {
        self.startResult = startResult
    }

    func start(eventHandler: @escaping @Sendable (HIDSourceEvent) -> Void) -> IOReturn {
        handler = eventHandler
        return startResult
    }

    func stop() {
        stopCount += 1
        handler = nil
    }

    func emit(_ event: HIDSourceEvent) {
        handler?(event)
    }
}

@MainActor
private final class FakeBluetoothEventSource: BluetoothEventSourcing {
    private let writeEvents = AsyncStream.makeStream(of: Void.self, bufferingPolicy: .bufferingNewest(1))
    private(set) var isReady = false
    private var handler: (@MainActor (BluetoothAdapterEvent) -> Void)?
    private(set) var writes: [Data] = []

    func start(eventHandler: @escaping @MainActor (BluetoothAdapterEvent) -> Void) {
        handler = eventHandler
        eventHandler(.searching)
    }

    func stop() {
        isReady = false
        handler = nil
    }

    func write(_ data: Data) throws {
        guard isReady else { throw HeadsetError.disconnected }
        writes.append(data)
        writeEvents.continuation.yield()
    }

    func waitForWrite() async {
        for await _ in writeEvents.stream { return }
    }

    func emit(_ event: BluetoothAdapterEvent) {
        switch event {
        case .ready:
            isReady = true
        case .disconnected, .permissionDenied, .unavailable, .failed:
            isReady = false
        default:
            break
        }
        handler?(event)
    }
}

@MainActor
private final class FakeHIDMonitor: HIDMonitoring {
    private(set) var startCount = 0
    private(set) var stopCount = 0

    func start(updateHandler: @escaping @Sendable (TransportUpdate) -> Void) {
        startCount += 1
        updateHandler(.searching(.receiver))
    }

    func stop() {
        stopCount += 1
    }
}

@MainActor
private final class FakeRawTransport: RawHeadsetTransport {
    let kind: TransportKind = .bluetooth
    var isReady = true
    let response = Data([0x10, 0x20])
    private let error: (any Error)?
    private var handler: (@Sendable (TransportUpdate) -> Void)?
    private(set) var transactions: [TransportTransaction] = []
    private(set) var stopCount = 0

    init(error: (any Error)? = nil) {
        self.error = error
    }

    func configure(updateHandler: @escaping @Sendable (TransportUpdate) -> Void) {
        handler = updateHandler
    }

    func start() {}

    func stop() {
        stopCount += 1
    }

    func transact(_ transaction: TransportTransaction, timeout: Duration) async throws -> Data {
        transactions.append(transaction)
        if let error { throw error }
        return response
    }

    func emit(_ update: TransportUpdate) {
        handler?(update)
    }
}

private func descriptor(registryID: UInt64, product: String) -> HIDInterfaceDescriptor {
    let identity = HIDInterfaceIdentity(
        registryEntryID: registryID,
        locationID: Int(registryID),
        usagePage: 12,
        usage: 1,
        sessionIdentifier: "session-\(registryID)"
    )
    return HIDInterfaceDescriptor(
        identity: identity,
        summary: summary(vendorID: 0x413C, productID: Int(registryID), product: product),
        diagnosticDetails: ["interfaceIdentity": identity.description]
    )
}

private func input(for identity: HIDInterfaceIdentity, value: Int) -> HIDInputEvent {
    HIDInputEvent(
        identity: identity,
        usagePage: 12,
        usage: 1,
        reportID: 2,
        value: value,
        timestamp: UInt64(value)
    )
}

private func summary(vendorID: Int, productID: Int, product: String) -> HIDDeviceSummary {
    HIDDeviceSummary(
        vendorID: vendorID,
        productID: productID,
        manufacturer: "Dell",
        product: product,
        serialNumber: "fixture",
        maximumInputReportSize: 64,
        maximumOutputReportSize: 64
    )
}

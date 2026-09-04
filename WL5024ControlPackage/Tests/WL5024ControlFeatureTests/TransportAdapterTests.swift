import Foundation
@preconcurrency import IOKit.hid
import Testing
@testable import WL5024ControlFeature

@MainActor
struct TransportAdapterTests {
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
        await #expect(throws: CancellationError.self) { try await responseTask.value }

        source.emit(.lifecycle(.setupFailed))
        source.emit(.failed(message: "fixture setup failure", willRetry: true))
        #expect(transport.lifecycle == .retrying)
        #expect(collector.updates.contains(.failed(
            source: .bluetooth,
            message: "fixture setup failure",
            willRetry: true
        )))
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

        source.emit(.removed(first.identity))
        #expect(monitor.retainedInterfaceCount == 1)
        #expect(!collector.updates.contains(.receiverRemoved))

        source.emit(.removed(second.identity))
        #expect(monitor.retainedInterfaceCount == 0)
        #expect(collector.updates.last == .receiverRemoved)
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
    }

    func emit(_ event: BluetoothAdapterEvent) {
        switch event {
        case .ready:
            isReady = true
        case .disconnected, .permissionDenied, .unavailable:
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

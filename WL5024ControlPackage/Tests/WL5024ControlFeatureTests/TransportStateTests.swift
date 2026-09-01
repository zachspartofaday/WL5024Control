import Foundation
import Testing
@testable import WL5024ControlFeature

struct TransportStateTests {
    @Test func bluetoothLifecycleTransitions() {
        #expect(BluetoothLifecyclePolicy.next(after: .startScanning) == .scanning)
        #expect(BluetoothLifecyclePolicy.next(after: .discoveredPeripheral) == .connecting)
        #expect(BluetoothLifecyclePolicy.next(after: .connected) == .discovering)
        #expect(BluetoothLifecyclePolicy.next(after: .discoveredCharacteristics) == .subscribing)
        #expect(BluetoothLifecyclePolicy.next(after: .notificationsEnabled) == .ready)
        #expect(BluetoothLifecyclePolicy.next(after: .setupFailed) == .retrying)
        #expect(BluetoothLifecyclePolicy.next(after: .stop) == .stopped)
    }

    @Test func receiverRemovalDoesNotDisconnectBluetooth() {
        var snapshot = HeadsetSnapshot(
            connection: .connected(.bluetooth),
            device: .init(transport: .bluetooth, receiverDetected: true)
        )

        TransportStateReducer.apply(.receiverRemoved, to: &snapshot)

        #expect(snapshot.connection == .connected(.bluetooth))
        #expect(snapshot.device.transport == .bluetooth)
        #expect(!snapshot.device.receiverDetected)
    }

    @Test func bluetoothLossFallsBackToDetectedReceiver() {
        var snapshot = HeadsetSnapshot(
            connection: .connected(.bluetooth),
            device: .init(transport: .bluetooth, receiverDetected: true)
        )

        TransportStateReducer.apply(.bluetoothDisconnected, to: &snapshot)

        #expect(snapshot.connection == .qualificationRequired(.receiver))
        #expect(snapshot.device.transport == .receiver)
    }

    @Test @MainActor func refreshFailureThrowsWithoutMarkingDataFresh() async {
        let transport = FakeHeadsetTransport(
            responses: [.failure(HeadsetError.timeout)]
        )
        let controller = LiveHeadsetController(transport: transport)
        await controller.start()

        await #expect(throws: HeadsetError.timeout) {
            try await controller.refresh()
        }
        #expect(controller.currentSnapshot.lastUpdated == nil)
        #expect(controller.currentSnapshot.lastAttemptedAt != nil)
    }

    @Test @MainActor func refreshPublishesOnlyMatchedDecodedValue() async throws {
        let response = RaceFrame(
            opcode: 0x2C83,
            payload: Data([0x02, 0x00, 0x00])
        ).encoded
        let transport = FakeHeadsetTransport(responses: [.success(response)])
        let controller = LiveHeadsetController(transport: transport)
        await controller.start()

        let snapshot = try await controller.refresh()

        #expect(snapshot.values[.automaticMedia] == .boolean(false))
        #expect(snapshot.confidence(for: .automaticMedia) == .deviceConfirmed)
        #expect(snapshot.readiness(for: .automaticMedia) == .readOnly)
        #expect(transport.transactions == [WL5024Command.getAutomaticMedia.transaction])
    }

    @Test @MainActor func malformedRefreshDoesNotMarkDataFresh() async {
        let transport = FakeHeadsetTransport(responses: [.success(Data([0x00, 0x05]))])
        let controller = LiveHeadsetController(transport: transport)
        await controller.start()

        await #expect(throws: HeadsetError.malformedResponse) {
            try await controller.refresh()
        }
        #expect(controller.currentSnapshot.lastUpdated == nil)
        #expect(controller.currentSnapshot.values[.automaticMedia] == nil)
    }

    @Test @MainActor func cancelledRefreshDoesNotMarkDataFresh() async {
        let transport = FakeHeadsetTransport(responses: [.failure(CancellationError())])
        let controller = LiveHeadsetController(transport: transport)
        await controller.start()

        await #expect(throws: CancellationError.self) {
            try await controller.refresh()
        }
        #expect(controller.currentSnapshot.lastUpdated == nil)
        #expect(controller.currentSnapshot.values[.automaticMedia] == nil)
    }

    @Test @MainActor func qualifiedWritePublishesOnlyAfterAcknowledgementAndReadback() async throws {
        let acknowledgement = RaceFrame(
            opcode: 0x2C82,
            payload: Data([0x02, 0x00, 0x00])
        ).encoded
        let readback = RaceFrame(
            opcode: 0x2C83,
            payload: Data([0x02, 0x00, 0x00])
        ).encoded
        let transport = FakeHeadsetTransport(responses: [.success(acknowledgement), .success(readback)])
        let controller = LiveHeadsetController(
            transport: transport,
            qualifiedWrites: [.automaticMedia]
        )
        await controller.start()

        let snapshot = try await controller.set(.automaticMedia, value: .boolean(false))

        #expect(snapshot.values[.automaticMedia] == .boolean(false))
        #expect(transport.transactions == [
            WL5024Command.setAutomaticMedia(false).transaction,
            WL5024Command.getAutomaticMedia.transaction,
        ])
    }

    @Test @MainActor func readbackMismatchDoesNotPublishRequestedValue() async {
        let acknowledgement = RaceFrame(
            opcode: 0x2C82,
            payload: Data([0x02, 0x00, 0x00])
        ).encoded
        let mismatchedReadback = RaceFrame(
            opcode: 0x2C83,
            payload: Data([0x02, 0x00, 0x01])
        ).encoded
        let transport = FakeHeadsetTransport(
            responses: [.success(acknowledgement), .success(mismatchedReadback)]
        )
        let controller = LiveHeadsetController(
            transport: transport,
            qualifiedWrites: [.automaticMedia]
        )
        await controller.start()

        await #expect(throws: HeadsetError.readbackMismatch(.automaticMedia)) {
            try await controller.set(.automaticMedia, value: .boolean(false))
        }
        #expect(controller.currentSnapshot.values[.automaticMedia] == nil)
        #expect(controller.currentSnapshot.lastUpdated == nil)
    }
}

@MainActor
private final class FakeHeadsetTransport: HeadsetTransporting {
    private(set) var activeKind: TransportKind? = .bluetooth
    private(set) var transactions: [TransportTransaction] = []
    private var responses: [Result<Data, any Error>]
    private var updateHandler: (@Sendable (TransportUpdate) -> Void)?

    init(responses: [Result<Data, any Error>]) {
        self.responses = responses
    }

    func start(updateHandler: @escaping @Sendable (TransportUpdate) -> Void) {
        self.updateHandler = updateHandler
        updateHandler(.connectedBluetooth(name: "Test WL5024"))
    }

    func stop() {
        activeKind = nil
        updateHandler = nil
    }

    func transact(
        _ transaction: TransportTransaction,
        timeout: Duration
    ) async throws -> Data {
        transactions.append(transaction)
        guard !responses.isEmpty else { throw HeadsetError.timeout }
        return try responses.removeFirst().get()
    }
}

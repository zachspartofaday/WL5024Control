import Foundation

@MainActor
final class TransportCoordinator: HeadsetTransporting {
    private let bluetooth: any RawHeadsetTransport
    private let hidMonitor: any HIDMonitoring
    private var updateHandler: (@Sendable (TransportUpdate) -> Void)?
    private(set) var activeKind: TransportKind?
    private var activeBluetoothIdentifier: UUID?

    init(
        bluetooth: any RawHeadsetTransport = BLETransport(),
        hidMonitor: any HIDMonitoring = HIDMonitor()
    ) {
        self.bluetooth = bluetooth
        self.hidMonitor = hidMonitor
    }

    func start(updateHandler: @escaping @Sendable (TransportUpdate) -> Void) {
        self.updateHandler = updateHandler
        bluetooth.configure { [weak self] update in
            MainActor.assumeIsolated {
                self?.handleBluetooth(update)
            }
        }
        hidMonitor.start { [weak self] update in
            MainActor.assumeIsolated {
                self?.handleHID(update)
            }
        }
        bluetooth.start()
    }

    func stop() {
        bluetooth.stop()
        hidMonitor.stop()
        activeKind = nil
        activeBluetoothIdentifier = nil
        updateHandler = nil
    }

    func transact(_ transaction: TransportTransaction, timeout: Duration = .seconds(3)) async throws -> Data {
        guard activeKind == .bluetooth else {
            throw HeadsetError.transport("The receiver report profile still needs hardware qualification.")
        }
        return try await bluetooth.transact(transaction, timeout: timeout)
    }

    private func handleBluetooth(_ update: TransportUpdate) {
        if case .connectedBluetooth(_, let identifier) = update, activeKind == nil {
            activeKind = .bluetooth
            activeBluetoothIdentifier = identifier
        } else if case .bluetoothDisconnected(let identifier) = update,
                  activeKind == .bluetooth,
                  activeBluetoothIdentifier == identifier {
            activeKind = nil
            activeBluetoothIdentifier = nil
        } else if case .bluetoothDisconnected = update {
            return
        }
        updateHandler?(update)
    }

    private func handleHID(_ update: TransportUpdate) {
        // Receiver writes remain disabled until its exact interface and report IDs
        // are captured from the user's hardware. Discovery is intentionally read-only.
        updateHandler?(update)
    }
}

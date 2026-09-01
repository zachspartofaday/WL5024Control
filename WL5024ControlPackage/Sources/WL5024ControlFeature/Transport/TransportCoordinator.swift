import Foundation

@MainActor
final class TransportCoordinator {
    private let bluetooth = BLETransport()
    private let hidMonitor = HIDMonitor()
    private var updateHandler: (@Sendable (TransportUpdate) -> Void)?
    private(set) var activeKind: TransportKind?

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
        updateHandler = nil
    }

    func transact(_ request: Data, timeout: Duration = .seconds(3)) async throws -> Data {
        guard activeKind == .bluetooth else {
            throw HeadsetError.transport("The receiver report profile still needs hardware qualification.")
        }
        return try await bluetooth.transact(request, timeout: timeout)
    }

    private func handleBluetooth(_ update: TransportUpdate) {
        if case .connectedBluetooth = update, activeKind == nil {
            activeKind = .bluetooth
        } else if case .disconnected = update, activeKind == .bluetooth {
            activeKind = nil
        }
        updateHandler?(update)
    }

    private func handleHID(_ update: TransportUpdate) {
        // Receiver writes remain disabled until its exact interface and report IDs
        // are captured from the user's hardware. Discovery is intentionally read-only.
        updateHandler?(update)
    }
}

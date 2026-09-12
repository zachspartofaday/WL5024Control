import Foundation

enum TransportStateReducer {
    static func apply(_ update: TransportUpdate, to snapshot: inout HeadsetSnapshot) {
        switch update {
        case .searching(.bluetooth):
            if !snapshot.connection.isConnected {
                snapshot.connection = snapshot.device.receiverDetected
                    ? .qualificationRequired(.receiver)
                    : .searching
            }
        case .searching(.receiver):
            break
        case .connectedBluetooth(_, let identifier):
            invalidateLiveValues(&snapshot)
            snapshot.device.bluetoothSessionId = identifier
            snapshot.connection = .connected(.bluetooth)
            snapshot.device.transport = .bluetooth
        case .receiverFound:
            snapshot.device.receiverDetected = true
            if !snapshot.connection.isConnected {
                snapshot.connection = .qualificationRequired(.receiver)
                snapshot.device.transport = .receiver
            }
        case .receiverRemoved:
            snapshot.device.receiverDetected = false
            if snapshot.connection == .qualificationRequired(.receiver) {
                snapshot.connection = .searching
                snapshot.device.transport = nil
            }
        case .bluetoothDisconnected(let identifier):
            guard snapshot.device.transport == .bluetooth else { break }
            // Ignore stale disconnects for a previous peripheral session.
            if let session = snapshot.device.bluetoothSessionId, session != identifier {
                break
            }
            invalidateLiveValues(&snapshot)
            snapshot.device.bluetoothSessionId = nil
            snapshot.device.transport = snapshot.device.receiverDetected ? .receiver : nil
            snapshot.connection = snapshot.device.receiverDetected
                ? .qualificationRequired(.receiver)
                : .searching
        case .bluetoothPermissionDenied:
            endBluetoothSession(&snapshot)
            snapshot.connection = .bluetoothPermissionDenied
        case .bluetoothUnavailable:
            endBluetoothSession(&snapshot)
            snapshot.connection = snapshot.device.receiverDetected
                ? .qualificationRequired(.receiver)
                : .unavailable
        case .failed(let source, _, let willRetry):
            if source == .bluetooth {
                endBluetoothSession(&snapshot)
                snapshot.connection = snapshot.device.receiverDetected
                    ? .qualificationRequired(.receiver)
                    : (willRetry ? .searching : .failed)
            } else if !willRetry, source == .receiver,
                      source == snapshot.device.transport,
                      !snapshot.connection.isConnected {
                // A receiver-monitor failure must not terminate the
                // independent Bluetooth search path.
                snapshot.device.transport = nil
                snapshot.connection = .searching
            }
        case .unsolicitedBluetooth:
            break
        }
    }

    private static func endBluetoothSession(_ snapshot: inout HeadsetSnapshot) {
        invalidateLiveValues(&snapshot)
        snapshot.device.bluetoothSessionId = nil
        snapshot.device.transport = snapshot.device.receiverDetected ? .receiver : nil
    }

    /// Removes live values/confidence/freshness so a new session cannot
    /// present an earlier peripheral's state as device-confirmed (AUD-001).
    /// Callers set transport/connection/session fields after invoking.
    static func invalidateLiveValues(_ snapshot: inout HeadsetSnapshot) {
        snapshot.values.removeAll()
        snapshot.valueConfidence.removeAll()
        snapshot.readiness.removeAll()
        snapshot.lastUpdated = nil
        snapshot.lastAttemptedAt = nil
    }
}

private extension ConnectionState {
    var isConnected: Bool {
        if case .connected = self { true } else { false }
    }
}

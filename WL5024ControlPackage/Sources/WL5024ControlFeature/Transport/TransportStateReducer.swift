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
            if snapshot.device.bluetoothSessionId != identifier {
                invalidateLiveValues(&snapshot)
                snapshot.device.bluetoothSessionId = identifier
            }
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
            if !snapshot.connection.isConnected {
                snapshot.connection = .bluetoothPermissionDenied
            }
        case .bluetoothUnavailable:
            if !snapshot.connection.isConnected {
                snapshot.connection = .unavailable
            }
        case .failed(let source, _, let willRetry):
            if !snapshot.connection.isConnected, willRetry {
                snapshot.connection = snapshot.device.receiverDetected
                    ? .qualificationRequired(.receiver)
                    : .searching
            } else if !willRetry, source == .bluetooth,
                      source == snapshot.device.transport || !snapshot.connection.isConnected {
                // A terminal Bluetooth failure ends that session/search, but
                // a detected receiver remains a valid discovery fallback.
                if snapshot.device.transport == .bluetooth {
                    invalidateLiveValues(&snapshot)
                    snapshot.device.bluetoothSessionId = nil
                }
                snapshot.device.transport = snapshot.device.receiverDetected ? .receiver : nil
                snapshot.connection = snapshot.device.receiverDetected
                    ? .qualificationRequired(.receiver)
                    : .failed
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

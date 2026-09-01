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
        case .connectedBluetooth:
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
        case .bluetoothDisconnected:
            if snapshot.device.transport == .bluetooth {
                snapshot.device.transport = snapshot.device.receiverDetected ? .receiver : nil
                snapshot.connection = snapshot.device.receiverDetected
                    ? .qualificationRequired(.receiver)
                    : .searching
            }
        case .bluetoothPermissionDenied:
            if !snapshot.connection.isConnected {
                snapshot.connection = .bluetoothPermissionDenied
            }
        case .bluetoothUnavailable:
            if !snapshot.connection.isConnected {
                snapshot.connection = .unavailable
            }
        case .failed(let source, _, let willRetry):
            if source == snapshot.device.transport, !willRetry {
                snapshot.connection = .failed
            } else if !snapshot.connection.isConnected, willRetry {
                snapshot.connection = snapshot.device.receiverDetected
                    ? .qualificationRequired(.receiver)
                    : .searching
            }
        case .unsolicitedBluetooth:
            break
        }
    }
}

private extension ConnectionState {
    var isConnected: Bool {
        if case .connected = self { true } else { false }
    }
}

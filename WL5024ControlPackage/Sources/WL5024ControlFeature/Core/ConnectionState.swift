import Foundation

public enum ConnectionState: Sendable, Equatable {
    case idle
    case searching
    case connected(TransportKind)
    case qualificationRequired(TransportKind)
    case bluetoothPermissionDenied
    case unavailable
    case failed
}

import Foundation

public enum TransportUpdate: Sendable, Equatable {
    case searching
    case connectedBluetooth(name: String)
    case receiverFound(HIDDeviceSummary)
    case disconnected
    case bluetoothPermissionDenied
    case unavailable
    case failed(String)
}

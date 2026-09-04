import Foundation

public enum TransportUpdate: Sendable, Equatable {
    case searching(TransportKind)
    case connectedBluetooth(name: String, identifier: UUID)
    case receiverFound(HIDDeviceSummary)
    case bluetoothDisconnected(identifier: UUID)
    case receiverRemoved
    case bluetoothPermissionDenied
    case bluetoothUnavailable
    case unsolicitedBluetooth(Data)
    case failed(source: TransportKind, message: String, willRetry: Bool)
}

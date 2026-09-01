import Foundation

enum BluetoothLifecycleState: Equatable {
    case stopped
    case scanning
    case connecting
    case discovering
    case subscribing
    case ready
    case retrying
}

enum BluetoothLifecycleEvent {
    case startScanning
    case discoveredPeripheral
    case connected
    case discoveredCharacteristics
    case notificationsEnabled
    case setupFailed
    case stop
}

enum BluetoothLifecyclePolicy {
    static func next(
        after event: BluetoothLifecycleEvent
    ) -> BluetoothLifecycleState {
        switch event {
        case .startScanning: .scanning
        case .discoveredPeripheral: .connecting
        case .connected: .discovering
        case .discoveredCharacteristics: .subscribing
        case .notificationsEnabled: .ready
        case .setupFailed: .retrying
        case .stop: .stopped
        }
    }
}

@preconcurrency import CoreBluetooth
import Foundation

struct BluetoothConnectionMetadata: Equatable {
    let name: String
    let identifier: UUID
    let diagnosticDetails: [String: String]
}

enum BluetoothDiscoveryPolicy {
    static let controlServiceIdentifier = "5052494D-2DAB-0341-6972-6F6861424C45"

    static func isCandidate(
        peripheralName: String?,
        advertisedName: String?,
        advertisedServiceIdentifiers: [String]
    ) -> Bool {
        if advertisedServiceIdentifiers.contains(where: {
            $0.caseInsensitiveCompare(controlServiceIdentifier) == .orderedSame
        }) {
            return true
        }
        return [peripheralName, advertisedName]
            .compactMap { $0 }
            .map(normalize)
            .contains(where: { $0.contains("wl5024") })
    }

    private static func normalize(_ name: String) -> String {
        name.unicodeScalars
            .filter(CharacterSet.alphanumerics.contains)
            .map(String.init)
            .joined()
            .lowercased()
    }
}

enum BluetoothAdapterEvent {
    case lifecycle(BluetoothLifecycleEvent)
    case searching
    case ready(BluetoothConnectionMetadata)
    case disconnected(identifier: UUID)
    case permissionDenied
    case unavailable
    case received(Data)
    case writeAcknowledged(characteristic: String)
    case writeFailed(String)
    case failed(message: String, willRetry: Bool)
}

@MainActor
protocol BluetoothEventSourcing: AnyObject {
    var isReady: Bool { get }
    func start(eventHandler: @escaping @MainActor (BluetoothAdapterEvent) -> Void)
    func stop()
    func write(_ data: Data) throws
}

@MainActor
final class CoreBluetoothEventSource: NSObject, BluetoothEventSourcing {
    static let serviceUUID = CBUUID(string: BluetoothDiscoveryPolicy.controlServiceIdentifier)
    static let firstCharacteristicUUID = CBUUID(string: "43484152-2DAB-3141-6972-6F6861424C45")
    static let secondCharacteristicUUID = CBUUID(string: "43484152-2DAB-3241-6972-6F6861424C45")
    private static let connectionTimeout: Duration = .seconds(12)

    private(set) var isReady = false
    private var centralManager: CBCentralManager?
    private var peripheral: CBPeripheral?
    private var writeCharacteristic: CBCharacteristic?
    private var notifyCharacteristic: CBCharacteristic?
    private var retryTask: Task<Void, Never>?
    private var connectionTimeoutTask: Task<Void, Never>?
    private var connectionAttempt = 0
    private var eventHandler: (@MainActor (BluetoothAdapterEvent) -> Void)?

    func start(eventHandler: @escaping @MainActor (BluetoothAdapterEvent) -> Void) {
        guard centralManager == nil else { return }
        self.eventHandler = eventHandler
        DiagnosticRecorder.shared.record("bluetooth", "Starting CoreBluetooth discovery")
        emit(.lifecycle(.startScanning))
        emit(.searching)
        centralManager = CBCentralManager(delegate: self, queue: .main)
    }

    func stop() {
        retryTask?.cancel()
        retryTask = nil
        connectionTimeoutTask?.cancel()
        connectionTimeoutTask = nil
        if let peripheral {
            centralManager?.cancelPeripheralConnection(peripheral)
        }
        centralManager?.stopScan()
        centralManager = nil
        peripheral = nil
        writeCharacteristic = nil
        notifyCharacteristic = nil
        connectionAttempt = 0
        isReady = false
        emit(.lifecycle(.stop))
        eventHandler = nil
    }

    func write(_ data: Data) throws {
        guard isReady, let peripheral, let writeCharacteristic else {
            throw HeadsetError.disconnected
        }
        let writeType: CBCharacteristicWriteType = writeCharacteristic.properties.contains(.write)
            ? .withResponse
            : .withoutResponse
        peripheral.writeValue(data, for: writeCharacteristic, type: writeType)
    }

    private func emit(_ event: BluetoothAdapterEvent) {
        eventHandler?(event)
    }

    private func beginScanningIfPossible() {
        guard let centralManager else { return }
        switch centralManager.state {
        case .poweredOn:
            guard peripheral == nil, !centralManager.isScanning else { return }
            emit(.lifecycle(.startScanning))
            emit(.searching)
            let connected = centralManager.retrieveConnectedPeripherals(
                withServices: [Self.serviceUUID]
            )
            DiagnosticRecorder.shared.record(
                "bluetooth",
                "Connected-peripheral query completed",
                details: [
                    "count": String(connected.count),
                    "service": Self.serviceUUID.uuidString,
                ]
            )
            if let candidate = connected.first(where: {
                BluetoothDiscoveryPolicy.isCandidate(
                    peripheralName: $0.name,
                    advertisedName: nil,
                    advertisedServiceIdentifiers: [Self.serviceUUID.uuidString]
                )
            }) ?? connected.first {
                select(
                    candidate,
                    using: centralManager,
                    source: "connectedPeripheralQuery",
                    diagnosticDetails: [:]
                )
                return
            }

            DiagnosticRecorder.shared.record(
                "bluetooth",
                "Starting name-gated discovery fallback",
                details: [
                    "acceptedName": "WL5024 (spacing and punctuation ignored)",
                    "acceptedService": Self.serviceUUID.uuidString,
                ]
            )
            centralManager.scanForPeripherals(
                withServices: nil,
                options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
            )
        case .unauthorized:
            emit(.permissionDenied)
        case .unsupported, .poweredOff:
            emit(.unavailable)
        case .resetting, .unknown:
            emit(.searching)
        @unknown default:
            emit(.unavailable)
        }
    }

    private func select(
        _ candidate: CBPeripheral,
        using central: CBCentralManager,
        source: String,
        diagnosticDetails: [String: String]
    ) {
        guard peripheral == nil else { return }
        let details = diagnosticDetails.merging([
            "name": candidate.name ?? "",
            "identifier": candidate.identifier.uuidString,
            "source": source,
        ]) { current, _ in current }
        DiagnosticRecorder.shared.record(
            "bluetooth",
            "WL5024 candidate selected",
            details: details
        )
        connectionTimeoutTask?.cancel()
        connectionAttempt += 1
        peripheral = candidate
        emit(.lifecycle(.discoveredPeripheral))
        candidate.delegate = self
        central.stopScan()
        DiagnosticRecorder.shared.record(
            "bluetooth",
            "Peripheral connection attempt started",
            details: [
                "attempt": String(connectionAttempt),
                "identifier": candidate.identifier.uuidString,
                "timeoutSeconds": "12",
            ]
        )
        central.connect(candidate)
        connectionTimeoutTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: Self.connectionTimeout)
                guard let self,
                      self.peripheral?.identifier == candidate.identifier,
                      !self.isReady else { return }
                DiagnosticRecorder.shared.record(
                    "bluetooth",
                    "Peripheral connection timed out",
                    details: [
                        "attempt": String(self.connectionAttempt),
                        "identifier": candidate.identifier.uuidString,
                    ]
                )
                self.failSetup("The Bluetooth connection attempt timed out.")
            } catch is CancellationError {
                // Readiness, failure, or source shutdown cancelled the watchdog.
            } catch {
                guard let self,
                      self.peripheral?.identifier == candidate.identifier,
                      !self.isReady else { return }
                self.failSetup("The Bluetooth connection attempt timed out.")
            }
        }
    }

    private func configureCharacteristics(_ characteristics: [CBCharacteristic]) {
        writeCharacteristic = characteristics.first {
            $0.properties.contains(.write) || $0.properties.contains(.writeWithoutResponse)
        }
        notifyCharacteristic = characteristics.first {
            $0.properties.contains(.notify) || $0.properties.contains(.indicate)
        }
        guard let peripheral, writeCharacteristic != nil, let notifyCharacteristic else {
            failSetup("The Airoha control characteristics were incomplete.", willRetry: false)
            return
        }
        peripheral.setNotifyValue(true, for: notifyCharacteristic)
        emit(.lifecycle(.discoveredCharacteristics))
    }

    private func completeSetup() {
        guard let peripheral,
              let writeCharacteristic,
              let notifyCharacteristic,
              notifyCharacteristic.isNotifying else {
            failSetup("The headset did not enable control notifications.")
            return
        }
        isReady = true
        connectionTimeoutTask?.cancel()
        connectionTimeoutTask = nil
        retryTask?.cancel()
        retryTask = nil
        emit(.lifecycle(.notificationsEnabled))
        let name = peripheral.name?.isEmpty == false ? peripheral.name! : "Dell WL5024"
        let details = [
            "name": name,
            "identifier": peripheral.identifier.uuidString,
            "writeCharacteristic": writeCharacteristic.uuid.uuidString,
            "writeProperties": String(writeCharacteristic.properties.rawValue),
            "notifyCharacteristic": notifyCharacteristic.uuid.uuidString,
            "notifyProperties": String(notifyCharacteristic.properties.rawValue),
            "maximumWriteWithResponse": String(peripheral.maximumWriteValueLength(for: .withResponse)),
            "maximumWriteWithoutResponse": String(peripheral.maximumWriteValueLength(for: .withoutResponse)),
        ]
        DiagnosticRecorder.shared.record("bluetooth", "Control characteristics ready", details: details)
        emit(.ready(BluetoothConnectionMetadata(
            name: name,
            identifier: peripheral.identifier,
            diagnosticDetails: details
        )))
        if notifyCharacteristic == writeCharacteristic,
           notifyCharacteristic.properties.contains(.read) {
            peripheral.readValue(for: notifyCharacteristic)
        }
    }

    private func failSetup(_ message: String, willRetry: Bool = true) {
        connectionTimeoutTask?.cancel()
        connectionTimeoutTask = nil
        isReady = false
        writeCharacteristic = nil
        notifyCharacteristic = nil
        emit(.lifecycle(.setupFailed))
        emit(.failed(message: message, willRetry: willRetry))
        if let peripheral {
            centralManager?.cancelPeripheralConnection(peripheral)
        }
        peripheral = nil
        retryTask?.cancel()
        guard willRetry else {
            retryTask = nil
            return
        }
        retryTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .seconds(1))
                self?.beginScanningIfPossible()
            } catch is CancellationError {
                // Stopping the source cancels the retry.
            } catch {
                self?.beginScanningIfPossible()
            }
        }
    }
}

extension CoreBluetoothEventSource: @preconcurrency CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        DiagnosticRecorder.shared.record(
            "bluetooth",
            "Central state changed",
            details: [
                "state": String(central.state.rawValue),
                "stateName": Self.stateName(central.state),
                "authorization": String(CBCentralManager.authorization.rawValue),
            ]
        )
        beginScanningIfPossible()
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        guard self.peripheral == nil else { return }
        let advertisedName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        let advertisedServices = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? [])
            .map(\.uuidString)
        guard BluetoothDiscoveryPolicy.isCandidate(
            peripheralName: peripheral.name,
            advertisedName: advertisedName,
            advertisedServiceIdentifiers: advertisedServices
        ) else { return }
        select(
            peripheral,
            using: central,
            source: "nameGatedScan",
            diagnosticDetails: [
                "advertisedName": advertisedName ?? "",
                "advertisedServices": advertisedServices.sorted().joined(separator: ","),
                "isConnectable": String(
                    (advertisementData[CBAdvertisementDataIsConnectable] as? NSNumber)?.boolValue ?? false
                ),
                "rssi": RSSI.stringValue,
                "advertisementKeys": advertisementData.keys.sorted().joined(separator: ","),
            ]
        )
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        guard self.peripheral?.identifier == peripheral.identifier else {
            central.cancelPeripheralConnection(peripheral)
            return
        }
        emit(.lifecycle(.connected))
        DiagnosticRecorder.shared.record(
            "bluetooth",
            "Peripheral connected",
            details: ["identifier": peripheral.identifier.uuidString]
        )
        peripheral.discoverServices([Self.serviceUUID])
    }

    func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: (any Error)?
    ) {
        guard self.peripheral?.identifier == peripheral.identifier else { return }
        failSetup(error?.localizedDescription ?? "Unable to connect over Bluetooth.")
    }

    func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        timestamp: CFAbsoluteTime,
        isReconnecting: Bool,
        error: (any Error)?
    ) {
        guard self.peripheral?.identifier == peripheral.identifier else { return }
        connectionTimeoutTask?.cancel()
        connectionTimeoutTask = nil
        isReady = false
        DiagnosticRecorder.shared.record(
            "bluetooth",
            "Peripheral disconnected",
            details: [
                "identifier": peripheral.identifier.uuidString,
                "error": error?.localizedDescription ?? "",
            ]
        )
        self.peripheral = nil
        writeCharacteristic = nil
        notifyCharacteristic = nil
        emit(.disconnected(identifier: peripheral.identifier))
        beginScanningIfPossible()
    }
}

private extension CoreBluetoothEventSource {
    static func stateName(_ state: CBManagerState) -> String {
        switch state {
        case .unknown: "unknown"
        case .resetting: "resetting"
        case .unsupported: "unsupported"
        case .unauthorized: "unauthorized"
        case .poweredOff: "poweredOff"
        case .poweredOn: "poweredOn"
        @unknown default: "unrecognized"
        }
    }
}

extension CoreBluetoothEventSource: @preconcurrency CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: (any Error)?) {
        if let error {
            failSetup(error.localizedDescription)
            return
        }
        guard let service = peripheral.services?.first(where: { $0.uuid == Self.serviceUUID }) else {
            failSetup("The WL5024 control service was not found.", willRetry: false)
            return
        }
        DiagnosticRecorder.shared.record(
            "bluetooth",
            "Control service discovered",
            details: ["uuid": service.uuid.uuidString]
        )
        peripheral.discoverCharacteristics(
            [Self.firstCharacteristicUUID, Self.secondCharacteristicUUID],
            for: service
        )
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: (any Error)?
    ) {
        if let error {
            failSetup(error.localizedDescription)
        } else {
            configureCharacteristics(service.characteristics ?? [])
        }
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateNotificationStateFor characteristic: CBCharacteristic,
        error: (any Error)?
    ) {
        guard characteristic.uuid == notifyCharacteristic?.uuid else { return }
        if let error {
            failSetup(error.localizedDescription)
        } else {
            completeSetup()
        }
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: (any Error)?
    ) {
        if let error {
            emit(.failed(message: error.localizedDescription, willRetry: false))
            return
        }
        guard characteristic.uuid == notifyCharacteristic?.uuid, let value = characteristic.value else {
            return
        }
        DiagnosticRecorder.shared.record(
            "bluetooth-rx",
            "Characteristic notification",
            details: [
                "characteristic": characteristic.uuid.uuidString,
                "bytes": DiagnosticRecorder.hex(value),
            ]
        )
        emit(.received(value))
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didWriteValueFor characteristic: CBCharacteristic,
        error: (any Error)?
    ) {
        if let error {
            emit(.writeFailed(error.localizedDescription))
        } else {
            emit(.writeAcknowledged(characteristic: characteristic.uuid.uuidString))
        }
    }
}

@preconcurrency import CoreBluetooth
import Foundation

@MainActor
final class BLETransport: NSObject, RawHeadsetTransport {
    static let serviceUUID = CBUUID(string: "5052494D-2DAB-0341-6972-6F6861424C45")
    static let firstCharacteristicUUID = CBUUID(string: "43484152-2DAB-3141-6972-6F6861424C45")
    static let secondCharacteristicUUID = CBUUID(string: "43484152-2DAB-3241-6972-6F6861424C45")

    let kind = TransportKind.bluetooth
    private(set) var isReady = false

    private var centralManager: CBCentralManager?
    private var peripheral: CBPeripheral?
    private var writeCharacteristic: CBCharacteristic?
    private var notifyCharacteristic: CBCharacteristic?
    private var updateHandler: (@Sendable (TransportUpdate) -> Void)?
    private var pendingContinuation: CheckedContinuation<Data, any Error>?
    private var timeoutTask: Task<Void, Never>?

    func configure(updateHandler: @escaping @Sendable (TransportUpdate) -> Void) {
        self.updateHandler = updateHandler
    }

    func start() {
        guard centralManager == nil else { return }
        DiagnosticRecorder.shared.record("bluetooth", "Starting CoreBluetooth discovery")
        updateHandler?(.searching)
        centralManager = CBCentralManager(delegate: self, queue: .main)
    }

    func stop() {
        timeoutTask?.cancel()
        timeoutTask = nil
        finishPending(with: .failure(CancellationError()))
        if let peripheral {
            centralManager?.cancelPeripheralConnection(peripheral)
        }
        centralManager?.stopScan()
        centralManager = nil
        self.peripheral = nil
        writeCharacteristic = nil
        notifyCharacteristic = nil
        isReady = false
    }

    func transact(_ request: Data, timeout: Duration) async throws -> Data {
        guard isReady,
              let peripheral,
              let writeCharacteristic else {
            throw HeadsetError.disconnected
        }
        guard pendingContinuation == nil else {
            throw HeadsetError.busy
        }

        DiagnosticRecorder.shared.record(
            "bluetooth-tx",
            "RACE request",
            details: ["bytes": DiagnosticRecorder.hex(request)]
        )

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                pendingContinuation = continuation
                let writeType: CBCharacteristicWriteType = writeCharacteristic.properties.contains(.write)
                    ? .withResponse
                    : .withoutResponse
                peripheral.writeValue(request, for: writeCharacteristic, type: writeType)

                timeoutTask = Task { @MainActor [weak self] in
                    do {
                        try await Task.sleep(for: timeout)
                        self?.finishPending(with: .failure(HeadsetError.timeout))
                    } catch is CancellationError {
                        // The response arrived or the transport stopped.
                    } catch {
                        self?.finishPending(with: .failure(HeadsetError.timeout))
                    }
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.finishPending(with: .failure(CancellationError()))
            }
        }
    }

    private func beginScanningIfPossible() {
        guard let centralManager else { return }
        switch centralManager.state {
        case .poweredOn:
            updateHandler?(.searching)
            centralManager.scanForPeripherals(
                withServices: [Self.serviceUUID],
                options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
            )
        case .unauthorized:
            updateHandler?(.bluetoothPermissionDenied)
        case .unsupported, .poweredOff:
            updateHandler?(.unavailable)
        case .resetting, .unknown:
            updateHandler?(.searching)
        @unknown default:
            updateHandler?(.unavailable)
        }
    }

    private func configureCharacteristics(_ characteristics: [CBCharacteristic]) {
        writeCharacteristic = characteristics.first { characteristic in
            characteristic.properties.contains(.write) || characteristic.properties.contains(.writeWithoutResponse)
        }
        notifyCharacteristic = characteristics.first { $0.properties.contains(.notify) || $0.properties.contains(.indicate) }

        guard let peripheral,
              let writeCharacteristic,
              let notifyCharacteristic else {
            updateHandler?(.failed("The Airoha control characteristics were incomplete."))
            return
        }

        peripheral.setNotifyValue(true, for: notifyCharacteristic)
        isReady = true
        let name = peripheral.name?.isEmpty == false ? peripheral.name! : "Dell WL5024"
        DiagnosticRecorder.shared.record(
            "bluetooth",
            "Control characteristics ready",
            details: [
                "name": name,
                "identifier": peripheral.identifier.uuidString,
                "writeCharacteristic": writeCharacteristic.uuid.uuidString,
                "writeProperties": String(writeCharacteristic.properties.rawValue),
                "notifyCharacteristic": notifyCharacteristic.uuid.uuidString,
                "notifyProperties": String(notifyCharacteristic.properties.rawValue),
                "maximumWriteWithResponse": String(peripheral.maximumWriteValueLength(for: .withResponse)),
                "maximumWriteWithoutResponse": String(peripheral.maximumWriteValueLength(for: .withoutResponse)),
            ]
        )
        updateHandler?(.connectedBluetooth(name: name))

        if notifyCharacteristic == writeCharacteristic,
           notifyCharacteristic.properties.contains(.read) {
            peripheral.readValue(for: notifyCharacteristic)
        }
    }

    private func finishPending(with result: Result<Data, any Error>) {
        timeoutTask?.cancel()
        timeoutTask = nil
        guard let continuation = pendingContinuation else { return }
        pendingContinuation = nil
        continuation.resume(with: result)
    }
}

extension BLETransport: @preconcurrency CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        DiagnosticRecorder.shared.record(
            "bluetooth",
            "Central state changed",
            details: ["state": String(central.state.rawValue)]
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
        DiagnosticRecorder.shared.record(
            "bluetooth",
            "Control-service peripheral discovered",
            details: [
                "name": peripheral.name ?? "",
                "identifier": peripheral.identifier.uuidString,
                "rssi": RSSI.stringValue,
                "advertisementKeys": advertisementData.keys.sorted().joined(separator: ","),
            ]
        )
        self.peripheral = peripheral
        peripheral.delegate = self
        central.stopScan()
        central.connect(peripheral)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
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
        self.peripheral = nil
        updateHandler?(.failed(error?.localizedDescription ?? "Unable to connect over Bluetooth."))
        beginScanningIfPossible()
    }

    func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        timestamp: CFAbsoluteTime,
        isReconnecting: Bool,
        error: (any Error)?
    ) {
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
        finishPending(with: .failure(HeadsetError.disconnected))
        updateHandler?(.disconnected)
        beginScanningIfPossible()
    }
}

extension BLETransport: @preconcurrency CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: (any Error)?) {
        if let error {
            updateHandler?(.failed(error.localizedDescription))
            return
        }
        guard let service = peripheral.services?.first(where: { $0.uuid == Self.serviceUUID }) else {
            updateHandler?(.failed("The WL5024 control service was not found."))
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
            updateHandler?(.failed(error.localizedDescription))
            return
        }
        configureCharacteristics(service.characteristics ?? [])
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: (any Error)?
    ) {
        if let error {
            finishPending(with: .failure(error))
            return
        }
        guard characteristic.uuid == notifyCharacteristic?.uuid,
              let value = characteristic.value else {
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
        guard pendingContinuation != nil else { return }
        finishPending(with: .success(value))
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didWriteValueFor characteristic: CBCharacteristic,
        error: (any Error)?
    ) {
        if let error {
            finishPending(with: .failure(error))
        }
    }
}

@preconcurrency import CoreBluetooth
import Foundation

@MainActor
final class BLETransport: NSObject, RawHeadsetTransport {
    static let serviceUUID = CBUUID(string: "5052494D-2DAB-0341-6972-6F6861424C45")
    static let firstCharacteristicUUID = CBUUID(string: "43484152-2DAB-3141-6972-6F6861424C45")
    static let secondCharacteristicUUID = CBUUID(string: "43484152-2DAB-3241-6972-6F6861424C45")

    let kind = TransportKind.bluetooth
    private(set) var isReady = false
    private(set) var lifecycle: BluetoothLifecycleState = .stopped

    private var centralManager: CBCentralManager?
    private var peripheral: CBPeripheral?
    private var writeCharacteristic: CBCharacteristic?
    private var notifyCharacteristic: CBCharacteristic?
    private var updateHandler: (@Sendable (TransportUpdate) -> Void)?
    private var pendingContinuation: CheckedContinuation<Data, any Error>?
    private var pendingMatcher: RaceResponseMatcher?
    private var timeoutTask: Task<Void, Never>?
    private var retryTask: Task<Void, Never>?

    func configure(updateHandler: @escaping @Sendable (TransportUpdate) -> Void) {
        self.updateHandler = updateHandler
    }

    func start() {
        guard centralManager == nil else { return }
        DiagnosticRecorder.shared.record("bluetooth", "Starting CoreBluetooth discovery")
        transition(.startScanning)
        updateHandler?(.searching(.bluetooth))
        centralManager = CBCentralManager(delegate: self, queue: .main)
    }

    func stop() {
        timeoutTask?.cancel()
        timeoutTask = nil
        retryTask?.cancel()
        retryTask = nil
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
        transition(.stop)
    }

    func transact(_ transaction: TransportTransaction, timeout: Duration) async throws -> Data {
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
            details: ["bytes": DiagnosticRecorder.hex(transaction.request)]
        )

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                pendingContinuation = continuation
                pendingMatcher = transaction.expectedResponse
                let writeType: CBCharacteristicWriteType = writeCharacteristic.properties.contains(.write)
                    ? .withResponse
                    : .withoutResponse
                peripheral.writeValue(transaction.request, for: writeCharacteristic, type: writeType)

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
            transition(.startScanning)
            updateHandler?(.searching(.bluetooth))
            centralManager.scanForPeripherals(
                withServices: [Self.serviceUUID],
                options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
            )
        case .unauthorized:
            updateHandler?(.bluetoothPermissionDenied)
        case .unsupported, .poweredOff:
            updateHandler?(.bluetoothUnavailable)
        case .resetting, .unknown:
            updateHandler?(.searching(.bluetooth))
        @unknown default:
            updateHandler?(.bluetoothUnavailable)
        }
    }

    private func configureCharacteristics(_ characteristics: [CBCharacteristic]) {
        writeCharacteristic = characteristics.first { characteristic in
            characteristic.properties.contains(.write) || characteristic.properties.contains(.writeWithoutResponse)
        }
        notifyCharacteristic = characteristics.first { $0.properties.contains(.notify) || $0.properties.contains(.indicate) }

        guard let peripheral,
              writeCharacteristic != nil,
              let notifyCharacteristic else {
            failSetup("The Airoha control characteristics were incomplete.")
            return
        }

        peripheral.setNotifyValue(true, for: notifyCharacteristic)
        transition(.discoveredCharacteristics)
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
        transition(.notificationsEnabled)
        retryTask?.cancel()
        retryTask = nil
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
        pendingMatcher = nil
        continuation.resume(with: result)
    }

    private func failSetup(_ message: String) {
        isReady = false
        transition(.setupFailed)
        writeCharacteristic = nil
        notifyCharacteristic = nil
        finishPending(with: .failure(HeadsetError.transport(message)))
        updateHandler?(.failed(source: .bluetooth, message: message, willRetry: true))

        if let peripheral {
            centralManager?.cancelPeripheralConnection(peripheral)
        }
        peripheral = nil
        retryTask?.cancel()
        retryTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .seconds(1))
                self?.beginScanningIfPossible()
            } catch is CancellationError {
                // The transport stopped or a newer retry replaced this one.
            } catch {
                self?.beginScanningIfPossible()
            }
        }
    }

    private func transition(_ event: BluetoothLifecycleEvent) {
        lifecycle = BluetoothLifecyclePolicy.next(after: event)
        DiagnosticRecorder.shared.record(
            "bluetooth",
            "Lifecycle changed",
            details: ["state": String(describing: lifecycle)]
        )
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
        transition(.discoveredPeripheral)
        peripheral.delegate = self
        central.stopScan()
        central.connect(peripheral)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        transition(.connected)
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
        updateHandler?(.bluetoothDisconnected)
        beginScanningIfPossible()
    }
}

extension BLETransport: @preconcurrency CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: (any Error)?) {
        if let error {
            failSetup(error.localizedDescription)
            return
        }
        guard let service = peripheral.services?.first(where: { $0.uuid == Self.serviceUUID }) else {
            failSetup("The WL5024 control service was not found.")
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
            return
        }
        configureCharacteristics(service.characteristics ?? [])
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateNotificationStateFor characteristic: CBCharacteristic,
        error: (any Error)?
    ) {
        guard characteristic.uuid == notifyCharacteristic?.uuid else { return }
        if let error {
            failSetup(error.localizedDescription)
            return
        }
        completeSetup()
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: (any Error)?
    ) {
        if let error {
            if pendingContinuation != nil {
                finishPending(with: .failure(error))
            } else {
                updateHandler?(.failed(source: .bluetooth, message: error.localizedDescription, willRetry: false))
            }
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
        guard pendingContinuation != nil,
              TransactionResponseRouter.classify(value, pending: pendingMatcher) == .matched else {
            updateHandler?(.unsolicitedBluetooth(value))
            return
        }
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

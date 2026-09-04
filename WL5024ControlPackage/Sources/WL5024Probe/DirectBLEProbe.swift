@preconcurrency import CoreBluetooth
import CoreFoundation
import Foundation
import WL5024ControlFeature

/// A terminal-first, read-only CoreBluetooth probe for adaptive hardware research.
///
/// Unlike the app's diagnostic recorder, this prints service discovery, GATT acknowledgements,
/// notifications, and RACE response matching as they happen. Its request list contains only
/// recovered getter commands; it never constructs setters or maintenance operations.
enum DirectBLEProbe {
    private static let defaultPreferenceModules: [UInt16] = [0, 1, 6, 7, 8, 9, 16]

    static func run(arguments: [String]) {
        let options = Options(arguments: arguments)
        let runner = Runner(options: options)
        if runner.start() {
            CFRunLoopRun()
        }
    }
}

private extension DirectBLEProbe {
    struct Options {
        let preferenceModules: [UInt16]
        let responseTimeout: TimeInterval
        let finalListenDuration: TimeInterval
        let onlyIdentifiers: Set<String>
        let repeatCount: Int

        init(arguments: [String]) {
            let explicitModules = arguments.compactMap { argument -> UInt16? in
                guard argument.hasPrefix("--module=") else { return nil }
                return UInt16(argument.dropFirst("--module=".count))
            }

            if arguments.contains("--all-modules") {
                preferenceModules = Array(0...255)
            } else if explicitModules.isEmpty {
                preferenceModules = DirectBLEProbe.defaultPreferenceModules
            } else {
                preferenceModules = Array(Set(explicitModules)).sorted()
            }

            responseTimeout = Self.seconds(
                arguments: arguments,
                prefix: "--timeout-ms=",
                divisor: 1_000,
                defaultValue: 1.5,
                range: 0.25...10
            )
            finalListenDuration = Self.seconds(
                arguments: arguments,
                prefix: "--listen-seconds=",
                divisor: 1,
                defaultValue: 2,
                range: 0...60
            )
            onlyIdentifiers = Set(arguments.compactMap { argument in
                guard argument.hasPrefix("--only=") else { return nil }
                return String(argument.dropFirst("--only=".count))
            })
            repeatCount = arguments.first(where: { $0.hasPrefix("--repeat=") })
                .flatMap { Int($0.dropFirst("--repeat=".count)) }
                .map { min(max($0, 1), 100) }
                ?? 1
        }

        private static func seconds(
            arguments: [String],
            prefix: String,
            divisor: Double,
            defaultValue: Double,
            range: ClosedRange<Double>
        ) -> Double {
            guard let argument = arguments.first(where: { $0.hasPrefix(prefix) }),
                  let rawValue = Double(argument.dropFirst(prefix.count)) else {
                return defaultValue
            }
            return min(max(rawValue / divisor, range.lowerBound), range.upperBound)
        }
    }

    struct Probe {
        let name: String
        let transaction: TransportTransaction
    }

    final class Runner: NSObject {
        private static let serviceUUID = CBUUID(string: "5052494D-2DAB-0341-6972-6F6861424C45")
        private static let deviceInformationServiceUUID = CBUUID(string: "180A")
        private static let firmwareRevisionCharacteristicUUID = CBUUID(string: "2A26")
        private static let firstCharacteristicUUID = CBUUID(
            string: "43484152-2DAB-3141-6972-6F6861424C45"
        )
        private static let secondCharacteristicUUID = CBUUID(
            string: "43484152-2DAB-3241-6972-6F6861424C45"
        )

        private let options: Options
        private let probes: [Probe]
        private let launchUptime = ProcessInfo.processInfo.systemUptime

        private var central: CBCentralManager?
        private var peripheral: CBPeripheral?
        private var writeCharacteristic: CBCharacteristic?
        private var notifyCharacteristic: CBCharacteristic?
        private var connectionTimer: Timer?
        private var responseTimer: Timer?
        private var transitionTimer: Timer?
        private var nextProbeIndex = 0
        private var pendingProbe: Probe?
        private var pendingStartedAt: TimeInterval?
        private var responseCount = 0
        private var timeoutCount = 0
        private var unsolicitedCount = 0
        private var finished = false

        init(options: Options) {
            self.options = options
            let availableProbes = options.preferenceModules.map { module in
                Probe(
                    name: "preference.module.\(module)",
                    transaction: WL5024Command.getPreference(module: module).transaction
                )
            } + [
                Probe(name: "wear-detection", transaction: WL5024Command.getWearDetection.transaction),
                Probe(name: "busy-light", transaction: WL5024Command.getBusyLight.transaction),
                Probe(name: "voice-guidance", transaction: WL5024Command.getVoiceGuidance.transaction),
                Probe(
                    name: "incoming-audio-noise-cancellation",
                    transaction: WL5024Command.getIncomingAudioNoiseCancellation.transaction
                ),
                Probe(
                    name: "microphone-noise-cancellation",
                    transaction: WL5024Command.getMicrophoneNoiseCancellation.transaction
                ),
                Probe(
                    name: "environment-detection",
                    transaction: WL5024Command.getEnvironmentDetection.transaction
                ),
                Probe(name: "smart-switch", transaction: WL5024Command.getSmartSwitch.transaction),
                Probe(
                    name: "firmware-v4.mic-flip-action",
                    transaction: WL5024Command.getMicFlipAction.transaction
                ),
                Probe(
                    name: "firmware-v4.uc-profile",
                    transaction: WL5024Command.getUCProfile.transaction
                ),
                Probe(
                    name: "firmware-v4.uc-app-status",
                    transaction: WL5024Command.getUCAppStatus.transaction
                ),
                Probe(
                    name: "firmware-v4.le-audio-feature-mode",
                    transaction: WL5024Command.getLEAudioFeatureMode.transaction
                ),
                Probe(
                    name: "vendor.anc-status",
                    transaction: Self.vendorSettingGetter(module: 5)
                ),
                Probe(
                    name: "vendor.pass-through-gain",
                    transaction: Self.vendorSettingGetter(module: 7)
                ),
            ]
            let selectedProbes = options.onlyIdentifiers.isEmpty
                ? availableProbes
                : availableProbes.filter { options.onlyIdentifiers.contains($0.name) }
            probes = (0..<options.repeatCount).flatMap { repetition in
                selectedProbes.map { probe in
                    guard options.repeatCount > 1 else { return probe }
                    return Probe(
                        name: "\(probe.name)#\(repetition + 1)",
                        transaction: probe.transaction
                    )
                }
            }
        }

        private static func vendorSettingGetter(module: UInt16) -> TransportTransaction {
            let payload = Data([
                UInt8(truncatingIfNeeded: module),
                UInt8(truncatingIfNeeded: module >> 8),
            ])
            return TransportTransaction(
                request: RaceFrame(opcode: 0x0901, payload: payload).encoded,
                expectedResponse: RaceResponseMatcher(opcode: 0x0901, module: module)
            )
        }

        func start() -> Bool {
            guard !probes.isEmpty else {
                log("ERROR", "No getter matched the supplied --only identifier.")
                return false
            }
            log("START", "read-only direct probe; \(probes.count) requests; timeout \(options.responseTimeout)s")
            central = CBCentralManager(delegate: self, queue: .main)
            connectionTimer = scheduledTimer(seconds: 30, selector: #selector(connectionTimedOut))
            return true
        }

        @objc private func connectionTimedOut() {
            fail("No ready WL5024 control service within 30 seconds.")
        }

        @objc private func responseTimedOut() {
            guard let pendingProbe else { return }
            timeoutCount += 1
            log("TIMEOUT", "\(pendingProbe.name) after \(format(options.responseTimeout))s")
            self.pendingProbe = nil
            pendingStartedAt = nil
            scheduleAdvance()
        }

        @objc private func advance() {
            transitionTimer?.invalidate()
            transitionTimer = nil

            guard !finished else { return }
            guard nextProbeIndex < probes.count else {
                beginFinalListen()
                return
            }
            guard let peripheral, let writeCharacteristic else {
                fail("The control characteristic became unavailable.")
                return
            }

            let probe = probes[nextProbeIndex]
            nextProbeIndex += 1
            pendingProbe = probe
            pendingStartedAt = ProcessInfo.processInfo.systemUptime
            log("TX", "\(probe.name) | \(hex(probe.transaction.request))")

            let writeType: CBCharacteristicWriteType = writeCharacteristic.properties.contains(.write)
                ? .withResponse
                : .withoutResponse
            peripheral.writeValue(probe.transaction.request, for: writeCharacteristic, type: writeType)
            responseTimer = scheduledTimer(
                seconds: options.responseTimeout,
                selector: #selector(responseTimedOut)
            )
        }

        @objc private func finishAfterListening() {
            succeed()
        }

        private func beginScanning() {
            guard let central else { return }
            let connected = central.retrieveConnectedPeripherals(withServices: [Self.serviceUUID])
            log("SCAN", "retrieveConnectedPeripherals returned \(connected.count) candidate(s)")
            if let candidate = connected.first(where: { Self.isWL5024($0.name) }) ?? connected.first {
                connect(candidate, source: "connected service query")
                return
            }
            log("SCAN", "starting name/service-gated scan")
            central.scanForPeripherals(
                withServices: nil,
                options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
            )
        }

        private func connect(_ candidate: CBPeripheral, source: String) {
            guard peripheral == nil, let central else { return }
            peripheral = candidate
            candidate.delegate = self
            central.stopScan()
            log(
                "CONNECT",
                "\(candidate.name ?? "unnamed") | \(candidate.identifier.uuidString) | \(source)"
            )
            central.connect(candidate)
        }

        private func configure(_ characteristics: [CBCharacteristic]) {
            for characteristic in characteristics {
                log(
                    "GATT",
                    "characteristic \(characteristic.uuid.uuidString) properties "
                        + Self.propertyDescription(characteristic.properties)
                )
            }

            writeCharacteristic = characteristics.first(where: {
                $0.uuid == Self.firstCharacteristicUUID
                    && ($0.properties.contains(.write) || $0.properties.contains(.writeWithoutResponse))
            }) ?? characteristics.first(where: {
                $0.properties.contains(.write) || $0.properties.contains(.writeWithoutResponse)
            })
            notifyCharacteristic = characteristics.first(where: {
                $0.uuid == Self.secondCharacteristicUUID
                    && ($0.properties.contains(.notify) || $0.properties.contains(.indicate))
            }) ?? characteristics.first(where: {
                $0.properties.contains(.notify) || $0.properties.contains(.indicate)
            })

            guard let peripheral, writeCharacteristic != nil, let notifyCharacteristic else {
                fail("The recovered service did not expose both writable and notifying characteristics.")
                return
            }
            peripheral.setNotifyValue(true, for: notifyCharacteristic)
        }

        private func ready() {
            connectionTimer?.invalidate()
            connectionTimer = nil
            guard let peripheral, let writeCharacteristic, let notifyCharacteristic else {
                fail("The recovered characteristics disappeared during setup.")
                return
            }

            log(
                "READY",
                "write \(writeCharacteristic.uuid.uuidString), notify \(notifyCharacteristic.uuid.uuidString), "
                    + "MTU withResponse=\(peripheral.maximumWriteValueLength(for: .withResponse)), "
                    + "withoutResponse=\(peripheral.maximumWriteValueLength(for: .withoutResponse))"
            )
            transitionTimer = scheduledTimer(seconds: 0.2, selector: #selector(advance))
        }

        private func handleNotification(_ data: Data) {
            let frameDescription: String
            if let frame = try? RaceFrame(decoding: data) {
                frameDescription = "type=0x\(String(format: "%02X", frame.packetType.rawValue)) "
                    + "opcode=0x\(String(format: "%04X", frame.opcode)) "
                    + "payload=[\(hex(frame.payload))]"
            } else {
                frameDescription = "not a complete RACE frame"
            }
            log("RX", "\(hex(data)) | \(frameDescription)")

            guard let pendingProbe else {
                unsolicitedCount += 1
                log("UNSOLICITED", "notification arrived with no pending request")
                return
            }

            let exactMatch = pendingProbe.transaction.expectedResponse.matches(data)
            let statusOnlyMatch: Bool
            if let frame = try? RaceFrame(decoding: data) {
                statusOnlyMatch = frame.packetType == .response
                    && frame.opcode == pendingProbe.transaction.expectedResponse.opcode
                    && frame.payload.count == 1
            } else {
                statusOnlyMatch = false
            }
            guard exactMatch || statusOnlyMatch else {
                unsolicitedCount += 1
                log("UNSOLICITED", "notification did not match the pending request")
                return
            }

            responseCount += 1
            let latency = pendingStartedAt.map {
                (ProcessInfo.processInfo.systemUptime - $0) * 1_000
            } ?? 0
            let matchKind = statusOnlyMatch ? "status-only" : "value"
            log("MATCH", "\(pendingProbe.name) in \(format(latency))ms (\(matchKind) response)")
            responseTimer?.invalidate()
            responseTimer = nil
            self.pendingProbe = nil
            pendingStartedAt = nil
            scheduleAdvance()
        }

        private func scheduleAdvance() {
            transitionTimer?.invalidate()
            transitionTimer = scheduledTimer(seconds: 0.1, selector: #selector(advance))
        }

        private func beginFinalListen() {
            guard options.finalListenDuration > 0 else {
                succeed()
                return
            }
            log("LISTEN", "capturing unsolicited notifications for \(format(options.finalListenDuration))s")
            transitionTimer = scheduledTimer(
                seconds: options.finalListenDuration,
                selector: #selector(finishAfterListening)
            )
        }

        private func succeed() {
            finish(
                status: "DONE",
                message: "requests=\(probes.count) responses=\(responseCount) "
                    + "timeouts=\(timeoutCount) unsolicited=\(unsolicitedCount)"
            )
        }

        private func fail(_ message: String) {
            finish(status: "ERROR", message: message)
        }

        private func finish(status: String, message: String) {
            guard !finished else { return }
            finished = true
            connectionTimer?.invalidate()
            responseTimer?.invalidate()
            transitionTimer?.invalidate()
            if let peripheral {
                central?.cancelPeripheralConnection(peripheral)
            }
            central?.stopScan()
            log(status, message)
            CFRunLoopStop(CFRunLoopGetMain())
        }

        private func scheduledTimer(seconds: TimeInterval, selector: Selector) -> Timer {
            let timer = Timer(timeInterval: seconds, target: self, selector: selector, userInfo: nil, repeats: false)
            RunLoop.main.add(timer, forMode: .common)
            return timer
        }

        private func log(_ category: String, _ message: String) {
            let elapsed = ProcessInfo.processInfo.systemUptime - launchUptime
            print("[+\(format(elapsed))s] \(category) \(message)")
            fflush(stdout)
        }

        private func hex(_ data: Data) -> String {
            data.map { String(format: "%02X", $0) }.joined(separator: " ")
        }

        private func format(_ value: Double) -> String {
            String(format: "%.1f", value)
        }

        private static func isWL5024(_ name: String?) -> Bool {
            guard let name else { return false }
            let normalized = name.unicodeScalars
                .filter(CharacterSet.alphanumerics.contains)
                .map(String.init)
                .joined()
                .lowercased()
            return normalized.contains("wl5024")
        }

        private static func propertyDescription(_ properties: CBCharacteristicProperties) -> String {
            var names: [String] = []
            if properties.contains(.read) { names.append("read") }
            if properties.contains(.write) { names.append("write") }
            if properties.contains(.writeWithoutResponse) { names.append("writeWithoutResponse") }
            if properties.contains(.notify) { names.append("notify") }
            if properties.contains(.indicate) { names.append("indicate") }
            return "0x\(String(properties.rawValue, radix: 16)) [\(names.joined(separator: ","))]"
        }
    }
}

extension DirectBLEProbe.Runner: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        log(
            "CENTRAL",
            "state=\(central.state.rawValue) authorization=\(CBCentralManager.authorization.rawValue)"
        )
        switch central.state {
        case .poweredOn:
            beginScanning()
        case .unauthorized:
            fail("Bluetooth access is not authorized for this command-line probe.")
        case .poweredOff:
            fail("Bluetooth is powered off.")
        case .unsupported:
            fail("CoreBluetooth is unsupported on this Mac.")
        case .unknown, .resetting:
            break
        @unknown default:
            fail("CoreBluetooth entered an unknown state.")
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        let advertisedName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        let advertisedServices = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? []
        let exposesControlService = advertisedServices.contains(Self.serviceUUID)
        guard Self.isWL5024(peripheral.name) || Self.isWL5024(advertisedName) || exposesControlService else {
            return
        }
        log(
            "DISCOVER",
            "name=\(peripheral.name ?? advertisedName ?? "unnamed") rssi=\(RSSI) "
                + "services=\(advertisedServices.map(\.uuidString).joined(separator: ","))"
        )
        connect(peripheral, source: "name/service-gated scan")
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        log("CONNECTED", peripheral.identifier.uuidString)
        peripheral.discoverServices(nil)
    }

    func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: (any Error)?
    ) {
        fail("Connection failed: \(error?.localizedDescription ?? "unknown error")")
    }

    func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        timestamp: CFAbsoluteTime,
        isReconnecting: Bool,
        error: (any Error)?
    ) {
        guard !finished else { return }
        fail("Disconnected: \(error?.localizedDescription ?? "no CoreBluetooth error")")
    }
}

extension DirectBLEProbe.Runner: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: (any Error)?) {
        if let error {
            fail("Service discovery failed: \(error.localizedDescription)")
            return
        }
        guard let services = peripheral.services else {
            fail("Service discovery returned no services.")
            return
        }
        for service in services {
            log("GATT", "service \(service.uuid.uuidString)")
        }
        guard services.contains(where: { $0.uuid == Self.serviceUUID }) else {
            fail("The recovered Airoha control service was not present.")
            return
        }
        for service in services where service.uuid == Self.serviceUUID
            || service.uuid == Self.deviceInformationServiceUUID {
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: (any Error)?
    ) {
        if let error {
            fail("Characteristic discovery failed: \(error.localizedDescription)")
            return
        }
        let characteristics = service.characteristics ?? []
        if service.uuid == Self.serviceUUID {
            configure(characteristics)
            return
        }
        for characteristic in characteristics {
            log(
                "GATT",
                "characteristic \(characteristic.uuid.uuidString) properties "
                    + Self.propertyDescription(characteristic.properties)
            )
            if characteristic.uuid == Self.firmwareRevisionCharacteristicUUID,
               characteristic.properties.contains(.read) {
                peripheral.readValue(for: characteristic)
            }
        }
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateNotificationStateFor characteristic: CBCharacteristic,
        error: (any Error)?
    ) {
        if let error {
            fail("Notification subscription failed: \(error.localizedDescription)")
            return
        }
        guard characteristic.uuid == notifyCharacteristic?.uuid, characteristic.isNotifying else { return }
        ready()
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: (any Error)?
    ) {
        if let error {
            log("RX-ERROR", error.localizedDescription)
            return
        }
        guard let value = characteristic.value else { return }
        if characteristic.uuid == Self.firmwareRevisionCharacteristicUUID {
            let revisionBytes = value.prefix { $0 != 0 }
            let revision = String(data: Data(revisionBytes), encoding: .utf8) ?? hex(value)
            log("DEVICE-INFO", "firmware revision \(revision)")
            return
        }
        guard characteristic.uuid == notifyCharacteristic?.uuid else { return }
        handleNotification(value)
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didWriteValueFor characteristic: CBCharacteristic,
        error: (any Error)?
    ) {
        if let error {
            log("GATT-ERROR", "write \(characteristic.uuid.uuidString): \(error.localizedDescription)")
        } else {
            log("GATT-ACK", characteristic.uuid.uuidString)
        }
    }
}

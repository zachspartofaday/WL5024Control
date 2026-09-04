import Foundation

public struct HeadsetSnapshot: Sendable, Equatable {
    public struct DeviceInfo: Sendable, Equatable {
        public var model: String
        public var headsetFirmware: String?
        public var receiverFirmware: String?
        public var batteryPercent: Int?
        public var isCharging: Bool
        public var transport: TransportKind?
        public var receiverDetected: Bool
        /// Identity of the Bluetooth peripheral that produced the current
        /// live values. Cleared on disconnect/stop; values are invalidated
        /// whenever the session ends or changes (AUD-001).
        public var bluetoothSessionId: UUID?

        public init(
            model: String = "Dell WL5024",
            headsetFirmware: String? = nil,
            receiverFirmware: String? = nil,
            batteryPercent: Int? = nil,
            isCharging: Bool = false,
            transport: TransportKind? = nil,
            receiverDetected: Bool = false,
            bluetoothSessionId: UUID? = nil
        ) {
            self.model = model
            self.headsetFirmware = headsetFirmware
            self.receiverFirmware = receiverFirmware
            self.batteryPercent = batteryPercent
            self.isCharging = isCharging
            self.transport = transport
            self.receiverDetected = receiverDetected
            self.bluetoothSessionId = bluetoothSessionId
        }
    }

    public var connection: ConnectionState
    public var device: DeviceInfo
    public var capabilities: Set<HeadsetSettingKey>
    public var values: [HeadsetSettingKey: SettingValue]
    public var readiness: [HeadsetSettingKey: CapabilityReadiness]
    public var valueConfidence: [HeadsetSettingKey: ValueConfidence]
    public var lastUpdated: Date?
    public var lastAttemptedAt: Date?

    public init(
        connection: ConnectionState,
        device: DeviceInfo = DeviceInfo(),
        capabilities: Set<HeadsetSettingKey> = [],
        values: [HeadsetSettingKey: SettingValue] = [:],
        readiness: [HeadsetSettingKey: CapabilityReadiness] = [:],
        valueConfidence: [HeadsetSettingKey: ValueConfidence] = [:],
        lastUpdated: Date? = nil,
        lastAttemptedAt: Date? = nil
    ) {
        self.connection = connection
        self.device = device
        self.capabilities = capabilities
        self.values = values
        self.readiness = readiness
        self.valueConfidence = valueConfidence
        self.lastUpdated = lastUpdated
        self.lastAttemptedAt = lastAttemptedAt
    }

    public static let disconnected = HeadsetSnapshot(connection: .idle)

    public static func demo() -> HeadsetSnapshot {
        let capabilities = Set(HeadsetSettingKey.allCases)
        let values = Dictionary(uniqueKeysWithValues: capabilities.map { ($0, $0.defaultValue) })
        return HeadsetSnapshot(
            connection: .connected(.receiver),
            device: DeviceInfo(
                headsetFirmware: "2.8.1",
                receiverFirmware: "2.1.0",
                batteryPercent: 82,
                isCharging: false,
                transport: .receiver,
                receiverDetected: true
            ),
            capabilities: capabilities,
            values: values,
            readiness: Dictionary(uniqueKeysWithValues: capabilities.map {
                ($0, $0.controlKind == .readOnlyValue ? .readOnly : .ready)
            }),
            valueConfidence: Dictionary(uniqueKeysWithValues: capabilities.map { ($0, .simulated) }),
            lastUpdated: .now
        )
    }

    public func readiness(for key: HeadsetSettingKey) -> CapabilityReadiness {
        readiness[key] ?? .unavailable
    }

    public func confidence(for key: HeadsetSettingKey) -> ValueConfidence {
        valueConfidence[key] ?? .unknown
    }
}

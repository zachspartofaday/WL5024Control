import Foundation

public struct HeadsetSnapshot: Sendable, Equatable {
    public struct DeviceInfo: Sendable, Equatable {
        public var model: String
        public var headsetFirmware: String?
        public var receiverFirmware: String?
        public var batteryPercent: Int?
        public var isCharging: Bool
        public var transport: TransportKind?

        public init(
            model: String = "Dell WL5024",
            headsetFirmware: String? = nil,
            receiverFirmware: String? = nil,
            batteryPercent: Int? = nil,
            isCharging: Bool = false,
            transport: TransportKind? = nil
        ) {
            self.model = model
            self.headsetFirmware = headsetFirmware
            self.receiverFirmware = receiverFirmware
            self.batteryPercent = batteryPercent
            self.isCharging = isCharging
            self.transport = transport
        }
    }

    public var connection: ConnectionState
    public var device: DeviceInfo
    public var capabilities: Set<HeadsetSettingKey>
    public var values: [HeadsetSettingKey: SettingValue]
    public var lastUpdated: Date?

    public init(
        connection: ConnectionState,
        device: DeviceInfo = DeviceInfo(),
        capabilities: Set<HeadsetSettingKey> = [],
        values: [HeadsetSettingKey: SettingValue] = [:],
        lastUpdated: Date? = nil
    ) {
        self.connection = connection
        self.device = device
        self.capabilities = capabilities
        self.values = values
        self.lastUpdated = lastUpdated
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
                transport: .receiver
            ),
            capabilities: capabilities,
            values: values,
            lastUpdated: .now
        )
    }
}

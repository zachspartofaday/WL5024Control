import Foundation

public enum CommandQualification: String, Sendable, Codable {
    case staticallyRecovered
    case windowsPluginMapped
    case hardwareValidationPending
    case hardwareReadValidated

    public var label: String {
        switch self {
        case .staticallyRecovered: "Recovered from firmware"
        case .windowsPluginMapped: "Mapped from Dell software"
        case .hardwareValidationPending: "Ready for device validation"
        case .hardwareReadValidated: "Read validated; write pending"
        }
    }
}

public enum CapabilityAccess: String, Sendable, Codable {
    case readWrite
    case action
}

public enum WireRecipe: Sendable, Equatable {
    case genericPreference(module: UInt16, scalar: ScalarEncoding)
    case wearDetectionComposite
    case environmentDetection
    case smartSwitch
    case vendorFunction(String)

    public enum ScalarEncoding: String, Sendable, Codable {
        case byte
        case littleEndianUInt16
        case littleEndianInt32
        case utf8
        case composite
    }

    public var summary: String {
        switch self {
        case .genericPreference(let module, let scalar):
            "RACE preference module \(module), \(scalar.rawValue)"
        case .wearDetectionComposite:
            "RACE get 0x0021 / set 0x0020, UInt16 bitmask"
        case .environmentDetection:
            "RACE opcode 0x0E17"
        case .smartSwitch:
            "RACE get 0x0901 / set 0x1101"
        case .vendorFunction(let symbol):
            symbol
        }
    }
}

public struct CapabilityDefinition: Sendable, Equatable, Identifiable {
    public let key: HeadsetSettingKey
    public let access: CapabilityAccess
    public let recipe: WireRecipe
    public let qualification: CommandQualification
    public let evidence: String

    public var id: HeadsetSettingKey { key }

    public init(
        key: HeadsetSettingKey,
        access: CapabilityAccess = .readWrite,
        recipe: WireRecipe,
        qualification: CommandQualification,
        evidence: String
    ) {
        self.key = key
        self.access = access
        self.recipe = recipe
        self.qualification = qualification
        self.evidence = evidence
    }
}

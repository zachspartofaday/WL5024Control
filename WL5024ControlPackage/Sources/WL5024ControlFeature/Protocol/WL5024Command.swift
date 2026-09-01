import Foundation

public enum WL5024Command: Sendable, Equatable {
    case getAutomaticMedia
    case setAutomaticMedia(Bool)
    case getPreference(module: UInt16)
    case setPreferenceByte(module: UInt16, value: UInt8)
    case setPreferenceUInt16(module: UInt16, value: UInt16)
    case getEnvironmentDetection
    case setEnvironmentDetection(Bool)
    case getSmartSwitch
    case setSmartSwitch(Bool)

    private static let getPreferenceOpcode: UInt16 = 0x2C83
    private static let setPreferenceOpcode: UInt16 = 0x2C82
    private static let automaticMediaModule: UInt16 = 0x0002

    public var frame: RaceFrame {
        switch self {
        case .getAutomaticMedia:
            return RaceFrame(
                opcode: Self.getPreferenceOpcode,
                payload: Self.modulePayload(Self.automaticMediaModule)
            )
        case .setAutomaticMedia(let enabled):
            var payload = Self.modulePayload(Self.automaticMediaModule)
            payload.append(enabled ? 1 : 0)
            return RaceFrame(opcode: Self.setPreferenceOpcode, payload: payload)
        case .getPreference(let module):
            return RaceFrame(opcode: Self.getPreferenceOpcode, payload: Self.modulePayload(module))
        case .setPreferenceByte(let module, let value):
            return RaceFrame(
                opcode: Self.setPreferenceOpcode,
                payload: Self.modulePayload(module) + Data([value])
            )
        case .setPreferenceUInt16(let module, let value):
            return RaceFrame(
                opcode: Self.setPreferenceOpcode,
                payload: Self.modulePayload(module) + Data(Self.littleEndian(value))
            )
        case .getEnvironmentDetection:
            return RaceFrame(opcode: 0x0E17, payload: Data([0x03, 0x02]))
        case .setEnvironmentDetection(let enabled):
            return RaceFrame(opcode: 0x0E17, payload: Data([0x03, enabled ? 1 : 0]))
        case .getSmartSwitch:
            return RaceFrame(opcode: 0x0901, payload: Data([0x06]))
        case .setSmartSwitch(let enabled):
            return RaceFrame(opcode: 0x1101, payload: Data(Self.littleEndian(enabled ? 0x00A4 : 0x00A5)))
        }
    }

    public func decodeAutomaticMedia(from response: Data) throws -> Bool {
        let frame = try RaceFrame(decoding: response)
        guard case .getAutomaticMedia = self,
              frame.payload.count >= 3 else {
            throw HeadsetError.malformedResponse
        }

        let bytes = Array(frame.payload)
        let module = UInt16(bytes[0]) | (UInt16(bytes[1]) << 8)
        guard module == Self.automaticMediaModule else {
            throw HeadsetError.malformedResponse
        }
        return bytes[2] != 0
    }

    private static func modulePayload(_ module: UInt16) -> Data {
        Data(littleEndian(module))
    }

    private static func littleEndian(_ value: UInt16) -> [UInt8] {
        [UInt8(truncatingIfNeeded: value), UInt8(truncatingIfNeeded: value >> 8)]
    }
}

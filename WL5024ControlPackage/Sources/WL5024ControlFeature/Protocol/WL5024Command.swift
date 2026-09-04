import Foundation

struct AutomaticPowerOffStatus: Sendable, Equatable {
    struct Profile: Sendable, Equatable {
        let isEnabled: Bool
        let seconds: UInt16
    }

    let primary: Profile
    let secondary: Profile

    var settingValue: SettingValue {
        get throws {
            guard primary.seconds == secondary.seconds else {
                throw HeadsetError.malformedResponse
            }
            guard primary.isEnabled || secondary.isEnabled else { return .choice("off") }
            switch primary.seconds {
            case 900: return .choice("15m")
            case 1_800: return .choice("30m")
            case 3_600: return .choice("1h")
            case 7_200: return .choice("2h")
            case 14_400: return .choice("4h")
            case 21_600: return .choice("6h")
            case 28_800: return .choice("8h")
            default: throw HeadsetError.malformedResponse
            }
        }
    }
}

public enum WL5024Command: Sendable, Equatable {
    case getWearDetection
    case setWearDetection(UInt16)
    case getPreference(module: UInt16)
    case setPreferenceByte(module: UInt16, value: UInt8)
    case setPreferenceUInt16(module: UInt16, value: UInt16)
    case setAutoPowerOff(enabled: Bool, seconds: UInt16)
    case getBusyLight
    case setBusyLight(Bool)
    case getVoiceGuidance
    case setVoiceGuidance(Bool)
    case getIncomingAudioNoiseCancellation
    case setIncomingAudioNoiseCancellation(Bool)
    case getMicrophoneNoiseCancellation
    case setMicrophoneNoiseCancellation(Bool)
    case getEnvironmentDetection
    case setEnvironmentDetection(Bool)
    case getSmartSwitch
    case setSmartSwitch(Bool)
    case getMicFlipAction
    case getUCProfile
    case getUCAppStatus
    case getLEAudioFeatureMode

    private static let getPreferenceOpcode: UInt16 = 0x2C83
    private static let setPreferenceOpcode: UInt16 = 0x2C82

    public var frame: RaceFrame {
        switch self {
        case .getWearDetection:
            return RaceFrame(opcode: 0x0021)
        case .setWearDetection(let flags):
            return RaceFrame(opcode: 0x0020, payload: Data(Self.littleEndian(flags)))
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
        case .setAutoPowerOff(let enabled, let seconds):
            return RaceFrame(
                opcode: Self.setPreferenceOpcode,
                payload: Self.modulePayload(1)
                    + Data(Self.littleEndian(enabled ? 1 : 0))
                    + Data(Self.littleEndian(seconds))
            )
        case .getBusyLight:
            return RaceFrame(opcode: 0x0023)
        case .setBusyLight(let enabled):
            return RaceFrame(opcode: 0x0022, payload: Data([enabled ? 1 : 0]))
        case .getVoiceGuidance:
            return RaceFrame(opcode: 0x0025)
        case .setVoiceGuidance(let enabled):
            return RaceFrame(opcode: 0x0024, payload: Data([enabled ? 1 : 0]))
        case .getIncomingAudioNoiseCancellation:
            return RaceFrame(opcode: 0x0044)
        case .setIncomingAudioNoiseCancellation(let enabled):
            return RaceFrame(opcode: 0x0043, payload: Data([enabled ? 1 : 0]))
        case .getMicrophoneNoiseCancellation:
            return RaceFrame(opcode: 0x0EFF)
        case .setMicrophoneNoiseCancellation(let enabled):
            return RaceFrame(opcode: 0x0E0D, payload: Data([enabled ? 1 : 0]))
        case .getEnvironmentDetection:
            return RaceFrame(opcode: 0x0E17, payload: Data([0x03, 0x02]))
        case .setEnvironmentDetection(let enabled):
            return RaceFrame(opcode: 0x0E17, payload: Data([0x03, enabled ? 1 : 0]))
        case .getSmartSwitch:
            return RaceFrame(opcode: 0x0901, payload: Self.modulePayload(6))
        case .setSmartSwitch(let enabled):
            return RaceFrame(opcode: 0x1101, payload: Data(Self.littleEndian(enabled ? 0x00A4 : 0x00A5)))
        case .getMicFlipAction:
            return RaceFrame(opcode: 0x0029)
        case .getUCProfile:
            return RaceFrame(opcode: 0x0041)
        case .getUCAppStatus:
            return RaceFrame(opcode: 0x0042)
        case .getLEAudioFeatureMode:
            return RaceFrame(opcode: Self.getPreferenceOpcode, payload: Self.modulePayload(0x0031))
        }
    }

    public func decodeWearDetectionFlags(from response: Data) throws -> UInt16 {
        guard case .getWearDetection = self else {
            throw HeadsetError.malformedResponse
        }
        let frame = try RaceFrame(decoding: response)
        guard frame.packetType == .response,
              frame.opcode == 0x0021,
              frame.payload.count == 3 else {
            throw HeadsetError.malformedResponse
        }
        let bytes = Array(frame.payload)
        guard bytes[0] == 0 else { throw HeadsetError.malformedResponse }
        return UInt16(bytes[1]) | (UInt16(bytes[2]) << 8)
    }

    public func validateWearDetectionAcknowledgement(_ response: Data) throws {
        guard case .setWearDetection = self else {
            throw HeadsetError.malformedResponse
        }
        let frame = try RaceFrame(decoding: response)
        guard frame.packetType == .response,
              frame.opcode == 0x0020,
              frame.payload.count == 1 else {
            throw HeadsetError.malformedResponse
        }
        guard frame.payload[frame.payload.startIndex] == 0 else {
            throw HeadsetError.commandRejected
        }
    }

    public func decodePreferenceValueStrict(
        from response: Data,
        expectedValueLength: Int
    ) throws -> Data {
        guard case .getPreference(let module) = self else {
            throw HeadsetError.malformedResponse
        }
        let frame = try RaceFrame(decoding: response)
        let bytes = Array(frame.payload)
        guard frame.packetType == .response,
              frame.opcode == Self.getPreferenceOpcode,
              bytes.count == 3 + expectedValueLength,
              bytes[0] == 0,
              UInt16(bytes[1]) | (UInt16(bytes[2]) << 8) == module else {
            throw HeadsetError.malformedResponse
        }
        return Data(bytes.dropFirst(3))
    }

    public func validatePreferenceAcknowledgement(_ response: Data) throws {
        let module: UInt16
        switch self {
        case .setPreferenceByte(let commandModule, _), .setPreferenceUInt16(let commandModule, _):
            module = commandModule
        case .setAutoPowerOff:
            module = 1
        default:
            throw HeadsetError.malformedResponse
        }
        let frame = try RaceFrame(decoding: response)
        let bytes = Array(frame.payload)
        guard frame.packetType == .response,
              frame.opcode == Self.setPreferenceOpcode,
              bytes.count == 3,
              bytes[1] == UInt8(truncatingIfNeeded: module),
              bytes[2] == UInt8(truncatingIfNeeded: module >> 8) else {
            throw HeadsetError.malformedResponse
        }
        guard bytes[0] == 0 else { throw HeadsetError.commandRejected }
    }

    public func decodeStrictBoolean(from response: Data) throws -> Bool {
        let opcode = try simpleBooleanOpcode(isSetter: false)
        let frame = try RaceFrame(decoding: response)
        guard frame.packetType == .response,
              frame.opcode == opcode,
              frame.payload.count == 2 else {
            throw HeadsetError.malformedResponse
        }
        let bytes = Array(frame.payload)
        guard bytes[0] == 0, bytes[1] == 0 || bytes[1] == 1 else {
            throw HeadsetError.malformedResponse
        }
        return bytes[1] == 1
    }

    func decodeAutomaticPowerOffStatus(from response: Data) throws -> AutomaticPowerOffStatus {
        guard case .getPreference(module: 1) = self else {
            throw HeadsetError.malformedResponse
        }
        let data = try decodePreferenceValueStrict(from: response, expectedValueLength: 8)
        let words = stride(from: 0, to: data.count, by: 2).map { index in
            UInt16(data[index]) | (UInt16(data[index + 1]) << 8)
        }
        guard (words[0] == 0 || words[0] == 1),
              (words[2] == 0 || words[2] == 1) else {
            throw HeadsetError.malformedResponse
        }
        return AutomaticPowerOffStatus(
            primary: .init(isEnabled: words[0] == 1, seconds: words[1]),
            secondary: .init(isEnabled: words[2] == 1, seconds: words[3])
        )
    }

    func decodeEnvironmentDetection(from response: Data) throws -> Bool {
        guard case .getEnvironmentDetection = self else {
            throw HeadsetError.malformedResponse
        }
        let frame = try RaceFrame(decoding: response)
        guard frame.packetType == .response,
              frame.opcode == 0x0E17,
              frame.payload.count == 3 else {
            throw HeadsetError.malformedResponse
        }
        let bytes = Array(frame.payload)
        guard bytes[0] == 0x03,
              bytes[1] == 0x03,
              bytes[2] == 0 || bytes[2] == 1 else {
            throw HeadsetError.malformedResponse
        }
        return bytes[2] == 1
    }

    func decodeSmartSwitch(from response: Data) throws -> Bool {
        guard case .getSmartSwitch = self else {
            throw HeadsetError.malformedResponse
        }
        let frame = try RaceFrame(decoding: response)
        let bytes = Array(frame.payload)
        guard frame.packetType == .response,
              frame.opcode == 0x0901,
              bytes.count == 4,
              UInt16(bytes[0]) | (UInt16(bytes[1]) << 8) == 6,
              bytes[2] == 0,
              bytes[3] == 0 || bytes[3] == 1 else {
            throw HeadsetError.malformedResponse
        }
        return bytes[3] == 1
    }

    func decodeStatusByte(from response: Data) throws -> UInt8 {
        let opcode: UInt16
        switch self {
        case .getMicFlipAction: opcode = 0x0029
        case .getUCProfile: opcode = 0x0041
        case .getUCAppStatus: opcode = 0x0042
        default: throw HeadsetError.malformedResponse
        }
        let frame = try RaceFrame(decoding: response)
        let bytes = Array(frame.payload)
        guard frame.packetType == .response,
              frame.opcode == opcode,
              bytes.count == 2,
              bytes[0] == 0 else {
            throw HeadsetError.malformedResponse
        }
        return bytes[1]
    }

    func decodeLEAudioFeatureMode(from response: Data) throws -> UInt8 {
        guard case .getLEAudioFeatureMode = self else {
            throw HeadsetError.malformedResponse
        }
        let frame = try RaceFrame(decoding: response)
        let bytes = Array(frame.payload)
        guard frame.packetType == .response,
              frame.opcode == Self.getPreferenceOpcode,
              bytes.count == 7,
              bytes[0] == 0,
              UInt16(bytes[1]) | (UInt16(bytes[2]) << 8) == 0x0031,
              bytes[3] == 1 else {
            throw HeadsetError.malformedResponse
        }
        return bytes[4]
    }

    public func validateSimpleAcknowledgement(_ response: Data) throws {
        let opcode = try simpleBooleanOpcode(isSetter: true)
        let frame = try RaceFrame(decoding: response)
        guard frame.packetType == .response,
              frame.opcode == opcode,
              frame.payload.count == 1 else {
            throw HeadsetError.malformedResponse
        }
        guard frame.payload[frame.payload.startIndex] == 0 else {
            throw HeadsetError.commandRejected
        }
    }

    private func simpleBooleanOpcode(isSetter: Bool) throws -> UInt16 {
        switch (self, isSetter) {
        case (.getBusyLight, false): 0x0023
        case (.setBusyLight, true): 0x0022
        case (.getVoiceGuidance, false): 0x0025
        case (.setVoiceGuidance, true): 0x0024
        case (.getIncomingAudioNoiseCancellation, false): 0x0044
        case (.setIncomingAudioNoiseCancellation, true): 0x0043
        case (.getMicrophoneNoiseCancellation, false): 0x0EFF
        case (.setMicrophoneNoiseCancellation, true): 0x0E0D
        default: throw HeadsetError.malformedResponse
        }
    }

    static func decodePreferenceValue(
        from response: Data,
        opcode: UInt16 = getPreferenceOpcode,
        module: UInt16
    ) throws -> Data {
        let frame = try RaceFrame(decoding: response)
        guard frame.packetType == .response, frame.opcode == opcode else {
            throw HeadsetError.malformedResponse
        }

        let bytes = Array(frame.payload)

        // Physical WL5024 build-7 capture: status, module LE, then the value bytes.
        if bytes.count >= 3,
           UInt16(bytes[1]) | (UInt16(bytes[2]) << 8) == module {
            guard bytes[0] == 0 else { throw HeadsetError.malformedResponse }
            return Data(bytes.dropFirst(3))
        }

        // Some SDK paths expose a compact module-first payload.
        guard bytes.count >= 2,
              UInt16(bytes[0]) | (UInt16(bytes[1]) << 8) == module else {
            throw HeadsetError.malformedResponse
        }
        return Data(bytes.dropFirst(2))
    }

    private static func modulePayload(_ module: UInt16) -> Data {
        Data(littleEndian(module))
    }

    private static func littleEndian(_ value: UInt16) -> [UInt8] {
        [UInt8(truncatingIfNeeded: value), UInt8(truncatingIfNeeded: value >> 8)]
    }
}

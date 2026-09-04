import Foundation

public struct RaceResponseMatcher: Sendable, Equatable {
    public let opcode: UInt16
    public let module: UInt16?

    public init(opcode: UInt16, module: UInt16? = nil) {
        self.opcode = opcode
        self.module = module
    }

    public func matches(_ data: Data) -> Bool {
        guard let frame = try? RaceFrame(decoding: data),
              frame.packetType == .response,
              frame.opcode == opcode else {
            return false
        }
        guard let module else { return true }
        let bytes = Array(frame.payload)
        if bytes.count >= 2,
           UInt16(bytes[0]) | (UInt16(bytes[1]) << 8) == module {
            return true
        }
        return bytes.count >= 3
            && UInt16(bytes[1]) | (UInt16(bytes[2]) << 8) == module
    }
}

public struct TransportTransaction: Sendable, Equatable {
    public let request: Data
    public let expectedResponse: RaceResponseMatcher

    public init(request: Data, expectedResponse: RaceResponseMatcher) {
        self.request = request
        self.expectedResponse = expectedResponse
    }
}

extension WL5024Command {
    public var transaction: TransportTransaction {
        switch self {
        case .getWearDetection:
            TransportTransaction(
                request: frame.encoded,
                expectedResponse: RaceResponseMatcher(opcode: 0x0021)
            )
        case .setWearDetection:
            TransportTransaction(
                request: frame.encoded,
                expectedResponse: RaceResponseMatcher(opcode: 0x0020)
            )
        case .getPreference(let module):
            TransportTransaction(
                request: frame.encoded,
                expectedResponse: RaceResponseMatcher(opcode: 0x2C83, module: module)
            )
        case .setPreferenceByte(let module, _), .setPreferenceUInt16(let module, _):
            TransportTransaction(
                request: frame.encoded,
                expectedResponse: RaceResponseMatcher(opcode: 0x2C82, module: module)
            )
        case .setAutoPowerOff:
            TransportTransaction(
                request: frame.encoded,
                expectedResponse: RaceResponseMatcher(opcode: 0x2C82, module: 1)
            )
        case .getBusyLight:
            TransportTransaction(request: frame.encoded, expectedResponse: .init(opcode: 0x0023))
        case .setBusyLight:
            TransportTransaction(request: frame.encoded, expectedResponse: .init(opcode: 0x0022))
        case .getVoiceGuidance:
            TransportTransaction(request: frame.encoded, expectedResponse: .init(opcode: 0x0025))
        case .setVoiceGuidance:
            TransportTransaction(request: frame.encoded, expectedResponse: .init(opcode: 0x0024))
        case .getIncomingAudioNoiseCancellation:
            TransportTransaction(request: frame.encoded, expectedResponse: .init(opcode: 0x0044))
        case .setIncomingAudioNoiseCancellation:
            TransportTransaction(request: frame.encoded, expectedResponse: .init(opcode: 0x0043))
        case .getMicrophoneNoiseCancellation:
            TransportTransaction(request: frame.encoded, expectedResponse: .init(opcode: 0x0EFF))
        case .setMicrophoneNoiseCancellation:
            TransportTransaction(request: frame.encoded, expectedResponse: .init(opcode: 0x0E0D))
        case .getEnvironmentDetection, .setEnvironmentDetection:
            TransportTransaction(
                request: frame.encoded,
                expectedResponse: RaceResponseMatcher(opcode: 0x0E17)
            )
        case .getSmartSwitch:
            TransportTransaction(
                request: frame.encoded,
                expectedResponse: RaceResponseMatcher(opcode: 0x0901, module: 6)
            )
        case .setSmartSwitch:
            TransportTransaction(
                request: frame.encoded,
                expectedResponse: RaceResponseMatcher(opcode: 0x1101)
            )
        case .getMicFlipAction:
            TransportTransaction(request: frame.encoded, expectedResponse: .init(opcode: 0x0029))
        case .getUCProfile:
            TransportTransaction(request: frame.encoded, expectedResponse: .init(opcode: 0x0041))
        case .getUCAppStatus:
            TransportTransaction(request: frame.encoded, expectedResponse: .init(opcode: 0x0042))
        case .getLEAudioFeatureMode:
            TransportTransaction(
                request: frame.encoded,
                expectedResponse: RaceResponseMatcher(opcode: 0x2C83, module: 0x0031)
            )
        }
    }
}

import Foundation

public struct RaceResponseMatcher: Sendable, Equatable {
    public let opcode: UInt16
    public let module: UInt16?

    public init(opcode: UInt16, module: UInt16? = nil) {
        self.opcode = opcode
        self.module = module
    }

    public func matches(_ data: Data) -> Bool {
        guard let frame = try? RaceFrame(decoding: data), frame.opcode == opcode else {
            return false
        }
        guard let module else { return true }
        guard frame.payload.count >= 2 else { return false }
        let bytes = Array(frame.payload.prefix(2))
        return UInt16(bytes[0]) | (UInt16(bytes[1]) << 8) == module
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
        case .getAutomaticMedia:
            TransportTransaction(
                request: frame.encoded,
                expectedResponse: RaceResponseMatcher(opcode: 0x2C83, module: 2)
            )
        case .setAutomaticMedia:
            TransportTransaction(
                request: frame.encoded,
                expectedResponse: RaceResponseMatcher(opcode: 0x2C82, module: 2)
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
        case .getEnvironmentDetection, .setEnvironmentDetection:
            TransportTransaction(
                request: frame.encoded,
                expectedResponse: RaceResponseMatcher(opcode: 0x0E17)
            )
        case .getSmartSwitch:
            TransportTransaction(
                request: frame.encoded,
                expectedResponse: RaceResponseMatcher(opcode: 0x0901)
            )
        case .setSmartSwitch:
            TransportTransaction(
                request: frame.encoded,
                expectedResponse: RaceResponseMatcher(opcode: 0x1101)
            )
        }
    }
}

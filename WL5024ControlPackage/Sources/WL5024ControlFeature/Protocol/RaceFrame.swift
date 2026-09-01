import Foundation

/// The non-FOTA Airoha RACE frame used by the WL5024 preference commands.
public struct RaceFrame: Sendable, Equatable {
    public static let channel: UInt8 = 0x5A
    public static let commandType: UInt8 = 0x05

    public let opcode: UInt16
    public let payload: Data

    public init(opcode: UInt16, payload: Data = Data()) {
        self.opcode = opcode
        self.payload = payload
    }

    public var encoded: Data {
        let bodyLength = UInt16(payload.count + 2)
        var bytes: [UInt8] = [
            0x00,
            Self.commandType,
            Self.channel,
            UInt8(truncatingIfNeeded: bodyLength),
            UInt8(truncatingIfNeeded: bodyLength >> 8),
            UInt8(truncatingIfNeeded: opcode),
            UInt8(truncatingIfNeeded: opcode >> 8),
        ]
        bytes.append(contentsOf: payload)
        return Data(bytes)
    }

    public init(decoding transportData: Data) throws {
        let bytes = Array(transportData)
        guard let start = Self.findFrameStart(in: bytes) else {
            throw HeadsetError.malformedResponse
        }

        let bodyLength = Int(bytes[start + 3]) | (Int(bytes[start + 4]) << 8)
        guard bodyLength >= 2, start + 5 + bodyLength <= bytes.count else {
            throw HeadsetError.malformedResponse
        }

        opcode = UInt16(bytes[start + 5]) | (UInt16(bytes[start + 6]) << 8)
        let payloadStart = start + 7
        let payloadEnd = start + 5 + bodyLength
        payload = Data(bytes[payloadStart..<payloadEnd])
    }

    private static func findFrameStart(in bytes: [UInt8]) -> Int? {
        guard bytes.count >= 7 else { return nil }

        for index in 0...(bytes.count - 7) {
            guard bytes[index + 1] & 0x0F == commandType,
                  bytes[index + 2] == channel else {
                continue
            }

            let bodyLength = Int(bytes[index + 3]) | (Int(bytes[index + 4]) << 8)
            if bodyLength >= 2, index + 5 + bodyLength <= bytes.count {
                return index
            }
        }
        return nil
    }
}

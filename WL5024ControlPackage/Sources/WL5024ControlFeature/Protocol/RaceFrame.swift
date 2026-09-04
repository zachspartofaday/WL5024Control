import Foundation

public enum RacePacketType: UInt8, Sendable, Equatable {
    case commandExpectsResponse = 0x5A
    case response = 0x5B
    case commandExpectsNoResponse = 0x5C
    case indication = 0x5D
}

/// The non-FOTA Airoha RACE frame used by the WL5024 preference commands.
public struct RaceFrame: Sendable, Equatable {
    public static let header: UInt8 = 0x05

    public let packetType: RacePacketType
    public let opcode: UInt16
    public let payload: Data

    public init(
        packetType: RacePacketType = .commandExpectsResponse,
        opcode: UInt16,
        payload: Data = Data()
    ) {
        self.packetType = packetType
        self.opcode = opcode
        self.payload = payload
    }

    public var encoded: Data {
        let bodyLength = UInt16(payload.count + 2)
        var bytes: [UInt8] = [
            Self.header,
            packetType.rawValue,
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

        guard let packetType = RacePacketType(rawValue: bytes[start + 1]) else {
            throw HeadsetError.malformedResponse
        }
        let bodyLength = Int(bytes[start + 2]) | (Int(bytes[start + 3]) << 8)
        guard bodyLength >= 2, start + 4 + bodyLength <= bytes.count else {
            throw HeadsetError.malformedResponse
        }

        self.packetType = packetType
        opcode = UInt16(bytes[start + 4]) | (UInt16(bytes[start + 5]) << 8)
        let payloadStart = start + 6
        let payloadEnd = start + 4 + bodyLength
        payload = Data(bytes[payloadStart..<payloadEnd])
    }

    private static func findFrameStart(in bytes: [UInt8]) -> Int? {
        guard bytes.count >= 6 else { return nil }

        for index in 0...(bytes.count - 6) {
            guard bytes[index] == header,
                  RacePacketType(rawValue: bytes[index + 1]) != nil else {
                continue
            }

            let bodyLength = Int(bytes[index + 2]) | (Int(bytes[index + 3]) << 8)
            if bodyLength >= 2, index + 4 + bodyLength <= bytes.count {
                return index
            }
        }
        return nil
    }
}

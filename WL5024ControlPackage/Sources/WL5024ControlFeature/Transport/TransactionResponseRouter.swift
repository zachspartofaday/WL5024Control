import Foundation

public enum TransactionResponseDisposition: Equatable {
    case matched
    /// Success status with no attributable module/value bytes (e.g.
    /// preference module 10). Must be logged but never credited to the
    /// pending module; a late ambiguous packet must not complete the next
    /// request (AUD-008).
    case ambiguousStatusOnly
    case unsolicited
}

public enum TransactionResponseRouter {
    public static func classify(
        _ data: Data,
        pending matcher: RaceResponseMatcher?
    ) -> TransactionResponseDisposition {
        guard let matcher else { return .unsolicited }
        if matcher.matches(data) { return .matched }
        if isAmbiguousStatusOnly(data, opcode: matcher.opcode) {
            return .ambiguousStatusOnly
        }
        return .unsolicited
    }

    public static func isAmbiguousStatusOnly(_ data: Data, opcode: UInt16) -> Bool {
        guard let frame = try? RaceFrame(decoding: data),
              frame.packetType == .response,
              frame.opcode == opcode else {
            return false
        }
        return frame.payload.count == 1
    }
}

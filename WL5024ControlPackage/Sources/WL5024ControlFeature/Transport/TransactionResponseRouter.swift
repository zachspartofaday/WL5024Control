import Foundation

enum TransactionResponseDisposition: Equatable {
    case matched
    case unsolicited
}

enum TransactionResponseRouter {
    static func classify(
        _ data: Data,
        pending matcher: RaceResponseMatcher?
    ) -> TransactionResponseDisposition {
        guard let matcher, matcher.matches(data) else { return .unsolicited }
        return .matched
    }
}

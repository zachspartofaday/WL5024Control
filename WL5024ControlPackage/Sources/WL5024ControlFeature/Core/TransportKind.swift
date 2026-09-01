import Foundation

public enum TransportKind: String, Sendable, Equatable, Codable {
    case receiver
    case bluetooth

    public var displayName: LocalizedStringResource {
        switch self {
        case .receiver:
            LocalizedStringResource("HR024 receiver", bundle: #bundle)
        case .bluetooth:
            LocalizedStringResource("Bluetooth", bundle: #bundle)
        }
    }
}

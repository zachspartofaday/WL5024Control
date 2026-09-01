import Foundation

public enum CapabilityReadiness: String, Sendable, Equatable, Codable {
    case unavailable
    case readOnly
    case validationPending
    case ready

    public var allowsWrite: Bool { self == .ready }

    public var status: LocalizedStringResource {
        switch self {
        case .unavailable:
            LocalizedStringResource("Connect the headset to configure this setting", bundle: #bundle)
        case .readOnly:
            LocalizedStringResource("Current value available; writing awaits hardware validation", bundle: #bundle)
        case .validationPending:
            LocalizedStringResource("Writing awaits hardware validation", bundle: #bundle)
        case .ready:
            LocalizedStringResource("Ready", bundle: #bundle)
        }
    }
}

public enum ValueConfidence: String, Sendable, Equatable, Codable {
    case unknown
    case deviceConfirmed
    case simulated
}

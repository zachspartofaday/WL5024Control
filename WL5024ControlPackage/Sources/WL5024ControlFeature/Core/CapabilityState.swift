import Foundation

public enum CapabilityReadiness: String, Sendable, Equatable, Codable {
    case unavailable
    case readOnly
    case validationPending
    case experimental
    case ready

    public var allowsWrite: Bool { self == .ready || self == .experimental }

    public var status: LocalizedStringResource {
        switch self {
        case .unavailable:
            LocalizedStringResource("Connect the headset to configure this setting", bundle: #bundle)
        case .readOnly:
            LocalizedStringResource("Current value available; writing awaits hardware validation", bundle: #bundle)
        case .validationPending:
            LocalizedStringResource("Writing awaits hardware validation", bundle: #bundle)
        case .experimental:
            LocalizedStringResource("Experimental write — response and read-back verification required", bundle: #bundle)
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

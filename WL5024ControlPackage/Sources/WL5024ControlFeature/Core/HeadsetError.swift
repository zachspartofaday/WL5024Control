import Foundation

public enum HeadsetError: Error, Sendable, Equatable {
    case disconnected
    case busy
    case unsupported(HeadsetSettingKey)
    case invalidValue(HeadsetSettingKey)
    case commandRejected
    case malformedResponse
    case timeout
    case transport(String)
    case readbackMismatch(HeadsetSettingKey)
}

extension HeadsetError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .disconnected: "The headset is not connected."
        case .busy: "Another headset command is still in progress."
        case .unsupported(let key): "\(key.rawValue) is awaiting physical-device validation."
        case .invalidValue(let key): "The value for \(key.rawValue) is invalid."
        case .commandRejected: "The headset rejected the command."
        case .malformedResponse: "The headset returned an unexpected response."
        case .timeout: "The headset did not respond in time."
        case .transport(let message): message
        case .readbackMismatch(let key): "The headset did not retain the new \(key.rawValue) value."
        }
    }
}

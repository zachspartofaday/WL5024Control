import Foundation

public enum HeadsetEvent: Sendable, Equatable {
    case snapshot(HeadsetStateUpdate)
    case error(HeadsetError)
}

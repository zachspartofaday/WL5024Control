import Foundation

public enum HeadsetEvent: Sendable, Equatable {
    case snapshot(HeadsetSnapshot)
    case error(HeadsetError)
}

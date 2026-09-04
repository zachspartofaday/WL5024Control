import Foundation

public struct HeadsetStateUpdate: Sendable, Equatable {
    public let revision: UInt64
    public let snapshot: HeadsetSnapshot

    public init(revision: UInt64, snapshot: HeadsetSnapshot) {
        self.revision = revision
        self.snapshot = snapshot
    }
}

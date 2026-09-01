import Foundation

public enum RecoveryAction: Sendable, Equatable {
    case retry
    case reconnect
    case openBluetoothSettings
    case chooseAnotherLocation
    case dismiss
}

public struct HeadsetFailure: Sendable, Equatable, Identifiable {
    public let id: UUID
    public let title: LocalizedStringResource
    public let message: String
    public let technicalDetails: String
    public let primaryAction: RecoveryAction

    public init(
        id: UUID = UUID(),
        title: LocalizedStringResource,
        message: String,
        technicalDetails: String,
        primaryAction: RecoveryAction
    ) {
        self.id = id
        self.title = title
        self.message = message
        self.technicalDetails = technicalDetails
        self.primaryAction = primaryAction
    }
}

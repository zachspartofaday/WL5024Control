import Foundation

public struct SettingChoice: Identifiable, Sendable {
    public let id: String
    public let title: LocalizedStringResource

    public init(id: String, title: LocalizedStringResource) {
        self.id = id
        self.title = title
    }
}

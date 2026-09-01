import Foundation

public enum SettingValue: Sendable, Equatable, Codable {
    case boolean(Bool)
    case choice(String)
    case integer(Int)
    case text(String)
}

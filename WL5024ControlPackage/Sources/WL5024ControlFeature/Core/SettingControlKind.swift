import Foundation

public enum SettingControlKind: Sendable, Equatable {
    case toggle
    case choices
    case level(range: ClosedRange<Int>, step: Int)
    case text
    case action
}

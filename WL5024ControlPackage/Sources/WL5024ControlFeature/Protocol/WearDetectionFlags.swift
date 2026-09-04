import Foundation

/// The composite UInt16 used by Dell DDPM 2.3.0.9 for WL5024 wear-sensor behavior.
struct WearDetectionFlags: Sendable, Equatable {
    private(set) var rawValue: UInt16

    init(rawValue: UInt16) {
        self.rawValue = rawValue
    }

    func value(for key: HeadsetSettingKey) throws -> SettingValue {
        switch key {
        case .wearDetection:
            .boolean(rawValue & 0x0001 != 0)
        case .automaticMedia:
            .boolean(rawValue & 0x0002 != 0)
        case .muteMicrophoneOnRemoval:
            .boolean(rawValue & 0x0004 != 0)
        case .answerCallsOnWear:
            .boolean(rawValue & 0x0040 != 0)
        case .quickPause:
            .boolean(try quickPauseMode() != 0)
        case .quickPauseSensitivity:
            .choice(try quickPauseMode() == 2 ? "sensitive" : "normal")
        default:
            throw HeadsetError.unsupported(key)
        }
    }

    func updating(_ key: HeadsetSettingKey, to value: SettingValue) throws -> Self {
        var updated = rawValue
        switch key {
        case .wearDetection:
            try updateBoolean(value, key: key, mask: 0x0001, rawValue: &updated)
        case .automaticMedia:
            try updateBoolean(value, key: key, mask: 0x0002, rawValue: &updated)
        case .muteMicrophoneOnRemoval:
            try updateBoolean(value, key: key, mask: 0x0004, rawValue: &updated)
        case .answerCallsOnWear:
            try updateBoolean(value, key: key, mask: 0x0040, rawValue: &updated)
        case .quickPause:
            guard case .boolean(let enabled) = value else {
                throw HeadsetError.invalidValue(key)
            }
            if enabled {
                if try quickPauseMode() == 0 {
                    // DDPM uses Sensitive (2) when its Quick Pause switch enables the feature.
                    updated = (updated & ~0x0030) | 0x0020
                }
            } else {
                updated &= ~0x0030
            }
        case .quickPauseSensitivity:
            guard case .choice(let choice) = value else {
                throw HeadsetError.invalidValue(key)
            }
            let mode: UInt16
            switch choice {
            case "normal": mode = 1
            case "sensitive": mode = 2
            default: throw HeadsetError.invalidValue(key)
            }
            updated = (updated & ~0x0030) | (mode << 4)
        default:
            throw HeadsetError.unsupported(key)
        }
        return Self(rawValue: updated)
    }

    private func quickPauseMode() throws -> UInt16 {
        let mode = (rawValue >> 4) & 0x0003
        guard mode != 3 else {
            throw HeadsetError.invalidValue(.quickPauseSensitivity)
        }
        return mode
    }

    private func updateBoolean(
        _ value: SettingValue,
        key: HeadsetSettingKey,
        mask: UInt16,
        rawValue: inout UInt16
    ) throws {
        guard case .boolean(let enabled) = value else {
            throw HeadsetError.invalidValue(key)
        }
        if enabled {
            rawValue |= mask
        } else {
            rawValue &= ~mask
        }
    }
}

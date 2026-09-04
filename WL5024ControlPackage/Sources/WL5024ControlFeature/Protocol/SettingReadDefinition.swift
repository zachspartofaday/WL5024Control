import Foundation

struct SettingReadDefinition: Sendable {
    let key: HeadsetSettingKey
    let transactions: [TransportTransaction]
    let decoder: @Sendable ([Data]) throws -> SettingValue

    init(
        key: HeadsetSettingKey,
        transactions: [TransportTransaction],
        decoder: @escaping @Sendable ([Data]) throws -> SettingValue
    ) {
        self.key = key
        self.transactions = transactions
        self.decoder = decoder
    }

    init(_ qualification: WriteQualification) {
        self.init(
            key: qualification.key,
            transactions: qualification.readBackTransactions,
            decoder: qualification.readBackDecoder
        )
    }
}

enum ShippingSettingReads {
    static let orderedKeys: [HeadsetSettingKey] = [
        .wearDetection,
        .automaticMedia,
        .muteMicrophoneOnRemoval,
        .quickPause,
        .quickPauseSensitivity,
        .answerCallsOnWear,
        .autoPowerOff,
        .environmentDetection,
        .microphoneNoiseCancellation,
        .sidetone,
        .busyLight,
        .voiceGuidance,
        .smartSwitch,
        .micFlipAction,
        .ucProfile,
        .ucAppStatus,
        .leAudioFeatureMode,
    ]

    static let all: [HeadsetSettingKey: SettingReadDefinition] = {
        var definitions = Dictionary(
            uniqueKeysWithValues: ShippingWriteQualifications.all.values.map {
                ($0.key, SettingReadDefinition($0))
            }
        )
        definitions[.autoPowerOff] = SettingReadDefinition(
            key: .autoPowerOff,
            transactions: [WL5024Command.getPreference(module: 1).transaction],
            decoder: { responses in
                guard responses.count == 1 else { throw HeadsetError.malformedResponse }
                let status = try WL5024Command.getPreference(module: 1)
                    .decodeAutomaticPowerOffStatus(from: responses[0])
                return try status.settingValue
            }
        )
        definitions[.environmentDetection] = SettingReadDefinition(
            key: .environmentDetection,
            transactions: [WL5024Command.getEnvironmentDetection.transaction],
            decoder: { responses in
                guard responses.count == 1 else { throw HeadsetError.malformedResponse }
                return .boolean(
                    try WL5024Command.getEnvironmentDetection
                        .decodeEnvironmentDetection(from: responses[0])
                )
            }
        )
        definitions[.smartSwitch] = SettingReadDefinition(
            key: .smartSwitch,
            transactions: [WL5024Command.getSmartSwitch.transaction],
            decoder: { responses in
                guard responses.count == 1 else { throw HeadsetError.malformedResponse }
                return .boolean(
                    try WL5024Command.getSmartSwitch.decodeSmartSwitch(from: responses[0])
                )
            }
        )
        definitions[.micFlipAction] = statusByteDefinition(
            key: .micFlipAction,
            command: .getMicFlipAction
        )
        definitions[.ucProfile] = statusByteDefinition(
            key: .ucProfile,
            command: .getUCProfile
        )
        definitions[.ucAppStatus] = statusByteDefinition(
            key: .ucAppStatus,
            command: .getUCAppStatus
        )
        definitions[.leAudioFeatureMode] = SettingReadDefinition(
            key: .leAudioFeatureMode,
            transactions: [WL5024Command.getLEAudioFeatureMode.transaction],
            decoder: { responses in
                guard responses.count == 1 else { throw HeadsetError.malformedResponse }
                return .integer(Int(
                    try WL5024Command.getLEAudioFeatureMode
                        .decodeLEAudioFeatureMode(from: responses[0])
                ))
            }
        )
        return definitions
    }()

    private static func statusByteDefinition(
        key: HeadsetSettingKey,
        command: WL5024Command
    ) -> SettingReadDefinition {
        SettingReadDefinition(
            key: key,
            transactions: [command.transaction],
            decoder: { responses in
                guard responses.count == 1 else { throw HeadsetError.malformedResponse }
                return .integer(Int(try command.decodeStatusByte(from: responses[0])))
            }
        )
    }
}

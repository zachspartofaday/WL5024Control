import Foundation

struct WriteQualification: Sendable {
    struct Provenance: Sendable, Equatable {
        let captureIdentifier: String
        let sourceDescription: String
    }

    let key: HeadsetSettingKey
    let provenance: Provenance
    let preparationTransactions: [TransportTransaction]
    let requestEncoder: @Sendable (SettingValue, [Data]) throws -> [TransportTransaction]
    let acknowledgementValidator: @Sendable (Int, Data) throws -> Void
    let readBackTransactions: [TransportTransaction]
    let readBackDecoder: @Sendable ([Data]) throws -> SettingValue
    let comparison: @Sendable (SettingValue, SettingValue) -> Bool

    init(
        key: HeadsetSettingKey,
        provenance: Provenance,
        preparationTransactions: [TransportTransaction] = [],
        requestEncoder: @escaping @Sendable (SettingValue, [Data]) throws -> [TransportTransaction],
        acknowledgementValidator: @escaping @Sendable (Int, Data) throws -> Void,
        readBackTransactions: [TransportTransaction],
        readBackDecoder: @escaping @Sendable ([Data]) throws -> SettingValue,
        comparison: @escaping @Sendable (SettingValue, SettingValue) -> Bool
    ) {
        self.key = key
        self.provenance = provenance
        self.preparationTransactions = preparationTransactions
        self.requestEncoder = requestEncoder
        self.acknowledgementValidator = acknowledgementValidator
        self.readBackTransactions = readBackTransactions
        self.readBackDecoder = readBackDecoder
        self.comparison = comparison
    }

    func writeTransactions(
        for value: SettingValue,
        preparationResponses: [Data] = []
    ) throws -> [TransportTransaction] {
        try requestEncoder(value, preparationResponses)
    }
}

enum ShippingWriteQualifications {
    static let orderedKeys: [HeadsetSettingKey] = [
        .wearDetection,
        .automaticMedia,
        .muteMicrophoneOnRemoval,
        .quickPause,
        .quickPauseSensitivity,
        .answerCallsOnWear,
        .microphoneNoiseCancellation,
        .sidetone,
        .busyLight,
        .voiceGuidance,
    ]

    static let all: [HeadsetSettingKey: WriteQualification] = {
        var qualifications = Dictionary(
            uniqueKeysWithValues: wearKeys.map { ($0, wearDetectionQualification($0)) }
        )
        qualifications[.sidetone] = sidetoneQualification
        qualifications[.busyLight] = booleanQualification(
            key: .busyLight,
            getter: .getBusyLight,
            setter: WL5024Command.setBusyLight
        )
        qualifications[.voiceGuidance] = booleanQualification(
            key: .voiceGuidance,
            getter: .getVoiceGuidance,
            setter: WL5024Command.setVoiceGuidance
        )
        qualifications[.microphoneNoiseCancellation] = booleanQualification(
            key: .microphoneNoiseCancellation,
            getter: .getMicrophoneNoiseCancellation,
            setter: WL5024Command.setMicrophoneNoiseCancellation
        )
        return qualifications
    }()

    static let wearKeys: [HeadsetSettingKey] = [
        .wearDetection,
        .automaticMedia,
        .muteMicrophoneOnRemoval,
        .quickPause,
        .quickPauseSensitivity,
        .answerCallsOnWear,
    ]

    private static let wearProvenance = WriteQualification.Provenance(
        captureIdentifier: "dell-ddpm-2.3.0.9-static-2026-09-01",
        sourceDescription: "Dell DDPM WL5024 plug-in and AirohaHidCoreLib composite wear-detection command; user-authorized field validation pending"
    )

    private static let androidSDKProvenance = WriteQualification.Provenance(
        captureIdentifier: "dell-audio-android-1.1.2-airosdk-static-2026-09-01",
        sourceDescription: "Dell Audio 1.1.2 embedded Airoha Bluetooth SDK packet constructors and strict response parsers; user-authorized field validation pending"
    )

    private static func wearDetectionQualification(_ key: HeadsetSettingKey) -> WriteQualification {
        WriteQualification(
            key: key,
            provenance: wearProvenance,
            preparationTransactions: [WL5024Command.getWearDetection.transaction],
            requestEncoder: { value, preparationResponses in
                guard preparationResponses.count == 1 else { throw HeadsetError.malformedResponse }
                let current = try WL5024Command.getWearDetection.decodeWearDetectionFlags(
                    from: preparationResponses[0]
                )
                let updated = try WearDetectionFlags(rawValue: current).updating(key, to: value)
                return [WL5024Command.setWearDetection(updated.rawValue).transaction]
            },
            acknowledgementValidator: { index, response in
                guard index == 0 else { throw HeadsetError.malformedResponse }
                try WL5024Command.setWearDetection(0).validateWearDetectionAcknowledgement(response)
            },
            readBackTransactions: [WL5024Command.getWearDetection.transaction],
            readBackDecoder: { responses in
                guard responses.count == 1 else { throw HeadsetError.malformedResponse }
                let flags = try WL5024Command.getWearDetection.decodeWearDetectionFlags(from: responses[0])
                return try WearDetectionFlags(rawValue: flags).value(for: key)
            },
            comparison: ==
        )
    }

    private static let sidetoneQualification = WriteQualification(
        key: .sidetone,
        provenance: androidSDKProvenance,
        requestEncoder: { value, preparationResponses in
            guard preparationResponses.isEmpty,
                  case .choice(let choice) = value else {
                throw HeadsetError.invalidValue(.sidetone)
            }
            if choice == "off" {
                return [WL5024Command.setPreferenceByte(module: 7, value: 0).transaction]
            }
            guard let level = UInt16(choice), level <= 5 else {
                throw HeadsetError.invalidValue(.sidetone)
            }
            return [
                WL5024Command.setPreferenceByte(module: 7, value: 1).transaction,
                WL5024Command.setPreferenceUInt16(module: 6, value: level).transaction,
            ]
        },
        acknowledgementValidator: { index, response in
            let module: UInt16
            switch index {
            case 0: module = 7
            case 1: module = 6
            default: throw HeadsetError.malformedResponse
            }
            try WL5024Command.setPreferenceByte(module: module, value: 0)
                .validatePreferenceAcknowledgement(response)
        },
        readBackTransactions: [
            WL5024Command.getPreference(module: 7).transaction,
            WL5024Command.getPreference(module: 6).transaction,
        ],
        readBackDecoder: { responses in
            guard responses.count == 2 else { throw HeadsetError.malformedResponse }
            let state = try WL5024Command.getPreference(module: 7)
                .decodePreferenceValueStrict(from: responses[0], expectedValueLength: 1)
            guard let stateByte = state.first, stateByte == 0 || stateByte == 1 else {
                throw HeadsetError.malformedResponse
            }
            let levelData = try WL5024Command.getPreference(module: 6)
                .decodePreferenceValueStrict(from: responses[1], expectedValueLength: 2)
            let levelBytes = Array(levelData)
            let level = UInt16(levelBytes[0]) | (UInt16(levelBytes[1]) << 8)
            guard level <= 5 else { throw HeadsetError.malformedResponse }
            return stateByte == 0 ? .choice("off") : .choice(level.description)
        },
        comparison: ==
    )

    private static func booleanQualification(
        key: HeadsetSettingKey,
        getter: WL5024Command,
        setter: @escaping @Sendable (Bool) -> WL5024Command
    ) -> WriteQualification {
        WriteQualification(
            key: key,
            provenance: androidSDKProvenance,
            requestEncoder: { value, preparationResponses in
                guard preparationResponses.isEmpty,
                      case .boolean(let enabled) = value else {
                    throw HeadsetError.invalidValue(key)
                }
                return [setter(enabled).transaction]
            },
            acknowledgementValidator: { index, response in
                guard index == 0 else { throw HeadsetError.malformedResponse }
                try setter(false).validateSimpleAcknowledgement(response)
            },
            readBackTransactions: [getter.transaction],
            readBackDecoder: { responses in
                guard responses.count == 1 else { throw HeadsetError.malformedResponse }
                return .boolean(try getter.decodeStrictBoolean(from: responses[0]))
            },
            comparison: ==
        )
    }
}

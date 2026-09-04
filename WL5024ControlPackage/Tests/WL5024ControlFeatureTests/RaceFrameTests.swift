import Foundation
import Testing
@testable import WL5024ControlFeature

struct RaceFrameTests {
    @Test func encodesRecoveredWearDetectionPackets() {
        #expect(Array(WL5024Command.getWearDetection.frame.encoded) == [
            0x05, 0x5A, 0x02, 0x00, 0x21, 0x00,
        ])
        #expect(Array(WL5024Command.setWearDetection(0x0047).frame.encoded) == [
            0x05, 0x5A, 0x04, 0x00, 0x20, 0x00, 0x47, 0x00,
        ])
    }

    @Test func encodesAndroidSDKPreferencePackets() {
        #expect(Array(WL5024Command.getPreference(module: 8).frame.encoded) == [
            0x05, 0x5A, 0x04, 0x00, 0x83, 0x2C, 0x08, 0x00,
        ])
        #expect(Array(WL5024Command.setPreferenceByte(module: 8, value: 1).frame.encoded) == [
            0x05, 0x5A, 0x05, 0x00, 0x82, 0x2C, 0x08, 0x00, 0x01,
        ])
        #expect(Array(WL5024Command.setPreferenceUInt16(module: 6, value: 5).frame.encoded) == [
            0x05, 0x5A, 0x06, 0x00, 0x82, 0x2C, 0x06, 0x00, 0x05, 0x00,
        ])
    }

    @Test func strictlyDecodesAndAcknowledgesPreferencePackets() throws {
        let read = RaceFrame(
            packetType: .response,
            opcode: 0x2C83,
            payload: Data([0, 8, 0, 1])
        ).encoded
        #expect(try WL5024Command.getPreference(module: 8)
            .decodePreferenceValueStrict(from: read, expectedValueLength: 1) == Data([1]))

        let acknowledgement = RaceFrame(
            packetType: .response,
            opcode: 0x2C82,
            payload: Data([0, 8, 0])
        ).encoded
        try WL5024Command.setPreferenceByte(module: 8, value: 1)
            .validatePreferenceAcknowledgement(acknowledgement)

        let rejected = RaceFrame(
            packetType: .response,
            opcode: 0x2C82,
            payload: Data([1, 8, 0])
        ).encoded
        #expect(throws: HeadsetError.commandRejected) {
            try WL5024Command.setPreferenceByte(module: 8, value: 1)
                .validatePreferenceAcknowledgement(rejected)
        }

        for payload in [Data([0, 8]), Data([0, 9, 0])] {
            let invalid = RaceFrame(packetType: .response, opcode: 0x2C82, payload: payload).encoded
            #expect(throws: HeadsetError.malformedResponse) {
                try WL5024Command.setPreferenceByte(module: 8, value: 1)
                    .validatePreferenceAcknowledgement(invalid)
            }
        }
    }

    @Test func encodesAndStrictlyDecodesAndroidBooleanCommands() throws {
        let fixtures: [(WL5024Command, WL5024Command, UInt16, UInt16)] = [
            (.getBusyLight, .setBusyLight(true), 0x0023, 0x0022),
            (.getVoiceGuidance, .setVoiceGuidance(true), 0x0025, 0x0024),
            (.getIncomingAudioNoiseCancellation, .setIncomingAudioNoiseCancellation(true), 0x0044, 0x0043),
            (.getMicrophoneNoiseCancellation, .setMicrophoneNoiseCancellation(true), 0x0EFF, 0x0E0D),
        ]

        for (getter, setter, getOpcode, setOpcode) in fixtures {
            #expect(try RaceFrame(decoding: getter.frame.encoded).opcode == getOpcode)
            #expect(try RaceFrame(decoding: setter.frame.encoded).opcode == setOpcode)
            let read = RaceFrame(
                packetType: .response,
                opcode: getOpcode,
                payload: Data([0, 1])
            ).encoded
            #expect(try getter.decodeStrictBoolean(from: read))
            let acknowledgement = RaceFrame(
                packetType: .response,
                opcode: setOpcode,
                payload: Data([0])
            ).encoded
            try setter.validateSimpleAcknowledgement(acknowledgement)
            let rejected = RaceFrame(
                packetType: .response,
                opcode: setOpcode,
                payload: Data([1])
            ).encoded
            #expect(throws: HeadsetError.commandRejected) {
                try setter.validateSimpleAcknowledgement(rejected)
            }
        }
    }

    @Test func decodesBuildNineAutomaticPowerOffResponseStrictly() throws {
        let response = RaceFrame(
            packetType: .response,
            opcode: 0x2C83,
            payload: Data([0, 1, 0, 1, 0, 0x08, 0x07, 0, 0, 0x08, 0x07])
        ).encoded
        let status = try WL5024Command.getPreference(module: 1)
            .decodeAutomaticPowerOffStatus(from: response)
        #expect(status.primary == .init(isEnabled: true, seconds: 1_800))
        #expect(status.secondary == .init(isEnabled: false, seconds: 1_800))
        #expect(try status.settingValue == .choice("30m"))

        let oldAssumption = RaceFrame(
            packetType: .response,
            opcode: 0x2C83,
            payload: Data([0, 1, 0, 1, 0, 0x08, 0x07])
        ).encoded
        #expect(throws: HeadsetError.malformedResponse) {
            try WL5024Command.getPreference(module: 1)
                .decodeAutomaticPowerOffStatus(from: oldAssumption)
        }
    }

    @Test func decodesBuildNineEnvironmentDetectionResponseStrictly() throws {
        let response = RaceFrame(
            packetType: .response,
            opcode: 0x0E17,
            payload: Data([0x03, 0x03, 0])
        ).encoded
        #expect(try !WL5024Command.getEnvironmentDetection.decodeEnvironmentDetection(from: response))

        for payload in [Data([0, 0]), Data([0x03, 0x02, 0]), Data([0x03, 0x03, 2])] {
            let invalid = RaceFrame(packetType: .response, opcode: 0x0E17, payload: payload).encoded
            #expect(throws: HeadsetError.malformedResponse) {
                try WL5024Command.getEnvironmentDetection.decodeEnvironmentDetection(from: invalid)
            }
        }
    }

    @Test func encodesAndDecodesHardwareValidatedSmartSwitchResponse() throws {
        #expect(Array(WL5024Command.getSmartSwitch.frame.encoded) == [
            0x05, 0x5A, 0x04, 0x00, 0x01, 0x09, 0x06, 0x00,
        ])

        let response = RaceFrame(
            packetType: .response,
            opcode: 0x0901,
            payload: Data([0x06, 0x00, 0x00, 0x01])
        ).encoded
        #expect(try WL5024Command.getSmartSwitch.decodeSmartSwitch(from: response))
        #expect(WL5024Command.getSmartSwitch.transaction.expectedResponse.matches(response))

        for payload in [
            Data([0x06, 0x00, 0x00]),
            Data([0x05, 0x00, 0x00, 0x01]),
            Data([0x06, 0x00, 0x01, 0x01]),
            Data([0x06, 0x00, 0x00, 0x02]),
        ] {
            let invalid = RaceFrame(packetType: .response, opcode: 0x0901, payload: payload).encoded
            #expect(throws: HeadsetError.malformedResponse) {
                try WL5024Command.getSmartSwitch.decodeSmartSwitch(from: invalid)
            }
        }
    }

    @Test func encodesAndStrictlyDecodesFirmwareV4Settings() throws {
        let byteGetters: [(WL5024Command, UInt16, UInt8)] = [
            (.getMicFlipAction, 0x0029, 3),
            (.getUCProfile, 0x0041, 0),
            (.getUCAppStatus, 0x0042, 0),
        ]
        for (command, opcode, value) in byteGetters {
            #expect(Array(command.frame.encoded) == [
                0x05, 0x5A, 0x02, 0x00,
                UInt8(truncatingIfNeeded: opcode),
                UInt8(truncatingIfNeeded: opcode >> 8),
            ])
            let response = RaceFrame(
                packetType: .response,
                opcode: opcode,
                payload: Data([0, value])
            ).encoded
            #expect(try command.decodeStatusByte(from: response) == value)
            #expect(command.transaction.expectedResponse.matches(response))

            for payload in [Data([1, value]), Data([0]), Data([0, value, 0])] {
                let invalid = RaceFrame(
                    packetType: .response,
                    opcode: opcode,
                    payload: payload
                ).encoded
                #expect(throws: HeadsetError.malformedResponse) {
                    try command.decodeStatusByte(from: invalid)
                }
            }
        }

        #expect(Array(WL5024Command.getLEAudioFeatureMode.frame.encoded) == [
            0x05, 0x5A, 0x04, 0x00, 0x83, 0x2C, 0x31, 0x00,
        ])
        let leAudioResponse = RaceFrame(
            packetType: .response,
            opcode: 0x2C83,
            payload: Data([0, 0x31, 0, 1, 2, 2, 0])
        ).encoded
        #expect(try WL5024Command.getLEAudioFeatureMode
            .decodeLEAudioFeatureMode(from: leAudioResponse) == 2)
        #expect(WL5024Command.getLEAudioFeatureMode.transaction.expectedResponse.matches(leAudioResponse))

        for payload in [
            Data([0, 0x31, 0, 2, 2, 2, 0]),
            Data([0, 0x31, 0, 1, 2]),
            Data([1, 0x31, 0, 1, 2, 2, 0]),
        ] {
            let invalid = RaceFrame(packetType: .response, opcode: 0x2C83, payload: payload).encoded
            #expect(throws: HeadsetError.malformedResponse) {
                try WL5024Command.getLEAudioFeatureMode.decodeLEAudioFeatureMode(from: invalid)
            }
        }
    }

    @Test func decodesFrameInsideTransportWrapper() throws {
        let wrapped = Data([0xA1, 0x02]) + WL5024Command.getWearDetection.frame.encoded + Data([0xEE])
        #expect(try RaceFrame(decoding: wrapped) == WL5024Command.getWearDetection.frame)
    }

    @Test func decodesStrictWearDetectionResponse() throws {
        let response = wearResponse(flags: 0x0067)
        #expect(try WL5024Command.getWearDetection.decodeWearDetectionFlags(from: response) == 0x0067)
    }

    @Test func wearDetectionValuesUseRecoveredBitLayout() throws {
        let flags = WearDetectionFlags(rawValue: 0x0067)
        #expect(try flags.value(for: .wearDetection) == .boolean(true))
        #expect(try flags.value(for: .automaticMedia) == .boolean(true))
        #expect(try flags.value(for: .muteMicrophoneOnRemoval) == .boolean(true))
        #expect(try flags.value(for: .quickPause) == .boolean(true))
        #expect(try flags.value(for: .quickPauseSensitivity) == .choice("sensitive"))
        #expect(try flags.value(for: .answerCallsOnWear) == .boolean(true))
    }

    @Test func updatesOneCompositeFieldWithoutChangingOthers() throws {
        let original = WearDetectionFlags(rawValue: 0xA567)
        let updated = try original.updating(.automaticMedia, to: .boolean(false))
        #expect(updated.rawValue == 0xA565)
        #expect(try updated.updating(.automaticMedia, to: .boolean(true)).rawValue == original.rawValue)
    }

    @Test func quickPauseUsesDDPMModesAndPreservesUnrelatedBits() throws {
        let disabled = WearDetectionFlags(rawValue: 0xA547)
        #expect(try disabled.updating(.quickPause, to: .boolean(true)).rawValue == 0xA567)
        // Changing sensitivity while Quick Pause is off would silently enable it.
        #expect(throws: HeadsetError.invalidValue(.quickPauseSensitivity)) {
            try disabled.updating(.quickPauseSensitivity, to: .choice("normal"))
        }
        #expect(try WearDetectionFlags(rawValue: 0xA567)
            .updating(.quickPauseSensitivity, to: .choice("normal")).rawValue == 0xA557)
        #expect(try WearDetectionFlags(rawValue: 0xA567)
            .updating(.quickPause, to: .boolean(false)).rawValue == 0xA547)
    }

    @Test func rejectsUnknownQuickPauseMode() {
        let flags = WearDetectionFlags(rawValue: 0x0030)
        #expect(throws: HeadsetError.invalidValue(.quickPauseSensitivity)) {
            try flags.value(for: .quickPause)
        }
    }

    @Test func rejectsMalformedWearDetectionFrames() {
        let wrongOpcode = RaceFrame(packetType: .response, opcode: 0x0020, payload: Data([0, 1, 0])).encoded
        let failedStatus = RaceFrame(packetType: .response, opcode: 0x0021, payload: Data([1, 1, 0])).encoded
        let trailingPayload = RaceFrame(packetType: .response, opcode: 0x0021, payload: Data([0, 1, 0, 0])).encoded
        let echoedCommand = RaceFrame(opcode: 0x0021, payload: Data([0, 1, 0])).encoded

        for response in [wrongOpcode, failedStatus, trailingPayload, echoedCommand] {
            #expect(throws: HeadsetError.malformedResponse) {
                try WL5024Command.getWearDetection.decodeWearDetectionFlags(from: response)
            }
        }
    }

    @Test func acknowledgementMustBeExactSuccessStatus() throws {
        let valid = RaceFrame(packetType: .response, opcode: 0x0020, payload: Data([0])).encoded
        try WL5024Command.setWearDetection(0).validateWearDetectionAcknowledgement(valid)

        let rejected = RaceFrame(packetType: .response, opcode: 0x0020, payload: Data([1])).encoded
        #expect(throws: HeadsetError.commandRejected) {
            try WL5024Command.setWearDetection(0).validateWearDetectionAcknowledgement(rejected)
        }

        for payload in [Data(), Data([0, 0])] {
            let invalid = RaceFrame(packetType: .response, opcode: 0x0020, payload: payload).encoded
            #expect(throws: HeadsetError.malformedResponse) {
                try WL5024Command.setWearDetection(0).validateWearDetectionAcknowledgement(invalid)
            }
        }
    }

    @Test func readOnlyDiscoveryPlanContainsOnlyRecoveredGetterFamilies() throws {
        let probes = ReadOnlyDiscoveryPlan.probes
        #expect(probes.count == 266)
        #expect(ReadOnlyDiscoveryPlan.preferenceModules == 0...255)

        var opcodes: Set<UInt16> = []
        for probe in probes {
            let frame = try RaceFrame(decoding: probe.transaction.request)
            #expect(frame.packetType == .commandExpectsResponse)
            opcodes.insert(frame.opcode)
        }
        #expect(opcodes == [
            0x0021, 0x0023, 0x0025, 0x0029, 0x0041, 0x0042, 0x0044,
            0x0901, 0x0E17, 0x0EFF, 0x2C83,
        ])
        #expect(!opcodes.contains(0x0020))
        #expect(!opcodes.contains(0x2C82))
        #expect(!opcodes.contains(0x1101))
    }

    @Test func matcherRejectsWrongOpcodeAndCommandFrames() {
        let matcher = WL5024Command.getWearDetection.transaction.expectedResponse
        let wrongOpcode = RaceFrame(packetType: .response, opcode: 0x0E17).encoded
        let echoedCommand = WL5024Command.getWearDetection.frame.encoded
        let matching = wearResponse(flags: 0x0001)

        #expect(!matcher.matches(wrongOpcode))
        #expect(!matcher.matches(echoedCommand))
        #expect(matcher.matches(matching))
        #expect(TransactionResponseRouter.classify(wrongOpcode, pending: matcher) == .unsolicited)
        #expect(TransactionResponseRouter.classify(matching, pending: matcher) == .matched)
    }

    @Test func statusOnlyPreferenceResponseIsAmbiguousNotMatched() {
        let matcher = WL5024Command.getPreference(module: 10).transaction.expectedResponse
        let statusOnly = RaceFrame(packetType: .response, opcode: 0x2C83, payload: Data([0])).encoded
        #expect(!matcher.matches(statusOnly))
        #expect(TransactionResponseRouter.classify(statusOnly, pending: matcher) == .ambiguousStatusOnly)
        // Wrong opcode is not ambiguous even with one-byte payload.
        let otherOpcode = RaceFrame(packetType: .response, opcode: 0x0021, payload: Data([0])).encoded
        #expect(TransactionResponseRouter.classify(otherOpcode, pending: matcher) == .unsolicited)
    }
}

private func wearResponse(flags: UInt16) -> Data {
    RaceFrame(
        packetType: .response,
        opcode: 0x0021,
        payload: Data([0, UInt8(truncatingIfNeeded: flags), UInt8(truncatingIfNeeded: flags >> 8)])
    ).encoded
}

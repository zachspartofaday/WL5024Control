import Foundation

public enum CapabilityCatalog {
    public static let all: [CapabilityDefinition] = HeadsetSettingKey.allCases.map(definition)

    public static func definition(for key: HeadsetSettingKey) -> CapabilityDefinition {
        switch key {
        case .automaticMedia:
            recovered(key, .genericPreference(module: 2, scalar: .byte), "GetAvrcpPlayPause and SetAvrcpPlayPause")
        case .autoPowerOff:
            recovered(key, .genericPreference(module: 1, scalar: .littleEndianInt32), "GetAutoPowerOff and SetAutoPowerOff")
        case .sidetone:
            recovered(key, .genericPreference(module: 6, scalar: .littleEndianUInt16), "GetSidetoneLevel/State and SetSidetoneLevel/State")
        case .advancedPassthrough:
            recovered(key, .genericPreference(module: 8, scalar: .byte), "GetAdvancedPassthrough and SetAdvancedPassthrough")
        case .voicePrompts:
            recovered(key, .genericPreference(module: 9, scalar: .byte), "GetVoicePrompt and SetVoicePrompt")
        case .touchControls:
            recovered(key, .genericPreference(module: 0, scalar: .littleEndianUInt16), "GetTouchFunction and SetTouchFunction")
        case .environmentDetection:
            recovered(key, .environmentDetection, "GetEnvironmentDetection and SetEnvironmentDetection")
        case .smartSwitch:
            recovered(key, .smartSwitch, "GetSmartSwitch and SetSmartSwitch")
        case .findMyHeadset:
            mapped(key, access: .action, .vendorFunction("FindMyBuds"), "Firmware export FindMyBuds")
        case .ancMode:
            mapped(key, .vendorFunction("GetANC/SetANC"), "Firmware exports and Dell Peripheral Manager")
        case .microphoneNoiseCancellation:
            mapped(key, .vendorFunction("GetAINR/SetAINR"), "Windows WL5024 plug-in: outgoing microphone noise cancellation")
        case .incomingAudioNoiseCancellation:
            mapped(key, .vendorFunction("GetDownlinkNR/SetDownlinkNR"), "Windows WL5024 plug-in: incoming audio noise cancellation")
        case .adaptiveANC:
            mapped(key, .vendorFunction("GetAdaptiveANC/SetAdaptiveANC"), "Firmware export family")
        case .busyLight:
            mapped(key, .vendorFunction("GetBusyLight/SetBusyLight"), "Windows WL5024 plug-in")
        case .wearDetection, .muteMicrophoneOnRemoval, .answerCallsOnWear, .quickPause, .quickPauseSensitivity:
            mapped(key, .vendorFunction("GetWearDetectionMicOnOff/SetWearDetectionMicOnOff"), "Windows composite wear-detection bitmask")
        case .equalizerPreset, .bass, .mid, .treble:
            mapped(key, .vendorFunction("GetPEQ/SetPEQ"), "Windows WL5024 equalizer commands")
        case .adaptiveEQ:
            mapped(key, .vendorFunction("GetAdaptiveEQ/SetAdaptiveEQ"), "Firmware export family")
        case .maximumVolume:
            mapped(key, .vendorFunction("GetSoundMaxVolumeEx/SetSoundMaxVolumeEx"), "Firmware export family")
        case .voiceGuidance:
            mapped(key, .vendorFunction("GetVoiceGuidance/SetVoiceGuidance"), "Windows WL5024 plug-in")
        case .deviceName:
            mapped(key, .vendorFunction("GetDeviceName/SetDeviceName"), "Firmware export family")
        case .gestureControls:
            mapped(key, .vendorFunction("GetGesture/SetGesture"), "Firmware export family")
        case .multiAssistant:
            mapped(key, .vendorFunction("GetMultiAI/SetMultiAI"), "Firmware export family")
        case .gameChatBalance, .gameChatMix, .gameMicrophoneVolume:
            mapped(key, .vendorFunction("GetGameChat/SetGameChat"), "Firmware game/chat export family")
        }
    }

    private static func recovered(
        _ key: HeadsetSettingKey,
        _ recipe: WireRecipe,
        _ evidence: String
    ) -> CapabilityDefinition {
        CapabilityDefinition(
            key: key,
            recipe: recipe,
            qualification: .staticallyRecovered,
            evidence: evidence
        )
    }

    private static func mapped(
        _ key: HeadsetSettingKey,
        access: CapabilityAccess = .readWrite,
        _ recipe: WireRecipe,
        _ evidence: String
    ) -> CapabilityDefinition {
        CapabilityDefinition(
            key: key,
            access: access,
            recipe: recipe,
            qualification: .hardwareValidationPending,
            evidence: evidence
        )
    }
}

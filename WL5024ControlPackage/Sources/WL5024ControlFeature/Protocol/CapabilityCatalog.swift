import Foundation

public enum CapabilityCatalog {
    public static let all: [CapabilityDefinition] = HeadsetSettingKey.allCases.map(definition)
    public static let configurableSettings: [HeadsetSettingKey] = [
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
    public static let readOnlySettings: [HeadsetSettingKey] = [
        .autoPowerOff,
        .environmentDetection,
        .smartSwitch,
        .micFlipAction,
        .ucProfile,
        .ucAppStatus,
        .leAudioFeatureMode,
    ]
    public static let experimentalSettings = configurableSettings
    public static let visibleConfigurationSections: [SettingsSection] = [
        .noiseControl,
        .callsAndMicrophone,
        .wearAndAutomation,
        .device,
    ]

    public static func definition(for key: HeadsetSettingKey) -> CapabilityDefinition {
        switch key {
        case .automaticMedia:
            readValidated(key, .wearDetectionComposite, "Build 9 WL5024 capture plus Dell DDPM composite bit 1")
        case .autoPowerOff:
            readValidated(key, .genericPreference(module: 1, scalar: .composite), "Build 9 WL5024 capture: two Boolean/seconds UInt16 pairs; write layout remains unqualified")
        case .sidetone:
            readValidated(key, .genericPreference(module: 6, scalar: .littleEndianUInt16), "Build 9 WL5024 capture plus Dell Android SDK: state module 7 and level module 6")
        case .advancedPassthrough:
            recovered(key, .genericPreference(module: 8, scalar: .byte), "Dell Audio Android Airoha Bluetooth SDK: GetAdvancedPassthrough and SetAdvancedPassthrough")
        case .voicePrompts:
            recovered(key, .genericPreference(module: 9, scalar: .byte), "GetVoicePrompt and SetVoicePrompt")
        case .touchControls:
            recovered(key, .genericPreference(module: 0, scalar: .byte), "Build 9 returned one byte from GetTouchFunction module 0; value semantics remain unmapped")
        case .environmentDetection:
            readValidated(key, .environmentDetection, "Build 9 WL5024 capture confirmed GetEnvironmentDetection response 03 03 VV; setter remains unqualified")
        case .smartSwitch:
            readValidated(
                key,
                .smartSwitch,
                "Direct WL5024 capture confirmed get 0x0901 module 0x0006; write remains unqualified"
            )
        case .micFlipAction:
            readValidated(
                key,
                .vendorFunction("GetMicFlipAction/SetMicFlipAction"),
                "Dell August 2026 Windows SDK plus direct WL5024 response from get 0x0029; values and write remain unqualified"
            )
        case .ucProfile:
            readValidated(
                key,
                .vendorFunction("GetUcProfile/SetUcProfile"),
                "Dell August 2026 Windows SDK plus direct WL5024 response from get 0x0041; values and write remain unqualified"
            )
        case .ucAppStatus:
            readValidated(
                key,
                .vendorFunction("GetUcAppStatus"),
                "Dell August 2026 Windows SDK plus direct WL5024 response from read-only get 0x0042"
            )
        case .leAudioFeatureMode:
            readValidated(
                key,
                .genericPreference(module: 0x0031, scalar: .composite),
                "Firmware 4.1.4 direct capture plus Dell Windows SDK GetLEAFeatureMode/SetLEAFeatureMode; accepted write values remain unqualified"
            )
        case .findMyHeadset:
            mapped(key, access: .action, .vendorFunction("FindMyBuds"), "Firmware export FindMyBuds")
        case .ancMode:
            mapped(key, .vendorFunction("GetANC/SetANC"), "Firmware exports and Dell Peripheral Manager")
        case .microphoneNoiseCancellation:
            readValidated(key, .vendorFunction("GetAINR/SetAINR"), "Build 9 WL5024 capture confirmed Boolean getter 0x0EFF; setter 0x0E0D remains experimental")
        case .incomingAudioNoiseCancellation:
            recovered(key, .vendorFunction("GetDownlinkNR/SetDownlinkNR"), "Dell Audio Android Airoha Bluetooth SDK: boolean opcodes 0x0044/0x0043")
        case .adaptiveANC:
            mapped(key, .vendorFunction("GetAdaptiveANC/SetAdaptiveANC"), "Firmware export family")
        case .busyLight:
            readValidated(key, .vendorFunction("GetBusyLight/SetBusyLight"), "Build 9 WL5024 capture confirmed Boolean getter 0x0023; setter 0x0022 remains experimental")
        case .wearDetection:
            readValidated(key, .wearDetectionComposite, "Build 9 WL5024 capture plus Dell DDPM composite bit 0")
        case .muteMicrophoneOnRemoval:
            readValidated(key, .wearDetectionComposite, "Build 9 WL5024 capture plus Dell DDPM composite bit 2")
        case .quickPause:
            readValidated(key, .wearDetectionComposite, "Build 9 WL5024 capture plus Dell DDPM composite bits 4–5")
        case .quickPauseSensitivity:
            readValidated(key, .wearDetectionComposite, "Build 9 WL5024 capture plus Dell DDPM composite bits 4–5")
        case .answerCallsOnWear:
            readValidated(key, .wearDetectionComposite, "Build 9 WL5024 capture plus Dell DDPM composite bit 6")
        case .equalizerPreset, .bass, .mid, .treble:
            mapped(key, .vendorFunction("GetPEQ/SetPEQ"), "Windows WL5024 equalizer commands")
        case .adaptiveEQ:
            mapped(key, .vendorFunction("GetAdaptiveEQ/SetAdaptiveEQ"), "Firmware export family")
        case .maximumVolume:
            mapped(key, .vendorFunction("GetSoundMaxVolumeEx/SetSoundMaxVolumeEx"), "Firmware export family")
        case .voiceGuidance:
            readValidated(key, .vendorFunction("GetVoiceGuidance/SetVoiceGuidance"), "Build 9 WL5024 capture confirmed Boolean getter 0x0025; setter 0x0024 remains experimental")
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

    private static func readValidated(
        _ key: HeadsetSettingKey,
        _ recipe: WireRecipe,
        _ evidence: String
    ) -> CapabilityDefinition {
        CapabilityDefinition(
            key: key,
            recipe: recipe,
            qualification: .hardwareReadValidated,
            evidence: evidence
        )
    }
}

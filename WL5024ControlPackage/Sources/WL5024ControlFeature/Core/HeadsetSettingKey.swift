import Foundation

public enum HeadsetSettingKey: String, CaseIterable, Identifiable, Sendable, Codable {
    case ancMode
    case microphoneNoiseCancellation
    case incomingAudioNoiseCancellation
    case adaptiveANC
    case advancedPassthrough
    case environmentDetection
    case sidetone
    case busyLight
    case wearDetection
    case automaticMedia
    case muteMicrophoneOnRemoval
    case answerCallsOnWear
    case quickPause
    case quickPauseSensitivity
    case autoPowerOff
    case equalizerPreset
    case bass
    case mid
    case treble
    case adaptiveEQ
    case maximumVolume
    case voiceGuidance
    case voicePrompts
    case deviceName
    case touchControls
    case gestureControls
    case smartSwitch
    case micFlipAction
    case ucProfile
    case ucAppStatus
    case leAudioFeatureMode
    case multiAssistant
    case findMyHeadset
    case gameChatBalance
    case gameChatMix
    case gameMicrophoneVolume

    public var id: Self { self }

    public var section: SettingsSection {
        switch self {
        case .ancMode, .microphoneNoiseCancellation, .incomingAudioNoiseCancellation,
             .adaptiveANC, .advancedPassthrough, .environmentDetection:
            .noiseControl
        case .sidetone, .busyLight:
            .callsAndMicrophone
        case .wearDetection, .automaticMedia, .muteMicrophoneOnRemoval,
             .answerCallsOnWear, .quickPause, .quickPauseSensitivity, .autoPowerOff:
            .wearAndAutomation
        case .equalizerPreset, .bass, .mid, .treble, .adaptiveEQ,
             .maximumVolume, .gameChatBalance, .gameChatMix, .gameMicrophoneVolume:
            .sound
        case .voiceGuidance, .voicePrompts, .deviceName, .touchControls,
             .gestureControls, .smartSwitch, .micFlipAction, .ucProfile,
             .ucAppStatus, .leAudioFeatureMode, .multiAssistant, .findMyHeadset:
            .device
        }
    }

    public var title: LocalizedStringResource {
        switch self {
        case .ancMode: LocalizedStringResource("Listening Mode", bundle: #bundle)
        case .microphoneNoiseCancellation: LocalizedStringResource("Microphone noise cancellation", bundle: #bundle)
        case .incomingAudioNoiseCancellation: LocalizedStringResource("Incoming audio noise cancellation", bundle: #bundle)
        case .adaptiveANC: LocalizedStringResource("Adaptive noise cancellation", bundle: #bundle)
        case .advancedPassthrough: LocalizedStringResource("Advanced transparency", bundle: #bundle)
        case .environmentDetection: LocalizedStringResource("Environment detection", bundle: #bundle)
        case .sidetone: LocalizedStringResource("Sidetone", bundle: #bundle)
        case .busyLight: LocalizedStringResource("Busy light", bundle: #bundle)
        case .wearDetection: LocalizedStringResource("Wear detection", bundle: #bundle)
        case .automaticMedia: LocalizedStringResource("Automatically pause and resume media", bundle: #bundle)
        case .muteMicrophoneOnRemoval: LocalizedStringResource("Mute microphone when removed", bundle: #bundle)
        case .answerCallsOnWear: LocalizedStringResource("Answer calls when worn", bundle: #bundle)
        case .quickPause: LocalizedStringResource("Quick Pause", bundle: #bundle)
        case .quickPauseSensitivity: LocalizedStringResource("Quick Pause sensitivity", bundle: #bundle)
        case .autoPowerOff: LocalizedStringResource("Automatic power off", bundle: #bundle)
        case .equalizerPreset: LocalizedStringResource("Equalizer", bundle: #bundle)
        case .bass: LocalizedStringResource("Bass", bundle: #bundle)
        case .mid: LocalizedStringResource("Mid", bundle: #bundle)
        case .treble: LocalizedStringResource("Treble", bundle: #bundle)
        case .adaptiveEQ: LocalizedStringResource("Adaptive equalizer", bundle: #bundle)
        case .maximumVolume: LocalizedStringResource("Maximum volume", bundle: #bundle)
        case .voiceGuidance: LocalizedStringResource("Voice guidance", bundle: #bundle)
        case .voicePrompts: LocalizedStringResource("Voice prompts", bundle: #bundle)
        case .deviceName: LocalizedStringResource("Device name", bundle: #bundle)
        case .touchControls: LocalizedStringResource("Touch controls", bundle: #bundle)
        case .gestureControls: LocalizedStringResource("Button and gesture controls", bundle: #bundle)
        case .smartSwitch: LocalizedStringResource("Smart Switch", bundle: #bundle)
        case .micFlipAction: LocalizedStringResource("Microphone boom action", bundle: #bundle)
        case .ucProfile: LocalizedStringResource("UC profile", bundle: #bundle)
        case .ucAppStatus: LocalizedStringResource("UC app status", bundle: #bundle)
        case .leAudioFeatureMode: LocalizedStringResource("LE Audio feature mode", bundle: #bundle)
        case .multiAssistant: LocalizedStringResource("Voice assistant", bundle: #bundle)
        case .findMyHeadset: LocalizedStringResource("Find My Headset", bundle: #bundle)
        case .gameChatBalance: LocalizedStringResource("Game and chat balance", bundle: #bundle)
        case .gameChatMix: LocalizedStringResource("Game and chat mix", bundle: #bundle)
        case .gameMicrophoneVolume: LocalizedStringResource("Game microphone volume", bundle: #bundle)
        }
    }

    public var explanation: LocalizedStringResource {
        switch self {
        case .automaticMedia:
            LocalizedStringResource("Turn this off to prevent the headset from launching or controlling music when you put it on or remove it.", bundle: #bundle)
        case .wearDetection:
            LocalizedStringResource("Use the headset's wear sensor for the actions below.", bundle: #bundle)
        case .muteMicrophoneOnRemoval:
            LocalizedStringResource("Mute calls when you remove the headset.", bundle: #bundle)
        case .answerCallsOnWear:
            LocalizedStringResource("Answer an incoming call when you put the headset on.", bundle: #bundle)
        case .sidetone:
            LocalizedStringResource("Choose how much of your own voice you hear during calls.", bundle: #bundle)
        case .ancMode:
            LocalizedStringResource("Choose noise cancellation, transparency, or neither.", bundle: #bundle)
        case .equalizerPreset:
            LocalizedStringResource("Adjust the sound profile stored on the headset.", bundle: #bundle)
        case .autoPowerOff:
            LocalizedStringResource("Choose how long the idle headset waits before powering off.", bundle: #bundle)
        case .findMyHeadset:
            LocalizedStringResource("Play the headset's location sound.", bundle: #bundle)
        case .micFlipAction:
            LocalizedStringResource("Reports the action assigned to moving the microphone boom.", bundle: #bundle)
        case .ucProfile:
            LocalizedStringResource("Reports the headset's current unified-communications profile.", bundle: #bundle)
        case .ucAppStatus:
            LocalizedStringResource("Reports the current unified-communications application state.", bundle: #bundle)
        case .leAudioFeatureMode:
            LocalizedStringResource("Reports the LE Audio mode exposed by firmware 4.1.4.", bundle: #bundle)
        default:
            LocalizedStringResource("This preference is stored on the headset.", bundle: #bundle)
        }
    }

    public var controlKind: SettingControlKind {
        switch self {
        case .ancMode, .sidetone, .quickPauseSensitivity, .autoPowerOff,
             .equalizerPreset, .gestureControls, .multiAssistant:
            .choices
        case .bass, .mid, .treble:
            .level(range: -6...6, step: 1)
        case .maximumVolume, .gameChatBalance, .gameChatMix, .gameMicrophoneVolume:
            .level(range: 0...100, step: 1)
        case .deviceName:
            .text
        case .findMyHeadset:
            .action
        case .micFlipAction, .ucProfile, .ucAppStatus, .leAudioFeatureMode:
            .readOnlyValue
        default:
            .toggle
        }
    }

    public var choices: [SettingChoice] {
        switch self {
        case .ancMode:
            [
                SettingChoice(id: "anc", title: LocalizedStringResource("Noise Cancellation", bundle: #bundle)),
                SettingChoice(id: "transparency1", title: LocalizedStringResource("Transparency 1", bundle: #bundle)),
                SettingChoice(id: "transparency2", title: LocalizedStringResource("Transparency 2", bundle: #bundle)),
                SettingChoice(id: "transparency3", title: LocalizedStringResource("Transparency 3", bundle: #bundle)),
                SettingChoice(id: "transparency4", title: LocalizedStringResource("Transparency 4", bundle: #bundle)),
                SettingChoice(id: "transparency5", title: LocalizedStringResource("Transparency 5", bundle: #bundle)),
                SettingChoice(id: "off", title: LocalizedStringResource("Off", bundle: #bundle)),
            ]
        case .sidetone:
            [
                SettingChoice(id: "off", title: LocalizedStringResource("Off", bundle: #bundle)),
                SettingChoice(id: "0", title: LocalizedStringResource("Level 0", bundle: #bundle)),
                SettingChoice(id: "1", title: LocalizedStringResource("Level 1", bundle: #bundle)),
                SettingChoice(id: "2", title: LocalizedStringResource("Level 2", bundle: #bundle)),
                SettingChoice(id: "3", title: LocalizedStringResource("Level 3", bundle: #bundle)),
                SettingChoice(id: "4", title: LocalizedStringResource("Level 4", bundle: #bundle)),
                SettingChoice(id: "5", title: LocalizedStringResource("Level 5", bundle: #bundle)),
            ]
        case .quickPauseSensitivity:
            [
                SettingChoice(id: "normal", title: LocalizedStringResource("Normal", bundle: #bundle)),
                SettingChoice(id: "sensitive", title: LocalizedStringResource("Sensitive", bundle: #bundle)),
            ]
        case .autoPowerOff:
            [
                SettingChoice(id: "15m", title: LocalizedStringResource("15 minutes", bundle: #bundle)),
                SettingChoice(id: "30m", title: LocalizedStringResource("30 minutes", bundle: #bundle)),
                SettingChoice(id: "1h", title: LocalizedStringResource("1 hour", bundle: #bundle)),
                SettingChoice(id: "2h", title: LocalizedStringResource("2 hours", bundle: #bundle)),
                SettingChoice(id: "4h", title: LocalizedStringResource("4 hours", bundle: #bundle)),
                SettingChoice(id: "6h", title: LocalizedStringResource("6 hours", bundle: #bundle)),
                SettingChoice(id: "8h", title: LocalizedStringResource("8 hours", bundle: #bundle)),
                SettingChoice(id: "off", title: LocalizedStringResource("Off", bundle: #bundle)),
            ]
        case .equalizerPreset:
            [
                SettingChoice(id: "default", title: LocalizedStringResource("Default", bundle: #bundle)),
                SettingChoice(id: "bassBoost", title: LocalizedStringResource("Bass Boost", bundle: #bundle)),
                SettingChoice(id: "speechBoost", title: LocalizedStringResource("Speech Boost", bundle: #bundle)),
                SettingChoice(id: "trebleBoost", title: LocalizedStringResource("Treble Boost", bundle: #bundle)),
                SettingChoice(id: "custom", title: LocalizedStringResource("Custom", bundle: #bundle)),
            ]
        case .voiceGuidance:
            [
                SettingChoice(id: "off", title: LocalizedStringResource("Off", bundle: #bundle)),
                SettingChoice(id: "essential", title: LocalizedStringResource("Essential", bundle: #bundle)),
                SettingChoice(id: "all", title: LocalizedStringResource("All", bundle: #bundle)),
            ]
        case .gestureControls:
            [
                SettingChoice(id: "default", title: LocalizedStringResource("Default", bundle: #bundle)),
                SettingChoice(id: "media", title: LocalizedStringResource("Media Controls", bundle: #bundle)),
                SettingChoice(id: "calls", title: LocalizedStringResource("Call Controls", bundle: #bundle)),
            ]
        case .multiAssistant:
            [
                SettingChoice(id: "system", title: LocalizedStringResource("System Default", bundle: #bundle)),
                SettingChoice(id: "off", title: LocalizedStringResource("Off", bundle: #bundle)),
            ]
        default:
            []
        }
    }

    public var defaultValue: SettingValue {
        switch self {
        case .ancMode: .choice("anc")
        case .sidetone: .choice("2")
        case .quickPauseSensitivity: .choice("normal")
        case .autoPowerOff: .choice("2h")
        case .equalizerPreset: .choice("default")
        case .voiceGuidance: .boolean(true)
        case .gestureControls: .choice("default")
        case .multiAssistant: .choice("system")
        case .bass, .mid, .treble: .integer(0)
        case .gameChatBalance, .gameChatMix: .integer(50)
        case .maximumVolume, .gameMicrophoneVolume: .integer(100)
        case .deviceName: .text("Dell WL5024")
        case .findMyHeadset: .boolean(false)
        case .micFlipAction: .integer(3)
        case .ucProfile, .ucAppStatus: .integer(0)
        case .leAudioFeatureMode: .integer(2)
        default: .boolean(true)
        }
    }
}

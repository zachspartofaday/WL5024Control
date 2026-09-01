import Foundation

public enum SettingsPage: String, CaseIterable, Identifiable, Sendable {
    case overview
    case noiseControl
    case callsAndMicrophone
    case wearAndAutomation
    case sound
    case device
    case diagnostics

    public var id: Self { self }

    public var title: LocalizedStringResource {
        switch self {
        case .overview: LocalizedStringResource("Overview", bundle: #bundle)
        case .noiseControl: LocalizedStringResource("Noise Control", bundle: #bundle)
        case .callsAndMicrophone: LocalizedStringResource("Calls & Microphone", bundle: #bundle)
        case .wearAndAutomation: LocalizedStringResource("Wear & Automation", bundle: #bundle)
        case .sound: LocalizedStringResource("Sound", bundle: #bundle)
        case .device: LocalizedStringResource("Device", bundle: #bundle)
        case .diagnostics: LocalizedStringResource("Diagnostics", bundle: #bundle)
        }
    }

    public var symbolName: String {
        switch self {
        case .overview: "headphones"
        case .noiseControl: "waveform.badge.mic"
        case .callsAndMicrophone: "phone"
        case .wearAndAutomation: "ear"
        case .sound: "slider.horizontal.3"
        case .device: "gearshape"
        case .diagnostics: "stethoscope"
        }
    }
}

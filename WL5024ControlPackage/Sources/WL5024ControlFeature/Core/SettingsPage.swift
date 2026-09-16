import Foundation

public enum SettingsSection: String, CaseIterable, Identifiable, Sendable {
    case noiseControl
    case callsAndMicrophone
    case wearAndAutomation
    case sound
    case device

    public var id: Self { self }

    public var title: LocalizedStringResource {
        switch self {
        case .noiseControl: LocalizedStringResource("Noise Control", bundle: #bundle)
        case .callsAndMicrophone: LocalizedStringResource("Calls & Microphone", bundle: #bundle)
        case .wearAndAutomation: LocalizedStringResource("Wear & Automation", bundle: #bundle)
        case .sound: LocalizedStringResource("Sound", bundle: #bundle)
        case .device: LocalizedStringResource("Device", bundle: #bundle)
        }
    }
}

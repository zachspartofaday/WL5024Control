import Foundation
import WL5024ControlFeature

enum ProbeExitStatus {
    static let success: Int32 = 0
    /// Invalid arguments (sysexits EX_USAGE).
    static let usage: Int32 = 64
    /// Setup failure, timeout, I/O failure, or malformed response (EX_IOERR).
    static let failure: Int32 = 74
}

@main
struct WL5024Probe {
    static func main() {
        let rawArguments = Array(CommandLine.arguments.dropFirst())
        let arguments = Set(rawArguments)

        if arguments.contains("--usb") {
            let code = DirectUSBProbe.run(arguments: rawArguments)
            if code != ProbeExitStatus.success { Foundation.exit(code) }
            return
        }

        if arguments.contains("--live") {
            let code = DirectBLEProbe.run(arguments: rawArguments)
            if code != ProbeExitStatus.success { Foundation.exit(code) }
            return
        }

        if arguments.contains("--packets") {
            printPacket("get-wear-detection-flags", WL5024Command.getWearDetection.frame.encoded)
            printPacket("set-wear-detection-flags-example", WL5024Command.setWearDetection(0x0047).frame.encoded)
            printPacket("get-automatic-power-off", WL5024Command.getPreference(module: 1).frame.encoded)
            printPacket("disable-automatic-power-off", WL5024Command.setAutoPowerOff(enabled: false, seconds: 0).frame.encoded)
            printPacket("automatic-power-off-15-minutes", WL5024Command.setAutoPowerOff(enabled: true, seconds: 900).frame.encoded)
            printPreferencePackets(name: "advanced-transparency", module: 8)
            printPacket("get-sidetone-state", WL5024Command.getPreference(module: 7).frame.encoded)
            printPacket("get-sidetone-level", WL5024Command.getPreference(module: 6).frame.encoded)
            printPacket("disable-sidetone", WL5024Command.setPreferenceByte(module: 7, value: 0).frame.encoded)
            printPacket("enable-sidetone", WL5024Command.setPreferenceByte(module: 7, value: 1).frame.encoded)
            printPacket("set-sidetone-level-5", WL5024Command.setPreferenceUInt16(module: 6, value: 5).frame.encoded)
            printBooleanPackets(
                name: "busy-light",
                getter: .getBusyLight,
                disable: .setBusyLight(false),
                enable: .setBusyLight(true)
            )
            printBooleanPackets(
                name: "voice-guidance",
                getter: .getVoiceGuidance,
                disable: .setVoiceGuidance(false),
                enable: .setVoiceGuidance(true)
            )
            printBooleanPackets(
                name: "incoming-audio-noise-cancellation",
                getter: .getIncomingAudioNoiseCancellation,
                disable: .setIncomingAudioNoiseCancellation(false),
                enable: .setIncomingAudioNoiseCancellation(true)
            )
            printBooleanPackets(
                name: "microphone-noise-cancellation",
                getter: .getMicrophoneNoiseCancellation,
                disable: .setMicrophoneNoiseCancellation(false),
                enable: .setMicrophoneNoiseCancellation(true)
            )
            printBooleanPackets(
                name: "smart-switch",
                getter: .getSmartSwitch,
                disable: .setSmartSwitch(false),
                enable: .setSmartSwitch(true)
            )
            return
        }

        print("WL5024 firmware capability catalog (\(CapabilityCatalog.all.count) settings)")
        for definition in CapabilityCatalog.all {
            print("\(definition.key.rawValue)\t\(definition.qualification.rawValue)\t\(definition.recipe.summary)")
        }
        print("\nUse --packets to print the bounded experimental RACE frames.")
        print("Use --live to query the connected headset directly with read-only commands.")
        print("Use --usb to query the directly connected headset over its vendor HID channel.")
        print("Add --only=smart-switch, --repeat=N, --timeout-ms=N, or --listen-seconds=N to narrow a live run.")
    }

    private static func printPreferencePackets(name: String, module: UInt16) {
        printPacket("get-\(name)", WL5024Command.getPreference(module: module).frame.encoded)
        printPacket("disable-\(name)", WL5024Command.setPreferenceByte(module: module, value: 0).frame.encoded)
        printPacket("enable-\(name)", WL5024Command.setPreferenceByte(module: module, value: 1).frame.encoded)
    }

    private static func printBooleanPackets(
        name: String,
        getter: WL5024Command,
        disable: WL5024Command,
        enable: WL5024Command
    ) {
        printPacket("get-\(name)", getter.frame.encoded)
        printPacket("disable-\(name)", disable.frame.encoded)
        printPacket("enable-\(name)", enable.frame.encoded)
    }

    private static func printPacket(_ name: String, _ data: Data) {
        let value = data.map { String(format: "%02X", $0) }.joined(separator: " ")
        print("\(name): \(value)")
    }
}

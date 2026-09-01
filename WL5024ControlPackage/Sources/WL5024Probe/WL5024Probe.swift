import Foundation
import WL5024ControlFeature

@main
struct WL5024Probe {
    static func main() {
        let arguments = Set(CommandLine.arguments.dropFirst())

        if arguments.contains("--packets") {
            printPacket("get-automatic-media", WL5024Command.getAutomaticMedia.frame.encoded)
            printPacket("disable-automatic-media", WL5024Command.setAutomaticMedia(false).frame.encoded)
            printPacket("enable-automatic-media", WL5024Command.setAutomaticMedia(true).frame.encoded)
            return
        }

        print("WL5024 firmware capability catalog (\(CapabilityCatalog.all.count) settings)")
        for definition in CapabilityCatalog.all {
            print("\(definition.key.rawValue)\t\(definition.qualification.rawValue)\t\(definition.recipe.summary)")
        }
        print("\nUse --packets to print the recovered automatic-media RACE frames.")
    }

    private static func printPacket(_ name: String, _ data: Data) {
        let value = data.map { String(format: "%02X", $0) }.joined(separator: " ")
        print("\(name): \(value)")
    }
}

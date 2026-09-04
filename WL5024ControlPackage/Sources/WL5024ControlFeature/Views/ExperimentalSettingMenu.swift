import SwiftUI

struct ExperimentalSettingMenu: View {
    let key: HeadsetSettingKey
    let apply: (SettingValue) -> Void

    var body: some View {
        Menu("Set Value…") {
            switch key.controlKind {
            case .toggle:
                Button("Turn On") { apply(.boolean(true)) }
                Button("Turn Off") { apply(.boolean(false)) }
            case .choices:
                ForEach(key.choices) { choice in
                    Button {
                        apply(.choice(choice.id))
                    } label: {
                        Text(choice.title)
                    }
                }
            case .level, .text, .action, .readOnlyValue:
                EmptyView()
            }
        }
        .frame(width: DetailLayoutMetrics.pickerWidth, alignment: .trailing)
        .frame(maxWidth: .infinity, alignment: .trailing)
        .accessibilityLabel(key.title)
        .accessibilityHint("Experimental write; the current value has not been read from the headset")
        .accessibilityIdentifier("setting.experimental.\(key.rawValue)")
    }
}

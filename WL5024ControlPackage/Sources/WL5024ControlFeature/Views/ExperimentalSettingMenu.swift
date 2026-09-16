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
        .frame(width: 140, alignment: .trailing)
        // Visible action is "Set Value…"; expose an unambiguous name that
        // does not duplicate the hidden row title (AUD-010).
        .accessibilityLabel("Set value for \(String(localized: key.title))")
        .accessibilityHint("Experimental write; the current value has not been read from the headset")
        .accessibilityIdentifier("setting.experimental.\(key.rawValue)")
    }
}

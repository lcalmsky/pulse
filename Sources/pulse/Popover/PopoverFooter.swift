import AppKit
import PulseCore
import SwiftUI

struct PopoverFooter: View {
    @ObservedObject var model: AppModel
    @ObservedObject var state: PopoverState

    var body: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(PopoverPalette.stroke)
                .frame(height: 1)
            HStack(spacing: 2) {
                Text(updatedText)
                    .font(.system(size: 11))
                    .foregroundColor(PopoverPalette.secondary)
                    .lineLimit(1)

                Spacer(minLength: 4)

                Text("⌃⌥P")
                    .font(.system(size: 11))
                    .foregroundColor(PopoverPalette.secondary)
                    .padding(.trailing, 4)

                PopoverIconButton(
                    symbol: "sidebar.right",
                    help: model.panelVisible ? L10n.hideFloatingWindow : L10n.showFloatingWindow
                ) {
                    model.togglePanel()
                }
                if state.shortcutHintsVisible {
                    ShortcutKeycap(text: L10n.keySettings)
                        .padding(.trailing, 2)
                }
                PopoverIconButton(
                    symbol: "gearshape",
                    help: L10n.viewSettingsShortcut,
                    selected: state.settingsOpen
                ) {
                    state.settingsOpen.toggle()
                }
                PopoverIconButton(symbol: "power", help: L10n.quit) {
                    NSApp.terminate(nil)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
        }
    }

    private var updatedText: String {
        TimePhrase.relative(from: model.lastSuccess, to: Date()).map { L10n.updated($0) } ?? L10n.notUpdatedYet
    }
}

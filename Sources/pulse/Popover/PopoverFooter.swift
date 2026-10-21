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
                    help: model.panelVisible ? "플로팅 창 숨기기" : "플로팅 창 보기"
                ) {
                    model.togglePanel()
                }
                PopoverIconButton(
                    symbol: "gearshape",
                    help: "보기 설정 (⌘,)",
                    selected: state.settingsOpen
                ) {
                    state.settingsOpen.toggle()
                }
                PopoverIconButton(symbol: "power", help: "종료") {
                    NSApp.terminate(nil)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
        }
    }

    private var updatedText: String {
        TimePhrase.relative(from: model.lastSuccess, to: Date()).map { "\($0) 갱신" } ?? "갱신 전"
    }
}

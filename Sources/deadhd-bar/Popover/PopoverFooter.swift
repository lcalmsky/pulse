import AppKit
import DeadhdBarCore
import SwiftUI

struct PopoverFooter: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Color.primary.opacity(0.08))
                .frame(height: 1)
            HStack(spacing: 2) {
                PopoverTextButton(
                    symbol: "checkmark.circle",
                    title: "완료 전부 확인",
                    help: "완료 항목을 모두 확인 처리해요",
                    enabled: !model.groups.done.isEmpty
                ) {
                    model.acknowledgeAllDone()
                }
                PopoverTextButton(
                    symbol: "eye",
                    title: "다시 보기",
                    help: "확인한 완료 \(model.hiddenDoneCount)개를 다시 보여요",
                    enabled: model.hiddenDoneCount > 0
                ) {
                    model.restoreAcknowledgedDone()
                }

                Spacer(minLength: 4)

                HStack(spacing: 3) {
                    KeyHint("↑↓")
                    KeyHint("↩")
                    KeyHint("⌫")
                    KeyHint("⌥")
                }
                .padding(.trailing, 4)

                PopoverIconButton(symbol: "power", help: "종료") {
                    NSApp.terminate(nil)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
    }
}

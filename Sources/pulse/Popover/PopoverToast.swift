import PulseCore
import SwiftUI

struct PopoverToast: View {
    let count: Int
    let onUndo: () -> Void

    @State private var progress: CGFloat = 1

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text(L10n.acknowledgedDone(count))
                    .font(.system(size: 12, weight: .medium))
                Button(L10n.undo, action: onUndo)
                    .font(.system(size: 12, weight: .bold))
                    .buttonStyle(.plain)
                    .foregroundColor(.blue)
                    .contentShape(Rectangle())
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 10)

            GeometryReader { geometry in
                Rectangle()
                    .fill(Color.blue)
                    .frame(width: geometry.size.width * progress, height: 2)
            }
            .frame(height: 2)
            .padding(.horizontal, 8)
            .padding(.bottom, 3)
        }
        .foregroundColor(Color(nsColor: .windowBackgroundColor))
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.primary.opacity(0.92))
        )
        .shadow(color: Color.black.opacity(0.35), radius: 14, y: 6)
        .fixedSize(horizontal: true, vertical: false)
        .onAppear {
            progress = 1
            withAnimation(.linear(duration: UndoToast.duration)) {
                progress = 0
            }
        }
    }
}

struct NoticeToastView: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .medium))
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: 300)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .foregroundColor(Color(nsColor: .windowBackgroundColor))
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.primary.opacity(0.92))
            )
            .shadow(color: Color.black.opacity(0.35), radius: 14, y: 6)
    }
}

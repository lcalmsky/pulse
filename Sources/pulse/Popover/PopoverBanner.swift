import SwiftUI

enum PopoverBannerStyle {
    case error
    case muted
}

struct PopoverBanner: View {
    let style: PopoverBannerStyle
    let message: String
    let retry: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            if style == .error {
                Text("!")
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundColor(.red)
            }
            Text(message)
                .font(.system(size: 12))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button("지금 재시도", action: retry)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(style == .error ? .red : .blue)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(background)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(border, lineWidth: 1)
        )
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    private var background: Color {
        style == .error ? Color.red.opacity(0.14) : Color.primary.opacity(0.05)
    }

    private var border: Color {
        style == .error ? Color.red.opacity(0.35) : Color.primary.opacity(0.10)
    }
}

struct PopoverEmptyState: View {
    var body: some View {
        VStack(spacing: 14) {
            EmptyOrb()
            VStack(spacing: 4) {
                Text("할 일이 비었어요")
                    .font(.system(size: 15, weight: .semibold))
                Text("새 세션이 시작되면 바로 알려 드릴게요.")
                    .font(.system(size: 12))
                    .foregroundColor(PopoverPalette.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 36)
        .padding(.bottom, 40)
    }
}

private struct EmptyOrb: View {
    // 스피너와 같은 이유로 무한 반복 애니메이션 대신 시각에서 각도를 계산한다.
    var body: some View {
        TimelineView(.animation) { context in
            let angle = context.date.timeIntervalSinceReferenceDate
                .truncatingRemainder(dividingBy: 8) / 8 * 360
            ZStack {
                Circle()
                    .fill(
                        AngularGradient(
                            gradient: Gradient(colors: [.green, .blue, .purple, .green]),
                            center: .center
                        )
                    )
                    .rotationEffect(.degrees(angle))
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color.white.opacity(0.35), .clear],
                            center: UnitPoint(x: 0.35, y: 0.3),
                            startRadius: 0,
                            endRadius: 42
                        )
                    )
            }
        }
        .frame(width: 84, height: 84)
        .clipShape(Circle())
        .shadow(color: Color.blue.opacity(0.35), radius: 18, y: 8)
    }
}

import AppKit
import PulseCore

enum MenuBarIcon {
    static let size: CGFloat = 22

    /// 메뉴 막대 외형은 앱 테마와 별개다. 색은 상태 버튼의 외형으로 풀어야 한다.
    static func image(
        counts: GroupedSessions.Counts,
        unavailable: Bool,
        appearance: NSAppearance
    ) -> NSImage {
        let scale: CGFloat = 4
        let image = NSImage(
            size: NSSize(width: size * scale, height: size * scale),
            flipped: false
        ) { _ in
            appearance.performAsCurrentDrawingAppearance {
                NSGraphicsContext.current?.cgContext.scaleBy(x: scale, y: scale)
                draw(counts: counts, unavailable: unavailable)
            }
            return true
        }
        image.size = NSSize(width: size, height: size)
        // 상태별 색 조각을 살려야 해서 템플릿으로 두지 않는다.
        image.isTemplate = false
        return image
    }

    private static func draw(counts: GroupedSessions.Counts, unavailable: Bool) {
        let center = NSPoint(x: size / 2, y: size / 2)
        let radius: CGFloat = 8.8

        if unavailable {
            let glyph = NSBezierPath()
            glyph.appendArc(withCenter: center, radius: radius, startAngle: 0, endAngle: 360)
            glyph.lineWidth = 1.7
            NSColor.labelColor.setStroke()
            glyph.stroke()
            drawWave(center: center, radius: radius, color: NSColor.labelColor.withAlphaComponent(0.45))
            return
        }

        let track = NSBezierPath()
        track.appendArc(withCenter: center, radius: radius, startAngle: 0, endAngle: 360)
        track.lineWidth = 2.8
        NSColor.labelColor.withAlphaComponent(0.18).setStroke()
        track.stroke()

        let ratio = SegmentRatio.make(
            attention: counts.attention,
            working: counts.working,
            done: counts.done
        )
        let segments: [(Double, NSColor)] = [
            (ratio.attention, .systemOrange),
            (ratio.working, .systemBlue),
            (ratio.done, .systemGreen),
        ]
        let circumference = 2 * CGFloat.pi * radius
        var offset = 0.0
        for (fraction, color) in segments where fraction > 0 {
            let length = circumference * CGFloat(fraction)
            let drawn = max(length - 1.6, 0.1)
            let arc = NSBezierPath()
            arc.appendArc(
                withCenter: center,
                radius: radius,
                startAngle: 90 - offset * 360,
                endAngle: 90 - (offset + Double(drawn / circumference)) * 360,
                clockwise: true
            )
            arc.lineWidth = 2.8
            arc.lineCapStyle = .round
            color.setStroke()
            arc.stroke()
            offset += fraction
        }

        drawWave(center: center, radius: radius, color: .labelColor)
    }

    private static func drawWave(center: NSPoint, radius: CGFloat, color: NSColor) {
        let path = NSBezierPath()
        for (index, point) in PulseGlyph.wave.enumerated() {
            let target = NSPoint(x: center.x + point.x * radius, y: center.y + point.y * radius)
            if index == 0 { path.move(to: target) } else { path.line(to: target) }
        }
        path.lineWidth = 1.7
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        color.setStroke()
        path.stroke()
    }

    static func title(counts: GroupedSessions.Counts, unavailable: Bool) -> NSAttributedString {
        if unavailable {
            return NSAttributedString(
                string: "읽기 실패",
                attributes: [
                    .font: NSFont.systemFont(ofSize: 11, weight: .medium),
                    .foregroundColor: NSColor.tertiaryLabelColor,
                ]
            )
        }

        let number: Int?
        let color: NSColor
        switch MenuBarCounter.make(attention: counts.attention, working: counts.working) {
        case let .attention(count):
            number = count
            color = .systemOrange
        case let .working(count):
            number = count
            color = .secondaryLabelColor
        case .none:
            number = nil
            color = .secondaryLabelColor
        }
        guard let number else { return NSAttributedString(string: "") }
        return NSAttributedString(
            string: "\(number)",
            attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium),
                .foregroundColor: color,
            ]
        )
    }
}

import PulseCore
import SwiftUI

/// 알림 카드 패널. 카드가 하나면 그 카드가 곧 패널이고, 둘 이상이면 머리글 아래에 쌓는다.
struct CardPanelView: View {
    @ObservedObject var model: AppModel
    var onContentHeightChange: (() -> Void)?

    @State private var naturalHeight: CGFloat = 0

    var body: some View {
        content
            .frame(width: 340)
            .coordinateSpace(name: "cardPanel")
            .background(PopoverBackground())
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(key: CardHeightKey.self, value: proxy.size.height)
                }
            )
            .onPreferenceChange(CardHeightKey.self) { height in
                guard abs(height - naturalHeight) > 0.5 else { return }
                naturalHeight = height
                onContentHeightChange?()
            }
    }

    @ViewBuilder
    private var content: some View {
        let away = model.cards.filter { $0.kind == .away }
        let shown = model.cards.compactMap { card -> ShownCard? in
            guard card.kind != .away, let item = liveItem(for: card) else { return nil }
            return ShownCard(card: card, item: item)
        }
        if away.isEmpty, shown.count == 1, let entry = shown.first {
            SingleCard(card: entry.card, item: entry.item, model: model)
        } else if away.count == 1, shown.isEmpty, let card = away.first {
            AwayCard(card: card, model: model, stacked: false)
        } else if !away.isEmpty || !shown.isEmpty {
            VStack(spacing: 0) {
                header
                ForEach(away) { card in
                    AwayCard(card: card, model: model, stacked: true)
                        .padding(.horizontal, 6)
                        .padding(.bottom, 4)
                }
                ForEach(shown) { entry in
                    switch entry.card.kind {
                    case .attention:
                        AttentionCardRow(card: entry.card, item: entry.item, model: model)
                            .padding(.horizontal, 6)
                            .padding(.bottom, 4)
                    case .done:
                        DoneCardRow(card: entry.card, item: entry.item, model: model)
                            .padding(.horizontal, 6)
                    case .away:
                        EmptyView()
                    }
                }
            }
            .padding(.top, 6)
            .padding(.bottom, 4)
        } else {
            Color.clear.frame(width: 340, height: 0)
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            CardGlyph(
                size: 16,
                ring: .segments(SegmentRatio.make(
                    attention: model.groups.counts.attention,
                    working: model.groups.counts.working,
                    done: model.groups.counts.done
                ))
            )
            Text("Pulse")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(PopoverPalette.text)
            Spacer(minLength: 0)
            if let text = CardDeck.headerText(
                attention: model.cards.filter { $0.kind == .attention }.count,
                done: model.cards.filter { $0.kind == .done }.count
            ) {
                Text(text)
                    .font(.system(size: 11))
                    .foregroundColor(PopoverPalette.secondary)
            }
            Button(L10n.acknowledgeAll) { model.acknowledgeAllCards() }
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(PopoverPalette.link)
                .buttonStyle(.borderless)
                .padding(.horizontal, 2)
        }
        .padding(.top, 6)
        .padding(.bottom, 8)
        .padding(.leading, 14)
        .padding(.trailing, 10)
    }

    private func liveItem(for card: NotificationCard) -> DisplayItem? {
        let items = card.kind == .attention ? model.groups.attention : model.groups.done
        return items.first { $0.sessionId == card.sessionId }
    }
}

/// 비활성 앱 창에서는 SwiftUI `onHover` 가 불리지 않아 호스팅 뷰의 추적 영역 위치로 호버를 판정한다.
final class CardPointer: ObservableObject {
    @Published private(set) var location: CGPoint?

    func move(to point: CGPoint?) {
        guard point != location else { return }
        location = point
    }
}

private struct ShownCard: Identifiable {
    let card: NotificationCard
    let item: DisplayItem

    var id: String { card.sessionId }
}

private struct SingleCard: View {
    let card: NotificationCard
    let item: DisplayItem
    @ObservedObject var model: AppModel

    @State private var hovering = false

    var body: some View {
        switch card.kind {
        case .attention: attention
        case .done: done
        case .away: EmptyView()
        }
    }

    private var attention: some View {
        HStack(spacing: 10) {
            CardGlyph(size: 32, ring: .solid(PopoverPalette.attention))
            VStack(alignment: .leading, spacing: 1) {
                Text(CardPanelText.question(item))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(PopoverPalette.text)
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    if let kind = item.multiplexer?.kind.rawValue {
                        MultiplexerBadge(kind: kind)
                    }
                    attentionMeta
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            Spacer(minLength: 0)
            if hovering && item.isStall {
                CardButtons(item: item, model: model, showsSnooze: true, showsAnswer: false, showsOpen: false, showsAcknowledge: false)
            }
            answerButton
        }
        .padding(.top, 10)
        .padding(.bottom, 10)
        .padding(.leading, 10)
        .padding(.trailing, 10)
        .contentShape(Rectangle())
        .cardHover($hovering)
        .onTapGesture {
            guard item.isActionable else { return }
            model.openCard(item)
        }
    }

    private var attentionMeta: Text {
        var meta = Text("")
        if let place = item.placeText?.trimmingCharacters(in: .whitespacesAndNewlines), !place.isEmpty {
            meta = meta + Text("\(place) · ")
                .font(.system(size: 11))
                .foregroundColor(PopoverPalette.secondary)
        }
        meta = meta + Text(L10n.groupAttention)
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(PopoverPalette.attention)
        if let elapsed = TimePhrase.soFar(from: item.sortDate, to: Date()) {
            meta = meta + Text(" · \(elapsed)")
                .font(.system(size: 11))
                .foregroundColor(PopoverPalette.secondary)
        }
        return meta
    }

    private var answerButton: some View {
        Button {
            if canAnswer(item) {
                model.answerCard(item)
            } else {
                model.openCard(item)
            }
        } label: {
            Text(canAnswer(item) ? L10n.reply : L10n.open)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(Color.black.opacity(0.85))
                .padding(.horizontal, 11)
                .frame(height: 24)
                .background(Capsule().fill(PopoverPalette.attention))
        }
        .buttonStyle(.plain)
        .disabled(!item.isActionable)
    }

    private var done: some View {
        HStack(spacing: 10) {
            RemainingRing(card: card, paused: model.cardsPaused)
            VStack(alignment: .leading, spacing: 1) {
                Text(CardText.doneSummary(summary: item.summary, status: item.status))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(PopoverPalette.text)
                    .lineLimit(1)
                    .truncationMode(.tail)
                HStack(spacing: 6) {
                    if let kind = item.multiplexer?.kind.rawValue {
                        MultiplexerBadge(kind: kind)
                    }
                    Text(CardText.doneMeta(title: item.title, runDuration: card.runDuration))
                        .font(.system(size: 11))
                        .foregroundColor(PopoverPalette.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            Spacer(minLength: 0)
            if hovering {
                CardButtons(item: item, model: model, showsSnooze: false, showsAnswer: false, showsOpen: true, showsAcknowledge: true)
            }
        }
        .padding(.top, 10)
        .padding(.bottom, 10)
        .padding(.leading, 10)
        .padding(.trailing, hovering ? 10 : 12)
        .contentShape(Rectangle())
        .cardHover($hovering)
        .onTapGesture {
            guard item.isActionable else { return }
            model.openCard(item)
        }
    }
}

private struct AttentionCardRow: View {
    let card: NotificationCard
    let item: DisplayItem
    @ObservedObject var model: AppModel

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(PopoverPalette.attention)
                .frame(width: 8, height: 8)
                .padding(.top, 5)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    if let kind = item.multiplexer?.kind.rawValue {
                        MultiplexerBadge(kind: kind)
                    }
                    Text(item.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(PopoverPalette.text)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 0)
                    if let waiting = RowText.waiting(since: item.sortDate, now: Date()) {
                        Text(waiting)
                            .font(.system(size: 11))
                            .foregroundColor(PopoverPalette.attention)
                            .fixedSize()
                    }
                }
                Text(CardPanelText.question(item))
                    .font(.system(size: 12.5))
                    .foregroundColor(PopoverPalette.text)
                    .lineSpacing(3)
                    .lineLimit(6)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            CardButtons(item: item, model: model, showsSnooze: true, showsAnswer: true, showsOpen: false, showsAcknowledge: false)
                .frame(maxHeight: .infinity, alignment: .center)
        }
        .padding(.top, 9)
        .padding(.bottom, 9)
        .padding(.leading, 12)
        .padding(.trailing, 8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(PopoverPalette.attention.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(PopoverPalette.attention.opacity(0.30), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            guard item.isActionable else { return }
            model.openCard(item)
        }
    }
}

private struct DoneCardRow: View {
    let card: NotificationCard
    let item: DisplayItem
    @ObservedObject var model: AppModel

    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            RemainingRing(card: card, paused: model.cardsPaused, size: 22)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    if let kind = item.multiplexer?.kind.rawValue {
                        MultiplexerBadge(kind: kind)
                    }
                    Text(item.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(PopoverPalette.text)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if let trail = CardText.doneTrail(
                        runDuration: card.runDuration,
                        finishedAt: item.sortDate,
                        now: Date()
                    ) {
                        Text(trail)
                            .font(.system(size: 11))
                            .foregroundColor(PopoverPalette.tertiary)
                            .fixedSize()
                    }
                }
                Text(CardText.doneSummary(summary: item.summary, status: item.status))
                    .font(.system(size: 12))
                    .foregroundColor(PopoverPalette.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer(minLength: 0)
            if hovering {
                CardButtons(item: item, model: model, showsSnooze: false, showsAnswer: false, showsOpen: true, showsAcknowledge: true)
            } else if let time = TimePhrase.relative(from: item.sortDate, to: Date()) {
                Text(time)
                    .font(.system(size: 11))
                    .foregroundColor(PopoverPalette.tertiary)
                    .fixedSize()
            }
        }
        .frame(height: 48)
        .padding(.leading, 12)
        .padding(.trailing, 8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(hovering ? PopoverPalette.rowHover : Color.clear)
        )
        .contentShape(Rectangle())
        .cardHover($hovering)
        .onTapGesture {
            guard item.isActionable else { return }
            model.openCard(item)
        }
    }
}

/// 목록 항목이 없어 다른 카드 뷰와 달리 `liveItem` 없이 그리는 자리 비움 요약 카드.
private struct AwayCard: View {
    let card: NotificationCard
    @ObservedObject var model: AppModel
    let stacked: Bool

    @State private var hovering = false

    var body: some View {
        if stacked {
            stackedBody
        } else {
            singleBody
        }
    }

    private var singleBody: some View {
        HStack(spacing: 10) {
            if card.expires {
                RemainingRing(card: card, paused: model.cardsPaused)
            } else {
                CardGlyph(size: 32, ring: .solid(PopoverPalette.attention))
            }
            text(metaSize: 11, spacing: 1)
            Spacer(minLength: 0)
        }
        .padding(.top, 10)
        .padding(.bottom, 10)
        .padding(.leading, 10)
        .padding(.trailing, 10)
        .contentShape(Rectangle())
        .onTapGesture { model.openAwaySummary() }
    }

    private var stackedBody: some View {
        Group {
            if card.expires {
                HStack(spacing: 10) {
                    RemainingRing(card: card, paused: model.cardsPaused, size: 22)
                    text(metaSize: 12, spacing: 1)
                    Spacer(minLength: 0)
                }
                .frame(height: 48)
                .padding(.leading, 12)
                .padding(.trailing, 8)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(hovering ? PopoverPalette.rowHover : Color.clear)
                )
            } else {
                HStack(alignment: .top, spacing: 10) {
                    Circle()
                        .fill(PopoverPalette.attention)
                        .frame(width: 8, height: 8)
                        .padding(.top, 5)
                    text(metaSize: 12, spacing: 3)
                    Spacer(minLength: 0)
                }
                .padding(.top, 9)
                .padding(.bottom, 9)
                .padding(.leading, 12)
                .padding(.trailing, 8)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(PopoverPalette.attention.opacity(0.12))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(PopoverPalette.attention.opacity(0.30), lineWidth: 1)
                )
            }
        }
        .contentShape(Rectangle())
        .cardHover($hovering)
        .onTapGesture { model.openAwaySummary() }
    }

    private func text(metaSize: CGFloat, spacing: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: spacing) {
            Text(CardText.awayHeadline(attention: card.awayAttention, done: card.awayDone))
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(PopoverPalette.text)
                .lineLimit(1)
                .truncationMode(.tail)
            Text(CardText.awayMeta(attention: card.awayAttention, done: card.awayDone))
                .font(.system(size: metaSize))
                .foregroundColor(PopoverPalette.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }
}

private struct CardButtons: View {
    let item: DisplayItem
    @ObservedObject var model: AppModel
    let showsSnooze: Bool
    let showsAnswer: Bool
    let showsOpen: Bool
    let showsAcknowledge: Bool

    var body: some View {
        HStack(spacing: 4) {
            if showsSnooze {
                PopoverIconButton(
                    symbol: "clock",
                    help: item.isStall ? L10n.waitTenMoreMinutes : L10n.cannotSnoozeQuestion,
                    enabled: item.isStall,
                    symbolSize: 13,
                    restingFill: PopoverPalette.rowHover,
                    restingGlyph: PopoverPalette.text
                ) {
                    model.snoozeCard(item)
                }
            }
            if showsOpen {
                PopoverIconButton(
                    symbol: "arrow.up.forward.square",
                    help: item.multiplexer.map { L10n.multiplexerMove($0.kind.rawValue) } ?? L10n.openInOrca,
                    enabled: item.isActionable,
                    symbolSize: 13,
                    restingFill: PopoverPalette.rowHover,
                    restingGlyph: PopoverPalette.text
                ) {
                    model.openCard(item)
                }
            }
            if showsAcknowledge {
                PopoverIconButton(
                    symbol: "checkmark",
                    help: L10n.acknowledge,
                    symbolSize: 13,
                    restingFill: PopoverPalette.rowHover,
                    restingGlyph: PopoverPalette.text
                ) {
                    model.acknowledgeCard(item)
                }
            }
            if showsAnswer {
                PopoverIconButton(
                    symbol: "arrowshape.turn.up.left",
                    help: item.multiplexer.map { L10n.multiplexerMove($0.kind.rawValue) } ?? L10n.replyInOrca,
                    enabled: canAnswer(item),
                    symbolSize: 13,
                    restingFill: PopoverPalette.attention,
                    restingGlyph: Color.black.opacity(0.85)
                ) {
                    model.answerCard(item)
                }
            }
        }
    }
}

/// Orca 나 멀티플렉서 패널로 답할 수 있는 항목인지. 답하기 버튼과 캡슐 버튼이 같은 기준을 쓴다.
private func canAnswer(_ item: DisplayItem) -> Bool {
    item.orcaTerminal != nil || item.cwd != nil || item.multiplexer != nil
}

/// 남은 시간 링 글리프.
private struct RemainingRing: View {
    let card: NotificationCard
    let paused: Bool
    var size: CGFloat = 32

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: paused)) { context in
            CardGlyph(
                size: size,
                ring: .remaining(CardDeck.remainingFraction(of: card, paused: paused, now: context.date))
            )
        }
    }
}

/// 메뉴 막대 아이콘(MenuBarIcon)과 같은 비율의 링과 파형.
private struct CardGlyph: View {
    enum Ring {
        case remaining(Double)
        case solid(Color)
        case segments(SegmentRatio)
    }

    let size: CGFloat
    let ring: Ring

    var body: some View {
        let radius = size * 8.8 / 22
        let line = size * 2.8 / 22
        ZStack {
            Circle()
                .stroke(PopoverPalette.text.opacity(0.18), lineWidth: line)
                .frame(width: radius * 2, height: radius * 2)
            ringLayer(radius: radius, line: line)
            CardWave()
                .stroke(
                    PopoverPalette.text,
                    style: StrokeStyle(lineWidth: size * 1.7 / 22, lineCap: .round, lineJoin: .round)
                )
                .frame(width: radius * 2, height: radius * 2)
        }
        .frame(width: size, height: size)
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func ringLayer(radius: CGFloat, line: CGFloat) -> some View {
        switch ring {
        case let .remaining(fraction):
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(PopoverPalette.done, style: StrokeStyle(lineWidth: line, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: radius * 2, height: radius * 2)
        case let .solid(color):
            Circle()
                .stroke(color, lineWidth: line)
                .frame(width: radius * 2, height: radius * 2)
        case let .segments(ratio):
            SegmentRing(ratio: ratio, radius: radius, line: line)
        }
    }
}

private struct SegmentRing: View {
    let ratio: SegmentRatio
    let radius: CGFloat
    let line: CGFloat

    private static let unit = 1 / (2 * Double.pi * 8.8)

    var body: some View {
        ZStack {
            ForEach(arcs.indices, id: \.self) { index in
                Circle()
                    .trim(from: arcs[index].start, to: arcs[index].end)
                    .stroke(arcs[index].color, style: StrokeStyle(lineWidth: line, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: radius * 2, height: radius * 2)
            }
        }
    }

    private var arcs: [(start: Double, end: Double, color: Color)] {
        let pieces: [(Double, Color)] = [
            (ratio.attention, PopoverPalette.attention),
            (ratio.working, PopoverPalette.working),
            (ratio.done, PopoverPalette.done),
        ]
        var offset = 0.0
        var result: [(start: Double, end: Double, color: Color)] = []
        for (fraction, color) in pieces where fraction > 0 {
            let drawn = max(fraction - 1.6 * Self.unit, 0.1 * Self.unit)
            result.append((offset, offset + drawn, color))
            offset += fraction
        }
        return result
    }
}

private struct CardWave: Shape {
    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        var path = Path()
        for (index, point) in PulseGlyph.wave.enumerated() {
            let target = CGPoint(x: center.x + point.x * radius, y: center.y - point.y * radius)
            if index == 0 { path.move(to: target) } else { path.addLine(to: target) }
        }
        return path
    }
}

private enum CardPanelText {
    static func question(_ item: DisplayItem) -> String {
        "“\(RowText.question(detail: item.detail, replyTail: item.replyTail, status: item.status, isStall: item.isStall))”"
    }
}

private struct CardHover: ViewModifier {
    @EnvironmentObject private var pointer: CardPointer
    @Binding var hovering: Bool

    func body(content: Content) -> some View {
        content.background(
            GeometryReader { proxy in
                let frame = proxy.frame(in: .named("cardPanel"))
                Color.clear
                    .allowsHitTesting(false)
                    .onAppear { update(frame: frame) }
                    .onChange(of: frame) { newFrame in update(frame: newFrame) }
                    .onChange(of: pointer.location) { _ in update(frame: frame) }
            }
        )
    }

    private func update(frame: CGRect) {
        let inside = pointer.location.map(frame.contains) ?? false
        guard inside != hovering else { return }
        hovering = inside
    }
}

private extension View {
    func cardHover(_ hovering: Binding<Bool>) -> some View {
        modifier(CardHover(hovering: hovering))
    }
}

private struct CardHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

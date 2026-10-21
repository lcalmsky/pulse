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
            PulseMark(size: 16)
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
            Button("모두 확인") { model.acknowledgeAllCards() }
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
            PulseMark(size: 24, badge: true, circular: true)
                .frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 1) {
                Text(CardPanelText.question(item))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(PopoverPalette.text)
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .fixedSize(horizontal: false, vertical: true)
                attentionMeta
                    .lineLimit(1)
                    .truncationMode(.tail)
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
        .onHover { hovering = $0 }
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
        meta = meta + Text("확인 필요")
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(PopoverPalette.attention)
        if let elapsed = TimePhrase.duration(from: item.sortDate, to: Date()) {
            meta = meta + Text(" · \(elapsed)째")
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
            Text(canAnswer(item) ? "답하기" : "열기")
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
                Text(CardText.doneMeta(title: item.title, runDuration: card.runDuration))
                    .font(.system(size: 11))
                    .foregroundColor(PopoverPalette.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
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
        .onHover { hovering = $0 }
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
        .onHover { hovering = $0 }
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
                PulseMark(size: 24, badge: true, circular: true)
                    .frame(width: 32, height: 32)
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
        .onHover { hovering = $0 }
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
                    help: item.isStall ? "10분 더 기다리기" : "질문·권한 대기는 미룰 수 없어요",
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
                    help: "Orca 에서 열기",
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
                    help: "확인",
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
                    help: "답하기 · Orca 에서 터미널 열기",
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

/// Orca 로 답할 수 있는 항목인지. 답하기 버튼과 캡슐 버튼이 같은 기준을 쓴다.
private func canAnswer(_ item: DisplayItem) -> Bool {
    item.orcaTerminal != nil || item.cwd != nil
}

/// 아이콘을 두른 남은 시간 링.
private struct RemainingRing: View {
    let card: NotificationCard
    let paused: Bool
    var size: CGFloat = 32

    @State private var fraction: Double = 1

    var body: some View {
        ZStack {
            Circle().strokeBorder(PopoverPalette.stroke, lineWidth: 2)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(PopoverPalette.done, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .padding(1)
            PulseMark(size: size - 8, circular: true)
        }
        .frame(width: size, height: size)
        .allowsHitTesting(false)
        .onAppear { sync() }
        .onChange(of: paused) { _ in sync() }
    }

    private func sync() {
        let current = frozenFraction()
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { fraction = current }
        guard !paused else { return }
        let remaining = current * CardDeck.doneLifetime
        guard remaining > 0 else { return }
        // 무한 반복 없이 한 번만 줄인다. 창 높이는 건드리지 않는다.
        withAnimation(.linear(duration: remaining)) { fraction = 0 }
    }

    private func frozenFraction() -> Double {
        CardDeck.remainingFraction(of: card, paused: paused, now: Date())
    }
}

struct PulseMark: View {
    let size: CGFloat
    var badge: Bool = false
    var circular: Bool = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if circular {
                    Circle().fill(PopoverPalette.working)
                } else {
                    RoundedRectangle(cornerRadius: size * 9 / 40).fill(PopoverPalette.working)
                }
            }
            .frame(width: size, height: size)
            PulseLine()
                .stroke(
                    Color.white,
                    style: StrokeStyle(
                        lineWidth: size * 3 / 40,
                        lineCap: .round,
                        lineJoin: .round
                    )
                )
                .frame(width: size, height: size)
            if badge {
                Circle()
                    .fill(PopoverPalette.attention)
                    .frame(width: 7, height: 7)
                    .overlay(Circle().strokeBorder(PopoverPalette.glassSolid, lineWidth: 1.5))
                    .offset(x: circular ? 1 : 2, y: circular ? -1 : -2)
            }
        }
        .frame(width: size, height: size)
    }
}

private struct PulseLine: Shape {
    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width, rect.height) / 40
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * scale, y: rect.minY + y * scale)
        }
        var path = Path()
        path.move(to: point(8, 21))
        path.addLine(to: point(14, 21))
        path.addLine(to: point(17, 13))
        path.addLine(to: point(21, 28))
        path.addLine(to: point(25, 17))
        path.addLine(to: point(27, 21))
        path.addLine(to: point(32, 21))
        return path
    }
}

private enum CardPanelText {
    static func question(_ item: DisplayItem) -> String {
        "“\(RowText.question(detail: item.detail, replyTail: item.replyTail, status: item.status))”"
    }
}

private struct CardHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

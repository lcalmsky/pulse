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
        let shown = model.cards.compactMap { card -> ShownCard? in
            guard let item = liveItem(for: card) else { return nil }
            return ShownCard(card: card, item: item)
        }
        if shown.count == 1, let entry = shown.first {
            SingleCard(card: entry.card, item: entry.item, model: model)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(
                            entry.card.kind == .attention
                                ? PopoverPalette.attention.opacity(0.40)
                                : PopoverPalette.stroke,
                            lineWidth: 1
                        )
                )
        } else if !shown.isEmpty {
            VStack(spacing: 0) {
                header
                ForEach(shown) { entry in
                    switch entry.card.kind {
                    case .attention:
                        AttentionCardRow(card: entry.card, item: entry.item, model: model)
                            .padding(.horizontal, 6)
                            .padding(.bottom, 4)
                    case .done:
                        DoneCardRow(card: entry.card, item: entry.item, model: model)
                            .padding(.horizontal, 6)
                    }
                }
            }
            .padding(.top, 6)
            .padding(.bottom, 4)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(PopoverPalette.stroke, lineWidth: 1)
            )
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

    var body: some View {
        switch card.kind {
        case .attention: attention
        case .done: done
        }
    }

    private var attention: some View {
        HStack(alignment: .top, spacing: 10) {
            PulseMark(size: 22, badge: true)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(item.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(PopoverPalette.text)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Text("확인 필요")
                        .font(.system(size: 11))
                        .foregroundColor(PopoverPalette.attention)
                        .fixedSize()
                }
                Text(CardPanelText.question(item))
                    .font(.system(size: 12.5))
                    .foregroundColor(PopoverPalette.text)
                    .lineSpacing(3)
                    .lineLimit(6)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 6) {
                    if let meta = CardText.attentionMeta(place: item.placeText, since: item.sortDate, now: Date()) {
                        Text(meta)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(PopoverPalette.tertiary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    Spacer(minLength: 0)
                    CardButtons(item: item, model: model, showsSnooze: true, showsAnswer: true, showsOpen: true, showsAcknowledge: false)
                }
                .padding(.top, 4)
            }
        }
        .padding(.top, 10)
        .padding(.bottom, 10)
        .padding(.leading, 14)
        .padding(.trailing, 10)
        .contentShape(Rectangle())
        .onTapGesture {
            guard item.isActionable else { return }
            model.openCard(item)
        }
    }

    private var done: some View {
        HStack(spacing: 10) {
            PulseMark(size: 22)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(item.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(PopoverPalette.text)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Text(CardText.doneBanner(runDuration: card.runDuration))
                        .font(.system(size: 11))
                        .foregroundColor(PopoverPalette.done)
                        .fixedSize()
                }
                Text(CardText.doneSummary(summary: item.summary, status: item.status))
                    .font(.system(size: 12))
                    .foregroundColor(PopoverPalette.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer(minLength: 0)
            CardButtons(item: item, model: model, showsSnooze: false, showsAnswer: false, showsOpen: true, showsAcknowledge: false)
        }
        .frame(height: 56)
        .padding(.leading, 14)
        .padding(.trailing, 10)
        .overlay(alignment: .bottomLeading) {
            RemainingBar(card: card, paused: model.cardsPaused)
        }
        .contentShape(Rectangle())
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
            Image(systemName: "checkmark")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(PopoverPalette.done)
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
        .overlay(alignment: .bottomLeading) {
            RemainingBar(card: card, paused: model.cardsPaused)
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture {
            guard item.isActionable else { return }
            model.openCard(item)
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

    private var showsOrca: Bool { item.orcaTerminal != nil || item.cwd != nil }

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
                    enabled: showsOrca,
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

/// 카드 아래 2px 남은 시간 선. 레이아웃 높이에 끼어들지 않도록 overlay 로만 그린다.
private struct RemainingBar: View {
    let card: NotificationCard
    let paused: Bool

    @State private var fraction: Double = 1

    var body: some View {
        GeometryReader { proxy in
            Rectangle()
                .fill(PopoverPalette.done.opacity(0.7))
                .frame(width: max(0, proxy.size.width * fraction), height: 2)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        }
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

    var body: some View {
        ZStack(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: size * 9 / 40)
                .fill(PopoverPalette.working)
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
                    .offset(x: 2, y: -2)
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

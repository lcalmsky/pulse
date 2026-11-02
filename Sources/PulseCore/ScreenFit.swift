import CoreGraphics

/// 창을 화면 안으로 맞추는 계산. 화면 구성이 바뀐 뒤 저장된 프레임이 지금 화면에 들어가는지 판정하는 데 쓴다.
public enum ScreenFit {
    /// 노치 오른쪽 영역에서 기준점을 띄울 거리.
    public static let notchOffset: CGFloat = 12

    /// 창이 놓인 화면을 고른다. 겹치는 화면이 없으면 창 중심에서 가장 가까운 화면을 고른다.
    public static func screenIndex(for frame: CGRect, screens: [CGRect]) -> Int? {
        guard !screens.isEmpty else { return nil }
        var best: (index: Int, area: CGFloat)?
        for (index, screen) in screens.enumerated() {
            let overlap = frame.intersection(screen)
            guard !overlap.isNull else { continue }
            let area = overlap.width * overlap.height
            guard area > 0 else { continue }
            if best == nil || area > best!.area {
                best = (index, area)
            }
        }
        if let best { return best.index }

        let center = CGPoint(x: frame.midX, y: frame.midY)
        var nearest: (index: Int, distance: CGFloat)?
        for (index, screen) in screens.enumerated() {
            let dx = screen.midX - center.x
            let dy = screen.midY - center.y
            let distance = dx * dx + dy * dy
            if nearest == nil || distance < nearest!.distance {
                nearest = (index, distance)
            }
        }
        return nearest?.index
    }

    /// 폭·높이를 화면 안으로 줄이고, 창 전체가 화면 안에 들어오도록 origin 을 옮긴다.
    /// 화면보다 큰 minimumSize 는 화면 크기까지만 지킨다.
    public static func fit(frame: CGRect, into visible: CGRect, minimumSize: CGSize) -> CGRect {
        var result = frame
        result.size = CGSize(
            width: min(visible.width, max(frame.width, minimumSize.width)),
            height: min(visible.height, max(frame.height, minimumSize.height))
        )
        if result.maxX > visible.maxX { result.origin.x = visible.maxX - result.width }
        if result.minX < visible.minX { result.origin.x = visible.minX }
        if result.maxY > visible.maxY { result.origin.y = visible.maxY - result.height }
        if result.minY < visible.minY { result.origin.y = visible.minY }
        return result
    }

    /// 버튼 가로 중심이 노치 구간에 있으면 팝오버 기준 x 를, 아니면 nil 을 돌려준다.
    /// 노치 구간은 왼쪽 보조 영역과 오른쪽 보조 영역 사이로, 두 영역이 모두 있어야 노치가 있다.
    public static func notchAnchorX(
        buttonMidX: CGFloat,
        leftArea: CGRect?,
        rightArea: CGRect?,
        offset: CGFloat = ScreenFit.notchOffset
    ) -> CGFloat? {
        guard let leftArea, let rightArea else { return nil }
        guard buttonMidX >= leftArea.maxX, buttonMidX <= rightArea.minX else { return nil }
        return rightArea.minX + offset
    }
}

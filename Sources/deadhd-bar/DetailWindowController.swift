import AppKit
import DeadhdBarCore
import WebKit

final class DetailWindowController: NSObject, DetailPresenting, WKScriptMessageHandler, WKNavigationDelegate {
    private struct ViewMode {
        let id: String
        let label: String
        let elementID: String
    }

    private static let modes = [
        ViewMode(id: "full", label: "원본", elementID: "v-full"),
        ViewMode(id: "a", label: "스트립", elementID: "v-a"),
        ViewMode(id: "b", label: "타임라인", elementID: "v-b"),
        ViewMode(id: "c", label: "타일", elementID: "v-c"),
    ]
    private static let modeKey = "detailViewMode"
    private static let frameName = "deadhdDetailWindow"
    private static let messageName = "deadhdView"

    private let model: AppModel
    private let defaults = UserDefaults.standard
    private var window: NSWindow?
    private let webView: WKWebView
    private let titleLabel = NSTextField(labelWithString: "")
    private lazy var modeControl = NSSegmentedControl(
        labels: Self.modes.map(\.label),
        trackingMode: .selectOne,
        target: self,
        action: #selector(modeChanged(_:))
    )
    private lazy var orcaButton = NSButton(
        title: "Orca 로 이동",
        target: self,
        action: #selector(openInOrca)
    )
    private lazy var browserButton = NSButton(
        title: "브라우저로 열기",
        target: self,
        action: #selector(openInBrowser)
    )
    private var currentItem: DisplayItem?
    private var loadedHref: String?

    init(model: AppModel) {
        self.model = model
        let controller = WKUserContentController()
        let configuration = WKWebViewConfiguration()
        configuration.userContentController = controller
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        controller.add(WeakScriptHandler(self), name: Self.messageName)
        controller.addUserScript(WKUserScript(
            source: Self.bridgeScript,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        ))
        webView.navigationDelegate = self
    }

    func showDetail(for item: DisplayItem) {
        guard let href = item.href, let url = URL(string: href) else { return }
        currentItem = item
        titleLabel.stringValue = item.title
        titleLabel.toolTip = item.title
        orcaButton.isEnabled = item.orcaTerminal != nil
        browserButton.isEnabled = true

        let window = window ?? makeWindow()
        self.window = window
        if loadedHref != href {
            loadedHref = href
            webView.load(URLRequest(url: url))
        } else if webView.url != nil {
            applyStoredMode()
        }
        window.title = item.title
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 960, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.minSize = NSSize(width: 520, height: 420)
        window.isReleasedWhenClosed = false
        if !window.setFrameUsingName(Self.frameName) {
            window.center()
        }
        window.setFrameAutosaveName(Self.frameName)

        let content = NSView()
        let bar = NSVisualEffectView()
        bar.material = .headerView
        bar.blendingMode = .withinWindow
        bar.state = .active

        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        modeControl.controlSize = .small
        modeControl.selectedSegment = modeIndex(for: storedMode())
        modeControl.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        modeControl.setContentCompressionResistancePriority(.required, for: .horizontal)

        for button in [orcaButton, browserButton] {
            button.controlSize = .small
            button.bezelStyle = .rounded
            button.setContentHuggingPriority(.defaultHigh, for: .horizontal)
            button.setContentCompressionResistancePriority(.required, for: .horizontal)
        }

        let stack = NSStackView(views: [titleLabel, modeControl, orcaButton, browserButton])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(stack)

        bar.translatesAutoresizingMaskIntoConstraints = false
        webView.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(bar)
        content.addSubview(webView)

        NSLayoutConstraint.activate([
            bar.topAnchor.constraint(equalTo: content.topAnchor),
            bar.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            bar.heightAnchor.constraint(equalToConstant: 44),
            stack.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: bar.trailingAnchor, constant: -12),
            stack.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            webView.topAnchor.constraint(equalTo: bar.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])

        window.contentView = content
        return window
    }

    private func storedMode() -> String {
        let stored = defaults.string(forKey: Self.modeKey) ?? "full"
        return Self.modes.contains { $0.id == stored } ? stored : "full"
    }

    private func modeIndex(for id: String) -> Int {
        Self.modes.firstIndex { $0.id == id } ?? 0
    }

    // 페이지의 보기 버튼을 눌러 내부 상태(vst)와 localStorage 를 함께 갱신한다.
    private func applyStoredMode() {
        let elementID = Self.modes[modeIndex(for: storedMode())].elementID
        webView.evaluateJavaScript(
            "var b = document.getElementById('\(elementID)'); if (b) { b.click(); }",
            completionHandler: nil
        )
    }

    @objc private func modeChanged(_ sender: NSSegmentedControl) {
        let index = sender.selectedSegment
        guard Self.modes.indices.contains(index) else { return }
        let mode = Self.modes[index]
        defaults.set(mode.id, forKey: Self.modeKey)
        webView.evaluateJavaScript(
            "var b = document.getElementById('\(mode.elementID)'); if (b) { b.click(); }",
            completionHandler: nil
        )
    }

    @objc private func openInOrca() {
        guard let item = currentItem else { return }
        model.openInOrca(item)
    }

    @objc private func openInBrowser() {
        guard let href = currentItem?.href, let url = URL(string: href) else { return }
        NSWorkspace.shared.open(url)
    }

    private func reflectPageMode(_ value: String) {
        guard Self.modes.contains(where: { $0.id == value }) else { return }
        modeControl.selectedSegment = modeIndex(for: value)
        defaults.set(value, forKey: Self.modeKey)
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        applyStoredMode()
    }

    // MARK: - WKScriptMessageHandler

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == Self.messageName, let value = message.body as? String else { return }
        reflectPageMode(value)
    }

    private static let bridgeScript = """
    (function () {
      function report() {
        try {
          var v = document.body && document.body.dataset ? document.body.dataset.view : '';
          window.webkit.messageHandlers.\(messageName).postMessage(v || '');
        } catch (e) {}
      }
      document.addEventListener('click', function (event) {
        var button = event.target && event.target.closest
          ? event.target.closest('#views button') : null;
        if (button) setTimeout(report, 0);
      }, true);
    })();
    """
}

private final class WeakScriptHandler: NSObject, WKScriptMessageHandler {
    private weak var target: WKScriptMessageHandler?

    init(_ target: WKScriptMessageHandler) {
        self.target = target
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(userContentController, didReceive: message)
    }
}

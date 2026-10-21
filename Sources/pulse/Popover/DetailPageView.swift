import AppKit
import PulseCore
import SwiftUI
import WebKit

/// deadhd 진행 페이지의 보기 모드. 페이지의 버튼 id 와 저장 키를 함께 다룬다.
enum DetailPageMode {
    struct Mode {
        let id: String
        let label: String
        let elementID: String
    }

    static let all = [
        Mode(id: "full", label: "원본", elementID: "v-full"),
        Mode(id: "a", label: "스트립", elementID: "v-a"),
        Mode(id: "b", label: "타임라인", elementID: "v-b"),
        Mode(id: "c", label: "타일", elementID: "v-c"),
    ]
    static let defaultsKey = "detailViewMode"
    static let messageName = "deadhdView"

    static func stored() -> String {
        let stored = UserDefaults.standard.string(forKey: defaultsKey) ?? "full"
        return all.contains { $0.id == stored } ? stored : "full"
    }

    static func elementID(for id: String) -> String {
        all.first { $0.id == id }?.elementID ?? "v-full"
    }

    static func id(forPageValue value: String) -> String? {
        all.contains { $0.id == value } ? value : nil
    }

    fileprivate static let bridgeScript = """
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

struct DetailPageView: View {
    @ObservedObject var model: AppModel
    let target: DetailTarget

    @State private var mode = DetailPageMode.stored()

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle()
                .fill(PopoverPalette.stroke)
                .frame(height: 1)
            DetailWebView(url: target.url, mode: $mode)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(PopoverBackground())
        .onAppear { mode = DetailPageMode.stored() }
        .onChange(of: mode) { value in
            UserDefaults.standard.set(value, forKey: DetailPageMode.defaultsKey)
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            PopoverTextButton(
                symbol: "chevron.left",
                title: "목록",
                help: "목록으로 (Esc)"
            ) {
                model.closeDetail()
            }
            Text(target.item.title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(PopoverPalette.text)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            Picker("보기", selection: $mode) {
                ForEach(DetailPageMode.all, id: \.id) { item in
                    Text(item.label).tag(item.id)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.small)
            .fixedSize()
            PopoverIconButton(
                symbol: "arrow.up.right.square",
                help: "Orca 로 이동",
                enabled: target.item.orcaTerminal != nil || target.item.cwd != nil
            ) {
                model.openInOrca(target.item)
            }
            PopoverIconButton(symbol: "safari", help: "브라우저로 열기") {
                model.openLink(target.url.absoluteString)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

private struct DetailWebView: NSViewRepresentable {
    let url: URL
    @Binding var mode: String

    func makeCoordinator() -> Coordinator {
        Coordinator(mode: $mode)
    }

    func makeNSView(context: Context) -> WKWebView {
        let controller = WKUserContentController()
        controller.add(WeakScriptHandler(context.coordinator), name: DetailPageMode.messageName)
        controller.addUserScript(WKUserScript(
            source: DetailPageMode.bridgeScript,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        ))
        let configuration = WKWebViewConfiguration()
        configuration.userContentController = controller
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        context.coordinator.load(url, in: webView)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.mode = $mode
        context.coordinator.update(url, mode: mode, in: webView)
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var mode: Binding<String>
        private var loadedHref: String?
        private var appliedMode: String?

        init(mode: Binding<String>) {
            self.mode = mode
        }

        func load(_ url: URL, in webView: WKWebView) {
            loadedHref = url.absoluteString
            appliedMode = nil
            webView.load(URLRequest(url: url))
        }

        func update(_ url: URL, mode: String, in webView: WKWebView) {
            if loadedHref != url.absoluteString {
                load(url, in: webView)
            } else if appliedMode != mode, webView.url != nil {
                apply(mode, in: webView)
            }
        }

        // 페이지의 보기 버튼을 눌러 내부 상태(vst)와 localStorage 를 함께 갱신한다.
        private func apply(_ id: String, in webView: WKWebView) {
            appliedMode = id
            webView.evaluateJavaScript(
                "var b = document.getElementById('\(DetailPageMode.elementID(for: id))'); if (b) { b.click(); }",
                completionHandler: nil
            )
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            apply(DetailPageMode.stored(), in: webView)
        }

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            guard message.name == DetailPageMode.messageName,
                  let value = message.body as? String,
                  let id = DetailPageMode.id(forPageValue: value) else { return }
            appliedMode = id
            DispatchQueue.main.async { [weak self] in
                guard let self, self.mode.wrappedValue != id else { return }
                self.mode.wrappedValue = id
            }
        }
    }
}

private final class WeakScriptHandler: NSObject, WKScriptMessageHandler {
    private weak var target: WKScriptMessageHandler?

    init(_ target: WKScriptMessageHandler) {
        self.target = target
    }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        target?.userContentController(userContentController, didReceive: message)
    }
}

import SwiftUI
import WebKit

/// Policy for the HTML/SVG Preview WebView (R7, N5): no script, no
/// fetching of the page over the network, no unconstrained `file://`.
/// The Mac sandbox still needs `network.client` so WebKit can spawn
/// its WebContent helper for `loadHTMLString` — that is not a license
/// to load `http`/`https`/`file` (the delegate and content rules stop those).
enum LockedHTMLPreviewPolicy {
    static func makeConfiguration() -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        return configuration
    }

    /// `loadHTMLString` document plus a minimal SVG wrapper. `baseURL` is
    /// always `nil` at the load site so relative URLs cannot resolve to
    /// a file sandbox.
    static func documentHTML(buffer: String, kind: DocumentKind) -> String {
        if kind == .svg {
            return "<!DOCTYPE html><html><head><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width, initial-scale=1\"></head><body style=\"margin:0\">\(buffer)</body></html>"
        }
        return buffer
    }

    static func allows(_ url: URL?) -> Bool {
        guard let url else { return false }
        let scheme = (url.scheme ?? "").lowercased()
        switch scheme {
        case "http", "https", "file", "ftp", "ws", "wss":
            return false
        case "about", "data", "":
            return true
        default:
            return false
        }
    }
}

/// Compiles once and attaches to the `WKUserContentController` that was
/// passed into `WKWebView(frame:configuration:)` — not to
/// `webView.configuration`, which is a copy (N5).
enum LockedHTMLPreviewNetworkBlocker {
    static let identifier = "markus.locked-html-preview"

    /// Blanket block of every subresource URL. Main-frame `loadHTMLString`
    /// is not a URL fetch; document navigations stay on the delegate.
    static let encodedRules = """
    [{"trigger":{"url-filter":".*","resource-type":["image","style-sheet","script","font","raw","svg-document","media","popup","ping","fetch","websocket"]},"action":{"type":"block"}}]
    """

    /// Fallback if a WebKit build rejects a resource-type token.
    static let encodedRulesFallback = """
    [{"trigger":{"url-filter":".*"},"action":{"type":"block"}}]
    """

    private static var cached: WKContentRuleList?
    private static var compiling = false
    private static var waiters: [(WKContentRuleList?) -> Void] = []

    static func prepare(_ completion: @escaping (WKContentRuleList?) -> Void) {
        if let cached {
            completion(cached)
            return
        }
        waiters.append(completion)
        guard !compiling else { return }
        compiling = true
        guard let store = contentRuleStore() else {
            finish(nil)
            return
        }
        store.lookUpContentRuleList(forIdentifier: identifier) { list, _ in
            if let list {
                finish(list)
                return
            }
            store.compileContentRuleList(
                forIdentifier: identifier,
                encodedContentRuleList: encodedRules
            ) { list, _ in
                if let list {
                    finish(list)
                    return
                }
                store.compileContentRuleList(
                    forIdentifier: identifier + ".fallback",
                    encodedContentRuleList: encodedRulesFallback
                ) { list, _ in
                    finish(list)
                }
            }
        }
    }

    private static func contentRuleStore() -> WKContentRuleListStore? {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let url = caches.appendingPathComponent("MarkusContentRules", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return WKContentRuleListStore(url: url)
    }

    private static func finish(_ list: WKContentRuleList?) {
        cached = list
        compiling = false
        let pending = waiters
        waiters = []
        DispatchQueue.main.async {
            for waiter in pending {
                waiter(list)
            }
        }
    }
}

/// WKWebView of the current buffer. Navigation and script are locked.
/// The representable must not replace `SessionEditorRepresentable`.
#if os(macOS)
struct LockedHTMLPreviewRepresentable: NSViewRepresentable {
    var buffer: String
    var kind: DocumentKind
    var isVisible: Bool

    func makeCoordinator() -> LockedHTMLPreviewCoordinator {
        LockedHTMLPreviewCoordinator()
    }

    func makeNSView(context: Context) -> WKWebView {
        makeLockedWebView(coordinator: context.coordinator)
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        webView.isHidden = !isVisible
        context.coordinator.load(buffer, kind: kind, into: webView, isVisible: isVisible)
    }
}
#else
struct LockedHTMLPreviewRepresentable: UIViewRepresentable {
    var buffer: String
    var kind: DocumentKind
    var isVisible: Bool

    func makeCoordinator() -> LockedHTMLPreviewCoordinator {
        LockedHTMLPreviewCoordinator()
    }

    func makeUIView(context: Context) -> WKWebView {
        makeLockedWebView(coordinator: context.coordinator)
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        webView.isHidden = !isVisible
        context.coordinator.load(buffer, kind: kind, into: webView, isVisible: isVisible)
    }
}
#endif

@MainActor
final class LockedHTMLPreviewCoordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
    private var lastLoaded: String?
    private var pendingHTML: String?
    private var debounceTimer: Timer?
    private var rulesReady = false
    private var isVisible = false
    private weak var webView: WKWebView?
    private static let debounceInterval: TimeInterval = 0.12

    func attach(webView: WKWebView, contentController: WKUserContentController) {
        self.webView = webView
        LockedHTMLPreviewNetworkBlocker.prepare { [weak self, weak contentController] list in
            guard let self, let contentController, let list else { return }
            contentController.add(list)
            self.rulesReady = true
            self.flushIfNeeded()
        }
    }

    func load(_ buffer: String, kind: DocumentKind, into webView: WKWebView, isVisible: Bool) {
        self.webView = webView
        self.isVisible = isVisible
        let html = LockedHTMLPreviewPolicy.documentHTML(buffer: buffer, kind: kind)
        pendingHTML = html
        if isVisible {
            debounceTimer?.invalidate()
            debounceTimer = Timer.scheduledTimer(withTimeInterval: Self.debounceInterval, repeats: false) { [weak self] _ in
                DispatchQueue.main.async {
                    self?.flushIfNeeded()
                }
            }
        } else {
            debounceTimer?.invalidate()
            debounceTimer = nil
        }
        flushIfNeeded()
    }

    private func flushIfNeeded() {
        guard rulesReady, isVisible, let webView, let html = pendingHTML else { return }
        guard html != lastLoaded else { return }
        debounceTimer?.invalidate()
        debounceTimer = nil
        lastLoaded = html
        webView.loadHTMLString(html, baseURL: nil)
    }

    deinit {
        debounceTimer?.invalidate()
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        if navigationAction.navigationType == .linkActivated
            || navigationAction.navigationType == .formSubmitted
            || navigationAction.navigationType == .formResubmitted
            || navigationAction.navigationType == .backForward
            || navigationAction.navigationType == .reload {
            decisionHandler(.cancel)
            return
        }
        guard LockedHTMLPreviewPolicy.allows(navigationAction.request.url) else {
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationResponse: WKNavigationResponse,
        decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void
    ) {
        guard LockedHTMLPreviewPolicy.allows(navigationResponse.response.url) else {
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        nil
    }
}

private func makeLockedWebView(coordinator: LockedHTMLPreviewCoordinator) -> WKWebView {
    let configuration = LockedHTMLPreviewPolicy.makeConfiguration()
    let contentController = configuration.userContentController
    let webView = WKWebView(frame: .zero, configuration: configuration)
    webView.navigationDelegate = coordinator
    webView.uiDelegate = coordinator
    webView.allowsBackForwardNavigationGestures = false
    #if os(macOS)
    webView.allowsMagnification = true
    #else
    webView.isOpaque = true
    #endif
    coordinator.attach(webView: webView, contentController: contentController)
    return webView
}

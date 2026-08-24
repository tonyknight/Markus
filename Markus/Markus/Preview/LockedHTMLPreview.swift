import SwiftUI
import WebKit

/// Policy for the HTML/SVG Preview WebView (R7).
///
/// Product override (punch list round 3): HTML Preview is a working
/// preview of the buffer — CSS, JS, and images load. Relative URLs
/// resolve against the document's directory when the file is on disk.
/// Link clicks, forms, popups, and main-frame navigations stay blocked
/// so Preview is not a browser.
///
/// SVG Preview stays locked: no script, no network, `baseURL` nil (N5).
enum LockedHTMLPreviewPolicy {
    static func makeConfiguration() -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        return configuration
    }

    static func enableScript(for kind: DocumentKind) -> Bool {
        kind == .html
    }

    static func baseURL(for kind: DocumentKind, fileURL: URL?) -> URL? {
        guard kind == .html, let fileURL else { return nil }
        return fileURL.deletingLastPathComponent()
    }

    /// `loadHTMLString` document plus a minimal SVG wrapper.
    static func documentHTML(buffer: String, kind: DocumentKind) -> String {
        if kind == .svg {
            return wrappedSVG(buffer)
        }
        return buffer
    }

    /// Inline the SVG in an HTML shell. Strip `<?xml …?>` and an SVG
    /// `<!DOCTYPE …>` first — WebKit can fail the WebContent process
    /// when those sit inside `<body>`.
    static func wrappedSVG(_ buffer: String) -> String {
        let svg = stripLeadingXMLProlog(buffer)
        return "<!DOCTYPE html><html><head><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width, initial-scale=1\"></head><body style=\"margin:0\">\(svg)</body></html>"
    }

    static func stripLeadingXMLProlog(_ buffer: String) -> String {
        var remainder = buffer
        while true {
            let trimmed = remainder.trimmingCharacters(in: .whitespacesAndNewlines)
            let lower = trimmed.lowercased()
            if lower.hasPrefix("<?xml"), let end = trimmed.range(of: "?>") {
                remainder = String(trimmed[end.upperBound...])
                continue
            }
            if lower.hasPrefix("<!doctype"), let end = trimmed.range(of: ">") {
                remainder = String(trimmed[end.upperBound...])
                continue
            }
            return trimmed
        }
    }

    /// SVG: only about/data. HTML: subresources may be http(s)/file/data.
    static func allows(_ url: URL?, kind: DocumentKind) -> Bool {
        guard let url else { return false }
        let scheme = (url.scheme ?? "").lowercased()
        if kind == .html {
            switch scheme {
            case "http", "https", "file", "data", "about", "blob", "":
                return true
            default:
                return false
            }
        }
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
    var fileURL: URL?
    var isVisible: Bool

    func makeCoordinator() -> LockedHTMLPreviewCoordinator {
        LockedHTMLPreviewCoordinator()
    }

    func makeNSView(context: Context) -> WKWebView {
        makeLockedWebView(coordinator: context.coordinator)
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        webView.isHidden = !isVisible
        context.coordinator.load(buffer, kind: kind, fileURL: fileURL, into: webView, isVisible: isVisible)
    }
}
#else
struct LockedHTMLPreviewRepresentable: UIViewRepresentable {
    var buffer: String
    var kind: DocumentKind
    var fileURL: URL?
    var isVisible: Bool

    func makeCoordinator() -> LockedHTMLPreviewCoordinator {
        LockedHTMLPreviewCoordinator()
    }

    func makeUIView(context: Context) -> WKWebView {
        makeLockedWebView(coordinator: context.coordinator)
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        webView.isHidden = !isVisible
        context.coordinator.load(buffer, kind: kind, fileURL: fileURL, into: webView, isVisible: isVisible)
    }
}
#endif

@MainActor
final class LockedHTMLPreviewCoordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
    private var lastLoaded: String?
    private var pendingHTML: String?
    private var pendingKind: DocumentKind = .html
    private var pendingFileURL: URL?
    private var debounceTimer: Timer?
    private var svgRulesReady = false
    private var svgBlockerInstalled = false
    private var isVisible = false
    private weak var webView: WKWebView?
    private weak var contentController: WKUserContentController?
    private var svgRuleList: WKContentRuleList?
    private static let debounceInterval: TimeInterval = 0.12

    func attach(webView: WKWebView, contentController: WKUserContentController) {
        self.webView = webView
        self.contentController = contentController
        LockedHTMLPreviewNetworkBlocker.prepare { [weak self] list in
            guard let self else { return }
            self.svgRuleList = list
            self.svgRulesReady = list != nil
            self.installSVGBlockerIfNeeded()
            self.flushIfNeeded()
        }
    }

    func load(
        _ buffer: String,
        kind: DocumentKind,
        fileURL: URL?,
        into webView: WKWebView,
        isVisible: Bool
    ) {
        self.webView = webView
        self.isVisible = isVisible
        pendingKind = kind
        pendingFileURL = fileURL
        webView.configuration.defaultWebpagePreferences.allowsContentJavaScript =
            LockedHTMLPreviewPolicy.enableScript(for: kind)
        pendingHTML = LockedHTMLPreviewPolicy.documentHTML(buffer: buffer, kind: kind)
        installSVGBlockerIfNeeded()
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

    private func installSVGBlockerIfNeeded() {
        guard pendingKind == .svg, !svgBlockerInstalled,
              let contentController, let svgRuleList else { return }
        contentController.add(svgRuleList)
        svgBlockerInstalled = true
    }

    private func flushIfNeeded() {
        if pendingKind == .svg, !svgRulesReady { return }
        guard isVisible, let webView, let html = pendingHTML else { return }
        let base = LockedHTMLPreviewPolicy.baseURL(for: pendingKind, fileURL: pendingFileURL)
        let key = "\(pendingKind.rawValue)\n\(base?.path ?? "")\n\(html)"
        guard key != lastLoaded else { return }
        debounceTimer?.invalidate()
        debounceTimer = nil
        lastLoaded = key
        webView.loadHTMLString(html, baseURL: base)
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
        if pendingKind == .html,
           navigationAction.targetFrame?.isMainFrame == true,
           navigationAction.navigationType == .other {
            let scheme = (navigationAction.request.url?.scheme ?? "").lowercased()
            if scheme == "http" || scheme == "https" {
                decisionHandler(.cancel)
                return
            }
        }
        guard LockedHTMLPreviewPolicy.allows(navigationAction.request.url, kind: pendingKind) else {
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
        guard LockedHTMLPreviewPolicy.allows(navigationResponse.response.url, kind: pendingKind) else {
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

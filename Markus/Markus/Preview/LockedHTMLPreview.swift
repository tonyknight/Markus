import SwiftUI
import WebKit

/// HTML/SVG Preview. Product override of N5: render the current buffer
/// the way Safari would — JavaScript on, local folder access, CSS/JS/
/// images/fonts, http(s) subresources. Not a URL-bar browser: popups
/// are folded back into this WebView.
enum LockedHTMLPreviewPolicy {
    static func makeConfiguration() -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
        return configuration
    }

    /// Current buffer plus a minimal SVG wrapper.
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

    static func allows(_ url: URL?) -> Bool {
        guard let url else { return true }
        let scheme = (url.scheme ?? "").lowercased()
        switch scheme {
        case "http", "https", "file", "data", "about", "blob", "ws", "wss", "":
            return true
        default:
            return false
        }
    }

    /// `document.write` payload. JSON-encode so quotes and newlines
    /// cannot break the script.
    static func documentWriteJavaScript(_ html: String) -> String? {
        guard let data = try? JSONEncoder().encode(html),
              let json = String(data: data, encoding: .utf8)
        else { return nil }
        return "document.open('text/html','replace');document.write(\(json));document.close();"
    }
}

/// WKWebView of the current buffer. Must not replace `SessionEditorRepresentable`.
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
        makePreviewWebView(coordinator: context.coordinator)
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
        makePreviewWebView(coordinator: context.coordinator)
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        webView.isHidden = !isVisible
        context.coordinator.load(buffer, kind: kind, fileURL: fileURL, into: webView, isVisible: isVisible)
    }
}
#endif

@MainActor
final class LockedHTMLPreviewCoordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
    /// Same controller the WKWebView was created with. Do not add
    /// scripts via `webView.configuration` — that value is a copy.
    let userContentController = WKUserContentController()

    private var lastLoaded: String?
    private var pendingHTML: String?
    private var pendingKind: DocumentKind = .html
    private var pendingFileURL: URL?
    private var debounceTimer: Timer?
    private var isVisible = false
    private weak var webView: WKWebView?
    private var accessingDirectory: URL?
    private var hasNavigatedAway = false
    private var isInjectingLiveHTML = false
    private var establishedFilePath: String?
    private static let debounceInterval: TimeInterval = 0.12

    func load(
        _ buffer: String,
        kind: DocumentKind,
        fileURL: URL?,
        into webView: WKWebView,
        isVisible: Bool
    ) {
        self.webView = webView
        let becameVisible = isVisible && !self.isVisible
        self.isVisible = isVisible
        pendingKind = kind
        pendingFileURL = fileURL
        pendingHTML = LockedHTMLPreviewPolicy.documentHTML(buffer: buffer, kind: kind)
        if becameVisible {
            hasNavigatedAway = false
            lastLoaded = nil
            establishedFilePath = nil
        }
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
        guard isVisible, let webView, let html = pendingHTML else { return }
        if hasNavigatedAway { return }
        let key = "\(pendingKind.rawValue)\n\(pendingFileURL?.path ?? "")\n\(html)"
        guard key != lastLoaded else { return }
        debounceTimer?.invalidate()
        debounceTimer = nil
        lastLoaded = key
        loadIntoWebView(html, fileURL: pendingFileURL, webView: webView)
    }

    private func loadIntoWebView(
        _ html: String,
        fileURL: URL?,
        webView: WKWebView
    ) {
        guard let fileURL else {
            releaseDirectoryAccess()
            establishedFilePath = nil
            userContentController.removeAllUserScripts()
            webView.loadHTMLString(html, baseURL: nil)
            return
        }

        let path = fileURL.standardizedFileURL.path
        if establishedFilePath == path, webView.url?.isFileURL == true {
            injectLiveHTML(html, into: webView)
            return
        }

        beginDirectoryAccess(for: fileURL)
        installLiveHTMLUserScript(html)
        establishedFilePath = path
        webView.loadFileURL(fileURL, allowingReadAccessTo: fileURL.deletingLastPathComponent())
    }

    /// Replace the on-disk document with the live buffer *before* page
    /// scripts run. Origin and folder access stay on the opened file,
    /// so relative CSS/JS/images resolve like Safari.
    private func installLiveHTMLUserScript(_ html: String) {
        userContentController.removeAllUserScripts()
        guard let js = LockedHTMLPreviewPolicy.documentWriteJavaScript(html) else { return }
        userContentController.addUserScript(
            WKUserScript(source: js, injectionTime: .atDocumentStart, forMainFrameOnly: true)
        )
    }

    private func injectLiveHTML(_ html: String, into webView: WKWebView) {
        guard let js = LockedHTMLPreviewPolicy.documentWriteJavaScript(html) else { return }
        isInjectingLiveHTML = true
        webView.evaluateJavaScript(js) { [weak self] _, _ in
            DispatchQueue.main.async {
                self?.isInjectingLiveHTML = false
            }
        }
    }

    private func beginDirectoryAccess(for fileURL: URL) {
        releaseDirectoryAccess()
        _ = fileURL.startAccessingSecurityScopedResource()
        let directory = fileURL.deletingLastPathComponent()
        if directory.startAccessingSecurityScopedResource() {
            accessingDirectory = directory
        }
    }

    private func releaseDirectoryAccess() {
        if let accessingDirectory {
            accessingDirectory.stopAccessingSecurityScopedResource()
            self.accessingDirectory = nil
        }
    }

    deinit {
        debounceTimer?.invalidate()
        if let accessingDirectory {
            accessingDirectory.stopAccessingSecurityScopedResource()
        }
    }

    func webView(
        _ webView: WKWebView,
        didFinish navigation: WKNavigation!
    ) {
        userContentController.removeAllUserScripts()
        if isInjectingLiveHTML {
            isInjectingLiveHTML = false
        }
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        if navigationAction.navigationType == .linkActivated {
            hasNavigatedAway = true
            userContentController.removeAllUserScripts()
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
        hasNavigatedAway = true
        userContentController.removeAllUserScripts()
        if let url = navigationAction.request.url {
            webView.load(URLRequest(url: url))
        }
        return nil
    }
}

private func makePreviewWebView(coordinator: LockedHTMLPreviewCoordinator) -> WKWebView {
    let configuration = LockedHTMLPreviewPolicy.makeConfiguration()
    configuration.userContentController = coordinator.userContentController
    let webView = WKWebView(frame: .zero, configuration: configuration)
    webView.navigationDelegate = coordinator
    webView.uiDelegate = coordinator
    webView.allowsBackForwardNavigationGestures = true
    #if os(macOS)
    webView.allowsMagnification = true
    #else
    webView.isOpaque = true
    #endif
    return webView
}

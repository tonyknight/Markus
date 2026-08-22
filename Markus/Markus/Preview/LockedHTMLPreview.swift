import SwiftUI
import WebKit

/// Policy for the HTML/SVG Preview WebView (R7, N5): no script, no
/// network, no unconstrained `file://` sandbox. The buffer is untrusted.
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
        let webView = makeLockedWebView(coordinator: context.coordinator)
        context.coordinator.load(buffer, kind: kind, into: webView, immediate: true)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        webView.isHidden = !isVisible
        context.coordinator.load(buffer, kind: kind, into: webView, immediate: false)
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
        let webView = makeLockedWebView(coordinator: context.coordinator)
        context.coordinator.load(buffer, kind: kind, into: webView, immediate: true)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        webView.isHidden = !isVisible
        context.coordinator.load(buffer, kind: kind, into: webView, immediate: false)
    }
}
#endif

@MainActor
final class LockedHTMLPreviewCoordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
    private var lastLoaded: String?
    private var pendingHTML: String?
    private var debounceTimer: Timer?
    private static let debounceInterval: TimeInterval = 0.12

    func load(_ buffer: String, kind: DocumentKind, into webView: WKWebView, immediate: Bool) {
        let html = LockedHTMLPreviewPolicy.documentHTML(buffer: buffer, kind: kind)
        guard html != lastLoaded else { return }
        if immediate || lastLoaded == nil {
            debounceTimer?.invalidate()
            debounceTimer = nil
            pendingHTML = nil
            lastLoaded = html
            webView.loadHTMLString(html, baseURL: nil)
            return
        }
        pendingHTML = html
        debounceTimer?.invalidate()
        debounceTimer = Timer.scheduledTimer(withTimeInterval: Self.debounceInterval, repeats: false) { [weak self, weak webView] _ in
            DispatchQueue.main.async {
                self?.flush(into: webView)
            }
        }
    }

    private func flush(into webView: WKWebView?) {
        debounceTimer = nil
        guard let webView, let html = pendingHTML else { return }
        pendingHTML = nil
        guard html != lastLoaded else { return }
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

#if os(macOS)
private func makeLockedWebView(coordinator: LockedHTMLPreviewCoordinator) -> WKWebView {
    let webView = WKWebView(frame: .zero, configuration: LockedHTMLPreviewPolicy.makeConfiguration())
    webView.navigationDelegate = coordinator
    webView.uiDelegate = coordinator
    webView.allowsMagnification = true
    webView.allowsBackForwardNavigationGestures = false
    installNetworkBlocker(on: webView)
    return webView
}
#else
private func makeLockedWebView(coordinator: LockedHTMLPreviewCoordinator) -> WKWebView {
    let webView = WKWebView(frame: .zero, configuration: LockedHTMLPreviewPolicy.makeConfiguration())
    webView.navigationDelegate = coordinator
    webView.uiDelegate = coordinator
    webView.allowsBackForwardNavigationGestures = false
    webView.isOpaque = true
    installNetworkBlocker(on: webView)
    return webView
}
#endif

/// Extra belt for `<img src="https://…">` subresources that may not
/// go through `decidePolicyFor` as a main-frame navigation.
private func installNetworkBlocker(on webView: WKWebView) {
    let rules = """
    [{"trigger":{"url-filter":"^https?://"},"action":{"type":"block"}},{"trigger":{"url-filter":"^file://"},"action":{"type":"block"}}]
    """
    WKContentRuleListStore.default().compileContentRuleList(
        forIdentifier: "markus.locked-html-preview",
        encodedContentRuleList: rules
    ) { list, _ in
        guard let list else { return }
        webView.configuration.userContentController.add(list)
    }
}

import SwiftUI
import WebKit

/// HTML/SVG Preview. Product override of N5: full WebKit render of the
/// current buffer. The user’s file is **not** loaded with `loadFileURL`.
/// WebContent is a separate sandbox and cannot be granted a folder such
/// as `~/Documents/Repo/…` (`Ignoring request to load this main resource
/// because it is outside the sandbox`). The app process already has the
/// file (and Open Folder root); a custom scheme returns those bytes.
enum LockedHTMLPreviewPolicy {
    static let scheme = "markushtml"
    static let host = "preview"

    static func makeConfiguration(schemeHandler: WKURLSchemeHandler) -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
        configuration.setURLSchemeHandler(schemeHandler, forURLScheme: scheme)
        return configuration
    }

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
        case "http", "https", "data", "about", "blob", "ws", "wss", Self.scheme, "":
            return true
        case "file":
            return false
        default:
            return false
        }
    }

    /// Path of the live document under `resourceRoot`, used as the
    /// scheme URL so relative and root-relative links resolve like a
    /// local site, not like `file:///`.
    static func documentPath(fileURL: URL?, resourceRoot: URL?) -> String {
        guard let fileURL else { return "/index.html" }
        let filePath = fileURL.standardizedFileURL.path
        if let resourceRoot {
            let rootPath = resourceRoot.standardizedFileURL.path
            let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
            if filePath.hasPrefix(prefix) {
                let relative = String(filePath.dropFirst(prefix.count))
                return "/" + relative
            }
            if filePath == rootPath {
                return "/index.html"
            }
        }
        return "/" + fileURL.lastPathComponent
    }

    static func previewURL(documentPath: String, generation: Int) -> URL {
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.path = documentPath.hasPrefix("/") ? documentPath : "/" + documentPath
        components.queryItems = [URLQueryItem(name: "r", value: String(generation))]
        return components.url!
    }
}

/// Serves live HTML and sibling files from the app process.
final class LockedHTMLPreviewSchemeHandler: NSObject, WKURLSchemeHandler {
    private let lock = NSLock()
    private var html = ""
    private var documentPath = "/index.html"
    private var resourceRoot: URL?

    func update(html: String, documentPath: String, resourceRoot: URL?) {
        lock.lock()
        self.html = html
        self.documentPath = documentPath
        self.resourceRoot = resourceRoot
        lock.unlock()
    }

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        lock.lock()
        let html = self.html
        let documentPath = self.documentPath
        let resourceRoot = self.resourceRoot
        lock.unlock()

        guard let url = urlSchemeTask.request.url else {
            urlSchemeTask.didFailWithError(URLError(.badURL))
            return
        }
        let path = Self.normalizedPath(url.path)
        if path == documentPath || path == "/" {
            finish(urlSchemeTask, url: url, data: Data(html.utf8), mime: "text/html")
            return
        }
        guard let file = Self.fileURL(for: path, under: resourceRoot) else {
            urlSchemeTask.didFailWithError(URLError(.fileDoesNotExist))
            return
        }
        do {
            let data = try Data(contentsOf: file)
            finish(urlSchemeTask, url: url, data: data, mime: Self.mimeType(for: file))
        } catch {
            urlSchemeTask.didFailWithError(error)
        }
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}

    static func normalizedPath(_ path: String) -> String {
        if path.isEmpty { return "/" }
        var result = path.hasPrefix("/") ? path : "/" + path
        if result.count > 1, result.hasSuffix("/") {
            result.removeLast()
        }
        return result
    }

    static func fileURL(for path: String, under root: URL?) -> URL? {
        guard let root else { return nil }
        let relative = path.hasPrefix("/") ? String(path.dropFirst()) : path
        let resolvedRoot = root.resolvingSymlinksInPath()
        let candidate = resolvedRoot.appendingPathComponent(relative).resolvingSymlinksInPath()
        let rootPath = resolvedRoot.path
        let candidatePath = candidate.path
        if candidatePath == rootPath { return candidate }
        let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        guard candidatePath.hasPrefix(prefix) else { return nil }
        return candidate
    }

    private func finish(_ task: WKURLSchemeTask, url: URL, data: Data, mime: String) {
        let response = URLResponse(
            url: url,
            mimeType: mime,
            expectedContentLength: data.count,
            textEncodingName: "utf-8"
        )
        task.didReceive(response)
        task.didReceive(data)
        task.didFinish()
    }

    static func mimeType(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "html", "htm": return "text/html"
        case "css": return "text/css"
        case "js", "mjs", "cjs": return "text/javascript"
        case "json": return "application/json"
        case "svg": return "image/svg+xml"
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif": return "image/gif"
        case "webp": return "image/webp"
        case "ico": return "image/x-icon"
        case "woff": return "font/woff"
        case "woff2": return "font/woff2"
        case "ttf": return "font/ttf"
        case "otf": return "font/otf"
        case "mp4": return "video/mp4"
        case "webm": return "video/webm"
        case "mp3": return "audio/mpeg"
        case "pdf": return "application/pdf"
        default: return "application/octet-stream"
        }
    }
}

/// WKWebView of the current buffer. Must not replace `SessionEditorRepresentable`.
#if os(macOS)
struct LockedHTMLPreviewRepresentable: NSViewRepresentable {
    var buffer: String
    var kind: DocumentKind
    var fileURL: URL?
    var resourceRoot: URL?
    var isVisible: Bool

    func makeCoordinator() -> LockedHTMLPreviewCoordinator {
        LockedHTMLPreviewCoordinator()
    }

    func makeNSView(context: Context) -> WKWebView {
        makePreviewWebView(coordinator: context.coordinator)
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        webView.isHidden = !isVisible
        context.coordinator.load(
            buffer,
            kind: kind,
            fileURL: fileURL,
            resourceRoot: resourceRoot,
            into: webView,
            isVisible: isVisible
        )
    }
}
#else
struct LockedHTMLPreviewRepresentable: UIViewRepresentable {
    var buffer: String
    var kind: DocumentKind
    var fileURL: URL?
    var resourceRoot: URL?
    var isVisible: Bool

    func makeCoordinator() -> LockedHTMLPreviewCoordinator {
        LockedHTMLPreviewCoordinator()
    }

    func makeUIView(context: Context) -> WKWebView {
        makePreviewWebView(coordinator: context.coordinator)
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        webView.isHidden = !isVisible
        context.coordinator.load(
            buffer,
            kind: kind,
            fileURL: fileURL,
            resourceRoot: resourceRoot,
            into: webView,
            isVisible: isVisible
        )
    }
}
#endif

@MainActor
final class LockedHTMLPreviewCoordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
    let schemeHandler = LockedHTMLPreviewSchemeHandler()

    private var lastLoaded: String?
    private var pendingHTML: String?
    private var pendingKind: DocumentKind = .html
    private var pendingFileURL: URL?
    private var pendingResourceRoot: URL?
    private var debounceTimer: Timer?
    private var isVisible = false
    private weak var webView: WKWebView?
    private var accessingDirectory: URL?
    private var hasNavigatedAway = false
    private var generation = 0
    private static let debounceInterval: TimeInterval = 0.12

    func load(
        _ buffer: String,
        kind: DocumentKind,
        fileURL: URL?,
        resourceRoot: URL?,
        into webView: WKWebView,
        isVisible: Bool
    ) {
        self.webView = webView
        let becameVisible = isVisible && !self.isVisible
        self.isVisible = isVisible
        pendingKind = kind
        pendingFileURL = fileURL
        pendingResourceRoot = resourceRoot
        pendingHTML = LockedHTMLPreviewPolicy.documentHTML(buffer: buffer, kind: kind)
        if becameVisible {
            hasNavigatedAway = false
            lastLoaded = nil
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
        let key = "\(pendingKind.rawValue)\n\(pendingFileURL?.path ?? "")\n\(pendingResourceRoot?.path ?? "")\n\(html)"
        guard key != lastLoaded else { return }
        debounceTimer?.invalidate()
        debounceTimer = nil
        lastLoaded = key
        loadIntoWebView(html, fileURL: pendingFileURL, resourceRoot: pendingResourceRoot, webView: webView)
    }

    private func loadIntoWebView(
        _ html: String,
        fileURL: URL?,
        resourceRoot: URL?,
        webView: WKWebView
    ) {
        beginDirectoryAccess(resourceRoot)
        let documentPath = LockedHTMLPreviewPolicy.documentPath(fileURL: fileURL, resourceRoot: resourceRoot)
        schemeHandler.update(html: html, documentPath: documentPath, resourceRoot: resourceRoot)
        generation += 1
        let url = LockedHTMLPreviewPolicy.previewURL(documentPath: documentPath, generation: generation)
        webView.load(URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30))
    }

    private func beginDirectoryAccess(_ directory: URL?) {
        releaseDirectoryAccess()
        guard let directory else { return }
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
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        if navigationAction.navigationType == .linkActivated {
            hasNavigatedAway = true
        }
        guard let url = navigationAction.request.url else {
            decisionHandler(.allow)
            return
        }
        if url.isFileURL {
            decisionHandler(.cancel)
            if let mapped = schemeURL(forFile: url) {
                webView.load(URLRequest(url: mapped))
            }
            return
        }
        guard LockedHTMLPreviewPolicy.allows(url) else {
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
        if let url = navigationAction.request.url {
            if url.isFileURL, let mapped = schemeURL(forFile: url) {
                webView.load(URLRequest(url: mapped))
            } else {
                webView.load(URLRequest(url: url))
            }
        }
        return nil
    }

    private func schemeURL(forFile fileURL: URL) -> URL? {
        let path = LockedHTMLPreviewPolicy.documentPath(
            fileURL: fileURL,
            resourceRoot: pendingResourceRoot
        )
        let current = LockedHTMLPreviewPolicy.documentPath(
            fileURL: pendingFileURL,
            resourceRoot: pendingResourceRoot
        )
        if path != current {
            guard LockedHTMLPreviewSchemeHandler.fileURL(for: path, under: pendingResourceRoot) != nil else {
                return nil
            }
        }
        generation += 1
        return LockedHTMLPreviewPolicy.previewURL(documentPath: path, generation: generation)
    }
}

private func makePreviewWebView(coordinator: LockedHTMLPreviewCoordinator) -> WKWebView {
    let configuration = LockedHTMLPreviewPolicy.makeConfiguration(schemeHandler: coordinator.schemeHandler)
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

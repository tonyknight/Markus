import Foundation
import UniformTypeIdentifiers

/// Closed set of document kinds Markus can treat as themselves.
/// Wave B cases exist so later tickets can attach profiles without changing this kernel.
enum DocumentKind: String, CaseIterable, Hashable, Sendable {
    case markdown
    case json
    case html
    case svg
    case toml
    case css
    case javascript
    case typescript
    case swift
    case php
    case shell

    static let waveA: [DocumentKind] = [.markdown, .json, .html, .svg, .toml]

    var displayName: String {
        switch self {
        case .markdown: "Markdown"
        case .json: "JSON"
        case .html: "HTML"
        case .svg: "SVG"
        case .toml: "TOML"
        case .css: "CSS"
        case .javascript: "JavaScript"
        case .typescript: "TypeScript"
        case .swift: "Swift"
        case .php: "PHP"
        case .shell: "Shell"
        }
    }

    /// NSDocument type name / UTI identifier.
    var typeName: String {
        switch self {
        case .markdown: "net.daringfireball.markdown"
        case .json: "public.json"
        case .html: "public.html"
        case .svg: "public.svg-image"
        case .toml: "public.toml"
        case .css: "public.css"
        case .javascript: "com.netscape.javascript-source"
        case .typescript: "org.typescript.typescript"
        case .swift: "public.swift-source"
        case .php: "public.php-script"
        case .shell: "public.shell-script"
        }
    }

    var defaultExtension: String {
        filenameExtensions[0]
    }

    var filenameExtensions: [String] {
        switch self {
        case .markdown: ["md", "markdown", "mdown", "mkd"]
        case .json: ["json"]
        case .html: ["html", "htm"]
        case .svg: ["svg"]
        case .toml: ["toml"]
        case .css: ["css"]
        case .javascript: ["js", "mjs", "cjs"]
        case .typescript: ["ts", "tsx"]
        case .swift: ["swift"]
        case .php: ["php"]
        case .shell: ["sh", "bash", "zsh"]
        }
    }

    var contentType: UTType {
        UTType(typeName)
            ?? UTType(filenameExtension: defaultExtension)
            ?? UTType(importedAs: typeName)
    }

    /// Extension first, then the URL's resource UTI, then markdown.
    static func from(url: URL) -> DocumentKind {
        let ext = url.pathExtension
        if !ext.isEmpty, let kind = fromKnown(filenameExtension: ext) {
            return kind
        }
        if let identifier = (try? url.resourceValues(forKeys: [.typeIdentifierKey]))?.typeIdentifier,
           let kind = fromKnown(typeName: identifier) {
            return kind
        }
        return .markdown
    }

    static func from(typeName: String) -> DocumentKind {
        fromKnown(typeName: typeName) ?? .markdown
    }

    static func from(filenameExtension: String) -> DocumentKind {
        fromKnown(filenameExtension: filenameExtension) ?? .markdown
    }

    private static let kindsByExtension: [String: DocumentKind] = {
        var map: [String: DocumentKind] = [:]
        for kind in allCases {
            for ext in kind.filenameExtensions {
                map[ext] = kind
            }
        }
        return map
    }()

    private static let kindsByTypeName: [String: DocumentKind] = {
        var map: [String: DocumentKind] = [:]
        for kind in allCases {
            map[kind.typeName] = kind
        }
        return map
    }()

    private static func fromKnown(filenameExtension: String) -> DocumentKind? {
        kindsByExtension[filenameExtension.lowercased()]
    }

    private static func fromKnown(typeName: String) -> DocumentKind? {
        kindsByTypeName[typeName]
    }
}

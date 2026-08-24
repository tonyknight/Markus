import Foundation
import Testing
@testable import Markus

struct MarkdownFolderTreeTests {
    private func makeFixture() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("markus-tree-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("# Notes\n".utf8).write(to: root.appendingPathComponent("notes.md"))
        try Data("{}\n".utf8).write(to: root.appendingPathComponent("data.json"))
        try Data("plain\n".utf8).write(to: root.appendingPathComponent("ignore.txt"))
        try Data("# Hidden\n".utf8).write(to: root.appendingPathComponent(".hidden.md"))

        let sub = root.appendingPathComponent("sub", isDirectory: true)
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        try Data("# Page\n".utf8).write(to: sub.appendingPathComponent("page.markdown"))

        let empty = root.appendingPathComponent("empty", isDirectory: true)
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)

        let onlyOther = root.appendingPathComponent("only-other", isDirectory: true)
        try FileManager.default.createDirectory(at: onlyOther, withIntermediateDirectories: true)
        try Data("nope\n".utf8).write(to: onlyOther.appendingPathComponent("photo.png"))

        let jsonOnly = root.appendingPathComponent("json-only", isDirectory: true)
        try FileManager.default.createDirectory(at: jsonOnly, withIntermediateDirectories: true)
        try Data("{}\n".utf8).write(to: jsonOnly.appendingPathComponent("config.json"))

        return root
    }

    @Test func buildsShippedKindNestedTreeFromFixture() throws {
        let root = try makeFixture()
        defer { try? FileManager.default.removeItem(at: root) }

        let tree = MarkdownFolderTree.build(root: root)
        let names = tree.map(\.name).sorted()
        #expect(names == ["data.json", "json-only", "notes.md", "sub"])
        #expect(!names.contains("ignore.txt"))
        #expect(!names.contains(".hidden.md"))
        #expect(!names.contains("empty"))
        #expect(!names.contains("only-other"))

        let sub = try #require(tree.first { $0.name == "sub" })
        #expect(sub.isDirectory)
        #expect(sub.children.map(\.name) == ["page.markdown"])
        #expect(!sub.children[0].isDirectory)
        #expect(sub.children[0].url.lastPathComponent == "page.markdown")

        let notes = try #require(tree.first { $0.name == "notes.md" })
        #expect(!notes.isDirectory)
        #expect(notes.url.lastPathComponent == "notes.md")

        let jsonOnly = try #require(tree.first { $0.name == "json-only" })
        #expect(jsonOnly.isDirectory)
        #expect(jsonOnly.children.map(\.name) == ["config.json"])
    }

    @Test func includesJSONHTMLAndSVGAlongsideMarkdown() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("markus-tree-kinds-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("# A\n".utf8).write(to: root.appendingPathComponent("a.md"))
        try Data("{}\n".utf8).write(to: root.appendingPathComponent("b.json"))
        try Data("<p></p>\n".utf8).write(to: root.appendingPathComponent("c.html"))
        try Data("<svg></svg>\n".utf8).write(to: root.appendingPathComponent("d.svg"))
        try Data("skip\n".utf8).write(to: root.appendingPathComponent("e.txt"))

        let names = MarkdownFolderTree.build(root: root).map(\.name).sorted()
        #expect(names == ["a.md", "b.json", "c.html", "d.svg"])
    }

    @Test func buildDrivesFromInjectedURLBasedListerRatherThanReadingTheRealFilesystemDirectly() throws {
        // MarkdownFolderTree must reach every directory it enumerates
        // exclusively through the (URL) -> [URL] lister it is handed --
        // never by falling back to FileManager.default against a path
        // string of its own construction (N7). Proving this doesn't
        // require a real sandbox: none of these URLs exist on disk, so
        // any code path that still touches the real filesystem directly
        // sees nothing and the tree comes back empty.
        let root = URL(fileURLWithPath: "/nonexistent-markus-root-\(UUID().uuidString)", isDirectory: true)
        let onlyViaHook = root.appendingPathComponent("only-via-hook.md")
        let subdir = root.appendingPathComponent("sub", isDirectory: true)
        let nested = subdir.appendingPathComponent("nested.markdown", isDirectory: false)

        let tree = MarkdownFolderTree.build(root: root) { url in
            switch url {
            case root: return [onlyViaHook, subdir]
            case subdir: return [nested]
            default: return []
            }
        }

        let names = tree.map(\.name).sorted()
        #expect(names == ["only-via-hook.md", "sub"])

        let sub = try #require(tree.first { $0.name == "sub" })
        #expect(sub.isDirectory)
        #expect(sub.children.map(\.name) == ["nested.markdown"])
    }

    private func makeSandboxedFixture() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("markus-sandboxed-tree-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("# Index\n".utf8).write(to: root.appendingPathComponent("index.md"))
        try Data("readme\n".utf8).write(to: root.appendingPathComponent("README.txt"))
        try Data("# Dotfile\n".utf8).write(to: root.appendingPathComponent(".gitkeep.md"))

        let dotDir = root.appendingPathComponent(".obsidian", isDirectory: true)
        try FileManager.default.createDirectory(at: dotDir, withIntermediateDirectories: true)
        try Data("# Config\n".utf8).write(to: dotDir.appendingPathComponent("config.md"))

        let assets = root.appendingPathComponent("assets", isDirectory: true)
        try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
        try Data("PNG".utf8).write(to: assets.appendingPathComponent("logo.png"))

        let empty = root.appendingPathComponent("empty", isDirectory: true)
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)

        let notes = root.appendingPathComponent("notes", isDirectory: true)
        try FileManager.default.createDirectory(at: notes, withIntermediateDirectories: true)
        try Data("# Overview\n".utf8).write(to: notes.appendingPathComponent("overview.markdown"))

        let archive = notes.appendingPathComponent("archive", isDirectory: true)
        try FileManager.default.createDirectory(at: archive, withIntermediateDirectories: true)
        try Data("# Old\n".utf8).write(to: archive.appendingPathComponent("old.mdown"))

        let deep = archive.appendingPathComponent("deep", isDirectory: true)
        try FileManager.default.createDirectory(at: deep, withIntermediateDirectories: true)
        try Data("# Deepest\n".utf8).write(to: deep.appendingPathComponent("deepest.mkd"))

        return root
    }

    @Test func regressionEnumerationThroughRealSecurityScopedBookmarkPopulatesFullFilteredTree() throws {
        // Mirrors the production folder-open flow (RecentDocuments /
        // FolderSession) exactly, via RecentDocuments' own cross-platform
        // bookmark handling (security-scoped on macOS, plain resolution on
        // iOS/iPadOS where .withSecurityScope doesn't exist -- N6): a
        // bookmark is created for the fixture root, resolved, and access
        // is started before MarkdownFolderTree ever sees the URL. Every
        // assertion below is on MarkdownFolderTree.build's live output --
        // it fails outright if enumeration silently returns empty, or if
        // an excluded entry leaks through (N9).
        let root = try makeSandboxedFixture()
        defer { try? FileManager.default.removeItem(at: root) }

        let recents = RecentDocuments(defaults: UserDefaults(suiteName: "markus.folder.sandboxed.\(UUID().uuidString)")!)
        recents.record(url: root, isFolder: true)
        let item = try #require(recents.items.first)
        let resolved = try recents.startAccessing(item)
        defer { recents.stopAccessing(resolved) }

        let tree = MarkdownFolderTree.build(root: resolved)

        let topNames = tree.map(\.name).sorted()
        #expect(topNames == ["index.md", "notes"])
        #expect(!topNames.contains("README.txt"))
        #expect(!topNames.contains(".gitkeep.md"))
        #expect(!topNames.contains(".obsidian"))
        #expect(!topNames.contains("assets"))
        #expect(!topNames.contains("empty"))

        let index = try #require(tree.first { $0.name == "index.md" })
        #expect(!index.isDirectory)
        #expect(index.children.isEmpty)

        let notes = try #require(tree.first { $0.name == "notes" })
        #expect(notes.isDirectory)
        let notesNames = notes.children.map(\.name).sorted()
        #expect(notesNames == ["archive", "overview.markdown"])

        let archive = try #require(notes.children.first { $0.name == "archive" })
        #expect(archive.isDirectory)
        let archiveNames = archive.children.map(\.name).sorted()
        #expect(archiveNames == ["deep", "old.mdown"])

        let deep = try #require(archive.children.first { $0.name == "deep" })
        #expect(deep.isDirectory)
        #expect(deep.children.map(\.name) == ["deepest.mkd"])
        #expect(!deep.children[0].isDirectory)
    }

    @Test func includesMdownAndMkdExtensions() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("markus-tree-ext-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("# A\n".utf8).write(to: root.appendingPathComponent("a.mdown"))
        try Data("# B\n".utf8).write(to: root.appendingPathComponent("b.mkd"))
        try Data("# C\n".utf8).write(to: root.appendingPathComponent("c.MD"))

        let names = MarkdownFolderTree.build(root: root).map(\.name).sorted()
        #expect(names == ["a.mdown", "b.mkd", "c.MD"])
    }
}

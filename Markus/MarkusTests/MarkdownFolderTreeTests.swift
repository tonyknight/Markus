import Foundation
import Testing
@testable import Markus

struct MarkdownFolderTreeTests {
    private func makeFixture() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("markus-tree-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("# Notes\n".utf8).write(to: root.appendingPathComponent("notes.md"))
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

        return root
    }

    @Test func buildsMarkdownOnlyNestedTreeFromFixture() throws {
        let root = try makeFixture()
        defer { try? FileManager.default.removeItem(at: root) }

        let tree = MarkdownFolderTree.build(root: root)
        let names = tree.map(\.name).sorted()
        #expect(names == ["notes.md", "sub"])
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

import Foundation

struct OutlineItem: Equatable, Sendable {
    var title: String
    var sourceLine: Int
    var level: Int
}

enum OutlineJump {
    static func items(from blocks: [Block], markdown: String) -> [OutlineItem] {
        let utf8 = Array(markdown.utf8)
        return blocks.compactMap { block in
            guard case .heading(let level) = block.kind else { return nil }
            let slice = utf8[block.bytes]
            let raw = String(decoding: slice, as: UTF8.self)
            return OutlineItem(
                title: headingTitle(from: raw),
                sourceLine: block.id.startLine,
                level: level
            )
        }
    }

    private static func headingTitle(from raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while text.hasPrefix("#") {
            text.removeFirst()
        }
        return text.trimmingCharacters(in: .whitespaces)
    }
}

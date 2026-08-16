/// Stub parser for RED tests. T02 will wrap cmark-gfm.
struct MarkdownParser {
    func parse(_ markdown: String) -> [MarkdownBlock] {
        _ = markdown
        return []
    }
}

enum MarkdownBlockKind: Equatable {
    case heading(level: Int)
    case fencedCode
    case other
}

struct MarkdownBlock: Equatable {
    var kind: MarkdownBlockKind
}

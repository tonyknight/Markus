enum GFMPreviewFixture {
    static let markdown = """
    # Title

    | Col | Val |
    |-----|-----|
    | a   | b   |

    - [ ] unchecked
    - [x] checked

    Strike ~~gone~~ and `inline` plus a [link](https://example.com).

    Note.[^1]

    [^1]: Footnote body.

    ```swift
    let answer = 42
    ```

    Math is $x$ in prose.

    ```mermaid
    graph TD
      A-->B
    ```
    """
}

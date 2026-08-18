enum GFMPreviewFixture {
    static let markdown = """
    # Title

    ## Subtitle

    A paragraph with **bold** and *italic* words, plus ![a red fox](fox.png) embedded.

    > A block quote with a note inside it.

    ---

    | Col | Val |
    |-----|-----|
    | a   | b   |

    - [ ] unchecked
    - [x] checked
    - Outer item
      - Nested item

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

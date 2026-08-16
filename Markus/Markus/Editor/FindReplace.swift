import Foundation
#if os(macOS)
import AppKit
#else
import UIKit
#endif

enum FindReplace {
    static func search(_ query: String, in storage: NSTextStorage, from location: Int = 0) -> NSRange? {
        guard !query.isEmpty else { return nil }
        let haystack = storage.string as NSString
        let start = min(max(0, location), haystack.length)
        let remainder = NSRange(location: start, length: haystack.length - start)
        let found = haystack.range(of: query, options: [], range: remainder)
        if found.location != NSNotFound {
            return found
        }
        if start > 0 {
            let wrap = haystack.range(of: query, options: [], range: NSRange(location: 0, length: start))
            if wrap.location != NSNotFound {
                return wrap
            }
        }
        return nil
    }

    @discardableResult
    static func replace(_ range: NSRange, with replacement: String, in storage: NSTextStorage) -> Bool {
        guard range.location != NSNotFound, NSMaxRange(range) <= storage.length else { return false }
        storage.beginEditing()
        storage.replaceCharacters(in: range, with: replacement)
        storage.endEditing()
        return true
    }
}

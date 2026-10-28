import Foundation

/// UTF-16 ranges match NSTextView/NSString, including non-ASCII SQL literals.
/// A selection ending at the next line's beginning does not include that line.
public enum SQLLineComments {
    public struct Change: Sendable {
        public let range: NSRange
        public let replacement: String
        public let selections: [NSRange]
    }
    private struct Line {
        let start: Int
        let end: Int
        let contentEnd: Int
        let indentationEnd: Int
    }
    private struct Edit {
        let range: NSRange
        let replacement: String
    }
    public static func change(in source: NSString, selections: [NSRange]) -> Change? {
        let valid = selections.filter { $0.location != NSNotFound && $0.location <= source.length && $0.length <= source.length - $0.location }
        guard !valid.isEmpty else { return nil }
        var lines: [Int: Line] = [:]
        for selection in valid {
            let first = source.lineRange(for: NSRange(location: selection.location, length: 0))
            let lastIndex = selection.length == 0 ? selection.location : NSMaxRange(selection) - 1
            let last = source.lineRange(for: NSRange(location: lastIndex, length: 0))
            var location = first.location
            repeat {
                var start = 0, end = 0, contentEnd = 0
                source.getLineStart(&start, end: &end, contentsEnd: &contentEnd, for: NSRange(location: location, length: 0))
                var indentationEnd = start
                while indentationEnd < contentEnd,
                      source.character(at: indentationEnd) == 32 || source.character(at: indentationEnd) == 9 { indentationEnd += 1 }
                lines[start] = Line(start: start, end: end, contentEnd: contentEnd, indentationEnd: indentationEnd)
                guard end > location else { break }
                location = end
            } while location < NSMaxRange(last)
        }
        let ordered = lines.values.sorted { $0.start < $1.start }
        let nonempty = ordered.filter { $0.indentationEnd < $0.contentEnd }
        let targets = nonempty.isEmpty ? ordered : nonempty
        guard let first = targets.first, let last = targets.last else { return nil }
        let uncomment = targets.allSatisfy {
            $0.indentationEnd + 2 <= $0.contentEnd && source.substring(with: NSRange(location: $0.indentationEnd, length: 2)) == "--"
        }
        let edits = targets.map { line -> Edit in
            if uncomment {
                let following = line.indentationEnd + 2
                let length = following < line.contentEnd && source.character(at: following) == 32 ? 3 : 2
                return Edit(range: NSRange(location: line.indentationEnd, length: length), replacement: "")
            }
            return Edit(range: NSRange(location: line.indentationEnd, length: 0), replacement: "-- ")
        }
        let range = NSRange(location: first.start, length: last.end - first.start)
        let replacement = NSMutableString(string: source.substring(with: range))
        for edit in edits.reversed() {
            replacement.replaceCharacters(in: NSRange(location: edit.range.location - range.location, length: edit.range.length), with: edit.replacement)
        }
        func moved(_ position: Int, beforeInsertion: Bool) -> Int {
            var delta = 0
            for edit in edits {
                if position < edit.range.location { break }
                let added = (edit.replacement as NSString).length
                if edit.range.length == 0 {
                    if position != edit.range.location || !beforeInsertion { delta += added }
                } else if position >= NSMaxRange(edit.range) {
                    delta += added - edit.range.length
                } else { return edit.range.location + delta }
            }
            return position + delta
        }
        let transformed = valid.map { selection in
            let start = moved(selection.location, beforeInsertion: selection.length > 0)
            let end = moved(NSMaxRange(selection), beforeInsertion: false)
            return NSRange(location: start, length: max(0, end - start))
        }
        return Change(range: range, replacement: replacement as String, selections: transformed)
    }
}

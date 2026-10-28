import SwiftUI
import AppKit

enum SQLColors {
    private static let accent = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 0.35, green: 0.81, blue: 0.53, alpha: 1)
            : NSColor(srgbRed: 0.10, green: 0.42, blue: 0.23, alpha: 1)
    }
    static func highlighted(_ sql: String, fontSize: CGFloat = 14) -> NSAttributedString {
        let style = NSMutableParagraphStyle(); style.lineSpacing = 4; style.defaultTabInterval = fontSize * 2.4
        let value = NSMutableAttributedString(string: sql, attributes: [.font: NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular), .foregroundColor: NSColor.textColor, .paragraphStyle: style])
        let words = "SELECT FROM WHERE AND OR NOT NULL AS DISTINCT ORDER BY ASC DESC NULLS FIRST LAST LIMIT OFFSET FETCH WITH RECURSIVE MATERIALIZED INSERT INTO VALUES UPDATE SET DELETE RETURNING ON CONFLICT DO NOTHING CREATE ALTER DROP TABLE VIEW INDEX UNIQUE PRIMARY KEY FOREIGN REFERENCES CHECK DEFAULT GENERATED ALWAYS IDENTITY CONSTRAINT CASCADE RESTRICT GROUP HAVING COUNT SUM AVG MIN MAX FILTER OVER PARTITION ROWS RANGE GROUPS BETWEEN UNBOUNDED PRECEDING FOLLOWING CURRENT ROW EXCLUDE TIES INNER LEFT RIGHT FULL OUTER CROSS JOIN USING EXISTS IN IS LIKE ILIKE SIMILAR TO CASE WHEN THEN ELSE END CAST UNION ALL INTERSECT EXCEPT LATERAL WINDOW BEGIN COMMIT ROLLBACK SAVEPOINT RELEASE TRANSACTION ISOLATION LEVEL SERIALIZABLE REPEATABLE READ COMMITTED FOR SHARE NOWAIT SKIP LOCKED TRUNCATE EXPLAIN ANALYZE VACUUM VERBOSE BUFFERS FORMAT TRUE FALSE BOOLEAN INTEGER INT BIGINT SMALLINT NUMERIC DECIMAL TEXT VARCHAR DATE TIMESTAMP TIMESTAMPTZ INTERVAL JSON JSONB ARRAY UUID REAL DOUBLE PRECISION ENUM TYPE FUNCTION PROCEDURE TRIGGER RETURNS LANGUAGE PLPGSQL SQL DECLARE IF LOOP WHILE RAISE EXECUTE PERFORM NEW OLD BEFORE AFTER EACH STATEMENT OF CALL GRANT REVOKE ROLE PUBLIC SEQUENCE COALESCE NULLIF GREATEST LEAST ROUND LOWER UPPER LENGTH SUBSTRING CONCAT NOW DATE_TRUNC EXTRACT RANK DENSE_RANK ROW_NUMBER LAG LEAD FIRST_VALUE LAST_VALUE NTH_VALUE NTILE PERCENT_RANK CUME_DIST STRING_AGG ARRAY_AGG JSONB_AGG BOOL_AND BOOL_OR ROLLUP CUBE GROUPING SETS TO_TSVECTOR TO_TSQUERY WEBSEARCH_TO_TSQUERY GIN GIST BRIN HASH BTREE"
        let keywords = Set(words.split(separator: " ").map(String.init))
        let source = sql as NSString
        let units = Array(sql.utf16)
        let count = units.count
        func letter(_ c: UInt16) -> Bool { (65...90).contains(c) || (97...122).contains(c) || c == 95 || c > 127 }
        func digit(_ c: UInt16) -> Bool { (48...57).contains(c) }
        func identifier(_ c: UInt16) -> Bool { letter(c) || digit(c) || c == 36 }
        var i = 0
        while i < count {
            let start = i
            let c = units[i]
            var color: NSColor?
            if c == 45, i + 1 < count, units[i + 1] == 45 {
                i += 2
                while i < count, units[i] != 10 { i += 1 }
                color = .secondaryLabelColor
            } else if c == 47, i + 1 < count, units[i + 1] == 42 {
                i += 2; var depth = 1
                while i < count, depth > 0 {
                    if i + 1 < count, units[i] == 47, units[i + 1] == 42 { depth += 1; i += 2 }
                    else if i + 1 < count, units[i] == 42, units[i + 1] == 47 { depth -= 1; i += 2 }
                    else { i += 1 }
                }
                color = .secondaryLabelColor
            } else if c == 39 || c == 34 {
                let escape = c == 39 && i > 0 && (units[i - 1] == 69 || units[i - 1] == 101) && (i < 2 || !identifier(units[i - 2]))
                i += 1
                while i < count {
                    if escape, units[i] == 92 { i = min(count, i + 2) }
                    else if units[i] == c {
                        i += 1
                        if i < count, units[i] == c { i += 1 } else { break }
                    } else { i += 1 }
                }
                color = c == 39 ? .secondaryLabelColor : .textColor
            } else if c == 36 {
                var end = i + 1
                if end < count, letter(units[end]) {
                    end += 1
                    while end < count, letter(units[end]) || digit(units[end]) { end += 1 }
                }
                if end < count, units[end] == 36 {
                    let delimiter = source.substring(with: NSRange(location: i, length: end - i + 1))
                    let search = NSRange(location: end + 1, length: count - end - 1)
                    let close = source.range(of: delimiter, range: search)
                    i = close.location == NSNotFound ? count : NSMaxRange(close)
                    color = .secondaryLabelColor
                } else { i += 1 }
            } else if letter(c) {
                i += 1; while i < count, identifier(units[i]) { i += 1 }
                if keywords.contains(source.substring(with: NSRange(location: start, length: i - start)).uppercased()) { color = accent }
            } else if digit(c) {
                i += 1; while i < count, digit(units[i]) { i += 1 }
                if i < count, units[i] == 46 { i += 1; while i < count, digit(units[i]) { i += 1 } }
                if i < count, units[i] == 69 || units[i] == 101 {
                    i += 1
                    if i < count, units[i] == 43 || units[i] == 45 { i += 1 }
                    while i < count, digit(units[i]) { i += 1 }
                }
                color = accent
            } else { i += 1 }
            if let color { value.addAttribute(.foregroundColor, value: color, range: NSRange(location: start, length: i - start)) }
        }
        return value
    }
}

struct SQLEditor: NSViewRepresentable {
    @Binding var text: String
    var fontSize: CGFloat
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true; scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true; scroll.borderType = .noBorder
        // AppKit rulers may paint outside their scroll view unless its layer
        // clips drawing. Keep the gutter inside the editor, below its header.
        scroll.wantsLayer = true; scroll.layer?.masksToBounds = true
        scroll.drawsBackground = true; scroll.backgroundColor = .sqllyCanvas
        let view = SQLTextView(frame: .zero)
        view.isRichText = false; view.allowsUndo = true; view.isAutomaticQuoteSubstitutionEnabled = false
        view.isAutomaticDashSubstitutionEnabled = false; view.isAutomaticTextReplacementEnabled = false
        view.isAutomaticSpellingCorrectionEnabled = false
        view.isGrammarCheckingEnabled = false; view.usesFindBar = true; view.isIncrementalSearchingEnabled = true
        view.isContinuousSpellCheckingEnabled = false
        view.minSize = NSSize(width: 0, height: 0); view.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        view.isVerticallyResizable = true; view.isHorizontallyResizable = true
        view.autoresizingMask = [.width]
        view.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        view.textContainer?.widthTracksTextView = false
        view.textContainerInset = NSSize(width: 14, height: 14)
        view.backgroundColor = .sqllyCanvas; view.insertionPointColor = .controlAccentColor
        view.setAccessibilityLabel(L.text("PostgreSQL code editor"))
        view.delegate = context.coordinator
        scroll.documentView = view
        let ruler = LineNumberRuler(textView: view)
        scroll.verticalRulerView = ruler; scroll.hasVerticalRuler = true; scroll.rulersVisible = true
        context.coordinator.textView = view; context.coordinator.ruler = ruler
        context.coordinator.apply(text, fontSize: fontSize)
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let view = context.coordinator.textView else { return }
        if view.string != text || context.coordinator.fontSize != fontSize { context.coordinator.apply(text, fontSize: fontSize) }
    }
    @MainActor final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: SQLEditor
        weak var textView: NSTextView?
        weak var ruler: LineNumberRuler?
        var applying = false
        var fontSize: CGFloat = 14
        init(_ parent: SQLEditor) { self.parent = parent }
        func apply(_ text: String, fontSize: CGFloat) {
            guard let view = textView else { return }
            self.fontSize = fontSize
            applying = true
            let selected = view.selectedRanges
            view.textStorage?.setAttributedString(SQLColors.highlighted(text, fontSize: fontSize))
            let length = (text as NSString).length
            view.selectedRanges = selected.map { NSValue(range: NSRange(location: min($0.rangeValue.location, length), length: min($0.rangeValue.length, max(0, length - $0.rangeValue.location)))) }
            view.typingAttributes = [.font: NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular), .foregroundColor: NSColor.textColor]
            applying = false; ruler?.needsDisplay = true
        }
        func textDidChange(_ notification: Notification) {
            guard !applying, let view = textView else { return }
            let value = view.string
            parent.text = value
            apply(value, fontSize: parent.fontSize)
        }
    }
}

@MainActor final class SQLTextView: NSTextView {
    override func insertTab(_ sender: Any?) { insertText("    ", replacementRange: selectedRange()) }
    override func insertNewline(_ sender: Any?) {
        let text = string as NSString
        let range = text.lineRange(for: NSRange(location: min(selectedRange().location, text.length), length: 0))
        let line = text.substring(with: range)
        let indent = String(line.prefix { $0 == " " || $0 == "\t" })
        insertText("\n" + indent, replacementRange: selectedRange())
    }
}

@MainActor final class LineNumberRuler: NSRulerView {
    weak var editor: NSTextView?
    init(textView: NSTextView) {
        editor = textView
        super.init(scrollView: textView.enclosingScrollView, orientation: .verticalRuler)
        clientView = textView; ruleThickness = 42
    }
    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let editor, let layout = editor.layoutManager, let container = editor.textContainer else { return }
        NSColor.sqllySurface.setFill(); bounds.fill()
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular), .foregroundColor: NSColor.secondaryLabelColor]
        let text = editor.string as NSString
        let visible = editor.visibleRect
        let glyphRange = layout.glyphRange(forBoundingRect: visible, in: container)
        var glyph = glyphRange.location
        var line = 1
        if glyph > 0 {
            let character = layout.characterIndexForGlyph(at: glyph)
            line += text.substring(to: min(character, text.length)).filter { $0 == "\n" }.count
        }
        while glyph < NSMaxRange(glyphRange), glyph < layout.numberOfGlyphs {
            var effective = NSRange()
            let fragment = layout.lineFragmentRect(forGlyphAt: glyph, effectiveRange: &effective)
            let value = "\(line)" as NSString
            let y = fragment.minY + editor.textContainerOrigin.y - visible.minY + 2
            value.draw(at: NSPoint(x: ruleThickness - value.size(withAttributes: attrs).width - 9, y: y), withAttributes: attrs)
            line += 1; glyph = NSMaxRange(effective)
        }
        if text.length == 0 { ("1" as NSString).draw(at: NSPoint(x: 26, y: 16), withAttributes: attrs) }
    }
}

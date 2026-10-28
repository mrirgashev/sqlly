import AppKit
import SwiftUI
import Testing
@testable import SQLLY

@MainActor @Suite(.serialized)
struct SQLEditorTests {
    @Test func consecutiveLineCommentCommandsPreserveSelectionAndBinding() {
        _ = NSApplication.shared
        let original = "SELECT '🙂привет' AS greeting;\n  SELECT '東京' AS place;\n"
        let commented = "-- SELECT '🙂привет' AS greeting;\n  -- SELECT '東京' AS place;\n"
        let state = EditorState(original)
        let editor = SQLEditor(text: Binding(get: { state.text }, set: { state.text = $0 }), fontSize: 14)
        let coordinator = SQLEditor.Coordinator(editor)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let textView = SQLTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        textView.isRichText = false
        textView.allowsUndo = true
        textView.delegate = coordinator
        coordinator.textView = textView
        window.contentView = textView
        window.makeFirstResponder(textView)
        coordinator.apply(original, fontSize: 14)
        let originalSelection = NSRange(location: 0, length: (original as NSString).length)
        textView.setSelectedRange(originalSelection)

        textView.toggleSQLLineComments(nil)
        #expect(textView.string == commented)
        #expect(state.text == commented)
        #expect(textView.selectedRanges.map(\.rangeValue) == [NSRange(location: 0, length: (commented as NSString).length)])

        // This must act on the same selected lines, rather than an EOF caret
        // left behind by NSTextView's mutable backing string and highlighting.
        textView.toggleSQLLineComments(nil)
        #expect(textView.string == original)
        #expect(state.text == original)
        #expect(textView.selectedRanges.map(\.rangeValue) == [originalSelection])
    }

    @MainActor private final class EditorState {
        var text: String
        init(_ text: String) { self.text = text }
    }
}

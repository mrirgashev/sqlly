import SwiftUI
import AppKit

/// Handles curriculum navigation and editor focus in the workspace window.
struct WorkspaceKeyboardNavigation: NSViewRepresentable {
    var model: WorkspaceModel
    var focusRequest: Int

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }
    func makeNSView(context: Context) -> NSView {
        let view = TaskNavigationTarget(frame: .zero)
        view.setAccessibilityElement(true)
        view.setAccessibilityRole(.group)
        view.setAccessibilityLabel(L.text("Task navigation"))
        context.coordinator.view = view
        context.coordinator.install()
        return view
    }
    func updateNSView(_ view: NSView, context: Context) {
        context.coordinator.model = model
        context.coordinator.receiveFocusRequest(focusRequest)
    }
    static func dismantleNSView(_ view: NSView, coordinator: Coordinator) { coordinator.remove() }

    @MainActor final class TaskNavigationTarget: NSView {
        override var acceptsFirstResponder: Bool { true }
    }

    @MainActor final class Coordinator {
        var model: WorkspaceModel
        weak var view: NSView?
        private var monitor: Any?
        private var lastFocusRequest: Int
        init(model: WorkspaceModel) {
            self.model = model
            lastFocusRequest = model.taskFocusRequest
        }

        func receiveFocusRequest(_ request: Int) {
            receiveFocusRequest(request, keyWindow: NSApp.keyWindow)
        }

        func receiveFocusRequest(_ request: Int, keyWindow: NSWindow?) {
            guard request != lastFocusRequest else { return }
            lastFocusRequest = request
            guard let window = view?.window, window === keyWindow,
                  window.attachedSheet == nil,
                  !model.showStatistics, !model.showHistory, !model.showHelp else { return }
            moveFocusToTaskSection()
        }

        @discardableResult func moveFocusToTaskSection() -> Bool {
            guard let view, let window = view.window else { return false }
            return window.makeFirstResponder(view)
        }

        func install() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard Thread.isMainThread else { return event }
                // Pass only Sendable scalar values into the actor-isolated
                // decision; NSEvent itself remains in AppKit's event handler.
                let code = event.keyCode
                let modifiers = event.modifierFlags.rawValue
                let number = event.windowNumber
                let character = event.characters?.lowercased() == "e" ? "e" : event.charactersIgnoringModifiers
                let handled = MainActor.assumeIsolated {
                    self?.handleKey(keyCode: code, character: character, modifiers: modifiers, windowNumber: number, keyWindow: NSApp.keyWindow) ?? false
                }
                return handled ? nil : event
            }
        }
        func remove() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }
        func handleKey(keyCode: UInt16, character: String? = nil, modifiers: UInt, windowNumber: Int, keyWindow: NSWindow?) -> Bool {
            let flags = NSEvent.ModifierFlags(rawValue: modifiers).intersection([.command, .option, .control, .shift])
            let focusEditor = flags == .command && character?.lowercased() == "e"
            let navigate = flags.isEmpty && (keyCode == 123 || keyCode == 124)
            guard focusEditor || navigate,
                  let window = view?.window, window === keyWindow,
                  window.windowNumber == windowNumber, window.attachedSheet == nil,
                  !model.showStatistics, !model.showHistory, !model.showHelp else { return false }
            if focusEditor {
                guard model.requiresCodeEditor, model.inspectorVisible,
                      let content = window.contentView, let editor = editor(in: content) else { return false }
                if window.firstResponder === editor { return true }
                guard window.makeFirstResponder(editor), window.firstResponder === editor else { return false }
                editor.selectAll(nil)
                return true
            }
            if let responder = window.firstResponder {
                if let text = responder as? NSTextView,
                   text.isEditable || text.hasMarkedText() || text.selectedRange().length > 0 { return false }
                if responder is NSTextField || responder is NSSlider || responder is NSComboBox { return false }
            }
            model.navigate(keyCode == 123 ? -1 : 1)
            return true
        }

        private func editor(in view: NSView) -> SQLTextView? {
            guard !view.isHidden else { return nil }
            if let editor = view as? SQLTextView { return editor }
            for subview in view.subviews {
                if let editor = editor(in: subview) { return editor }
            }
            return nil
        }
    }
}

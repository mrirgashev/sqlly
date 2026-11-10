import SwiftUI
import AppKit

/// Plain arrows navigate the curriculum only in the workspace window. Text
/// editors, field editors, open sheets, and modified arrow keys retain their
/// native behavior. Course-wide ordering is owned by WorkspaceModel.navigate.
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
                let handled = MainActor.assumeIsolated {
                    self?.navigate(keyCode: code, modifiers: modifiers, windowNumber: number) ?? false
                }
                return handled ? nil : event
            }
        }
        func remove() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }
        func navigate(keyCode: UInt16, modifiers: UInt, windowNumber: Int) -> Bool {
            navigate(keyCode: keyCode, modifiers: modifiers, windowNumber: windowNumber, keyWindow: NSApp.keyWindow)
        }

        func navigate(keyCode: UInt16, modifiers: UInt, windowNumber: Int, keyWindow: NSWindow?) -> Bool {
            guard keyCode == 123 || keyCode == 124,
                  NSEvent.ModifierFlags(rawValue: modifiers).intersection([.command, .option, .control, .shift]).isEmpty,
                  let window = view?.window, window === keyWindow,
                  window.windowNumber == windowNumber, window.attachedSheet == nil,
                  !model.showStatistics, !model.showHistory, !model.showHelp else { return false }
            if let responder = window.firstResponder {
                if let text = responder as? NSTextView,
                   text.isEditable || text.hasMarkedText() || text.selectedRange().length > 0 { return false }
                if responder is NSTextField || responder is NSSlider || responder is NSComboBox { return false }
            }
            model.navigate(keyCode == 123 ? -1 : 1)
            return true
        }
    }
}

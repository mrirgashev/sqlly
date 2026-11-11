import AppKit
import SQLCore
import Testing
@testable import SQLLY

@MainActor @Suite(.serialized)
struct WorkspaceKeyboardTests {
    @Test func editorCommandReturnSubmitsWithoutInsertingText() throws {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let editor = SQLTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        editor.string = "SELECT * FROM customers;"
        var submitted = 0
        editor.onSubmit = { submitted += 1 }
        window.contentView = editor
        #expect(window.makeFirstResponder(editor))

        let enter = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero,
            modifierFlags: [.command], timestamp: 0, windowNumber: window.windowNumber,
            context: nil, characters: "\r", charactersIgnoringModifiers: "\r",
            isARepeat: false, keyCode: 36))
        #expect(editor.performKeyEquivalent(with: enter))
        #expect(submitted == 1)
        #expect(editor.string == "SELECT * FROM customers;")

        let keypadEnter = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero,
            modifierFlags: [.command, .numericPad], timestamp: 0, windowNumber: window.windowNumber,
            context: nil, characters: "\u{3}", charactersIgnoringModifiers: "\u{3}",
            isARepeat: false, keyCode: 76))
        #expect(editor.performKeyEquivalent(with: keypadEnter))
        #expect(submitted == 2)

        let modifiedEnter = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero,
            modifierFlags: [.command, .option], timestamp: 0, windowNumber: window.windowNumber,
            context: nil, characters: "\r", charactersIgnoringModifiers: "\r",
            isARepeat: false, keyCode: 36))
        _ = editor.performKeyEquivalent(with: modifiedEnter)
        #expect(submitted == 2)
    }

    @Test func acceptedSubmissionFocusResumesArrowNavigationAcrossTopics() async throws {
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("SQLLY-TaskFocus-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let model = WorkspaceModel(progressStore: try ProgressStore(url: root.appendingPathComponent("progress.sqlite")),
                                   practiceEngine: PostgresEngine(baseURL: root.appendingPathComponent("engine")))
        let course = try #require(model.course)
        let exerciseStep = try #require(course.steps.first(where: { $0.exercise != nil }))
        let exerciseIndex = try #require(course.steps.firstIndex(where: { $0.id == exerciseStep.id }))
        model.select(exerciseStep.id)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        let editor = SQLTextView(frame: container.bounds)
        let taskTarget = WorkspaceKeyboardNavigation.TaskNavigationTarget(frame: .zero)
        container.addSubview(editor)
        container.addSubview(taskTarget)
        window.contentView = container
        #expect(window.makeFirstResponder(editor))
        let coordinator = WorkspaceKeyboardNavigation.Coordinator(model: model)
        coordinator.view = taskTarget

        // Headless test runners do not provide NSApp.keyWindow. Supply this
        // test window to the same decision used by the native event monitor.
        #expect(!coordinator.handleKey(keyCode: 124, modifiers: 0, windowNumber: window.windowNumber, keyWindow: window))
        #expect(model.selection == exerciseStep.id)
        coordinator.receiveFocusRequest(model.taskFocusRequest, keyWindow: window)
        #expect(window.firstResponder === editor)
        model.taskFocusRequest &+= 1
        coordinator.receiveFocusRequest(model.taskFocusRequest, keyWindow: window)
        #expect(window.firstResponder === taskTarget)
        editor.string = "SELECT '🐘';"
        editor.setSelectedRange(NSRange(location: 1, length: 0))
        let command = NSEvent.ModifierFlags.command.rawValue
        #expect(coordinator.handleKey(keyCode: 14, character: "e", modifiers: command, windowNumber: window.windowNumber, keyWindow: window))
        #expect(window.firstResponder === editor)
        #expect(editor.selectedRange() == NSRange(location: 0, length: (editor.string as NSString).length))

        let caret = NSRange(location: 3, length: 0)
        editor.setSelectedRange(caret)
        #expect(coordinator.handleKey(keyCode: 14, character: "e", modifiers: command, windowNumber: window.windowNumber, keyWindow: window))
        #expect(editor.selectedRange() == caret)
        #expect(window.makeFirstResponder(taskTarget))
        model.inspectorVisible = false
        #expect(!coordinator.handleKey(keyCode: 14, character: "e", modifiers: command, windowNumber: window.windowNumber, keyWindow: window))
        #expect(window.firstResponder === taskTarget)
        model.inspectorVisible = true

        #expect(!coordinator.handleKey(keyCode: 124, modifiers: 0, windowNumber: window.windowNumber, keyWindow: nil))
        #expect(model.selection == exerciseStep.id)
        #expect(coordinator.handleKey(keyCode: 124, modifiers: 0, windowNumber: window.windowNumber, keyWindow: window))
        #expect(model.selection == course.steps[exerciseIndex + 1].id)
        #expect(coordinator.handleKey(keyCode: 123, modifiers: 0, windowNumber: window.windowNumber, keyWindow: window))
        #expect(model.selection == exerciseStep.id)
        #expect(!coordinator.handleKey(keyCode: 124, modifiers: NSEvent.ModifierFlags.command.rawValue, windowNumber: window.windowNumber, keyWindow: window))
        #expect(model.selection == exerciseStep.id)

        let firstTopicLastStep = try #require(course.modules.first?.lessons.flatMap(\.steps).last)
        let nextTopicFirstStep = try #require(course.modules.dropFirst().first?.lessons.first?.steps.first)
        model.select(firstTopicLastStep.id)
        #expect(coordinator.handleKey(keyCode: 124, modifiers: 0, windowNumber: window.windowNumber, keyWindow: window))
        #expect(model.selection == nextTopicFirstStep.id)

        // A request received while help is open must not steal focus later
        // when an unrelated view update happens after help is dismissed.
        #expect(window.makeFirstResponder(editor))
        model.showHelp = true
        model.taskFocusRequest &+= 1
        coordinator.receiveFocusRequest(model.taskFocusRequest, keyWindow: window)
        #expect(window.firstResponder === editor)
        model.showHelp = false
        coordinator.receiveFocusRequest(model.taskFocusRequest, keyWindow: window)
        #expect(window.firstResponder === editor)
        await model.shutdown()
    }

    @Test func completionOutlineKeepsTheOriginalStepIcon() throws {
        let course = try Curriculum.load()
        let reading = try #require(course.steps.first(where: { $0.exercise == nil }))
        let exercise = try #require(course.steps.first(where: { $0.exercise != nil }))
        var progress = StepProgress()
        progress.visits = 1
        let untouched = LessonStepButton(index: 0, step: reading, selected: true, progress: progress, action: {})
        #expect(untouched.symbol == "book")
        #expect(!untouched.completedSuccessfully)
        progress.completed = true
        let completed = LessonStepButton(index: 0, step: reading, selected: true, progress: progress, action: {})
        #expect(completed.symbol == "book")
        #expect(completed.completedSuccessfully)
        progress.review = true
        let mistaken = LessonStepButton(index: 1, step: exercise, selected: false, progress: progress, action: {})
        #expect(mistaken.symbol == "chevron.left.forwardslash.chevron.right")
        #expect(!mistaken.completedSuccessfully)
    }
}

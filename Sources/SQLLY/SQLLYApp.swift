import SwiftUI
import AppKit

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var workspace: WorkspaceModel?
    private var terminating = false
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        NativeMenus.refresh()
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let workspace, !terminating else { return .terminateNow }
        terminating = true
        Task { await workspace.shutdown(); sender.reply(toApplicationShouldTerminate: true) }
        return .terminateLater
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

@main struct SQLLYApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = WorkspaceModel()
    @AppStorage("appearance") private var appearance = "Dark"
    @AppStorage("language") private var language = "en"
    private var scheme: ColorScheme? { appearance == "Dark" ? .dark : appearance == "Light" ? .light : nil }
    var body: some Scene {
        Window("SQLLY", id: "workspace") {
            WorkspaceView(model: model)
                .controlSize(.large)
                .frame(minWidth: 1100, minHeight: 700)
                .preferredColorScheme(scheme)
                .environment(\.locale, Locale(identifier: language))
                .task { delegate.workspace = model; NativeMenus.refresh(); await model.start() }
                .onChange(of: language) { _, value in
                    model.setLanguage(value)
                    Task { @MainActor in await Task.yield(); NativeMenus.refresh() }
                }
        }
        .defaultSize(width: 1480, height: 930)
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(after: .importExport) {
                Button(L.text("Export Learning Progress…"), action: model.exportProgress).keyboardShortcut("e", modifiers: [.command, .shift])
                Button(L.text("Import Learning Progress…"), action: model.importProgress)
            }
            CommandMenu(L.text("Learn")) {
                Button(L.text("Run Query")) { Task { await model.run() } }.keyboardShortcut(.return, modifiers: .command).disabled(!model.engineReady || model.isRunning)
                Button(L.text("Submit Answer")) { Task { await model.run(submit: true) } }.keyboardShortcut(.return, modifiers: [.command, .shift]).disabled(model.isRunning || model.currentExercise == nil)
                Toggle(L.text("Live execution"), isOn: $model.liveEnabled)
                Divider()
                Button(L.text("Previous Step")) { model.navigate(-1) }.keyboardShortcut("[", modifiers: .command)
                Button(L.text("Next Step")) { model.navigate(1) }.keyboardShortcut("]", modifiers: .command)
                Button(L.text("Next Incomplete Exercise"), action: model.nextIncomplete).keyboardShortcut("n", modifiers: [.command, .shift])
                Divider()
                Button(L.text("Bookmark Step")) { model.toggle(\.bookmarked) }.keyboardShortcut("b", modifiers: [.command, .shift])
                Button(L.text("Mark for Review")) { model.toggle(\.review) }
                Button(L.text("Reset Code and Dataset"), action: model.reset)
                Button(L.text("Learning Center…")) { model.learningCenterTab = .activity; model.showStatistics = true }.keyboardShortcut("l", modifiers: [.command, .shift])
                Button(L.text("Attempt History…")) { model.learningCenterTab = .history; model.showStatistics = true }
            }
            CommandGroup(replacing: .help) { Button(L.text("SQLLY Help")) { model.showHelp = true } }
        }
        Settings {
            PreferencesView().frame(width: 470).padding(20)
                .controlSize(.large)
                .preferredColorScheme(scheme).environment(\.locale, Locale(identifier: language))
        }
    }
}

struct PreferencesView: View {
    @AppStorage("appearance") private var appearance = "Dark"
    @AppStorage("language") private var language = "en"
    @AppStorage("editorFontSize") private var fontSize = 14.0
    var body: some View {
        Form {
            Picker(L.text("Language"), selection: $language) { Text("English").tag("en"); Text("Русский").tag("ru") }
            Picker(L.text("Appearance"), selection: $appearance) {
                Text(L.text("Dark")).tag("Dark"); Text(L.text("Light")).tag("Light"); Text(L.text("System")).tag("System")
            }
            HStack { Text(L.text("Editor text size")); Slider(value: $fontSize, in: 11...22, step: 1); Text(L.format("%ld pt", Int(fontSize))).monospacedDigit().frame(width: 48) }
            Text(L.text("SQLLY runs PostgreSQL locally. Course content, queries, and learning progress stay on this Mac.")).font(.callout).foregroundStyle(.secondary)
        }.formStyle(.grouped)
            .onChange(of: language) { _, _ in Task { @MainActor in await Task.yield(); NativeMenus.refresh() } }
    }
}

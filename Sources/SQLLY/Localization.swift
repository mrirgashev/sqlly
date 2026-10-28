import Foundation
import AppKit
import SQLCore

/// Explicit language selection uses bundled localization resources and works offline.
enum L {
    static var language: String { UserDefaults.standard.string(forKey: "language") == "ru" ? "ru" : "en" }
    static func text(_ key: String, language: String = L.language) -> String {
        guard let path = Bundle.module.path(forResource: language, ofType: "lproj"),
              let bundle = Bundle(path: path) else { return key }
        return bundle.localizedString(forKey: key, value: key, table: nil)
    }
    static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: text(key), locale: Locale(identifier: language), arguments: arguments)
    }
    static func message(_ value: String) -> String {
        let core = CoreText.message(value, language: CourseLanguage(rawValue: language) ?? .english)
        if core != value { return core }
        let translated = text(value)
        if translated != value || language == "en" { return translated }
        if value.hasPrefix("PostgreSQL "), value.hasSuffix(" · Local") {
            return value.replacingOccurrences(of: " · Local", with: " · Локально")
        }
        func capture(_ pattern: String) -> String? {
            guard let expression = try? NSRegularExpression(pattern: pattern),
                  let match = expression.firstMatch(in: value, range: NSRange(location: 0, length: (value as NSString).length)),
                  match.numberOfRanges > 1 else { return nil }
            return (value as NSString).substring(with: match.range(at: 1))
        }
        if let path = capture(#"^The progress database was damaged\. It was preserved at (.+)\. A new database was created; you can import an exported backup\.$"#) {
            return format("The progress database was damaged. It was preserved at %@. A new database was created; you can import an exported backup.", path)
        }
        if let version = capture(#"^Unsupported backup format version (-?\d+)\.$"#) {
            return format("Unsupported backup format version %@.", version)
        }
        if let separator = value.range(of: ": ") {
            let context = String(value[..<separator.lowerBound])
            let localized = text(context)
            if localized != context { return localized + ": " + value[separator.upperBound...] }
        }
        return value
    }
}

extension NSColor {
    static let sqllyCanvas = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .black : .white
    }
    static let sqllySurface = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 0.065, green: 0.069, blue: 0.067, alpha: 1)
            : NSColor(srgbRed: 0.965, green: 0.969, blue: 0.965, alpha: 1)
    }
}

/// SwiftUI's standard AppKit menus follow the operating-system language.
/// Keep their titles in sync with SQLLY's explicit in-app language selection.
@MainActor enum NativeMenus {
    private static let observer = NativeMenuObserver()
    private static var observersInstalled = false
    private static var pendingRefresh: Task<Void, Never>?
    private static var isRefreshing = false
    private static let observedMenus = NSHashTable<NSMenu>.weakObjects()
    static func refresh() {
        installObservers()
        applyTitles()
    }
    private static func installObservers() {
        guard !observersInstalled else { return }
        observersInstalled = true
        for name in [NSMenu.didAddItemNotification, NSMenu.didChangeItemNotification, NSMenu.didRemoveItemNotification, NSMenu.didBeginTrackingNotification] {
            NotificationCenter.default.addObserver(observer, selector: #selector(NativeMenuObserver.menuChanged(_:)), name: name, object: nil)
        }
    }
    fileprivate static func didObserve(_ menu: NSMenu?) {
        if let menu { observedMenus.add(menu) }
        scheduleRefresh()
    }
    private static func scheduleRefresh() {
        guard !isRefreshing else { return }
        pendingRefresh?.cancel()
        pendingRefresh = Task { @MainActor in
            do { try await Task.sleep(for: .milliseconds(40)) } catch { return }
            guard !Task.isCancelled else { return }
            pendingRefresh = nil
            applyTitles()
        }
    }
    private static func applyTitles() {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        let keys = ["File", "Edit", "View", "Window", "Help", "About SQLLY", "Settings…", "Services",
                    "Hide SQLLY", "Hide Others", "Show All", "Quit SQLLY", "Close", "Close All",
                    "Undo", "Redo", "Cut", "Copy", "Paste", "Paste and Match Style", "Delete", "Select All",
                    "Find", "Find…", "Find and Replace…", "Find Next", "Find Previous", "Use Selection for Find",
                    "Jump to Selection", "Spelling and Grammar", "Substitutions", "Transformations", "Speech",
                    "Start Speaking", "Stop Speaking", "Minimize", "Zoom", "Bring All to Front",
                    "Enter Full Screen", "Exit Full Screen", "Show Sidebar", "Hide Sidebar",
                    "Show Toolbar", "Hide Toolbar", "Customize Toolbar…",
                    "Undo Typing", "Redo Typing", "Undo Paste", "Redo Paste", "Undo Cut", "Redo Cut", "Undo Delete", "Redo Delete",
                    "Show Spelling and Grammar", "Check Document Now", "Check Spelling While Typing", "Check Grammar With Spelling",
                    "Correct Spelling Automatically", "Show Substitutions", "Smart Quotes", "Smart Dashes", "Smart Links",
                    "Data Detectors", "Text Replacement", "Make Upper Case", "Make Lower Case", "Capitalize",
                    "Writing Tools", "Show Writing Tools", "Complete", "Emoji & Symbols"]
        let russian = Bundle.module.path(forResource: "ru", ofType: "lproj").flatMap(Bundle.init(path:))
        var aliases: [String: String] = [:]
        for key in keys {
            aliases[key] = key
            if let russian { aliases[russian.localizedString(forKey: key, value: key, table: nil)] = key }
        }
        func visit(_ menu: NSMenu) {
            // AppKit renders top-level menu-bar names from NSMenu.title,
            // rather than from the parent NSMenuItem's title.
            if let key = aliases[menu.title] {
                let translated = L.text(key)
                if menu.title != translated { menu.title = translated }
            }
            for item in menu.items {
                if let key = aliases[item.title] {
                    let translated = L.text(key)
                    if item.title != translated { item.title = translated }
                }
                if let submenu = item.submenu { visit(submenu) }
            }
        }
        if let menu = NSApp.mainMenu { visit(menu) }
        for menu in observedMenus.allObjects { visit(menu) }
        for window in NSApp.windows where window.identifier?.rawValue.contains("Settings") == true {
            let title = L.text("SQLLY Settings")
            if window.title != title { window.title = title }
        }
    }
}

/// AppKit menu mutations and their notifications are delivered on the main
/// thread. A selector observer avoids transferring Foundation.Notification
/// (whose userInfo can be non-Sendable) into an actor-isolated closure.
@MainActor private final class NativeMenuObserver: NSObject {
    @objc func menuChanged(_ notification: Notification) {
        NativeMenus.didObserve(notification.object as? NSMenu)
    }
}

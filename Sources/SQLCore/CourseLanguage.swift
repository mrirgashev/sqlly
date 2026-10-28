import Foundation

public enum CourseLanguage: String, CaseIterable, Codable, Sendable {
    case english = "en"
    case russian = "ru"
}

public enum CoreText {
    public static func text(_ key: String, language: CourseLanguage = .english) -> String {
        guard let path = Bundle.module.path(forResource: language.rawValue, ofType: "lproj", inDirectory: "Resources"),
              let bundle = Bundle(path: path) else { return key }
        return bundle.localizedString(forKey: key, value: key, table: "Core")
    }
    public static func format(_ key: String, language: CourseLanguage = .english, _ arguments: CVarArg...) -> String {
        String(format: text(key, language: language), locale: Locale(identifier: language.rawValue), arguments: arguments)
    }

    /// Translates persisted English feedback without rewriting old attempts.
    public static func message(_ value: String, language: CourseLanguage) -> String {
        guard language == .russian else { return value }
        let exact = text(value, language: language)
        if exact != value { return exact }
        func groups(_ pattern: String) -> [String]? {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: value, range: NSRange(location: 0, length: (value as NSString).length)) else { return nil }
            return (1..<match.numberOfRanges).map { (value as NSString).substring(with: match.range(at: $0)) }
        }
        if let g = groups(#"^Expected (\d+) columns, but your query returned (\d+)\. Check the SELECT list\.$"#) {
            return format("Expected %ld columns, but your query returned %ld. Check the SELECT list.", language: language, Int(g[0]) ?? 0, Int(g[1]) ?? 0)
        }
        if let g = groups(#"^Expected (\d+) rows, but your query returned (\d+)\. Check filters, JOIN cardinality, and duplicates\.$"#) {
            return format("Expected %ld rows, but your query returned %ld. Check filters, JOIN cardinality, and duplicates.", language: language, Int(g[0]) ?? 0, Int(g[1]) ?? 0)
        }
        if let g = groups(#"^Column names must be (.+)\. Check your aliases and column order\.$"#) {
            return format("Column names must be %@. Check your aliases and column order.", language: language, g[0])
        }
        if let g = groups(#"^(.+) Fixture (\d+) of (\d+)\.$"#) {
            return format("%@ Fixture %ld of %ld.", language: language, message(g[0], language: language), Int(g[1]) ?? 0, Int(g[2]) ?? 0)
        }
        if let g = groups(#"^Correct across all (\d+) datasets\. (.+)$"#) {
            return format("Correct across all %ld datasets. %@", language: language, Int(g[0]) ?? 0, message(g[1], language: language))
        }
        if let g = groups(#"^Correct prediction, verified by PostgreSQL across all (\d+) datasets\.$"#) {
            return format("Correct prediction, verified by PostgreSQL across all %ld datasets.", language: language, Int(g[0]) ?? 0)
        }
        if let g = groups(#"^Each predicted row needs (\d+) values\.$"#) {
            return format("Each predicted row needs %ld values.", language: language, Int(g[0]) ?? 0)
        }
        if let g = groups(#"^PostgreSQL (.+) · Local$"#) { return "PostgreSQL \(g[0]) · Локально" }
        if let g = groups(#"^Progress exported to (.+)\.$"#) { return "Прогресс сохранён в \(g[0])." }
        if let g = groups(#"^Merged (\d+) progress entries\. Existing drafts and position were preserved\.$"#) {
            return "Записей прогресса объединено: \(g[0]). Ваши черновики и текущая позиция сохранены."
        }
        if let g = groups(#"^Course could not load: (.+)$"#) { return "Не удалось открыть курс. Диагностика: \(g[0])" }
        return value
    }
}

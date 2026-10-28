import SwiftUI
import AppKit
import SQLCore

struct CodeBlock: View {
    let code: String
    var body: some View {
        VStack(spacing: 0) {
            HStack { Text("POSTGRESQL").font(.system(size: 10, weight: .semibold)).tracking(0.8); Spacer(); Button { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(code, forType: .string) } label: { Image(systemName: "doc.on.doc").font(.system(size: 14)).frame(width: 34, height: 34) }.buttonStyle(.borderless).controlSize(.large).help(L.text("Copy SQL")).accessibilityLabel(L.text("Copy SQL example")) }.foregroundStyle(.secondary).padding(.horizontal, 12).padding(.vertical, 4)
            ScrollView(.horizontal) {
                Text(AttributedString(SQLColors.highlighted(code, fontSize: 13))).textSelection(.enabled).padding(.horizontal, 12).padding(.bottom, 12).frame(maxWidth: .infinity, alignment: .leading)
            }
        }.background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Color.secondary.opacity(0.12)))
    }
}

/// A small native renderer for the course's documented Markdown subset.
/// The content remains selectable and links retain standard system behavior.
struct MarkdownContent: View {
    let text: String
    var blocks: [String] { text.components(separatedBy: "\n\n").filter { !$0.isEmpty } }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                if block.hasPrefix("```") {
                    let lines = block.components(separatedBy: "\n")
                    CodeBlock(code: lines.dropFirst().filter { !$0.hasPrefix("```") }.joined(separator: "\n"))
                } else if block.contains("|") && block.components(separatedBy: "\n").count > 1 {
                    markdownTable(block)
                } else if block.hasPrefix("#") {
                    Text(block.trimmingCharacters(in: CharacterSet(charactersIn: "# "))).font(.headline)
                } else if block.hasPrefix("- ") || block.hasPrefix("* ") {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(block.components(separatedBy: "\n").enumerated()), id: \.offset) { _, line in
                            HStack(alignment: .top, spacing: 9) { Text("•").foregroundStyle(Color.craft); rich(String(line.dropFirst(2))) }
                        }
                    }
                } else { rich(block) }
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private func rich(_ value: String) -> some View {
        Text((try? AttributedString(markdown: value, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(value))
            .font(.system(size: 14)).lineSpacing(5).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
    }
    private func markdownTable(_ block: String) -> some View {
        let rows = block.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: CharacterSet(charactersIn: "| :-—\t")).isEmpty }.map { line in
            var content = line.trimmingCharacters(in: .whitespaces)
            if content.hasPrefix("|") { content.removeFirst() }
            if content.hasSuffix("|") { content.removeLast() }
            return content.split(separator: "|", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
        }
        return ScrollView(.horizontal) {
            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 9) {
                ForEach(Array(rows.enumerated()), id: \.offset) { row, cells in
                    GridRow {
                        ForEach(Array(cells.enumerated()), id: \.offset) { _, cell in Text(cell).font(.system(size: 11, weight: row == 0 ? .semibold : .regular, design: .monospaced)).textSelection(.enabled) }
                    }
                    if row == 0 { Divider().gridCellColumns(max(1, cells.count)) }
                }
            }.padding(12)
        }.background(Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
    }
}

struct HistoryView: View {
    @Bindable var model: WorkspaceModel
    @Environment(\.dismiss) private var dismiss
    @State private var onlyCurrent = true
    var attempts: [Attempt] { onlyCurrent ? model.attempts.filter { $0.exerciseID == model.selection } : model.attempts }
    var body: some View {
        VStack(spacing: 0) {
            HStack { Text(L.text("Attempt history")).font(.title2.weight(.semibold)); Spacer(); Toggle(L.text("This exercise"), isOn: $onlyCurrent).toggleStyle(.switch).controlSize(.small); Button(L.text("Done")) { dismiss() }.keyboardShortcut(.cancelAction) }.padding(22)
            Divider()
            if attempts.isEmpty { EmptyPanel(symbol: "clock.arrow.circlepath", title: "No attempts yet", detail: "Submit an exercise to save your SQL and feedback here.") }
            else {
                List(attempts) { attempt in
                    DisclosureGroup {
                        if let exercise = model.course?.exercises.first(where: { $0.id == attempt.exerciseID }), ["choose", "predict", "explain"].contains(exercise.kind) {
                            Text(attempt.sql).font(.callout).textSelection(.enabled).padding(.vertical, 8)
                        } else { CodeBlock(code: attempt.sql) }
                        Text(L.message(attempt.feedback)).font(.callout).textSelection(.enabled)
                        HStack {
                            Button(L.text("Restore answer")) {
                                model.select(attempt.exerciseID)
                                if ["choose", "predict", "explain"].contains(model.currentExercise?.kind ?? "") { model.response = attempt.sql }
                                else { model.sql = attempt.sql }
                                dismiss()
                            }
                            Button(L.text("Open exercise")) { model.select(attempt.exerciseID); dismiss() }
                        }.padding(.vertical, 8)
                    } label: {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: attempt.passed ? "checkmark.circle.fill" : "arrow.counterclockwise.circle").foregroundStyle(attempt.passed ? Color.craft : .orange)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(model.course?.exercises.first(where: { $0.id == attempt.exerciseID })?.title ?? attempt.exerciseID).font(.callout.weight(.medium))
                                Text(attempt.date, format: .dateTime.month().day().hour().minute()).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer(); Text(L.text(attempt.feedback.hasPrefix("Self-assessed") || attempt.feedback.hasPrefix("Самостоятельная") ? "Reviewed" : attempt.passed ? "Correct" : "Keep practicing")).font(.caption).foregroundStyle(.secondary)
                        }.padding(.vertical, 5)
                    }
                }
            }
        }.frame(width: 760, height: 560)
    }
}

struct ProgressViewSheet: View {
    @Bindable var model: WorkspaceModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack { Text(L.text("Your learning progress")).font(.title2.weight(.semibold)); Spacer(); Button(L.text("Done")) { dismiss() }.keyboardShortcut(.cancelAction) }
            HStack(spacing: 32) {
                metric("Exercises solved", "\(model.completedExercises)")
                metric("Attempts", "\(model.attempts.count)")
                metric("For review", "\(model.progress.values.filter(\.review).count)")
                metric("Bookmarks", "\(model.progress.values.filter(\.bookmarked).count)")
            }.padding(.vertical, 5)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(model.course?.modules ?? []) { module in
                        let all = module.lessons.flatMap(\.exercises)
                        let done = all.filter { model.progress[$0.id]?.completed == true }.count
                        HStack { Text(module.title).font(.callout); Spacer(); Text("\(done)/\(all.count)").font(.caption).foregroundStyle(.secondary).monospacedDigit(); ProgressView(value: Double(done), total: Double(max(1, all.count))).frame(width: 100) }
                    }
                }
            }
            Divider()
            HStack {
                Button(L.text("Export progress…"), action: model.exportProgress)
                Button(L.text("Import & merge…"), action: model.importProgress)
                Spacer()
                Text(L.text("Saved locally on this Mac")).font(.caption).foregroundStyle(.secondary)
            }
        }.padding(24).frame(width: 670, height: 590)
    }
    private func metric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) { Text(value).font(.title.weight(.semibold)).monospacedDigit().foregroundStyle(Color.craft); Text(L.text(label)).font(.caption).foregroundStyle(.secondary) }
    }
}

struct HelpView: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack { Text(L.text("Welcome to SQLLY")).font(.title2.weight(.semibold)); Spacer(); Button { dismiss() } label: { Text(L.text("Done")).frame(minHeight: 34) }.controlSize(.large).keyboardShortcut(.cancelAction) }
            ScrollView { MarkdownContent(text: L.text("help.body")) }
        }.padding(26).frame(width: 650, height: 640)
    }
}

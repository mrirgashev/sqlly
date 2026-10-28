import SwiftUI
import AppKit
import SQLCore

struct SQLWorkspace: View {
    @Bindable var model: WorkspaceModel
    @AppStorage("editorFontSize") private var fontSize = 14.0
    var body: some View {
        VSplitView {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Text(L.text("SQL workspace")).font(.system(size: 14, weight: .semibold))
                    Spacer()
                    Menu {
                        Button(L.text("Reset code & dataset"), action: model.reset)
                        Button(L.text("Copy SQL")) { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(model.sql, forType: .string) }
                        Button(L.text("Increase text size")) { fontSize = min(22, fontSize + 1) }
                        Button(L.text("Decrease text size")) { fontSize = max(11, fontSize - 1) }
                    } label: {
                        Image(systemName: "ellipsis").font(.system(size: 16, weight: .medium)).frame(width: 36, height: 36)
                    }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                        .help(L.text("Editor options")).accessibilityLabel(L.text("Editor options"))
                }.padding(.horizontal, 16).frame(height: 54).background(Color.surface)
                SQLEditor(text: $model.sql, fontSize: fontSize).frame(minHeight: 160).clipped()
                Divider()
                HStack(spacing: 10) {
                    Button { Task { await model.run() } } label: { Label(L.text("Run query"), systemImage: "play.fill").frame(width: 24, height: 28) }
                        .labelStyle(.iconOnly).help(L.text("Run query · ⌘Return")).disabled(!model.engineReady || model.isRunning)
                    Button(action: model.reset) { Label(L.text("Reset code and dataset"), systemImage: "arrow.counterclockwise").frame(width: 24, height: 28) }
                        .labelStyle(.iconOnly).help(L.text("Reset code and dataset"))
                    Toggle(L.text("Live"), isOn: $model.liveEnabled).toggleStyle(.switch).controlSize(.small)
                        .font(.system(size: 12)).help(L.text("Executes after you pause typing")).accessibilityLabel(L.text("Live execution"))
                    Spacer()
                    if model.isRunning || model.isLiveRunning { ProgressView().controlSize(.small).accessibilityLabel(L.text("Executing SQL")) }
                    Button { Task { await model.run(submit: true) } } label: { Label(L.text("Submit answer"), systemImage: "checkmark").frame(width: 24, height: 28) }
                        .labelStyle(.iconOnly).buttonStyle(.borderedProminent).disabled(model.isRunning || model.currentExercise == nil)
                        .help(L.text("Check all fixtures · ⇧⌘Return"))
                }.font(.system(size: 15, weight: .medium)).buttonStyle(.bordered).controlSize(.large).padding(12).background(.bar)
            }.frame(minHeight: 255, idealHeight: 370)
            VStack(spacing: 0) {
                HStack(spacing: 17) {
                    ForEach(["Results", "Schema", "Preview"], id: \.self) { tab in
                        Button { model.selectedResultTab = tab } label: {
                            VStack(spacing: 0) {
                                Text(L.text(tab)).font(.system(size: 14, weight: model.selectedResultTab == tab ? .semibold : .regular)).frame(minHeight: 44)
                                Rectangle().fill(model.selectedResultTab == tab ? Color.craft : Color.clear).frame(height: 2)
                            }.foregroundStyle(model.selectedResultTab == tab ? .primary : .secondary)
                        }.buttonStyle(.plain)
                    }
                    Spacer()
                    if let result = model.result, model.selectedResultTab == "Results" {
                        Text(L.format("%ld rows · %ld ms", result.rows.count, Int(result.duration * 1000))).font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                    }
                }.padding(.horizontal, 15).background(.bar)
                Divider()
                if let feedback = model.feedback { NoticeBanner(text: L.message(feedback), kind: model.feedbackPassed == true ? .success : model.feedbackPassed == false ? .error : .info) }
                if let error = model.queryError {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 10) {
                            NoticeBanner(text: SQLExplanation.explain(error), kind: .error)
                            DisclosureGroup(L.text("Original PostgreSQL diagnostic")) { Text(error).font(.system(size: 11, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 6) }
                                .font(.caption).padding(.horizontal, 14)
                        }.padding(.bottom, 12)
                    }.frame(maxHeight: 170)
                    Divider()
                }
                if model.selectedResultTab == "Schema" { SchemaBrowser(model: model) }
                else if model.selectedResultTab == "Preview" {
                    if let preview = model.preview { ResultsTable(result: preview) }
                    else { EmptyPanel(symbol: "tablecells", title: "Explore the data", detail: "Choose a table in Schema to preview its first 50 rows.") }
                } else if let result = model.result {
                    if result.columns.isEmpty { EmptyPanel(symbol: "checkmark.circle", title: result.command.isEmpty ? L.text("Statement completed") : result.command, detail: L.text("The command did not return a table. Use RETURNING to inspect a data change.")) }
                    else { ResultsTable(result: result) }
                } else if model.queryError == nil {
                    EmptyPanel(symbol: "tablecells", title: L.text("Your results appear here"), detail: L.text("Pause typing to execute SQL automatically, or press ⌘Return. Submit separately to check your answer."))
                } else { Spacer(minLength: 0) }
            }.frame(minHeight: 200, idealHeight: 420)
        }.background(Color.canvas)
    }
}

struct SchemaBrowser: View {
    @Bindable var model: WorkspaceModel
    var tables: [String] { Array(Set(model.schema?.rows.compactMap { $0.first.flatMap { $0 } } ?? [])).sorted() }
    var body: some View {
        if let data = model.schema, !data.rows.isEmpty {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(tables, id: \.self) { table in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack { Label(table, systemImage: "tablecells").font(.callout.weight(.semibold)); Spacer(); Button { Task { await model.previewTable(table) } } label: { Text(L.text("Preview")).font(.system(size: 13, weight: .medium)).frame(minHeight: 32) }.buttonStyle(.link).controlSize(.large).disabled(model.isRunning) }
                            ForEach(Array(data.rows.filter { $0.first.flatMap { $0 } == table }.enumerated()), id: \.offset) { _, row in
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack { Text(cell(row, 1)).font(.system(size: 12, design: .monospaced)); Spacer(); Text(cell(row, 2)).font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary) }
                                    let constraints = cell(row, 5)
                                    if !constraints.isEmpty || cell(row, 3) == "NO" {
                                        Text(([constraints, cell(row, 3) == "NO" ? "NOT NULL" : ""].filter { !$0.isEmpty }).joined(separator: " · ")).font(.system(size: 9)).foregroundStyle(Color.craft)
                                    }
                                    if !cell(row, 4).isEmpty { Text(L.format("Default: %@", cell(row, 4))).font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary) }
                                }.padding(.leading, 20)
                            }
                        }
                    }
                    Text(L.text("Schema reflects the starting fixture. Each run is isolated; data changes do not carry into the next run.")).font(.caption).foregroundStyle(.secondary)
                }.padding(18)
            }
        } else { EmptyPanel(symbol: "square.stack.3d.up", title: "No tables in this fixture", detail: "This lesson may create its own tables or use expressions without a table.") }
    }
    func cell(_ row: [String?], _ index: Int) -> String { row.indices.contains(index) ? row[index] ?? "" : "" }
}

struct EmptyPanel: View {
    let symbol: String; let title: String; let detail: String
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 25, weight: .light)).foregroundStyle(.tertiary)
            Text(L.text(title)).font(.callout.weight(.medium))
            Text(L.text(detail)).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 320)
        }.frame(maxWidth: .infinity, maxHeight: .infinity).padding(24)
    }
}

enum SQLExplanation {
    static func explain(_ error: String) -> String {
        let e = error.lowercased()
        if e.contains("bundled postgresql") || e.contains("postgresql could not start") || e.contains("initdb failed") {
            return L.text("The local practice database could not start. Reopen SQLLY or reinstall the application. Your saved learning progress is stored separately.")
        }
        if e.contains("result exceeds") || e.contains("editor limit") || e.contains("copy streaming") { return L.message(error) }
        if e.contains("syntax error") { return L.text("Check the keyword near the reported position, commas between expressions, and matching quotes and parentheses. SQL uses single quotes for text and double quotes for identifiers.") }
        if e.contains("does not exist") { return L.text("Open Schema to check table and column names. Unquoted PostgreSQL identifiers are folded to lowercase. A fresh dataset is used for every run.") }
        if e.contains("permission denied") || e.contains("must be superuser") { return L.text("The practice login has limited privileges. Server administration, filesystem access, role changes, and extension installation are restricted. Those operations are taught with safe inspection tasks.") }
        if e.contains("timeout") || e.contains("time limit") || e.contains("canceling statement") { return L.text("The practice time limit was reached. Look for a missing JOIN condition, an unbounded recursive query, or an expensive expression. The next run starts with clean data.") }
        if e.contains("group by") || e.contains("aggregate") { return L.text("Every selected expression must be grouped or aggregated. WHERE filters source rows; HAVING filters the groups after aggregation.") }
        if e.contains("violates") || e.contains("duplicate key") { return L.text("A constraint protects the data. Check the primary key, foreign key, NOT NULL, UNIQUE, or CHECK rule named in the message.") }
        if e.contains("integer") || e.contains("numeric") || e.contains("type") { return L.text("Check the expression's data type and casts. For division, cast one operand to numeric when you need a fractional answer.") }
        return L.text("Check the lesson example, inspect the schema, or reveal a progressive hint before trying again.")
    }
}

struct ResultsTable: NSViewRepresentable {
    let result: QueryResult
    func makeCoordinator() -> Coordinator { Coordinator(result) }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView(); scroll.hasVerticalScroller = true; scroll.hasHorizontalScroller = true; scroll.autohidesScrollers = true
        scroll.backgroundColor = .sqllyCanvas
        let table = CopyableTable(); table.coordinator = context.coordinator
        table.delegate = context.coordinator; table.dataSource = context.coordinator
        table.usesAlternatingRowBackgroundColors = true; table.rowHeight = 30; table.intercellSpacing = NSSize(width: 12, height: 1)
        table.columnAutoresizingStyle = .noColumnAutoresizing; table.allowsMultipleSelection = true
        table.backgroundColor = .sqllyCanvas
        table.setAccessibilityLabel(L.text("SQL query results"))
        scroll.documentView = table; context.coordinator.table = table
        context.coordinator.update(result)
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) { context.coordinator.update(result) }
    @MainActor final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        var result: QueryResult; weak var table: NSTableView?
        init(_ result: QueryResult) { self.result = result }
        func update(_ value: QueryResult) {
            guard let table else { return }
            let changed = result.columns != value.columns || table.tableColumns.count != value.columns.count
            result = value
            if changed {
                for column in table.tableColumns { table.removeTableColumn(column) }
                for (index, item) in value.columns.enumerated() {
                    let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("\(index)")); column.title = item.name
                    let contentLength = value.rows.prefix(40).compactMap { $0.indices.contains(index) ? $0[index]?.count : nil }.max() ?? 0
                    column.width = min(360, max(125, CGFloat(max(item.name.count, contentLength) * 7 + 26))); column.minWidth = 65
                    table.addTableColumn(column)
                }
            }
            table.reloadData()
        }
        func numberOfRows(in tableView: NSTableView) -> Int { result.rows.count }
        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard let identifier = tableColumn?.identifier, let index = Int(identifier.rawValue), result.rows.indices.contains(row), result.rows[row].indices.contains(index) else { return nil }
            let value = result.rows[row][index]
            let field = NSTextField(labelWithString: value ?? "NULL")
            field.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
            field.textColor = value == nil ? .secondaryLabelColor : .textColor
            field.lineBreakMode = .byTruncatingTail; field.toolTip = value ?? L.text("SQL NULL (missing value)")
            field.setAccessibilityLabel("\(result.columns[index].name): \(value ?? "NULL")")
            return field
        }
    }
    @MainActor final class CopyableTable: NSTableView {
        weak var coordinator: Coordinator?
        @objc func copy(_ sender: Any?) {
            guard let result = coordinator?.result else { return }
            let rows = selectedRowIndexes.isEmpty ? Array(result.rows.indices) : Array(selectedRowIndexes)
            let text = ([result.columns.map(\.name).joined(separator: "\t")] + rows.compactMap { index in
                guard result.rows.indices.contains(index) else { return nil }
                return result.rows[index].map { $0 ?? "NULL" }.joined(separator: "\t")
            }).joined(separator: "\n")
            NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string)
        }
    }
}

import SwiftUI
import AppKit
import SQLCore

extension Color {
    static let craft = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 0.35, green: 0.81, blue: 0.53, alpha: 1)
            : NSColor(srgbRed: 0.10, green: 0.42, blue: 0.23, alpha: 1)
    })
    static let canvas = Color(nsColor: .sqllyCanvas)
    static let surface = Color(nsColor: .sqllySurface)
}

struct WorkspaceView: View {
    @Bindable var model: WorkspaceModel
    @State private var visibility = NavigationSplitViewVisibility.all
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        NavigationSplitView(columnVisibility: $visibility) {
            CurriculumSidebar(model: model)
                .navigationSplitViewColumnWidth(min: 245, ideal: 285, max: 380)
        } detail: {
            VStack(spacing: 0) {
                if let error = model.fatalError { NoticeBanner(text: L.message(error), kind: .error) }
                if let notice = model.storageNotice { NoticeBanner(text: L.message(notice), kind: .error, dismiss: { model.storageNotice = nil }) }
                if !model.engineReady { EngineAvailabilityNotice(model: model) }
                HSplitView {
                    LessonView(model: model).frame(minWidth: 340, idealWidth: 480)
                    if model.requiresCodeEditor && model.inspectorVisible { SQLWorkspace(model: model).frame(minWidth: 380, idealWidth: 600) }
                }
            }
            .background(Color.canvas)
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button { model.showStatistics = true } label: { Label(L.text("Learning Center"), systemImage: "square.grid.2x2") }
                        .labelStyle(.titleAndIcon).controlSize(.large).help(L.text("Learning Center"))
                    if model.requiresCodeEditor {
                        Button { model.inspectorVisible.toggle() } label: { Label(L.text("Toggle SQL Workspace"), systemImage: "sidebar.right").frame(minWidth: 30, minHeight: 32) }
                            .labelStyle(.iconOnly).controlSize(.large).help(L.text("Show or hide SQL workspace"))
                    }
                }
            }
        }
        .id(model.language)
        .tint(.craft)
        .background(WorkspaceKeyboardNavigation(model: model).frame(width: 0, height: 0))
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: model.feedbackPassed)
        .sheet(isPresented: $model.showHistory) { HistoryView(model: model).id(model.language) }
        .sheet(isPresented: $model.showStatistics) { LearningCenterView(model: model).id(model.language) }
        .sheet(isPresented: $model.showHelp) { HelpView().id(model.language) }
    }
}

struct EngineAvailabilityNotice: View {
    @Bindable var model: WorkspaceModel
    var body: some View {
        HStack(spacing: 10) {
            if model.queryError == nil { ProgressView().controlSize(.small) }
            else { Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange) }
            Text(L.message(model.engineStatus)).font(.system(size: 13))
            Spacer()
            if model.queryError != nil {
                Button(L.text("Retry")) { Task { await model.start() } }.controlSize(.large)
            }
        }.padding(.horizontal, 18).padding(.vertical, 8).background(Color.surface)
    }
}

/// The sidebar is a flat list of themes. Individual steps live only in the top strip.
struct CurriculumSidebar: View {
    @Bindable var model: WorkspaceModel
    private var topics: [CourseModule] { model.course?.modules ?? [] }
    private var activeID: String? { topics.first { $0.lessons.contains { $0.id == model.currentStep?.lessonID } }?.id }
    private func choose(_ module: CourseModule) {
        let all = module.lessons.flatMap(\.steps)
        let visited = all.filter { (model.progress[$0.id]?.visits ?? 0) > 0 }
        if let recent = visited.max(by: { (model.progress[$0.id]?.updatedAt ?? .distantPast) < (model.progress[$1.id]?.updatedAt ?? .distantPast) }) { model.select(recent.id) }
        else if let first = all.first { model.select(first.id) }
    }
    private func topicButton(for module: CourseModule) -> some View {
        let steps = module.lessons.flatMap(\.steps)
        let done = steps.filter { model.progress[$0.id]?.completed == true }.count
        let needsReview = steps.contains { model.progress[$0.id]?.review == true }
        return TopicSidebarButton(title: module.title, done: done, total: steps.count,
                                  needsReview: needsReview, active: activeID == module.id) { choose(module) }
    }
    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 15) {
                Text("SQLLY").font(.system(size: 22, weight: .semibold)).tracking(1.7)
                Text(L.text("Topics")).font(.system(size: 14, weight: .medium)).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, alignment: .leading).padding(20)
            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(topics) { module in topicButton(for: module) }
                }.padding(.horizontal, 8).padding(.vertical, 3)
            }
            Button { model.showStatistics = true } label: {
                Label(L.text("Learning Center"), systemImage: "square.grid.2x2")
                    .font(.system(size: 14, weight: .medium)).frame(maxWidth: .infinity, minHeight: 42, alignment: .leading)
            }.buttonStyle(.bordered).controlSize(.large).padding(14)
        }.background(Color.surface)
    }
}

private struct TopicSidebarButton: View {
    let title: String
    let done: Int
    let total: Int
    let needsReview: Bool
    let active: Bool
    let action: () -> Void
    private var titleColor: Color { active ? .craft : .primary }
    private var fillColor: Color { active ? Color.craft.opacity(0.04) : .clear }
    private var outlineColor: Color { active ? Color.craft.opacity(0.8) : .clear }
    private var progressText: String { L.format("%ld / %ld steps complete", done, total) }
    private var accessibilityText: String { title + ". " + progressText + (needsReview ? ". " + L.text("Review required") : "") }
    var body: some View {
        Button(action: action) {
            rowContent
                .padding(.leading, 16).padding(.trailing, 10).padding(.vertical, 12).frame(minHeight: 66)
                .background(alignment: .leading) { rail }
                .background(fillColor, in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(outlineColor, lineWidth: 1.25))
                .contentShape(RoundedRectangle(cornerRadius: 6))
        }.buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityText)
            .accessibilityAddTraits(.isButton)
            .accessibilityAddTraits(active ? .isSelected : [])
    }
    private var rowContent: some View {
        HStack(alignment: .center, spacing: 10) {
            labels
            Spacer(minLength: 0)
            if needsReview {
                Image(systemName: "exclamationmark").font(.system(size: 10, weight: .bold)).foregroundStyle(.orange)
                    .frame(width: 14, height: 18).help(L.text("Review required"))
            }
        }
    }
    private var labels: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.system(size: 14, weight: active ? .semibold : .medium))
                .foregroundStyle(titleColor).lineLimit(3).fixedSize(horizontal: false, vertical: true)
            Text(progressText).font(.system(size: 11)).monospacedDigit().foregroundStyle(.secondary)
        }
    }
    private var rail: some View {
        TopicProgressRail(fraction: Double(done) / Double(max(1, total)), active: active).padding(.vertical, 8)
    }
}

struct TopicProgressRail: View {
    let fraction: Double
    let active: Bool
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                Capsule().fill(active ? Color.craft.opacity(0.28) : Color.secondary.opacity(0.14))
                Capsule().fill(Color.craft).frame(height: geometry.size.height * min(1, max(0, fraction)))
            }
        }.frame(width: 3).accessibilityHidden(true)
    }
}

struct StepStatus: View {
    let progress: StepProgress?
    var isExercise = false
    var body: some View {
        Image(systemName: symbol).font(.system(size: 11))
            .foregroundStyle(progress?.review == true ? Color.orange : progress?.completed == true ? .craft : Color.secondary)
            .frame(width: 13, height: 15)
            .accessibilityLabel(L.text(progress?.review == true ? "Review required" : progress?.completed == true ? "Completed" : (progress?.visits ?? 0) > 0 ? "In progress" : "Untouched"))
    }
    var symbol: String {
        if progress?.review == true { return "exclamationmark.circle.fill" }
        if progress?.completed == true { return "checkmark.circle.fill" }
        if (progress?.visits ?? 0) > 0 { return "circle.lefthalf.filled" }
        return isExercise ? "circle" : "book"
    }
}

struct LessonView: View {
    @Bindable var model: WorkspaceModel
    private var topic: CourseModule? { model.course?.modules.first { $0.lessons.contains { $0.id == model.currentStep?.lessonID } } }
    private var topicSteps: [LearningStep] { topic?.lessons.flatMap(\.steps) ?? model.currentLesson?.steps ?? [] }
    private var topicPosition: Int { topicSteps.firstIndex { $0.id == model.selection } ?? 0 }
    var body: some View {
        VStack(spacing: 0) {
            if let lesson = model.currentLesson, let step = model.currentStep {
                VStack(alignment: .leading, spacing: 13) {
                    Text(topic?.title ?? model.breadcrumb).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    HStack(alignment: .top) {
                        Text(lesson.title).font(.system(size: 24, weight: .semibold)).tracking(-0.5)
                        Spacer()
                    }
                    HStack {
                        Text(L.format("Step %ld of %ld", topicPosition + 1, topicSteps.count)).font(.system(size: 10, weight: .semibold)).tracking(0.7).foregroundStyle(.secondary)
                        Spacer()
                        Text(L.text(step.exercise == nil ? "READ & EXPLORE" : "PRACTICE")).font(.system(size: 10, weight: .semibold)).tracking(0.7).foregroundStyle(Color.craft)
                    }
                    ScrollViewReader { proxy in
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 5) {
                                ForEach(Array(topicSteps.enumerated()), id: \.element.id) { index, item in
                                    LessonStepButton(index: index, step: item, selected: item.id == step.id, progress: model.progress[item.id]) { model.select(item.id) }.id(item.id)
                                }
                            }
                        }
                        .onAppear { proxy.scrollTo(step.id, anchor: .center) }
                        .onChange(of: model.selection) { _, id in proxy.scrollTo(id, anchor: .center) }
                    }
                }.padding(24)
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        if let ex = step.exercise { ExerciseContent(model: model, exercise: ex) }
                        else if step.section != nil {
                            Label(L.text("LEARN THE CONCEPT"), systemImage: "book").font(.system(size: 10, weight: .semibold)).tracking(0.8).foregroundStyle(Color.craft)
                            LessonReadingContent(model: model, step: step)
                            if model.position == 0, !lesson.prerequisites.isEmpty {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(L.text("BEFORE YOU BEGIN")).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                                    ForEach(lesson.prerequisites, id: \.self) { id in
                                        if let prerequisite = model.course?.lessons.first(where: { $0.id == id }), let first = prerequisite.steps.first {
                                            Button { model.select(first.id) } label: { Text(prerequisite.title).font(.system(size: 14)).frame(minHeight: 32, alignment: .leading) }.buttonStyle(.link)
                                        }
                                    }
                                }
                            }
                        }
                    }.padding(24).frame(maxWidth: 720, alignment: .leading).frame(maxWidth: .infinity, alignment: .topLeading)
                }.id(step.id)
                Divider()
                HStack {
                    Button { model.navigate(-1) } label: { Image(systemName: "chevron.left").frame(width: 24, height: 28) }
                        .buttonStyle(.bordered).help(L.text("Previous step · ⌘[")).accessibilityLabel(L.text("Previous Step"))
                    Spacer()
                    if step.exercise == nil {
                        Button(action: model.completeReading) {
                            HStack(spacing: 10) { Text(L.text("Continue")); Image(systemName: "arrow.right") }
                                .font(.system(size: 14, weight: .semibold)).frame(minHeight: 40).padding(.horizontal, 6)
                        }.buttonStyle(.borderedProminent)
                    } else {
                        Button { model.navigate(1) } label: {
                            HStack(spacing: 10) { Text(L.text("Next step")); Image(systemName: "arrow.right") }
                                .font(.system(size: 14, weight: .medium)).frame(minHeight: 36).padding(.horizontal, 6)
                        }.buttonStyle(.bordered).help(L.text("Next step"))
                    }
                }.controlSize(.large).padding(16)
            } else { ContentUnavailableView(L.text("Course unavailable"), systemImage: "book.closed", description: Text(L.text("Check the bundled curriculum resource."))) }
        }.background(Color.canvas)
    }
}

struct LessonReadingContent: View {
    @Bindable var model: WorkspaceModel
    let step: LearningStep
    @State private var deeper = false
    private var visible: [Int] { step.sections.indices.filter { $0 < 5 || $0 == 6 } }
    private var details: [Int] { step.sections.indices.filter { $0 >= 5 && $0 != 6 } }
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            ForEach(visible, id: \.self) { index in section(index) }
            if !details.isEmpty {
                DisclosureGroup(isExpanded: $deeper) {
                    VStack(alignment: .leading, spacing: 22) { ForEach(details, id: \.self) { index in section(index) } }.padding(.top, 16)
                } label: { Text(L.text("Go deeper")).font(.system(size: 14, weight: .medium)).frame(minHeight: 36) }
                .tint(.craft)
            }
        }
    }
    private func section(_ index: Int) -> some View {
        let section = step.sections[index]
        return VStack(alignment: .leading, spacing: 13) {
            Text(section.title).font(index == 0 ? .title2.weight(.semibold) : .headline)
            MarkdownContent(text: section.body)
            if let code = section.code, !code.isEmpty, index == 0 || step.sections[index - 1].code != code {
                CodeBlock(code: code)
            }
        }
    }
}

struct LessonStepButton: View {
    let index: Int
    let step: LearningStep
    let selected: Bool
    let progress: StepProgress?
    let action: () -> Void
    @State private var hovered = false
    private var visited: Bool { (progress?.visits ?? 0) > 0 }
    private var status: String { progress?.review == true ? "Review required" : progress?.completed == true ? "Completed" : visited ? "In progress" : "Untouched" }
    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Text("\(index + 1)").font(.system(size: 12, weight: .semibold)).monospacedDigit()
                Image(systemName: progress?.completed == true ? "checkmark" : step.exercise == nil ? "book" : "chevron.left.forwardslash.chevron.right").font(.system(size: 9, weight: .medium))
            }
            .frame(width: 38, height: 40)
            .foregroundStyle(selected ? Color.canvas : progress?.completed == true || visited ? .craft : .secondary)
            .background(selected ? Color.craft : Color.craft.opacity(hovered ? 0.16 : progress?.completed == true ? 0.12 : visited ? 0.07 : 0.025), in: RoundedRectangle(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder((progress?.review == true ? Color.orange : Color.craft).opacity(selected || progress?.completed == true ? 0.7 : hovered ? 0.45 : visited ? 0.35 : 0.12)))
        }.buttonStyle(.plain).onHover { hovered = $0 }
            .help(step.title).accessibilityLabel(L.format("Step %ld: %@", index + 1, step.title) + ". " + L.text(step.exercise == nil ? "READ & EXPLORE" : "PRACTICE") + ". " + L.text(status))
    }
}

struct ExerciseContent: View {
    @Bindable var model: WorkspaceModel
    let exercise: Exercise
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 9) {
                Label(L.text(exercise.difficulty.capitalized), systemImage: "chart.bar").font(.caption.weight(.medium))
                Text("•").foregroundStyle(.tertiary)
                Text(L.text(exercise.kind.capitalized)).font(.caption)
            }.foregroundStyle(Color.craft)
            Text(exercise.title).font(.title2.weight(.semibold))
            MarkdownContent(text: exercise.prompt)
            if ["predict", "choose", "explain"].contains(exercise.kind) {
                ConceptualAnswerView(model: model, exercise: exercise)
            }
            VStack(alignment: .leading, spacing: 10) {
                Label(L.text("Answer checks"), systemImage: "checkmark.shield").font(.callout.weight(.semibold))
                Text(policySummary)
                    .font(.callout).foregroundStyle(.secondary)
                Text(policyDescription)
                    .font(.callout).foregroundStyle(.secondary)
            }.padding(14).frame(maxWidth: .infinity, alignment: .leading).background(Color.craft.opacity(0.055), in: RoundedRectangle(cornerRadius: 8))
            Divider()
            HStack {
                Text(L.text("Need a direction?")).font(.callout.weight(.semibold))
                Spacer()
                Text("\(model.revealedHints)/\(exercise.hints.count)").font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                Button { model.revealedHints = min(model.revealedHints + 1, exercise.hints.count) } label: { Label(L.text("Show hint"), systemImage: "lightbulb").frame(width: 24, height: 28) }
                    .labelStyle(.iconOnly).controlSize(.large).help(L.format("Hint %ld of %ld", min(model.revealedHints + 1, exercise.hints.count), exercise.hints.count))
                    .disabled(model.revealedHints >= exercise.hints.count)
            }
            ForEach(Array(exercise.hints.prefix(model.revealedHints).enumerated()), id: \.offset) { index, hint in
                HStack(alignment: .top, spacing: 10) {
                    Text("\(index + 1)").font(.caption.weight(.semibold)).foregroundStyle(Color.craft)
                    MarkdownContent(text: hint)
                }
            }
            DisclosureGroup(isExpanded: Binding(get: { model.showSolution && model.canRevealSolution }, set: model.setSolutionRevealed)) {
                if model.canRevealSolution && model.showSolution {
                VStack(alignment: .leading, spacing: 14) {
                    if exercise.kind == "choose" {
                        Text(L.format("Valid choices: %@", (exercise.correctChoiceIDs ?? []).joined(separator: ", "))).font(.callout.weight(.medium))
                    } else if exercise.kind != "explain" { CodeBlock(code: exercise.solutionSQL) }
                    if let answer = exercise.modelAnswer { MarkdownContent(text: answer) }
                    MarkdownContent(text: exercise.explanation)
                    if model.requiresCodeEditor {
                        Button(action: model.loadWorkedSolution) { Text(L.text("Load solution in editor")).font(.system(size: 14, weight: .medium)).frame(minHeight: 34) }.buttonStyle(.link)
                    }
                }.padding(.top, 12)
                }
            } label: {
                HStack(spacing: 9) {
                    if !model.canRevealSolution { Image(systemName: "lock").accessibilityHidden(true) }
                    Text(L.text("Worked solution"))
                }.font(.system(size: 14, weight: .medium)).frame(minHeight: 36)
            }
            .disabled(!model.canRevealSolution)
            if model.requiresCodeEditor {
                Text(model.canRevealSolution
                     ? L.text("Worked solution unlocked. Open it when you are ready.")
                     : L.format("%ld of %ld distinct unsuccessful code attempts. Submit a different solution to keep trying.", min(model.solutionAccess.distinctFailedCodeAttempts, SolutionAccessPolicy.requiredDistinctFailures), SolutionAccessPolicy.requiredDistinctFailures))
                    .font(.caption).foregroundStyle(.secondary)
                if !model.canRevealSolution {
                    Text(L.text("Run and Live do not count. Repeated code or changes only to formatting or comments do not add an attempt."))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Text(L.format("Exercise %@", exercise.id)).font(.system(size: 10, design: .monospaced)).foregroundStyle(.tertiary).textSelection(.enabled)
        }
    }
    private var policySummary: String {
        if exercise.kind == "explain" { return L.text("Self-assessment with a worked rubric") }
        if exercise.kind == "choose" { return L.text("Select every valid option") }
        return L.format("%ld independent datasets", exercise.fixtureIDs.count) + " · " + L.text(exercise.ordered ? "Order matters" : "Any row order") + (exercise.columnNames ? " · " + L.text("Named columns") : "")
    }
    private var policyDescription: String {
        L.text(exercise.kind == "explain" ? "Write your reasoning before revealing the rubric. Explanation quality is reviewed by you; it is not automatically graded." : exercise.kind == "choose" ? "The check accepts exactly the set of valid choices. Incorrect attempts keep the worked answer hidden." : exercise.kind == "predict" ? "Predict the result before running the example. PostgreSQL calculates the reference result when you check your prediction." : exercise.validationSQL == nil ? "Run to explore. Submit to check your result against the reference on each dataset. Different correct SQL is welcome." : "Your SQL runs on a fresh dataset. Dedicated checks inspect the resulting data or schema.")
    }
}

struct ConceptualAnswerView: View {
    @Bindable var model: WorkspaceModel
    let exercise: Exercise
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if exercise.kind == "choose" {
                ForEach(exercise.choices ?? []) { choice in
                    Toggle(isOn: Binding(get: { model.selectedChoiceIDs.contains(choice.id) }, set: { value in
                        if value != model.selectedChoiceIDs.contains(choice.id) { model.toggleChoice(choice.id) }
                    })) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(choice.id.uppercased()).font(.caption.weight(.semibold)).foregroundStyle(Color.craft)
                            Text(choice.text).font(.system(size: 13, design: .monospaced)).textSelection(.enabled)
                        }.padding(.vertical, 6)
                    }.toggleStyle(.checkbox)
                }
            } else {
                if exercise.kind == "predict" {
                    CodeBlock(code: exercise.starterSQL)
                    Text(L.text("Enter one row for each predicted output row. Use t / f for Boolean values, and mark NULL for a missing SQL value."))
                        .font(.caption).foregroundStyle(.secondary)
                    PredictionGrid(model: model, columns: exercise.predictionColumns ?? ["Value"])
                } else {
                    Text(L.text("Explain in your own words. Include the reason and a concrete example.")).font(.callout).foregroundStyle(.secondary)
                    TextEditor(text: $model.response).font(.system(size: 14))
                        .padding(6).frame(minHeight: 145)
                        .background(Color.secondary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.secondary.opacity(0.25)))
                        .accessibilityLabel(L.text("Your explanation"))
                }
            }
            VStack(alignment: .leading, spacing: 10) {
                Button {
                    Task { await model.run(submit: true) }
                } label: {
                    Text(L.text(exercise.kind == "explain" ? "Review against rubric" : exercise.kind == "predict" ? "Check prediction" : "Check choices"))
                        .font(.system(size: 14, weight: .semibold)).frame(minHeight: 36)
                }.buttonStyle(.borderedProminent).disabled(model.isRunning || (exercise.kind == "predict" && !model.engineReady))
                if exercise.kind == "explain", model.showSolution {
                    Button(action: model.completeExplanation) { Text(L.text("Mark reviewed")).font(.system(size: 14, weight: .medium)).frame(minHeight: 36) }.disabled(model.response.isEmpty)
                }
            }.controlSize(.large)
            if let feedback = model.feedback { NoticeBanner(text: L.message(feedback), kind: model.feedbackPassed == true ? .success : model.feedbackPassed == false ? .error : .info) }
            if let error = model.queryError { NoticeBanner(text: L.message(error), kind: .error) }
        }
    }
}

struct PredictionGrid: View {
    @Bindable var model: WorkspaceModel
    let columns: [String]
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ScrollView(.horizontal) {
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 12) {
                    GridRow {
                        Text("#").foregroundStyle(.secondary)
                        ForEach(Array(columns.enumerated()), id: \.offset) { _, name in Text(name).font(.system(size: 11, weight: .semibold, design: .monospaced)).frame(width: 110, alignment: .leading) }
                    }
                    ForEach(Array(model.predictedRows.enumerated()), id: \.offset) { row, cells in
                        GridRow(alignment: .top) {
                            Text("\(row + 1)").font(.caption).foregroundStyle(.secondary).padding(.top, 5)
                            ForEach(Array(columns.enumerated()), id: \.offset) { column, name in
                                let value = cells.indices.contains(column) ? cells[column] : ""
                                VStack(alignment: .leading, spacing: 5) {
                                    TextField(L.text("Value"), text: Binding(get: { value ?? "" }, set: { model.updatePrediction(row: row, column: column, value: $0) }))
                                        .textFieldStyle(.roundedBorder).controlSize(.large).font(.system(size: 13, design: .monospaced)).disabled(value == nil)
                                        .accessibilityLabel(L.format("Row %ld, %@", row + 1, name))
                                    Toggle("NULL", isOn: Binding(get: { value == nil }, set: { model.updatePrediction(row: row, column: column, value: $0 ? nil : "") }))
                                        .toggleStyle(.checkbox).font(.system(size: 12)).accessibilityLabel(L.format("Row %ld, %@ is SQL NULL", row + 1, name))
                                }.frame(width: 110)
                            }
                        }
                    }
                }.padding(10)
            }.background(Color.secondary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) { predictionButtons }
                VStack(alignment: .leading, spacing: 10) { predictionButtons }
            }.controlSize(.large)
        }
    }
    @ViewBuilder private var predictionButtons: some View {
        Button { model.resizePrediction(add: true) } label: { Label(L.text("Add row"), systemImage: "plus").frame(minHeight: 32) }.disabled(model.predictedRows.count >= 30)
        Button { model.resizePrediction(add: false) } label: { Label(L.text("Remove last row"), systemImage: "minus").frame(minHeight: 32) }.disabled(model.predictedRows.isEmpty)
    }
}

struct NoticeBanner: View {
    enum Kind { case error, success, info }
    let text: String
    var kind: Kind = .info
    var dismiss: (() -> Void)?
    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: kind == .error ? "exclamationmark.circle" : kind == .success ? "checkmark.circle.fill" : "info.circle")
            Text(text).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
            if let dismiss { Button(action: dismiss) { Image(systemName: "xmark") }.buttonStyle(.plain).accessibilityLabel(L.text("Dismiss notice")) }
        }.font(.callout).foregroundStyle(kind == .error ? Color.red : kind == .success ? Color.craft : Color.secondary)
            .padding(12).background((kind == .error ? Color.red : Color.craft).opacity(0.06)).accessibilityElement(children: .combine)
    }
}

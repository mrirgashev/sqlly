import SwiftUI
import Observation
import AppKit
import SQLCore

@MainActor @Observable
final class WorkspaceModel {
    var course: Curriculum?
    let engine: PostgresEngine
    @ObservationIgnored private let liveController: LiveQueryController
    @ObservationIgnored private var liveRevision: UInt64 = 0
    @ObservationIgnored private var liveContext = ""
    @ObservationIgnored private var shuttingDown = false
    private let store: ProgressStore?
    var language = UserDefaults.standard.string(forKey: "language") ?? "en"
    var liveEnabled = UserDefaults.standard.object(forKey: "liveExecution") as? Bool ?? true {
        didSet { UserDefaults.standard.set(liveEnabled, forKey: "liveExecution"); scheduleLiveExecution() }
    }
    var isLiveRunning = false
    var fatalError: String?
    var storageNotice: String?
    var backupNotice: String?
    var engineStatus = "Starting PostgreSQL…"
    var engineReady = false
    var isRunning = false
    var selection: String = ""
    var search = ""
    var filter = "All"
    var progress: [String: StepProgress] = [:]
    var drafts: [String: String] = [:]
    var attempts: [Attempt] = []
    var sql = "" {
        didSet {
            guard !selection.isEmpty, sql != oldValue else { return }
            drafts[selection] = sql
            do { try store?.saveDraft(sql, for: selection) }
            catch { storageNotice = error.localizedDescription }
            feedback = nil; feedbackPassed = nil; queryError = nil
            scheduleLiveExecution()
        }
    }
    var response = "" {
        didSet {
            guard !selection.isEmpty, response != oldValue else { return }
            feedback = nil; feedbackPassed = nil; queryError = nil
            drafts[selection + ".response"] = response
            do { try store?.saveDraft(response, for: selection + ".response") }
            catch { storageNotice = error.localizedDescription }
        }
    }
    var result: QueryResult?
    var schema: QueryResult?
    var preview: QueryResult?
    var feedback: String?
    var feedbackPassed: Bool?
    var queryError: String?
    var revealedHints = 0
    var showSolution = false
    var selectedResultTab = "Results"
    var showHistory = false
    var showStatistics = false
    var learningCenterTab = LearningCenterTab.activity
    var showHelp = false
    var expanded: Set<String> = []
    var inspectorVisible = true
    private var booting = false

    init() {
        let initialLanguage = UserDefaults.standard.string(forKey: "language") ?? "en"
        var loaded: Curriculum?
        var storage: ProgressStore?
        do { loaded = try Curriculum.load(language: CourseLanguage(rawValue: initialLanguage) ?? .english) } catch { fatalError = "Course could not load: \(error.localizedDescription)" }
        do { storage = try ProgressStore() } catch { storageNotice = error.localizedDescription }
        course = loaded; store = storage
        let engine = PostgresEngine()
        self.engine = engine; liveController = LiveQueryController(engine: engine)
        do {
            try storage?.migrateReadingSteps(lessonIDs: loaded?.lessons.map(\.id) ?? [])
            progress = try storage?.allProgress() ?? [:]
            drafts = try storage?.drafts() ?? [:]
            attempts = try storage?.attempts() ?? []
            if storageNotice == nil { storageNotice = storage?.recoveryNotice }
            selection = try storage?.position() ?? loaded?.steps.first?.id ?? ""
        } catch { storageNotice = error.localizedDescription }
        if loaded?.steps.contains(where: { $0.id == selection }) != true { selection = loaded?.steps.first?.id ?? "" }
        expandToSelection()
        sql = drafts[selection] ?? currentExercise?.starterSQL ?? currentStep?.sections.compactMap(\.code).first ?? "SELECT 'Hello, PostgreSQL!' AS message;"
        response = drafts[selection + ".response"] ?? ""
    }

    var steps: [LearningStep] { course?.steps ?? [] }
    var currentStep: LearningStep? { steps.first { $0.id == selection } }
    var currentLesson: Lesson? { course?.lessons.first { $0.id == currentStep?.lessonID } }
    var currentExercise: Exercise? { currentStep?.exercise }
    var position: Int { currentLesson?.steps.firstIndex(where: { $0.id == selection }) ?? 0 }
    var completedExercises: Int { course?.exercises.filter { progress[$0.id]?.completed == true }.count ?? 0 }
    var completionFraction: Double { Double(completedExercises) / Double(max(course?.exercises.count ?? 1, 1)) }
    var breadcrumb: String {
        guard let course, let lesson = currentLesson else { return "SQL & PostgreSQL" }
        for module in course.modules {
            for topic in module.topics where topic.lessons.contains(where: { $0.id == lesson.id }) { return "\(module.title)  /  \(topic.title)" }
        }
        return "SQL & PostgreSQL"
    }
    var activeFixture: String {
        guard let course, let ex = currentExercise ?? currentLesson?.exercises.first else { return "" }
        return course.fixture(for: ex)
    }

    func start() async {
        guard !shuttingDown, !booting, !engineReady else { return }
        booting = true; engineStatus = "Starting PostgreSQL…"
        do {
            try await engine.start()
            engineReady = true; engineStatus = "PostgreSQL \(PostgresEngine.version) · Local"
            await refreshSchema()
            scheduleLiveExecution()
        } catch { engineStatus = "Database unavailable"; queryError = error.localizedDescription }
        booting = false
    }

    private var explorationSQL: String {
        "-- " + L.text("Explore this lesson's dataset.", language: language) + "\nSELECT * FROM information_schema.tables\nWHERE table_schema = 'public';"
    }

    func select(_ id: String) {
        guard id != selection, steps.contains(where: { $0.id == id }) else { return }
        selection = id
        result = nil; feedback = nil; feedbackPassed = nil; queryError = nil; preview = nil
        revealedHints = 0; showSolution = false; selectedResultTab = "Results"
        invalidateLiveExecution()
        sql = drafts[id] ?? currentExercise?.starterSQL ?? currentStep?.sections.compactMap(\.code).first ?? explorationSQL
        response = drafts[id + ".response"] ?? ""
        var state = progress[id] ?? StepProgress(); state.visits += 1; state.updatedAt = Date()
        save(state, id: id)
        do { try store?.setPosition(id) } catch { storageNotice = error.localizedDescription }
        expandToSelection()
        if engineReady { Task { await refreshSchema() } }
        scheduleLiveExecution()
    }

    func expandToSelection() {
        guard let course, let current = currentStep else { return }
        for module in course.modules {
            for topic in module.topics {
                if topic.lessons.contains(where: { $0.id == current.lessonID }) {
                    expanded.formUnion([module.id, topic.id, current.lessonID])
                }
            }
        }
    }

    func save(_ state: StepProgress, id: String? = nil) {
        let key = id ?? selection
        progress[key] = state
        do { try store?.save(state, for: key) } catch { storageNotice = error.localizedDescription }
    }

    func toggle(_ key: WritableKeyPath<StepProgress, Bool>) {
        var state = progress[selection] ?? StepProgress()
        state[keyPath: key].toggle(); state.updatedAt = Date(); save(state)
    }

    func completeReading() {
        var state = progress[selection] ?? StepProgress(); state.completed = true; state.updatedAt = Date(); save(state)
        navigate(1)
    }

    func navigate(_ delta: Int) {
        guard let index = steps.firstIndex(where: { $0.id == selection }), steps.indices.contains(index + delta) else { return }
        select(steps[index + delta].id)
    }

    func nextIncomplete() {
        guard let course else { return }
        let exercises = course.exercises
        let start = exercises.firstIndex { $0.id == selection }.map { $0 + 1 } ?? 0
        let ordered = Array(exercises.dropFirst(start)) + Array(exercises.prefix(start))
        if let next = ordered.first(where: { progress[$0.id]?.completed != true }) { select(next.id) }
    }

    func reset() {
        sql = currentExercise?.starterSQL ?? currentStep?.sections.compactMap(\.code).first ?? "SELECT 1;"
        response = ""
        result = nil; queryError = nil; feedback = "Dataset reset. Every run starts from a fresh, isolated copy."; feedbackPassed = nil
        Task { await refreshSchema() }
        scheduleLiveExecution()
    }

    func run(submit: Bool = false) async {
        let kind = currentExercise?.kind ?? "query"
        let needsSQL = !submit || !["predict", "choose", "explain"].contains(kind)
        let needsEngine = needsSQL || kind == "predict"
        guard !shuttingDown, !isRunning, !needsEngine || engineReady else { return }
        if needsSQL, sql.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { feedback = "Write a SQL statement before running or submitting."; return }
        isRunning = true; queryError = nil; feedback = nil; feedbackPassed = nil; selectedResultTab = "Results"
        let capturedID = selection, capturedSQL = sql, capturedResponse = response, fixture = activeFixture
        let capturedPredictionRows = predictedRows
        let exercise = currentExercise
        invalidateLiveExecution()
        await liveController.cancel(revision: liveRevision)
        defer {
            isRunning = false
            if capturedID != selection || capturedSQL != sql { scheduleLiveExecution() }
        }
        do {
            if submit, let exercise, ["predict", "choose", "explain"].contains(exercise.kind) {
                if exercise.kind == "explain" {
                    guard selection == capturedID, response == capturedResponse else { return }
                    guard !capturedResponse.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { feedback = "Write your explanation in the lesson panel first."; return }
                    showSolution = true
                    feedback = "Compare your explanation with the rubric. Mark it reviewed when you have checked each point."
                    return
                }
                guard let course else { return }
                let answer = exercise.kind == "predict" ? String(decoding: try JSONEncoder().encode(capturedPredictionRows), as: UTF8.self) : capturedResponse
                let grade = try await GradingService(engine: engine).gradeResponse(answer, exercise: exercise, curriculum: course)
                recordAssessment(id: capturedID, answer: answer, passed: grade.passed, message: grade.message)
                if selection == capturedID, response == capturedResponse { feedback = grade.message; feedbackPassed = grade.passed; if grade.passed { result = grade.result } }
                return
            }
            if submit, let exercise, let course {
                let grade = try await GradingService(engine: engine).grade(sql: capturedSQL, exercise: exercise, curriculum: course)
                let attempt = Attempt(exerciseID: capturedID, sql: capturedSQL, passed: grade.passed, feedback: grade.message)
                attempts.insert(attempt, at: 0)
                do { try store?.record(attempt) } catch { storageNotice = error.localizedDescription }
                var state = progress[capturedID] ?? StepProgress()
                state.completed = state.completed || grade.passed
                state.review = !grade.passed; state.visits = max(state.visits, 1); state.updatedAt = Date()
                save(state, id: capturedID)
                guard selection == capturedID, sql == capturedSQL else { return }
                result = grade.result; feedback = grade.message; feedbackPassed = grade.passed
            } else {
                let queryResult = try await engine.execute(sql: capturedSQL, fixture: fixture)
                guard selection == capturedID, sql == capturedSQL else { return }
                result = queryResult
            }
        } catch {
            guard !shuttingDown else { return }
            let message = error.localizedDescription
            let sameAnswer = ["predict", "choose", "explain"].contains(exercise?.kind ?? "") ? response == capturedResponse : sql == capturedSQL
            if selection == capturedID, sameAnswer { result = nil; queryError = message }
            if submit {
                let answer = ["predict", "choose", "explain"].contains(exercise?.kind ?? "") ? capturedResponse : capturedSQL
                let attempt = Attempt(exerciseID: capturedID, sql: answer, passed: false, feedback: message)
                attempts.insert(attempt, at: 0)
                do { try store?.record(attempt) } catch { storageNotice = error.localizedDescription }
                var state = progress[capturedID] ?? StepProgress(); state.review = true; state.updatedAt = Date(); save(state, id: capturedID)
            }
        }
    }

    var selectedChoiceIDs: Set<String> { Set((try? JSONDecoder().decode([String].self, from: Data(response.utf8))) ?? []) }
    var predictedRows: [[String?]] {
        (try? JSONDecoder().decode([[String?]].self, from: Data(response.utf8))) ?? [Array(repeating: "", count: max(1, currentExercise?.predictionColumns?.count ?? 1))]
    }
    func updatePrediction(row: Int, column: Int, value: String?) {
        var rows = predictedRows
        guard rows.indices.contains(row), rows[row].indices.contains(column) else { return }
        rows[row][column] = value
        response = String(decoding: (try? JSONEncoder().encode(rows)) ?? Data(), as: UTF8.self)
    }
    func resizePrediction(add: Bool) {
        var rows = predictedRows
        if add, rows.count < 30 { rows.append(Array(repeating: "", count: max(1, currentExercise?.predictionColumns?.count ?? 1))) }
        else if !add, !rows.isEmpty { rows.removeLast() }
        response = String(decoding: (try? JSONEncoder().encode(rows)) ?? Data(), as: UTF8.self)
    }
    func toggleChoice(_ id: String) {
        var selected = selectedChoiceIDs
        if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
        response = String(decoding: (try? JSONEncoder().encode(selected.sorted())) ?? Data(), as: UTF8.self)
    }
    private func recordAssessment(id: String, answer: String, passed: Bool, message: String) {
        let attempt = Attempt(exerciseID: id, sql: answer, passed: passed, feedback: message)
        attempts.insert(attempt, at: 0)
        do { try store?.record(attempt) } catch { storageNotice = error.localizedDescription }
        var state = progress[id] ?? StepProgress(); state.completed = state.completed || passed; state.review = !passed
        state.visits = max(1, state.visits); state.updatedAt = Date(); save(state, id: id)
    }
    func completeExplanation() {
        guard currentExercise?.kind == "explain", !response.isEmpty, showSolution else { return }
        recordAssessment(id: selection, answer: response, passed: true, message: "Self-assessed with the explanation rubric. This response was not automatically graded.")
        feedback = "Explanation reviewed and saved."; feedbackPassed = true
    }

    func refreshSchema() async {
        let id = selection, fixture = activeFixture
        guard engineReady else { return }
        do {
            let data = try await engine.execute(sql: """
            SELECT t.relname AS \"Table\", a.attname AS \"Column\", format_type(a.atttypid,a.atttypmod) AS \"Type\",
                   CASE WHEN a.attnotnull THEN 'NO' ELSE 'YES' END AS \"Nullable\",
                   COALESCE(pg_get_expr(d.adbin,d.adrelid),'') AS \"Default\",
                   COALESCE((SELECT string_agg(pg_get_constraintdef(c.oid), '; ' ORDER BY c.contype,pg_get_constraintdef(c.oid))
                     FROM pg_constraint c WHERE c.conrelid=t.oid AND a.attnum=ANY(c.conkey)), '') AS \"Constraints\"
            FROM pg_class t JOIN pg_namespace n ON n.oid=t.relnamespace
            JOIN pg_attribute a ON a.attrelid=t.oid AND a.attnum>0 AND NOT a.attisdropped
            LEFT JOIN pg_attrdef d ON d.adrelid=t.oid AND d.adnum=a.attnum
            WHERE n.nspname='public' AND t.relkind IN ('r','p','v','m')
            ORDER BY t.relname,a.attnum;
            """, fixture: fixture)
            if selection == id { schema = data }
        } catch { if selection == id { schema = nil } }
    }

    func previewTable(_ table: String) async {
        guard !shuttingDown, engineReady, !isRunning else { return }
        isRunning = true
        let id = selection, fixture = activeFixture
        invalidateLiveExecution()
        await liveController.cancel(revision: liveRevision)
        defer { isRunning = false; scheduleLiveExecution() }
        do {
            let quoted = table.replacingOccurrences(of: "\"", with: "\"\"")
            let data = try await engine.execute(sql: "SELECT * FROM public.\"\(quoted)\" LIMIT 50", fixture: fixture)
            if id == selection { preview = data; selectedResultTab = "Preview" }
        } catch { if id == selection { queryError = error.localizedDescription } }
    }

    func exportProgress() {
        backupNotice = nil
        let panel = NSSavePanel(); panel.nameFieldStringValue = "SQLLY-Progress.json"; panel.allowedContentTypes = [.json]
        panel.title = L.text("Export Learning Progress…")
        panel.prompt = L.text("Export")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            guard let data = try store?.exportData() else { throw StorageFailure(message: "Progress storage is unavailable.") }
            try data.write(to: url, options: .atomic)
            feedback = "Progress exported to \(url.lastPathComponent)."; backupNotice = feedback
        }
        catch { storageNotice = error.localizedDescription }
    }

    func importProgress() {
        backupNotice = nil
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]; panel.allowsMultipleSelection = false
        panel.title = L.text("Import Learning Progress…")
        panel.prompt = L.text("Import")
        panel.message = L.text("Merge a progress backup. Completion and review flags are combined; your existing drafts and current position are preserved.")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            guard let store else { throw StorageFailure(message: "Progress storage is unavailable.") }
            let count = try store.importData(Data(contentsOf: url))
            progress = try store.allProgress(); attempts = try store.attempts(); drafts = try store.drafts()
            feedback = "Merged \(count) progress entries. Existing drafts and position were preserved."
            backupNotice = feedback
        } catch { storageNotice = error.localizedDescription }
    }

    func setLanguage(_ value: String) {
        guard let newLanguage = CourseLanguage(rawValue: value) else { return }
        do {
            let previousStarter = currentExercise?.starterSQL ?? currentStep?.sections.compactMap(\.code).first ?? explorationSQL
            let translated = try Curriculum.load(language: newLanguage)
            course = translated; language = value
            UserDefaults.standard.set(value, forKey: "language")
            if sql == previousStarter {
                sql = currentExercise?.starterSQL ?? currentStep?.sections.compactMap(\.code).first ?? explorationSQL
            }
            feedback = nil; feedbackPassed = nil; queryError = nil; fatalError = nil
        } catch { fatalError = error.localizedDescription }
    }

    private func invalidateLiveExecution() {
        liveRevision &+= 1; liveContext = "\(selection)|\(liveRevision)"
        isLiveRunning = false
    }
    func scheduleLiveExecution() {
        invalidateLiveExecution()
        let context = liveContext, revision = liveRevision
        let text = sql, fixture = activeFixture, stepID = selection
        guard !shuttingDown, liveEnabled, engineReady, !isRunning, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !["choose", "explain", "predict"].contains(currentExercise?.kind ?? "") else {
            Task { await liveController.cancel(revision: revision) }
            return
        }
        isLiveRunning = true
        Task { [weak self, liveController] in
            await liveController.submit(sql: text, fixture: fixture, context: context, revision: revision) { [weak self] event in
                await MainActor.run {
                    guard let self, self.liveContext == context, self.selection == stepID,
                          self.liveEnabled, !self.isRunning else { return }
                    switch event {
                    case .started: self.isLiveRunning = true
                    case let .result(_, value): self.result = value.command.isEmpty && value.columns.isEmpty ? nil : value; self.queryError = nil; self.isLiveRunning = false
                    case let .failure(_, message): self.result = nil; self.queryError = message; self.isLiveRunning = false
                    case .idle: self.isLiveRunning = false
                    }
                }
            }
        }
    }
    func shutdown() async {
        shuttingDown = true; engineReady = false
        invalidateLiveExecution()
        await liveController.shutdown()
        await engine.shutdown()
    }
}

import SwiftUI
import SQLCore

enum LearningCenterTab: String, CaseIterable, Identifiable {
    case activity, map, history, settings
    var id: Self { self }
    var title: String {
        switch self {
        case .activity: "Daily activity"
        case .map: "Course map"
        case .history: "History"
        case .settings: "Settings"
        }
    }
    var symbol: String {
        switch self {
        case .activity: "square.grid.3x3"
        case .map: "point.topleft.down.to.point.bottomright.curvepath"
        case .history: "clock.arrow.circlepath"
        case .settings: "gearshape"
        }
    }
    var detail: String {
        switch self {
        case .activity: "A little practice, every day."
        case .map: "Your position in the complete learning path."
        case .history: "Revisit your submitted answers and feedback."
        case .settings: "Make SQLLY comfortable for you."
        }
    }
}

/// A single native destination for personal learning tools. Activity comes from
/// persisted submissions; selecting a calendar square never changes progress.
struct LearningCenterView: View {
    @Bindable var model: WorkspaceModel
    @Environment(\.dismiss) private var dismiss
    @State private var selectedDay = Calendar.current.startOfDay(for: Date())
    @State private var historyDay: Date?
    private var activity: LearningActivity { LearningActivity(attempts: model.attempts) }

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("SQLLY").font(.system(size: 19, weight: .semibold)).tracking(1.5).padding(.bottom, 4)
                Text(L.text("Learning Center")).font(.callout).foregroundStyle(.secondary).padding(.bottom, 24)
                ForEach(LearningCenterTab.allCases) { tab in
                    Button {
                        model.learningCenterTab = tab
                        if tab == .history { historyDay = nil }
                    } label: {
                        Label(L.text(tab.title), systemImage: tab.symbol)
                            .font(.system(size: 13, weight: model.learningCenterTab == tab ? .semibold : .regular))
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).padding(.horizontal, 12)
                            .foregroundStyle(model.learningCenterTab == tab ? Color.craft : .primary)
                            .background(model.learningCenterTab == tab ? Color.craft.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 8))
                    }.buttonStyle(.plain).accessibilityAddTraits(model.learningCenterTab == tab ? .isSelected : [])
                }
                Spacer()
                Button { dismiss() } label: {
                    Label {
                        Text(L.text("Back to lesson")).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    } icon: { Image(systemName: "arrow.left") }
                        .frame(maxWidth: .infinity, minHeight: 38)
                }.buttonStyle(.bordered).keyboardShortcut(.cancelAction)
            }.padding(18).frame(width: 190).frame(maxHeight: .infinity).background(Color.surface)
            Divider()
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text(L.text(model.learningCenterTab.title)).font(.title2.weight(.semibold))
                        Text(L.text(model.learningCenterTab.detail)).font(.callout).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { dismiss() } label: { Image(systemName: "xmark").frame(width: 32, height: 32) }
                        .buttonStyle(.borderless).accessibilityLabel(L.text("Close Learning Center"))
                }.padding(24)
                Divider()
                switch model.learningCenterTab {
                case .activity: activityPage
                case .map: CourseMapView(model: model, openStep: openStep)
                case .history: historyPage
                case .settings: settingsPage
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity).background(Color.canvas)
        }.frame(width: 960, height: 680).controlSize(.large).tint(.craft)
    }

    private var activityPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                HStack(alignment: .top, spacing: 30) {
                    ActivityMetric(title: "Exercises solved", value: "\(model.completedExercises) / \(model.course?.exercises.count ?? 0)")
                    ActivityMetric(title: "Active days · 26 weeks", value: "\(activity.activeDays)")
                    ActivityMetric(title: "Current streak · days", value: "\(activity.currentStreak)")
                }.frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text(L.text("Last 26 weeks")).font(.headline)
                        Spacer()
                        Text(L.format("%ld submissions", activity.totalAttempts)).font(.callout).foregroundStyle(.secondary)
                    }
                    ActivityCalendar(activity: activity, selectedDay: $selectedDay, language: model.language)
                    Text(L.text("Squares count submitted answers, including retries. Running SQL and reading do not add activity.")).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }.padding(18).background(Color.surface, in: RoundedRectangle(cornerRadius: 10))
                let day = activity.days.first { Calendar.current.isDate($0.date, inSameDayAs: selectedDay) }
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text(LearningDates.text(selectedDay, language: model.language)).font(.headline)
                        Spacer()
                        Button(L.text("View submissions")) { historyDay = selectedDay; model.learningCenterTab = .history }
                            .disabled((day?.attemptCount ?? 0) == 0)
                    }
                    Text(L.format("%ld submitted · %ld correct · %ld first solves", day?.attemptCount ?? 0, day?.correctAttemptCount ?? 0, day?.newlySolvedCount ?? 0))
                        .font(.callout).foregroundStyle(.secondary)
                    if activity.totalAttempts == 0 {
                        Text(L.text("Your first submitted answer starts your activity calendar. Your course position and reading progress are already saved.")).font(.callout).foregroundStyle(.secondary).lineSpacing(4)
                    }
                }
                HStack(spacing: 22) {
                    Label(L.format("Longest streak: %ld days", activity.longestStreak), systemImage: "flame")
                    if let date = activity.lastStudyDate {
                        HStack(spacing: 5) { Text(L.text("Last submission")); Text(LearningDates.text(date, language: model.language, includingTime: true)) }
                    }
                }.font(.caption).foregroundStyle(.secondary)
            }.padding(24)
        }
    }

    private var historyPage: some View {
        VStack(spacing: 0) {
            if let date = historyDay {
                HStack {
                    Text(LearningDates.text(date, language: model.language)).font(.callout.weight(.medium))
                    Spacer()
                    Button(L.text("Show all dates")) { historyDay = nil }
                }.padding(.horizontal, 24).padding(.vertical, 14)
                Divider()
            }
            let attempts = model.attempts.filter { attempt in historyDay.map { Calendar.current.isDate(attempt.date, inSameDayAs: $0) } ?? true }
            if attempts.isEmpty {
                EmptyPanel(symbol: "clock.arrow.circlepath", title: "No attempts yet", detail: "Submit an exercise to save your SQL and feedback here.")
            } else {
                List(attempts) { attempt in
                    LearningAttemptRow(model: model, attempt: attempt, openStep: openStep, restore: {
                        model.select(attempt.exerciseID)
                        if ["choose", "predict", "explain"].contains(model.currentExercise?.kind ?? "") { model.response = attempt.sql }
                        else { model.sql = attempt.sql }
                        dismiss()
                    })
                }.listStyle(.inset).scrollContentBackground(.hidden)
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var settingsPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PreferencesView().frame(height: 260).scrollContentBackground(.hidden)
                Divider()
                Text(L.text("Learning data")).font(.headline)
                Text(L.text("Export a local backup or merge one from another Mac. Imports preserve your existing answers and completion.")).font(.callout).foregroundStyle(.secondary)
                HStack(spacing: 12) {
                    Button { model.exportProgress() } label: { Label(L.text("Export progress…"), systemImage: "square.and.arrow.up").frame(minHeight: 28) }
                    Button { model.importProgress() } label: { Label(L.text("Import & merge…"), systemImage: "square.and.arrow.down").frame(minHeight: 28) }
                }.buttonStyle(.bordered)
                Text(L.text("Saved locally on this Mac")).font(.caption).foregroundStyle(.secondary)
                if let notice = model.backupNotice { NoticeBanner(text: L.message(notice), kind: .success) }
                if let notice = model.storageNotice { NoticeBanner(text: L.message(notice), kind: .error) }
            }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func openStep(_ id: String) { model.select(id); dismiss() }
}

private struct ActivityMetric: View {
    let title: String
    let value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(value).font(.system(size: 27, weight: .semibold, design: .rounded)).monospacedDigit()
            Text(L.text(title)).font(.caption).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ActivityCalendar: View {
    let activity: LearningActivity
    @Binding var selectedDay: Date
    let language: String
    private let size: CGFloat = 17
    private let gap: CGFloat = 4
    private var calendar: Calendar { var value = Calendar.current; value.firstWeekday = 2; return value }
    private var weeks: [[Date]] {
        guard let start = calendar.dateInterval(of: .weekOfYear, for: activity.startDate)?.start,
              let final = calendar.dateInterval(of: .weekOfYear, for: activity.endDate)?.end else { return [] }
        var dates: [Date] = [], date = start
        while date < final {
            dates.append(date)
            guard let next = calendar.date(byAdding: .day, value: 1, to: date) else { break }
            date = next
        }
        return stride(from: 0, to: dates.count, by: 7).map { Array(dates[$0..<min($0 + 7, dates.count)]) }
    }
    private var byDate: [Date: LearningActivity.Day] { Dictionary(uniqueKeysWithValues: activity.days.map { ($0.date, $0) }) }
    var body: some View {
        let groups = weeks
        let days = byDate
        ScrollView(.horizontal, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: gap) {
                    Color.clear.frame(width: 24, height: 16)
                    ZStack(alignment: .topLeading) {
                        ForEach(monthMarkers(groups), id: \.self) { index in
                            Text(month(groups[index][0])).font(.system(size: 10)).foregroundStyle(.secondary).fixedSize()
                                .offset(x: CGFloat(index) * (size + gap), y: 0)
                        }
                    }.frame(width: CGFloat(groups.count) * (size + gap), height: 16, alignment: .topLeading)
                }
                HStack(alignment: .top, spacing: gap) {
                    VStack(spacing: gap) {
                        ForEach(0..<7) { row in
                            Text([0, 2, 4].contains(row) ? weekday(row) : "").font(.system(size: 9)).foregroundStyle(.secondary).frame(width: 24, height: size, alignment: .leading)
                        }
                    }.accessibilityHidden(true)
                    ForEach(Array(groups.enumerated()), id: \.offset) { _, week in
                        VStack(spacing: gap) {
                            ForEach(week, id: \.self) { date in
                                if let day = days[date] {
                                    Button { selectedDay = date } label: {
                                        RoundedRectangle(cornerRadius: 3).fill(color(day.attemptCount))
                                            .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(Calendar.current.isDate(date, inSameDayAs: selectedDay) ? Color.primary.opacity(0.8) : Color.primary.opacity(0.06), lineWidth: Calendar.current.isDate(date, inSameDayAs: selectedDay) ? 1.5 : 0.5))
                                            .frame(width: size, height: size)
                                    }.buttonStyle(.plain).help(label(day)).accessibilityLabel(label(day))
                                        .accessibilityAddTraits(Calendar.current.isDate(date, inSameDayAs: selectedDay) ? .isSelected : [])
                                } else { Color.clear.frame(width: size, height: size).accessibilityHidden(true) }
                            }
                        }
                    }
                }
                HStack(spacing: 5) {
                    Spacer()
                    Text(L.text("Less activity")).font(.system(size: 10)).foregroundStyle(.secondary)
                    ForEach([0, 1, 3, 5, 8], id: \.self) { value in RoundedRectangle(cornerRadius: 2).fill(color(value)).frame(width: 11, height: 11).accessibilityHidden(true) }
                    Text(L.text("More activity")).font(.system(size: 10)).foregroundStyle(.secondary)
                }.padding(.top, 7)
            }.padding(.trailing, 8)
        }.accessibilityLabel(L.text("Daily submission calendar"))
    }
    private func color(_ count: Int) -> Color {
        count == 0 ? Color.secondary.opacity(0.12) : Color.craft.opacity(count == 1 ? 0.28 : count < 4 ? 0.48 : count < 7 ? 0.72 : 1)
    }
    private func monthMarkers(_ groups: [[Date]]) -> [Int] {
        let starts = groups.indices.filter { index in index == 0 || calendar.component(.month, from: groups[index][0]) != calendar.component(.month, from: groups[index - 1][0]) }
        // A one-week partial first month has no room for a second label beside it.
        return starts.filter { index in index != 0 || (starts.dropFirst().first.map { $0 >= 3 } ?? true) }
    }
    private func month(_ date: Date) -> String {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: language); formatter.setLocalizedDateFormatFromTemplate("MMM"); return formatter.string(from: date)
    }
    private func weekday(_ offset: Int) -> String {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: language)
        return formatter.veryShortWeekdaySymbols[(offset + 1) % 7]
    }
    private func label(_ day: LearningActivity.Day) -> String {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: language); formatter.dateStyle = .full
        return formatter.string(from: day.date) + ". " + L.format("%ld submitted · %ld correct · %ld first solves", day.attemptCount, day.correctAttemptCount, day.newlySolvedCount)
    }
}

private struct LearningAttemptRow: View {
    @Bindable var model: WorkspaceModel
    let attempt: Attempt
    let openStep: (String) -> Void
    let restore: () -> Void
    private var exercise: Exercise? { model.course?.exercises.first { $0.id == attempt.exerciseID } }
    var body: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 14) {
                if ["choose", "predict", "explain"].contains(exercise?.kind ?? "") { Text(attempt.sql).font(.callout).textSelection(.enabled) }
                else { CodeBlock(code: attempt.sql) }
                Text(L.message(attempt.feedback)).font(.callout).textSelection(.enabled)
                HStack(spacing: 12) {
                    Button(L.text("Restore answer"), action: restore)
                    Button(L.text("Open exercise")) { openStep(attempt.exerciseID) }
                }.buttonStyle(.bordered).padding(.bottom, 8)
            }.padding(.top, 14)
        } label: {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: attempt.passed ? "checkmark" : "arrow.counterclockwise").foregroundStyle(attempt.passed ? Color.craft : Color.orange).frame(width: 22)
                VStack(alignment: .leading, spacing: 6) {
                    Text(exercise?.title ?? attempt.exerciseID).font(.callout.weight(.medium))
                    Text(LearningDates.text(attempt.date, language: model.language, includingTime: true)).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text(L.text(attempt.feedback.hasPrefix("Self-assessed") || attempt.feedback.hasPrefix("Самостоятельная") ? "Reviewed" : attempt.passed ? "Correct" : "Keep practicing")).font(.caption).foregroundStyle(.secondary)
            }.padding(.vertical, 10)
        }
    }
}

/// Preformat dates with the explicit in-app language. SwiftUI's date Text
/// initializer can otherwise substitute the system locale in native sheets.
private enum LearningDates {
    static func text(_ date: Date, language: String, includingTime: Bool = false) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: language)
        formatter.setLocalizedDateFormatFromTemplate(includingTime ? "dMMMjm" : "EEEEdMMMM")
        return formatter.string(from: date)
    }
}

private struct CourseMapView: View {
    @Bindable var model: WorkspaceModel
    let openStep: (String) -> Void
    private var modules: [CourseModule] { model.course?.modules ?? [] }
    private var currentID: String? { modules.first { $0.lessons.contains { $0.id == model.currentStep?.lessonID } }?.id }
    var body: some View {
        ScrollViewReader { proxy in
            VStack(spacing: 0) {
                HStack {
                    Text(L.format("%ld / %ld exercises complete", model.completedExercises, model.course?.exercises.count ?? 0)).font(.callout).foregroundStyle(.secondary)
                    Spacer()
                    Button { if let currentID { proxy.scrollTo(currentID, anchor: .top) } } label: { Label(L.text("Find my position"), systemImage: "location") }
                }.padding(.horizontal, 24).padding(.vertical, 16)
                Divider()
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(modules.enumerated()), id: \.element.id) { index, module in
                            mapTopic(module, index: index).id(module.id)
                        }
                    }.padding(24)
                }.onAppear { if let currentID { proxy.scrollTo(currentID, anchor: .top) } }
            }
        }
    }
    private func mapTopic(_ module: CourseModule, index: Int) -> some View {
        let steps = module.lessons.flatMap(\.steps)
        let done = steps.filter { model.progress[$0.id]?.completed == true }.count
        let current = module.id == currentID
        let complete = done == steps.count
        return HStack(alignment: .top, spacing: 16) {
            VStack(spacing: 0) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8).fill(complete ? Color.craft : current ? Color.craft.opacity(0.16) : Color.secondary.opacity(0.09))
                    if complete { Image(systemName: "checkmark").foregroundStyle(Color.canvas) }
                    else { Text("\(index + 1)").font(.system(size: 13, weight: .semibold)).foregroundStyle(current ? Color.craft : .secondary) }
                }.frame(width: 36, height: 36).accessibilityHidden(true)
                Rectangle().fill((complete || current ? Color.craft : Color.secondary).opacity(0.22)).frame(width: 2).frame(maxHeight: .infinity).opacity(index == modules.count - 1 ? 0 : 1)
            }
            VStack(alignment: .leading, spacing: 13) {
                HStack(alignment: .top) {
                    Text(module.title).font(.headline)
                    Spacer()
                    if current { Text(L.text("You are here")).font(.caption.weight(.semibold)).foregroundStyle(Color.craft).padding(.horizontal, 8).padding(.vertical, 5).background(Color.craft.opacity(0.1), in: Capsule()) }
                }
                Text(L.format("%ld / %ld steps complete", done, steps.count)).font(.caption).foregroundStyle(.secondary)
                ForEach(module.lessons) { lesson in
                    let completed = lesson.steps.filter { model.progress[$0.id]?.completed == true }.count
                    let active = lesson.id == model.currentStep?.lessonID
                    Button {
                        if active { openStep(model.selection) }
                        else if let target = lesson.steps.first(where: { model.progress[$0.id]?.completed != true }) ?? lesson.steps.first { openStep(target.id) }
                    } label: {
                        HStack(spacing: 10) {
                            RoundedRectangle(cornerRadius: 1).fill(completed == lesson.steps.count ? Color.craft : active ? Color.teal : Color.secondary.opacity(0.25)).frame(width: 3, height: 22)
                            Text(lesson.title).font(.callout).multilineTextAlignment(.leading)
                            Spacer()
                            Text("\(completed)/\(lesson.steps.count)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                            Image(systemName: "arrow.up.right").font(.caption).foregroundStyle(.secondary)
                        }.padding(.horizontal, 12).frame(minHeight: 42)
                            .background(active ? Color.teal.opacity(0.08) : Color.surface, in: RoundedRectangle(cornerRadius: 6))
                    }.buttonStyle(.plain)
                    .accessibilityLabel(lesson.title + ". " + L.format("%ld / %ld steps complete", completed, lesson.steps.count) + (active ? ". " + L.text("You are here") : ""))
                }
            }.padding(.bottom, 28).padding(.top, 5)
        }.fixedSize(horizontal: false, vertical: true)
    }
}

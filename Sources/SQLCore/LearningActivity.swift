import Foundation

/// Study activity derived solely from persisted explicit submissions.
///
/// Both correct and incorrect submissions contribute to activity. Reading visits,
/// manual Run, and debounced live execution do not create `Attempt` records and
/// therefore do not contribute. This type does not read or modify persistence.
///
/// `days` and the attempt/active-day/solved totals cover the requested local-day
/// window, including today. Newly solved exercises are determined using their
/// first successful submission in the complete available history. Repeating an
/// exercise solved before the window contributes activity, but no new solution.
/// Streaks use the complete available history, so a long streak is not truncated
/// merely because the heatmap displays fewer days.
public struct LearningActivity: Sendable {
    public struct Day: Identifiable, Equatable, Sendable {
        /// Start of the local calendar day, suitable as a stable heatmap ID.
        public let date: Date
        public var id: Date { date }
        public let attemptCount: Int
        public let correctAttemptCount: Int
        public let newlySolvedCount: Int
        /// Number of distinct exercise IDs submitted on this day.
        public let uniqueExercises: Int
    }

    /// One entry per local calendar day, oldest first, including empty days.
    /// Day ranges are not week-aligned; the UI can pad its Monday-first grid.
    public let days: [Day]
    /// Calendar snapshot used for grouping and streak adjacency.
    public let calendar: Calendar
    /// Inclusive first and last displayed local-day starts.
    public let startDate: Date
    public let endDate: Date
    public let totalAttempts: Int
    public let correctAttemptCount: Int
    public let activeDays: Int
    /// Exercises whose first lifetime successful submission falls in the window.
    public let solvedCount: Int
    /// Consecutive active days ending today, or yesterday if today is inactive.
    public let currentStreak: Int
    /// Longest consecutive active-day run in the complete available history.
    public let longestStreak: Int
    /// Latest actual submission timestamp, even when older than the heatmap.
    public let lastStudyDate: Date?

    /// Deduplicates UUIDs and excludes timestamps after `now` before counting.
    /// If conflicting copies of one UUID occur, the earliest valid timestamp is
    /// retained; ties use exercise ID and prefer an unsuccessful outcome. Normal
    /// persisted attempts have immutable, unique UUIDs, so this is only a defensive
    /// rule for duplicated input. Nonpositive `dayCount` is treated as one day.
    public init(
        attempts: [Attempt],
        now: Date = Date(),
        calendar: Calendar = .current,
        dayCount: Int = 182
    ) {
        self.calendar = calendar
        let today = calendar.startOfDay(for: now)
        self.endDate = today

        // Calendar arithmetic, rather than 86,400-second intervals, preserves
        // midnight boundaries through daylight-saving and offset transitions.
        var descendingDates = [today]
        while descendingDates.count < max(1, dayCount) {
            let current = descendingDates[descendingDates.count - 1]
            guard let previous = Self.adjacentDay(to: current, offset: -1, calendar: calendar), previous < current else { break }
            descendingDates.append(previous)
        }
        let displayedDates = Array(descendingDates.reversed())
        self.startDate = displayedDates[0]

        var deduplicated: [UUID: Attempt] = [:]
        for attempt in attempts where attempt.date.timeIntervalSince1970.isFinite && attempt.date <= now {
            if let existing = deduplicated[attempt.id] {
                if Self.precedes(attempt, existing) { deduplicated[attempt.id] = attempt }
            } else { deduplicated[attempt.id] = attempt }
        }

        struct Counts {
            var attempts = 0
            var correct = 0
            var newlySolved = 0
            var exercises: Set<String> = []
        }
        var counts: [Date: Counts] = [:]
        var firstSuccess: [String: Date] = [:]
        for attempt in deduplicated.values {
            let day = calendar.startOfDay(for: attempt.date)
            var value = counts[day] ?? Counts()
            value.attempts += 1
            if attempt.passed {
                value.correct += 1
                if firstSuccess[attempt.exerciseID].map({ attempt.date < $0 }) ?? true {
                    firstSuccess[attempt.exerciseID] = attempt.date
                }
            }
            value.exercises.insert(attempt.exerciseID)
            counts[day] = value
        }
        for success in firstSuccess.values {
            let day = calendar.startOfDay(for: success)
            // A first success necessarily already has an activity bucket.
            counts[day, default: Counts()].newlySolved += 1
        }

        let activityDays = displayedDates.map { day in
            let value = counts[day] ?? Counts()
            return Day(date: day, attemptCount: value.attempts, correctAttemptCount: value.correct,
                       newlySolvedCount: value.newlySolved, uniqueExercises: value.exercises.count)
        }
        self.days = activityDays
        self.totalAttempts = activityDays.reduce(0) { $0 + $1.attemptCount }
        self.correctAttemptCount = activityDays.reduce(0) { $0 + $1.correctAttemptCount }
        self.activeDays = activityDays.filter { $0.attemptCount > 0 }.count
        self.solvedCount = activityDays.reduce(0) { $0 + $1.newlySolvedCount }
        self.lastStudyDate = deduplicated.values.map(\.date).max()

        let activeDates = counts.keys.sorted()
        var run = 0
        var longest = 0
        var previous: Date?
        for day in activeDates {
            if let previous, Self.adjacentDay(to: previous, offset: 1, calendar: calendar) == day { run += 1 }
            else { run = 1 }
            longest = max(longest, run)
            previous = day
        }
        self.longestStreak = longest
        let yesterday = Self.adjacentDay(to: today, offset: -1, calendar: calendar)
        if let latest = activeDates.last, latest == today || latest == yesterday { self.currentStreak = run }
        else { self.currentStreak = 0 }
    }

    private static func adjacentDay(to day: Date, offset: Int, calendar: Calendar) -> Date? {
        calendar.date(byAdding: .day, value: offset, to: day).map { calendar.startOfDay(for: $0) }
    }

    private static func precedes(_ first: Attempt, _ second: Attempt) -> Bool {
        if first.date != second.date { return first.date < second.date }
        if first.exerciseID != second.exerciseID { return first.exerciseID < second.exerciseID }
        return !first.passed && second.passed
    }
}

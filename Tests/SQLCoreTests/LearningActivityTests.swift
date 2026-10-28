import Foundation
import Testing
@testable import SQLCore

struct LearningActivityTests {
    private func date(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }
    private func calendar(_ zone: String = "UTC") -> Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: zone)!
        value.firstWeekday = 2
        return value
    }
    private func attempt(_ exercise: String, _ time: String, passed: Bool = false, id: UUID = UUID()) -> Attempt {
        var value = Attempt(exerciseID: exercise, sql: "SELECT 1", passed: passed, feedback: "")
        value.id = id; value.date = date(time)
        return value
    }

    @Test func emptyHistoryHasStableInclusiveWindow() {
        let now = date("2026-10-28T12:00:00Z")
        let summary = LearningActivity(attempts: [], now: now, calendar: calendar())
        #expect(summary.days.count == 182)
        #expect(summary.startDate == date("2026-04-30T00:00:00Z"))
        #expect(summary.endDate == date("2026-10-28T00:00:00Z"))
        #expect(summary.days.map(\.date) == summary.days.map(\.date).sorted())
        #expect(Set(summary.days.map(\.id)).count == 182)
        #expect(summary.days.allSatisfy { $0.attemptCount == 0 && $0.correctAttemptCount == 0 && $0.newlySolvedCount == 0 && $0.uniqueExercises == 0 })
        #expect(summary.totalAttempts == 0 && summary.correctAttemptCount == 0 && summary.activeDays == 0 && summary.solvedCount == 0)
        #expect(summary.currentStreak == 0 && summary.longestStreak == 0 && summary.lastStudyDate == nil)
        #expect(LearningActivity(attempts: [], now: now, calendar: calendar(), dayCount: 0).days.count == 1)
    }

    @Test func timezoneMidnightAndFutureCutoffAreAppliedBeforeGrouping() {
        let events = [
            attempt("before", "2026-10-27T18:55:00Z", passed: true),
            attempt("after", "2026-10-27T19:05:00Z", passed: true),
            attempt("future", "2026-10-27T19:20:00Z", passed: true)
        ]
        let summary = LearningActivity(attempts: events, now: date("2026-10-27T19:10:00Z"), calendar: calendar("Asia/Samarkand"), dayCount: 2)
        #expect(summary.days.map(\.date) == [date("2026-10-26T19:00:00Z"), date("2026-10-27T19:00:00Z")])
        #expect(summary.days.map(\.attemptCount) == [1, 1])
        #expect(summary.totalAttempts == 2 && summary.solvedCount == 2 && summary.activeDays == 2)
        #expect(summary.currentStreak == 2 && summary.longestStreak == 2)
        #expect(summary.lastStudyDate == date("2026-10-27T19:05:00Z"))
    }

    @Test func springDSTUsesCalendarDaysAndYesterdayGrace() {
        let events = [
            attempt("a", "2026-03-08T04:30:00Z"), // March 7, 23:30 EST.
            attempt("b", "2026-03-09T03:30:00Z"), // March 8, 23:30 EDT.
            attempt("c", "2026-03-09T04:30:00Z")  // March 9, 00:30 EDT.
        ]
        let cal = calendar("America/New_York")
        let summary = LearningActivity(attempts: events, now: date("2026-03-10T16:00:00Z"), calendar: cal, dayCount: 5)
        #expect(summary.days.map { cal.component(.day, from: $0.date) } == [6, 7, 8, 9, 10])
        #expect(summary.days.map(\.attemptCount) == [0, 1, 1, 1, 0])
        #expect(summary.days[3].date.timeIntervalSince(summary.days[2].date) == 23 * 3600)
        #expect(summary.currentStreak == 3 && summary.longestStreak == 3)
    }

    @Test func repeatedFallHourRemainsOneStudyDay() {
        let events = [
            attempt("a", "2026-11-01T05:30:00Z"), // First 01:30.
            attempt("b", "2026-11-01T06:30:00Z", passed: true) // Second 01:30.
        ]
        let summary = LearningActivity(attempts: events, now: date("2026-11-02T17:00:00Z"), calendar: calendar("America/New_York"), dayCount: 3)
        #expect(summary.days.map(\.attemptCount) == [0, 2, 0])
        #expect(summary.days[2].date.timeIntervalSince(summary.days[1].date) == 25 * 3600)
        #expect(summary.activeDays == 1 && summary.currentStreak == 1 && summary.longestStreak == 1)
        #expect(summary.days[1].uniqueExercises == 2 && summary.days[1].newlySolvedCount == 1)
    }

    @Test func duplicateUUIDsAndRepeatedSuccessesDoNotInflateLearning() {
        let repeated = attempt("a", "2026-10-28T09:00:00Z", passed: true)
        let events = [
            attempt("legacy", "2026-10-01T09:00:00Z", passed: true),
            attempt("a", "2026-10-26T09:00:00Z"),
            attempt("a", "2026-10-27T09:00:00Z", passed: true),
            repeated, repeated, repeated,
            attempt("b", "2026-10-28T10:00:00Z"),
            attempt("b", "2026-10-28T11:00:00Z"),
            attempt("legacy", "2026-10-28T12:00:00Z", passed: true)
        ]
        let summary = LearningActivity(attempts: events, now: date("2026-10-28T18:00:00Z"), calendar: calendar(), dayCount: 7)
        #expect(summary.totalAttempts == 6 && summary.correctAttemptCount == 3)
        #expect(summary.activeDays == 3 && summary.solvedCount == 1)
        #expect(summary.days.suffix(3).map(\.newlySolvedCount) == [0, 1, 0])
        #expect(summary.days.last?.attemptCount == 4)
        #expect(summary.days.last?.correctAttemptCount == 2)
        #expect(summary.days.last?.uniqueExercises == 3)
        #expect(summary.currentStreak == 3 && summary.longestStreak == 3)
    }

    @Test func wrongSubmissionsStillCountAsActivity() {
        let summary = LearningActivity(attempts: [attempt("same", "2026-10-28T09:00:00Z"), attempt("same", "2026-10-28T10:00:00Z")], now: date("2026-10-28T12:00:00Z"), calendar: calendar(), dayCount: 1)
        #expect(summary.totalAttempts == 2 && summary.correctAttemptCount == 0 && summary.solvedCount == 0)
        #expect(summary.activeDays == 1 && summary.days[0].uniqueExercises == 1)
        #expect(summary.currentStreak == 1 && summary.longestStreak == 1)
    }

    @Test func windowTotalsDoNotTruncateLifetimeStreaksOrFirstSuccesses() {
        let events = [
            attempt("legacy", "2026-10-01T09:00:00Z", passed: true),
            attempt("early", "2026-10-02T09:00:00Z"),
            attempt("early", "2026-10-03T09:00:00Z"),
            attempt("early", "2026-10-04T09:00:00Z"),
            attempt("early", "2026-10-05T09:00:00Z"),
            attempt("x", "2026-10-25T09:00:00Z"),
            attempt("x", "2026-10-26T09:00:00Z"),
            attempt("x", "2026-10-27T09:00:00Z"),
            attempt("legacy", "2026-10-28T09:00:00Z", passed: true)
        ]
        let summary = LearningActivity(attempts: events, now: date("2026-10-28T12:00:00Z"), calendar: calendar(), dayCount: 3)
        #expect(summary.totalAttempts == 3 && summary.activeDays == 3 && summary.correctAttemptCount == 1)
        #expect(summary.solvedCount == 0)
        #expect(summary.currentStreak == 4 && summary.longestStreak == 5)
        #expect(summary.lastStudyDate == date("2026-10-28T09:00:00Z"))
    }

    @Test func graceExpiresAfterOneInactiveDay() {
        let now = date("2026-10-28T12:00:00Z")
        let yesterday = [attempt("a", "2026-10-26T09:00:00Z"), attempt("b", "2026-10-27T09:00:00Z")]
        let older = [attempt("a", "2026-10-25T09:00:00Z"), attempt("b", "2026-10-26T09:00:00Z")]
        #expect(LearningActivity(attempts: yesterday, now: now, calendar: calendar()).currentStreak == 2)
        let summary = LearningActivity(attempts: older, now: now, calendar: calendar())
        #expect(summary.currentStreak == 0 && summary.longestStreak == 2)
    }

    @Test func futureAttemptsAreIgnoredAndRangeStartsAtLocalMidnight() {
        let events = [
            attempt("a", "2026-10-25T23:59:59Z", passed: true),
            attempt("b", "2026-10-26T00:00:00Z"),
            attempt("c", "2026-10-27T09:00:00Z", passed: true),
            attempt("a", "2026-10-28T11:00:00Z", passed: true),
            attempt("now", "2026-10-28T12:00:00Z"),
            attempt("future_today", "2026-10-28T12:00:01Z", passed: true),
            attempt("future_day", "2026-10-29T09:00:00Z", passed: true)
        ]
        let summary = LearningActivity(attempts: events, now: date("2026-10-28T12:00:00Z"), calendar: calendar(), dayCount: 3)
        #expect(summary.totalAttempts == 4 && summary.correctAttemptCount == 2 && summary.activeDays == 3)
        #expect(summary.solvedCount == 1)
        #expect(summary.currentStreak == 4 && summary.longestStreak == 4)
        #expect(summary.lastStudyDate == date("2026-10-28T12:00:00Z"))
    }

    @Test func oldHistoryRemainsAvailableForLastStudyDate() {
        let event = attempt("old", "2025-01-01T09:00:00Z", passed: true)
        let summary = LearningActivity(attempts: [event], now: date("2026-10-28T12:00:00Z"), calendar: calendar())
        #expect(summary.totalAttempts == 0 && summary.activeDays == 0 && summary.solvedCount == 0)
        #expect(summary.currentStreak == 0 && summary.longestStreak == 1)
        #expect(summary.lastStudyDate == event.date)
    }

    @Test func conflictingDuplicateIDsHaveDeterministicConservativeResolution() {
        let id = UUID()
        let early = attempt("a", "2026-10-27T09:00:00Z", passed: true, id: id)
        let late = attempt("a", "2026-10-28T09:00:00Z", id: id)
        let conflictID = UUID()
        let failed = attempt("b", "2026-10-28T10:00:00Z", id: conflictID)
        let passed = attempt("b", "2026-10-28T10:00:00Z", passed: true, id: conflictID)
        let future = attempt("a", "2026-11-01T09:00:00Z", passed: true, id: id)
        let input = [late, passed, future, early, failed]
        let first = LearningActivity(attempts: input, now: date("2026-10-28T12:00:00Z"), calendar: calendar(), dayCount: 2)
        let reversed = LearningActivity(attempts: input.reversed(), now: date("2026-10-28T12:00:00Z"), calendar: calendar(), dayCount: 2)
        #expect(first.days == reversed.days)
        #expect(first.totalAttempts == 2 && first.correctAttemptCount == 1 && first.solvedCount == 1)
        #expect(first.days.map(\.attemptCount) == [1, 1])
    }

    @Test func leapDayIsIncludedInTheCalendarRange() {
        let events = [attempt("a", "2028-02-28T09:00:00Z"), attempt("b", "2028-02-29T09:00:00Z"), attempt("c", "2028-03-01T09:00:00Z")]
        let summary = LearningActivity(attempts: events, now: date("2028-03-01T12:00:00Z"), calendar: calendar(), dayCount: 3)
        #expect(summary.days.map(\.date) == [date("2028-02-28T00:00:00Z"), date("2028-02-29T00:00:00Z"), date("2028-03-01T00:00:00Z")])
        #expect(summary.currentStreak == 3 && summary.longestStreak == 3)
    }
}

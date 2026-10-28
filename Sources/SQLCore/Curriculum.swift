import Foundation

public struct Curriculum: Codable, Sendable {
    public let title: String
    public let version: String
    public let postgresVersion: String
    public let fixtures: [String: String]
    public let modules: [CourseModule]

    public static func load(language: CourseLanguage = .english) throws -> Curriculum {
        let name = language == .russian ? "curriculum-ru" : "curriculum"
        guard let url = SQLLYResources.coreBundle?.url(forResource: name, withExtension: "json", subdirectory: "Resources") else {
            throw CocoaError(.fileNoSuchFile)
        }
        let course = try JSONDecoder().decode(Curriculum.self, from: Data(contentsOf: url))
        try course.validate()
        return course
    }

    public var lessons: [Lesson] { modules.flatMap(\.topics).flatMap(\.lessons) }
    public var exercises: [Exercise] { lessons.flatMap(\.exercises) }
    public var steps: [LearningStep] { lessons.flatMap(\.steps) }
    public func lesson(for step: LearningStep) -> Lesson? { lessons.first { $0.id == step.lessonID } }
    public func fixture(for exercise: Exercise, index: Int = 0) -> String {
        guard exercise.fixtureIDs.indices.contains(index) else { return "" }
        return fixtures[exercise.fixtureIDs[index]] ?? ""
    }

    public func validate() throws {
        let ids = modules.map(\.id) + modules.flatMap(\.topics).map(\.id) + lessons.map(\.id) + steps.map(\.id)
        guard ids.count == Set(ids).count else { throw ContentError.invalid("Duplicate curriculum identifiers") }
        let lessonIDs = Set(lessons.map(\.id))
        for lesson in lessons {
            guard !lesson.sections.isEmpty, !lesson.exercises.isEmpty else { throw ContentError.invalid("Empty lesson: \(lesson.id)") }
            guard lesson.prerequisites.allSatisfy({ lessonIDs.contains($0) }) else { throw ContentError.invalid("Unknown prerequisite: \(lesson.id)") }
            for exercise in lesson.exercises {
                guard !exercise.solutionSQL.isEmpty, !exercise.fixtureIDs.isEmpty,
                      exercise.fixtureIDs.allSatisfy({ fixtures[$0] != nil }), !exercise.hints.isEmpty else {
                    throw ContentError.invalid("Incomplete exercise: \(exercise.id)")
                }
                if exercise.kind == "choose" {
                    let choices = exercise.choices ?? []
                    let answer = exercise.correctChoiceIDs ?? []
                    guard choices.count >= 2, !answer.isEmpty, Set(answer).isSubset(of: Set(choices.map(\.id))) else {
                        throw ContentError.invalid("Invalid choice exercise: \(exercise.id)")
                    }
                }
                if exercise.kind == "explain", exercise.modelAnswer?.isEmpty != false {
                    throw ContentError.invalid("Explanation rubric missing: \(exercise.id)")
                }
            }
        }
    }
}

public enum ContentError: LocalizedError {
    case invalid(String)
    public var errorDescription: String? { if case let .invalid(message) = self { return message }; return nil }
}

public struct CourseModule: Codable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let topics: [Topic]
    public var lessons: [Lesson] { topics.flatMap(\.lessons) }
}

public struct Topic: Codable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let lessons: [Lesson]
}

public struct Lesson: Codable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let prerequisites: [String]
    public let sections: [LessonSection]
    public let exercises: [Exercise]
    public var steps: [LearningStep] {
        let introduction = LearningStep(id: "\(id).read.0", lessonID: id, title: title, sections: Array(sections.prefix(9)), exercise: nil)
        let practice = exercises.map { LearningStep(id: $0.id, lessonID: id, title: $0.title, sections: [], exercise: $0) }
        let recap = LearningStep(id: "\(id).read.9", lessonID: id, title: sections.last?.title ?? title, sections: Array(sections.dropFirst(9)), exercise: nil)
        return [introduction] + practice + (recap.sections.isEmpty ? [] : [recap])
    }
}

public struct LessonSection: Codable, Sendable {
    public let title: String
    public let body: String
    public let code: String?
}

public struct Exercise: Codable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let prompt: String
    public let difficulty: String
    public let kind: String
    public let starterSQL: String
    public let solutionSQL: String
    public let fixtureIDs: [String]
    public let ordered: Bool
    public let columnNames: Bool
    public let hints: [String]
    public let explanation: String
    public let validationSQL: String?
    public var stateValidationSQL: String? = nil
    public var choices: [AnswerChoice]? = nil
    public var correctChoiceIDs: [String]? = nil
    public var modelAnswer: String? = nil
    public var predictionColumns: [String]? = nil
    public var checkOutput: Bool? = nil
    public var outputOrdered: Bool? = nil
}

public struct AnswerChoice: Codable, Identifiable, Sendable {
    public let id: String
    public let text: String
}

public struct LearningStep: Identifiable, Sendable {
    public let id: String
    public let lessonID: String
    public let title: String
    public let sections: [LessonSection]
    public var section: LessonSection? { sections.first }
    public let exercise: Exercise?
}

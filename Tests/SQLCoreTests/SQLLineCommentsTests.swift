import Foundation
import Testing
import SQLCore

struct SQLLineCommentsTests {
    private func toggle(_ text: String, _ selections: [NSRange]) throws -> (text: String, selections: [NSRange]) {
        let change = try #require(SQLLineComments.change(in: text as NSString, selections: selections))
        let output = NSMutableString(string: text)
        output.replaceCharacters(in: change.range, with: change.replacement)
        for selection in change.selections {
            #expect(selection.location <= output.length && selection.length <= output.length - selection.location)
        }
        return (output as String, change.selections)
    }

    @Test func caretStaysWithItsSQLCharacterAndRoundTrips() throws {
        let sql = "\t  SELECT 1;\nSELECT 2;"
        let caret = NSRange(location: (sql as NSString).range(of: "1").location, length: 0)
        let commented = try toggle(sql, [caret])
        #expect(commented.text == "\t  -- SELECT 1;\nSELECT 2;")
        #expect(commented.selections == [NSRange(location: caret.location + 3, length: 0)])
        let restored = try toggle(commented.text, commented.selections)
        #expect(restored.text == sql)
        #expect(restored.selections == [caret])
    }

    @Test func multilineSelectionAndItsRangeRoundTrip() throws {
        let sql = "  SELECT 1;\n\tSELECT 2;\n"
        let selection = NSRange(location: 0, length: (sql as NSString).length)
        let commented = try toggle(sql, [selection])
        #expect(commented.text == "  -- SELECT 1;\n\t-- SELECT 2;\n")
        #expect(commented.selections == [NSRange(location: 0, length: selection.length + 6)])
        let restored = try toggle(commented.text, commented.selections)
        #expect(restored.text == sql)
        #expect(restored.selections == [selection])
    }

    @Test func selectionEndingAtNextLineStartExcludesThatLine() throws {
        let sql = "SELECT 1;\nSELECT 2;\n"
        let boundary = (sql as NSString).range(of: "SELECT 2").location
        let selection = NSRange(location: 0, length: boundary)
        let commented = try toggle(sql, [selection])
        #expect(commented.text == "-- SELECT 1;\nSELECT 2;\n")
        #expect(commented.selections == [NSRange(location: 0, length: boundary + 3)])
        let restored = try toggle(commented.text, commented.selections)
        #expect(restored.text == sql)
        #expect(restored.selections == [selection])
    }

    @Test func tabsSpacesAndInterveningBlankLinesArePreserved() throws {
        let sql = " \tSELECT 1;\n   \n\tSELECT 2;"
        let commented = try toggle(sql, [NSRange(location: 0, length: (sql as NSString).length)])
        #expect(commented.text == " \t-- SELECT 1;\n   \n\t-- SELECT 2;")
        let restored = try toggle(commented.text, commented.selections)
        #expect(restored.text == sql)

        let noSpace = " \t--SELECT 1;\n \t-- SELECT 2;\n"
        let uncommented = try toggle(noSpace, [NSRange(location: 0, length: (noSpace as NSString).length)])
        #expect(uncommented.text == " \tSELECT 1;\n \tSELECT 2;\n")
    }

    @Test func emptyDocumentBlankSelectionAndFinalLineCanBeCommented() throws {
        let empty = try toggle("", [NSRange(location: 0, length: 0)])
        #expect(empty.text == "-- ")
        #expect(empty.selections == [NSRange(location: 3, length: 0)])
        let restored = try toggle(empty.text, empty.selections)
        #expect(restored.text.isEmpty && restored.selections == [NSRange(location: 0, length: 0)])

        let blank = "\t \n  "
        let commented = try toggle(blank, [NSRange(location: 0, length: (blank as NSString).length)])
        #expect(commented.text == "\t -- \n  -- ")
        #expect(try toggle(commented.text, commented.selections).text == blank)

        let sql = "SELECT 1;\n"
        let final = try toggle(sql, [NSRange(location: (sql as NSString).length, length: 0)])
        #expect(final.text == "SELECT 1;\n-- ")
        #expect(try toggle(final.text, final.selections).text == sql)
    }

    @Test func emojiAndNonASCIIUseUTF16SelectionOffsets() throws {
        let sql = "  SELECT '🙂привет' AS greeting;\nSELECT '東京';"
        let selectedWord = (sql as NSString).range(of: "привет")
        let commented = try toggle(sql, [selectedWord])
        #expect(commented.text == "  -- SELECT '🙂привет' AS greeting;\nSELECT '東京';")
        #expect(commented.selections == [NSRange(location: selectedWord.location + 3, length: selectedWord.length)])
        #expect((commented.text as NSString).substring(with: commented.selections[0]) == "привет")
        #expect(Range(commented.selections[0], in: commented.text) != nil)
        let restored = try toggle(commented.text, commented.selections)
        #expect(restored.text == sql && restored.selections == [selectedWord])

        let all = try toggle(sql, [NSRange(location: 0, length: (sql as NSString).length)])
        #expect(all.text == "  -- SELECT '🙂привет' AS greeting;\n-- SELECT '東京';")
        #expect(Range(all.selections[0], in: all.text) != nil)
    }

    @Test func windowsLineEndingsRemainCRLF() throws {
        let sql = "  SELECT 1;\r\n\tSELECT 2;\r\n"
        let commented = try toggle(sql, [NSRange(location: 0, length: (sql as NSString).length)])
        #expect(commented.text == "  -- SELECT 1;\r\n\t-- SELECT 2;\r\n")
        #expect(commented.text.components(separatedBy: "\r\n").count == 3)
        let restored = try toggle(commented.text, commented.selections)
        #expect(restored.text == sql)
    }

    @Test func disjointAndOverlappingSelectionsDoNotCommentALineTwice() throws {
        let sql = "SELECT 1;\nSELECT 2;\nSELECT 3;"
        let source = sql as NSString
        let selections = [source.range(of: "1"), source.range(of: "SELECT 1"), source.range(of: "3")]
        let commented = try toggle(sql, selections)
        #expect(commented.text == "-- SELECT 1;\nSELECT 2;\n-- SELECT 3;")
        #expect(commented.selections.count == selections.count)
        let restored = try toggle(commented.text, commented.selections)
        #expect(restored.text == sql)
        #expect(restored.selections == selections)
    }

    @Test func mixedCommentedAndUncommentedLinesRoundTripWithoutLosingComments() throws {
        let sql = "  -- SELECT 1;\n  SELECT 2;"
        let commented = try toggle(sql, [NSRange(location: 0, length: (sql as NSString).length)])
        #expect(commented.text == "  -- -- SELECT 1;\n  -- SELECT 2;")
        #expect(try toggle(commented.text, commented.selections).text == sql)
    }
}

import XCTest
@testable import CodexDock

final class FileChangeReviewModelsTests: XCTestCase {
    func testDiffParserPreservesSignsAndLineNumbers() {
        let lines = FileChangeDiffParser.parse("""
        @@ -10,3 +10,4 @@
         keep
        -old
        +new
        +added
        """)

        XCTAssertEqual(lines.map(\.sign), ["@@", " ", "-", "+", "+"])
        XCTAssertEqual(lines[1].oldLine, 10)
        XCTAssertEqual(lines[1].newLine, 10)
        XCTAssertEqual(lines[2].oldLine, 11)
        XCTAssertNil(lines[2].newLine)
        XCTAssertNil(lines[3].oldLine)
        XCTAssertEqual(lines[3].newLine, 11)
        XCTAssertNil(lines[4].oldLine)
        XCTAssertEqual(lines[4].newLine, 12)
    }

    func testDiffParserTreatsFullContentAddedFileAsAdditions() {
        let lines = FileChangeDiffParser.parse("""
        first
        second
        """, fallbackKind: "add")

        XCTAssertEqual(lines.map(\.sign), ["+", "+"])
        XCTAssertEqual(lines.map(\.newLine), [1, 2])
        XCTAssertEqual(lines.map(\.kind), [.addition, .addition])
    }
}

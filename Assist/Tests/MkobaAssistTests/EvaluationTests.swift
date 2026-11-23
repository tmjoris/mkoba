import Foundation
import MkobaCore
import XCTest
@testable import MkobaAssist

final class EvaluationTests: XCTestCase {
    let cases = try! EvalCase.load(URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Evals/messages.jsonl"))
    let state = EvalChama.state()

    func testTheEvalChama() {
        XCTAssertEqual(state.members.count, 10)
        XCTAssertTrue(state.rejected.isEmpty)
        XCTAssertEqual(state.group?.schedule.cycle(containing: EvalChama.now), CycleID(10))
    }

    func testLabelsAreConsistent() {
        XCTAssertEqual(Set(cases.map(\.id)).count, cases.count)
        for c in cases where c.expect == .record {
            XCTAssertNotNil(EvalChama.roster.first { $0.name == c.member }, c.id)
            XCTAssertTrue(c.text.contains(c.receipt ?? "-"), c.id)
            XCTAssertNotNil(c.cycle, c.id)
        }
    }

    /// The baseline reader gets every standard SMS right, with or without checks.
    func testRegexOnStandardMessages() {
        for c in cases where c.kind == "standard" {
            let result = EvalResult.evaluate(c, reading: MpesaSMSReader.read(c.text), error: nil, seconds: 0,
                                             state: state)
            XCTAssertEqual(result.withChecks, .correct, "\(c.id) \(result.issues)")
        }
    }

    func testAWrongMemberIsScoredWrong() throws {
        let c = try XCTUnwrap(cases.first { $0.id == "standard-02" })
        var reading = MpesaSMSReader.read(c.text)
        reading.senderPhone = "0711222333" // Grace's number instead of Amina's
        let result = EvalResult.evaluate(c, reading: reading, error: nil, seconds: 0, state: state)
        XCTAssertEqual(result.withoutChecks, .wrong)
    }

    func testAnAmbiguousSenderNeedsAPersonOnlyWithChecks() throws {
        let c = try XCTUnwrap(cases.first { $0.id == "ambiguous-01" })
        let result = EvalResult.evaluate(c, reading: MpesaSMSReader.read(c.text), error: nil, seconds: 0, state: state)
        XCTAssertEqual(result.withChecks, .correct)
        XCTAssertEqual(result.withoutChecks, .wrong)
    }
}

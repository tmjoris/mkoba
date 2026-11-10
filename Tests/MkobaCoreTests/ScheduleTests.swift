import XCTest
@testable import MkobaCore

final class ScheduleTests: XCTestCase {
    let jan1 = Date(timeIntervalSince1970: 1_767_214_800) // 2026-01-01 00:00 Nairobi (UTC+3)

    func testMonthlyCycles() {
        let schedule = ContributionSchedule(frequency: .monthly, amount: .kes(2_000), startDate: jan1, lateFee: .kes(200))
        XCTAssertEqual(schedule.cycle(containing: jan1), CycleID(0))
        XCTAssertEqual(schedule.cycle(containing: jan1.addingTimeInterval(30 * 86_400)), CycleID(0)) // Jan 31
        XCTAssertEqual(schedule.cycle(containing: jan1.addingTimeInterval(31 * 86_400)), CycleID(1)) // Feb 1
        XCTAssertEqual(schedule.cycle(containing: jan1.addingTimeInterval(365 * 86_400)), CycleID(12))
        XCTAssertEqual(schedule.cycle(containing: jan1.addingTimeInterval(-5)), CycleID(0), "pre-start dates clamp")
    }

    func testWeeklyCyclesAndGrace() {
        let schedule = ContributionSchedule(frequency: .weekly, amount: .kes(500), startDate: jan1,
                                            lateFee: .kes(50), graceDays: 2)
        XCTAssertEqual(schedule.cycle(containing: jan1.addingTimeInterval(6 * 86_400)), CycleID(0))
        XCTAssertEqual(schedule.cycle(containing: jan1.addingTimeInterval(7 * 86_400)), CycleID(1))
        XCTAssertEqual(schedule.start(of: CycleID(2)), jan1.addingTimeInterval(14 * 86_400))
        XCTAssertEqual(schedule.dueDate(for: CycleID(0)), jan1.addingTimeInterval(2 * 86_400))
        XCTAssertFalse(schedule.isLate(jan1.addingTimeInterval(2 * 86_400), for: CycleID(0)))
        XCTAssertTrue(schedule.isLate(jan1.addingTimeInterval(2 * 86_400 + 1), for: CycleID(0)))
    }

    func testLoanPolicyMaths() throws {
        let policy = LoanPolicy.saccoDefault
        XCTAssertEqual(try policy.borrowingLimit(savings: .kes(10_000)), .kes(30_000))
        XCTAssertEqual(try policy.borrowingLimit(savings: .kes(-500)), .zero())
        XCTAssertEqual(try policy.interest(on: .kes(24_000), termMonths: 6), .kes(1_440))
        let instalments = try policy.instalments(principal: .kes(10_000), termMonths: 3)
        XCTAssertEqual(try Money.sum(instalments), .kes(10_300))
        XCTAssertEqual(instalments.map(\.minor), [343_334, 343_333, 343_333])
        XCTAssertEqual(LoanPolicy(maxGuaranteePercentOfSavings: 50).maxGuarantee(savings: .kes(10_000)), .kes(5_000))
    }
}

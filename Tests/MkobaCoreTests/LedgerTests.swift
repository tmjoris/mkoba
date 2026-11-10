import XCTest
@testable import MkobaCore

final class LedgerTests: XCTestCase {
    func testContributionsBuildThePot() {
        var chama = ChamaFixture()
        chama.contribute(chama.amina, .kes(2_000), cycle: 0)
        chama.contribute(chama.brian, .kes(2_000), cycle: 0)
        chama.contribute(chama.amina, .kes(500), cycle: 0, day: 2)

        let state = chama.state
        XCTAssertEqual(state.pot, .kes(4_500))
        XCTAssertEqual(state.balance(of: chama.amina).savings, .kes(2_500))
        XCTAssertEqual(state.contributions(in: CycleID(0)), .kes(4_500))
        XCTAssertTrue(state.rejected.isEmpty)
    }

    func testArrearsListsWhoStillOwes() {
        var chama = ChamaFixture()
        chama.contribute(chama.amina, .kes(2_000), cycle: 1)
        chama.contribute(chama.brian, .kes(1_500), cycle: 1)

        let arrears = chama.state.arrears(for: CycleID(1))
        XCTAssertEqual(arrears.count, 3) // chair, treasurer, brian
        XCTAssertEqual(arrears.first { $0.member == chama.brian }?.shortfall, .kes(500))
        XCTAssertNil(arrears.first { $0.member == chama.amina })
    }

    func testOnlyOfficialsCanRecordMoney() {
        var chama = ChamaFixture()
        let rogue = chama.log.record(
            .contributionRecorded(member: chama.brian, amount: .kes(5_000), cycle: CycleID(0), reference: nil),
            by: chama.brian, on: chama.phone, at: chama.date(day: 1))

        let state = chama.state
        XCTAssertEqual(state.rejected[rogue.id], .notAnOfficial(chama.brian))
        XCTAssertEqual(state.pot, .zero())
        XCTAssertTrue(state.applied.contains(rogue.id), "rejected events still count as seen")
    }

    func testPayoutCannotExceedPot() {
        var chama = ChamaFixture()
        chama.contribute(chama.amina, .kes(1_000), cycle: 0)
        let payout = chama.log.record(.payoutRecorded(member: chama.amina, amount: .kes(1_001), reason: "hospital"),
                                      by: chama.treasurer, on: chama.phone, at: chama.date(day: 3))
        XCTAssertEqual(chama.state.rejected[payout.id], .insufficientPot(available: .kes(1_000)))
    }

    func testFullLoanLifecycle() throws {
        var chama = ChamaFixture()
        // Amina saves 10,000 over five months; Brian saves 20,000.
        for cycle in 0..<5 {
            chama.contribute(chama.amina, .kes(2_000), cycle: cycle, day: cycle * 30 + 1)
            chama.contribute(chama.brian, .kes(4_000), cycle: cycle, day: cycle * 30 + 1)
        }
        let loan = LoanID()
        // 3x savings = 30,000 limit; ask for 24,000 over 6 months at 1%/month -> 1,440 interest.
        chama.log.record(.loanRequested(loan: loan, borrower: chama.amina, principal: .kes(24_000), termMonths: 6),
                         by: chama.amina, on: chama.phone, at: chama.date(day: 150))
        chama.log.record(.loanGuaranteed(loan: loan, guarantor: chama.brian, amount: .kes(20_000)),
                         by: chama.brian, on: chama.phone, at: chama.date(day: 151))

        // Not fully guaranteed yet: approval must be rejected.
        let early = chama.log.record(.loanApproved(loan: loan, approver: chama.chair),
                                     by: chama.chair, on: chama.phone, at: chama.date(day: 152))
        XCTAssertEqual(chama.state.rejected[early.id],
                       .insufficientGuarantees(required: .kes(24_000), pledged: .kes(20_000)))

        chama.log.record(.loanGuaranteed(loan: loan, guarantor: chama.chair, amount: .kes(4_000)),
                         by: chama.chair, on: chama.phone, at: chama.date(day: 152))
        // Chair has no savings, so this guarantee is rejected; treasurer must step in. Give the chair savings first.
        XCTAssertEqual(chama.state.loans[loan]?.guaranteed, .kes(20_000))
        chama.contribute(chama.treasurer, .kes(4_000), cycle: 5, day: 152)
        chama.log.record(.loanGuaranteed(loan: loan, guarantor: chama.treasurer, amount: .kes(4_000)),
                         by: chama.treasurer, on: chama.phone, at: chama.date(day: 153))
        XCTAssertEqual(chama.state.loans[loan]?.guaranteed, .kes(24_000))

        chama.log.record(.loanApproved(loan: loan, approver: chama.chair),
                         by: chama.chair, on: chama.phone, at: chama.date(day: 154))
        chama.log.record(.loanDisbursed(loan: loan, reference: PaymentReference(mpesaReceipt: "QGH7K2L9MN")),
                         by: chama.treasurer, on: chama.phone, at: chama.date(day: 155))

        var state = chama.state
        XCTAssertEqual(state.loans[loan]?.status, .disbursed)
        XCTAssertEqual(state.loans[loan]?.interest, .kes(1_440))
        XCTAssertEqual(state.loans[loan]?.outstanding, .kes(25_440))
        XCTAssertEqual(state.pot, .kes(34_000 - 24_000))
        XCTAssertEqual(state.balance(of: chama.amina).loansOutstanding, .kes(25_440))
        XCTAssertEqual(state.balance(of: chama.brian).guaranteesPledged, .kes(20_000))

        // Repay in six instalments that sum exactly to total due.
        let instalments = try LoanPolicy.saccoDefault.instalments(principal: .kes(24_000), termMonths: 6)
        XCTAssertEqual(try Money.sum(instalments), .kes(25_440))
        for (index, instalment) in instalments.enumerated() {
            chama.log.record(.loanRepaid(loan: loan, amount: instalment, reference: nil),
                             by: chama.treasurer, on: chama.phone, at: chama.date(day: 180 + index * 30))
        }
        state = chama.state
        XCTAssertEqual(state.loans[loan]?.status, .repaid)
        XCTAssertEqual(state.loans[loan]?.outstanding, .zero())
        XCTAssertEqual(state.pot, .kes(10_000 + 25_440))
        XCTAssertEqual(state.balance(of: chama.brian).guaranteesPledged, .zero(), "pledges release on repayment")

        let overpay = chama.log.record(.loanRepaid(loan: loan, amount: .kes(1), reference: nil),
                                       by: chama.treasurer, on: chama.phone, at: chama.date(day: 400))
        XCTAssertEqual(chama.state.rejected[overpay.id], .loanNotInStatus(loan, expected: "disbursed"))
    }

    func testLoanAbovePolicyLimitIsRejected() {
        var chama = ChamaFixture()
        chama.contribute(chama.amina, .kes(1_000), cycle: 0)
        let loan = chama.log.record(
            .loanRequested(loan: LoanID(), borrower: chama.amina, principal: .kes(3_001), termMonths: 3),
            by: chama.amina, on: chama.phone, at: chama.date(day: 2))
        XCTAssertEqual(chama.state.rejected[loan.id], .loanExceedsPolicy(limit: .kes(3_000)))
    }

    func testBorrowerCannotGuaranteeOwnLoan() {
        var chama = ChamaFixture()
        chama.contribute(chama.amina, .kes(10_000), cycle: 0)
        let loan = LoanID()
        chama.log.record(.loanRequested(loan: loan, borrower: chama.amina, principal: .kes(5_000), termMonths: 3),
                         by: chama.amina, on: chama.phone, at: chama.date(day: 2))
        let selfie = chama.log.record(.loanGuaranteed(loan: loan, guarantor: chama.amina, amount: .kes(5_000)),
                                      by: chama.amina, on: chama.phone, at: chama.date(day: 2))
        XCTAssertEqual(chama.state.rejected[selfie.id], .guarantorIsBorrower)
    }

    func testReplayIsIndependentOfArrivalOrderAndDuplicates() {
        var chama = ChamaFixture()
        for cycle in 0..<6 {
            chama.contribute(chama.amina, .kes(2_000), cycle: cycle, day: cycle * 30 + 1)
            chama.contribute(chama.brian, .kes(2_000), cycle: cycle, day: cycle * 30 + 2)
        }
        let loan = LoanID()
        chama.log.record(.loanRequested(loan: loan, borrower: chama.amina, principal: .kes(6_000), termMonths: 2),
                         by: chama.amina, on: chama.phone, at: chama.date(day: 200))
        chama.log.record(.loanGuaranteed(loan: loan, guarantor: chama.brian, amount: .kes(6_000)),
                         by: chama.brian, on: chama.phone, at: chama.date(day: 201))
        chama.log.record(.loanApproved(loan: loan, approver: chama.chair),
                         by: chama.chair, on: chama.phone, at: chama.date(day: 202))

        let canonical = chama.state
        let events = chama.log.ordered
        var generator = SeededGenerator(seed: 42)
        for _ in 0..<50 {
            var shuffled = events.shuffled(using: &generator)
            shuffled.append(contentsOf: events.prefix(5)) // duplicates
            XCTAssertEqual(Ledger.replay(shuffled), canonical)
        }
    }

    func testTwoOfflineDevicesConverge() {
        let chama = ChamaFixture()
        var treasurerPhone = chama.log
        var chairPhone = chama.log
        let chairDevice = DeviceID("iphone-chair")

        // Both record while offline. Each only knows its own writes.
        treasurerPhone.record(.contributionRecorded(member: chama.amina, amount: .kes(2_000), cycle: CycleID(0), reference: nil),
                              by: chama.treasurer, on: chama.phone, at: chama.date(day: 1))
        chairPhone.record(.contributionRecorded(member: chama.brian, amount: .kes(2_000), cycle: CycleID(0), reference: nil),
                          by: chama.chair, on: chairDevice, at: chama.date(day: 1))
        chairPhone.record(.payoutRecorded(member: chama.brian, amount: .kes(3_000), reason: "emergency"),
                          by: chama.chair, on: chairDevice, at: chama.date(day: 2))

        XCTAssertNotEqual(treasurerPhone.replay(), chairPhone.replay())

        // Sync both ways through a server copy.
        var server = chama.log
        let fromTreasurer = server.serve(SyncRequest(from: treasurerPhone, lastSynced: chama.log.clock))
        treasurerPhone.merge(fromTreasurer.events)
        let fromChair = server.serve(SyncRequest(from: chairPhone, lastSynced: chama.log.clock))
        chairPhone.merge(fromChair.events)
        let catchUp = server.serve(SyncRequest(from: treasurerPhone, lastSynced: treasurerPhone.clock))
        treasurerPhone.merge(catchUp.events)

        XCTAssertEqual(treasurerPhone.count, chairPhone.count)
        XCTAssertEqual(treasurerPhone.replay(), chairPhone.replay())

        // The payout was recorded on a device that only saw 2,000 in the pot, but after the
        // merge the pot held 4,000 when the payout's clock position is replayed, so it stands.
        let merged = treasurerPhone.replay()
        XCTAssertEqual(merged.pot, .kes(1_000))
        XCTAssertTrue(merged.rejected.isEmpty)
    }

    func testEventsBeforeGroupCreationAreRejected() {
        var log = EventLog(group: GroupID())
        let member = MemberID()
        let orphan = log.record(.memberJoined(member: member, name: "X", phone: PhoneNumber("0700000000")!, role: .member),
                                by: member, on: DeviceID("d"))
        XCTAssertEqual(log.replay().rejected[orphan.id], .groupNotCreated)
    }
}

/// Deterministic RNG so shuffle-based tests reproduce exactly.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed == 0 ? 0x9E37_79B9_7F4A_7C15 : seed }
    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
}

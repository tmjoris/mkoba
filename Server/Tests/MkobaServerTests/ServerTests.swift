import MkobaCore
import XCTVapor
@testable import MkobaServer

final class ServerTests: XCTestCase {
    var app: Application!
    var chama: ChamaSeed!

    override func setUp() async throws {
        app = try await Application.make(.testing)
        try await configure(app)
        chama = ChamaSeed()
        // Seed the group through the public sync endpoint, like a phone would.
        try await app.testable().test(.POST, "v1/groups/\(chama.group)/sync", beforeRequest: { req in
            try req.content.encode(SyncRequest(from: chama.log, lastSynced: VectorClock()))
        }, afterResponse: { res async throws in
            XCTAssertEqual(res.status, .ok)
            XCTAssertEqual(try res.content.decode(SyncResponse.self).accepted, chama.log.count)
        })
    }

    override func tearDown() async throws {
        try await app.asyncShutdown()
        app = nil
    }

    func testSyncReturnsOnlyWhatTheClientLacks() async throws {
        // A second device that knows nothing asks for everything.
        try await app.testable().test(.POST, "v1/groups/\(chama.group)/sync", beforeRequest: { req in
            try req.content.encode(SyncRequest(group: chama.group, known: VectorClock(), events: []))
        }, afterResponse: { res async throws in
            let body = try res.content.decode(SyncResponse.self)
            XCTAssertEqual(body.events.count, chama.log.count)
            XCTAssertEqual(body.accepted, 0)
        })
        // The original device, fully caught up, gets nothing back.
        try await app.testable().test(.POST, "v1/groups/\(chama.group)/sync", beforeRequest: { req in
            try req.content.encode(SyncRequest(group: chama.group, known: chama.log.clock, events: []))
        }, afterResponse: { res async throws in
            XCTAssertEqual(try res.content.decode(SyncResponse.self).events.count, 0)
        })
    }

    func testLedgerSummary() async throws {
        try await app.testable().test(.GET, "v1/groups/\(chama.group)/ledger") { res async throws in
            let summary = try res.content.decode(LedgerSummary.self)
            XCTAssertEqual(summary.name, "Umoja Chama")
            XCTAssertEqual(summary.members, 2)
            XCTAssertEqual(summary.pot, "KES 0.00")
        }
    }

    func testSuccessfulPaymentLandsOnLedgerExactlyOnce() async throws {
        let payment = try await createPayment(phone: "0712345600")
        XCTAssertEqual(payment.attempts, 1)
        guard case .promptSent(let checkout) = payment.status else { return XCTFail("expected prompt") }

        try await waitUntilTerminal(payment.id)
        let done = try await fetch(payment.id)
        guard case .completed(let receipt) = done.status else { return XCTFail("expected completed, got \(done.status)") }
        XCTAssertEqual(receipt.amount, .kes(2_000))

        // Daraja retries callbacks: replaying the same one must be a no-op.
        let replay = SimulatedDaraja.callback(for: try stkRequest(phone: "0712345600"), checkout: checkout, suffix: "00")
        try await app.testable().test(.POST, "v1/payments/daraja/callback", beforeRequest: { req in
            try req.content.encode(replay)
        }, afterResponse: { res async in
            XCTAssertEqual(res.status, .ok)
        })

        let state = await app.store.state(for: chama.group)!
        XCTAssertEqual(state.contributions.count, 1)
        XCTAssertEqual(state.pot, .kes(2_000))
        XCTAssertEqual(state.contributions.first?.reference?.mpesaReceipt, receipt.number)
        XCTAssertTrue(state.rejected.isEmpty)
    }

    func testCancelledPaymentCanBeRetriedButNeverDoubleCharges() async throws {
        let payment = try await createPayment(phone: "0712345611")
        try await waitUntilTerminal(payment.id)
        let cancelled = try await fetch(payment.id)
        guard case .failed(let code, _) = cancelled.status else { return XCTFail("expected failed") }
        XCTAssertEqual(code, 1032)
        XCTAssertTrue(cancelled.canSendPrompt)

        // Retry is allowed once, and a retry on a live prompt is refused with 409.
        try await app.testable().test(.POST, "v1/payments/\(payment.id)/retry") { res async in
            XCTAssertEqual(res.status, .ok)
        }
        try await app.testable().test(.POST, "v1/payments/\(payment.id)/retry") { res async in
            XCTAssertEqual(res.status, .conflict)
        }
        try await waitUntilTerminal(payment.id)
        let second = try await fetch(payment.id)
        XCTAssertEqual(second.attempts, 2)
        // Same phone suffix, so the customer "cancels" again: two prompts, zero debits, zero ledger entries.
        guard case .failed = second.status else { return XCTFail("expected second cancel") }
        let pot = await app.store.state(for: chama.group)!.pot
        XCTAssertEqual(pot, .zero())
        let contributions = await app.store.state(for: chama.group)!.contributions.count
        XCTAssertEqual(contributions, 0)
    }

    func testLostCallbackIsRecoveredByStatusQuery() async throws {
        let payment = try await createPayment(phone: "0712345633")
        try await Task.sleep(for: .milliseconds(150))
        var current = try await fetch(payment.id)
        guard case .promptSent = current.status else { return XCTFail("callback should have been lost") }

        // Nothing changes until the prompt is old enough to be treated as unknown.
        await app.payments.reconcile(now: Date())
        current = try await fetch(payment.id)
        guard case .promptSent = current.status else { return XCTFail("too early to reconcile") }

        await app.payments.reconcile(now: Date().addingTimeInterval(PendingPayment.callbackTimeout + 1))
        current = try await fetch(payment.id)
        guard case .completed = current.status else { return XCTFail("expected completed after query, got \(current.status)") }
        let pot2 = await app.store.state(for: chama.group)!.pot
        XCTAssertEqual(pot2, .kes(2_000))
    }

    func testPushDarajaNeverSawGoesBackToRequested() async throws {
        let payment = try await createPayment(phone: "0712345644")
        await app.payments.reconcile(now: Date().addingTimeInterval(PendingPayment.callbackTimeout + 1))
        let current = try await fetch(payment.id)
        XCTAssertEqual(current.status, .requested)
        XCTAssertTrue(current.canSendPrompt)
        let pot3 = await app.store.state(for: chama.group)!.pot
        XCTAssertEqual(pot3, .zero())
    }

    func testRejectsBadInput() async throws {
        try await app.testable().test(.POST, "v1/payments", beforeRequest: { req in
            try req.content.encode(CreatePaymentRequest(group: chama.group, member: chama.amina, amountMinor: 200_050,
                                                        cycle: 0, phone: "0712345600", accountReference: nil))
        }, afterResponse: { res async in
            XCTAssertEqual(res.status, .badRequest)
        })
        try await app.testable().test(.POST, "v1/payments", beforeRequest: { req in
            try req.content.encode(CreatePaymentRequest(group: chama.group, member: MemberID(), amountMinor: 200_000,
                                                        cycle: 0, phone: "0712345600", accountReference: nil))
        }, afterResponse: { res async in
            XCTAssertEqual(res.status, .notFound)
        })
    }

    // MARK: - Helpers

    private func createPayment(phone: String) async throws -> PendingPayment {
        var created: PendingPayment?
        try await app.testable().test(.POST, "v1/payments", beforeRequest: { req in
            try req.content.encode(CreatePaymentRequest(group: chama.group, member: chama.amina, amountMinor: 200_000,
                                                        cycle: 0, phone: phone, accountReference: "UMOJA"))
        }, afterResponse: { res async throws in
            XCTAssertEqual(res.status, .accepted)
            created = try res.content.decode(PendingPayment.self)
        })
        return try XCTUnwrap(created)
    }

    private func fetch(_ id: UUID) async throws -> PendingPayment {
        var fetched: PendingPayment?
        try await app.testable().test(.GET, "v1/payments/\(id)") { res async throws in
            fetched = try res.content.decode(PendingPayment.self)
        }
        return try XCTUnwrap(fetched)
    }

    private func waitUntilTerminal(_ id: UUID, timeout: Duration = .seconds(3)) async throws {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if try await fetch(id).status.isTerminal { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTFail("payment \(id) never reached a terminal state")
    }

    private func stkRequest(phone: String) throws -> Daraja.StkPushRequest {
        try Daraja.StkPushRequest(credentials: app.payments.credentials, amount: .kes(2_000),
                                  phone: PhoneNumber(phone)!, callback: app.payments.callbackURL,
                                  accountReference: "UMOJA", description: "test")
    }
}

/// A two-member chama built client-side, the way the iOS app would before its first sync.
struct ChamaSeed {
    let group = GroupID()
    let device = DeviceID("test-phone")
    let chair = MemberID()
    let amina = MemberID()
    var log: EventLog

    init() {
        log = EventLog(group: group)
        let start = Date(timeIntervalSince1970: 1_767_225_600)
        let schedule = ContributionSchedule(frequency: .monthly, amount: .kes(2_000), startDate: start, lateFee: .kes(200))
        log.record(.groupCreated(name: "Umoja Chama", currency: .kes, schedule: schedule, loanPolicy: .saccoDefault),
                   by: chair, on: device, at: start)
        log.record(.memberJoined(member: chair, name: "Wanjiru", phone: PhoneNumber("0712000001")!, role: .chair),
                   by: chair, on: device, at: start)
        log.record(.memberJoined(member: amina, name: "Amina", phone: PhoneNumber("0712345600")!, role: .member),
                   by: chair, on: device, at: start)
    }
}

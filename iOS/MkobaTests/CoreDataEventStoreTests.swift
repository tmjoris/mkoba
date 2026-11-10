import CoreData
import MkobaCore
import XCTest
@testable import Mkoba

final class CoreDataEventStoreTests: XCTestCase {
    var store: CoreDataEventStore!

    override func setUp() {
        store = CoreDataEventStore(container: PersistenceController(inMemory: true).container)
    }

    func testEventsRoundTripAndDeduplicate() async throws {
        let group = GroupID()
        let me = MemberID()
        var log = EventLog(group: group)
        let created = log.record(.groupCreated(name: "Test", currency: .kes,
                                               schedule: ContributionSchedule(frequency: .weekly, amount: .kes(500), startDate: Date(), lateFee: .kes(50)),
                                               loanPolicy: .saccoDefault), by: me, on: DeviceID("test"))
        let joined = log.record(.memberJoined(member: me, name: "Me", phone: PhoneNumber("0712345678")!, role: .chair),
                                by: me, on: DeviceID("test"))

        try await store.registerGroup(group, name: "Test", me: me)
        try await store.append([created, joined])
        try await store.append([joined]) // duplicate must be ignored by the uniqueness constraint

        let loaded = try await store.events(in: group)
        XCTAssertEqual(loaded.count, 2)
        XCTAssertEqual(Set(loaded.map(\.id)), [created.id, joined.id])
        XCTAssertEqual(Ledger.replay(loaded).members.count, 1)
    }

    func testSyncClockPersists() async throws {
        let group = GroupID()
        try await store.registerGroup(group, name: "Test", me: MemberID())
        let before = try await store.lastSyncedClock(for: group)
        XCTAssertNil(before)
        var clock = VectorClock()
        clock.observe(EventClock(counter: 7, device: DeviceID("a")))
        try await store.setLastSyncedClock(clock, for: group)
        let after = try await store.lastSyncedClock(for: group)
        XCTAssertEqual(after, clock)
    }

    func testPendingPaymentsHideTerminalOnes() async throws {
        let group = GroupID()
        let live = PendingPayment(group: group, member: MemberID(), amount: .kes(100), cycle: CycleID(0),
                                  phone: PhoneNumber("0712345678")!)
        let done = try PendingPayment(group: group, member: MemberID(), amount: .kes(100), cycle: CycleID(0),
                                      phone: PhoneNumber("0712345678")!)
            .promptSent(checkoutRequestID: "x", at: Date())
            .resolvedForTest()
        try await store.save(live)
        try await store.save(done)
        let pending = try await store.pendingPayments(in: group)
        XCTAssertEqual(pending.map(\.id), [live.id])
    }
}

private extension PendingPayment {
    func resolvedForTest() throws -> PendingPayment {
        let callback = Daraja.Callback(body: .init(stkCallback: .init(
            merchantRequestID: "m", checkoutRequestID: "x", resultCode: 1032, resultDesc: "cancelled", callbackMetadata: nil)))
        return try callbackReceived(callback, at: Date())
    }
}

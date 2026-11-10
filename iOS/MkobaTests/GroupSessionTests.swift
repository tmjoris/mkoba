import MkobaCore
import XCTest
@testable import Mkoba

@MainActor
final class GroupSessionTests: XCTestCase {
    func testRecordAppliesLocallyBeforeAnyNetwork() async throws {
        let store = CoreDataEventStore(container: PersistenceController(inMemory: true).container)
        let group = GroupID()
        let me = MemberID()
        var log = EventLog(group: group)
        log.record(.groupCreated(name: "T", currency: .kes,
                                 schedule: ContributionSchedule(frequency: .monthly, amount: .kes(1_000), startDate: Date(), lateFee: .kes(0)),
                                 loanPolicy: .saccoDefault), by: me, on: DeviceID("d"))
        log.record(.memberJoined(member: me, name: "Me", phone: PhoneNumber("0712345678")!, role: .treasurer), by: me, on: DeviceID("d"))
        try await store.registerGroup(group, name: "T", me: me)
        try await store.append(log.ordered)

        // Unroutable address: sync must fail without affecting the local write.
        let api = APIClient(baseURL: URL(string: "http://127.0.0.1:1")!)
        let session = GroupSession(log: log, device: DeviceID("d"), store: store, api: api, me: me)

        let event = try await session.record(.contributionRecorded(member: me, amount: .kes(1_000), cycle: CycleID(0), reference: nil))
        XCTAssertNil(session.rejection(of: event))
        XCTAssertEqual(session.state.pot, .kes(1_000))
        XCTAssertEqual(try await store.events(in: group).count, 3)

        let refused = try await session.record(.payoutRecorded(member: me, amount: .kes(5_000), reason: "too much"))
        XCTAssertEqual(session.rejection(of: refused), .insufficientPot(available: .kes(1_000)))
        XCTAssertEqual(session.state.pot, .kes(1_000))
    }
}

import Foundation
import MkobaCore

/// Durable storage for events and sync bookkeeping. Core Data in the app, in-memory in tests.
protocol EventStore: Sendable {
    func groups() async throws -> [(GroupID, String)]
    func identities() async throws -> [GroupID: MemberID]
    func registerGroup(_ group: GroupID, name: String, me: MemberID) async throws
    func events(in group: GroupID) async throws -> [LedgerEvent]
    func append(_ events: [LedgerEvent]) async throws
    func lastSyncedClock(for group: GroupID) async throws -> VectorClock?
    func setLastSyncedClock(_ clock: VectorClock, for group: GroupID) async throws
    func pendingPayments(in group: GroupID) async throws -> [PendingPayment]
    func save(_ payment: PendingPayment) async throws
}

enum JSON {
    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

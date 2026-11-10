import Foundation
import MkobaCore
import Observation

/// One open chama: the event log, its replayed state, and the write path.
/// Recording is local-first: the event is on disk and on screen before any network call.
@Observable
@MainActor
final class GroupSession {
    private(set) var log: EventLog
    private(set) var state: LedgerState
    private(set) var isSyncing = false
    private(set) var lastSyncError: String?
    private(set) var lastSyncedAt: Date?
    let device: DeviceID
    let me: MemberID?

    private let store: any EventStore
    private let api: APIClient

    init(log: EventLog, device: DeviceID, store: any EventStore, api: APIClient, me: MemberID?) {
        self.log = log
        self.state = log.replay()
        self.device = device
        self.store = store
        self.api = api
        self.me = me
    }

    var group: GroupID { log.group }
    var myRole: MemberRole? { me.flatMap { state.members[$0]?.role } }
    var amOfficial: Bool { myRole?.isOfficial ?? false }

    var currentCycle: CycleID {
        state.group?.schedule.cycle(containing: Date()) ?? CycleID(0)
    }

    /// Appends, persists, re-projects, then syncs in the background.
    @discardableResult
    func record(_ kind: EventKind) async throws -> LedgerEvent {
        guard let me else { throw SessionError.notAMember }
        let event = log.record(kind, by: me, on: device)
        state = Ledger.apply(event, to: state)
        try await store.append([event])
        Task { await sync() }
        return event
    }

    /// Why the user's last action was refused, if the ledger rejected it.
    func rejection(of event: LedgerEvent) -> LedgerError? {
        state.rejected[event.id]
    }

    func sync() async {
        guard !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }
        do {
            let lastSynced = try await store.lastSyncedClock(for: group) ?? VectorClock()
            let request = SyncRequest(from: log, lastSynced: lastSynced)
            let response = try await api.sync(request)
            let added = log.merge(response.events)
            if added > 0 {
                try await store.append(response.events)
                state = log.replay()
            }
            try await store.setLastSyncedClock(response.clock, for: group)
            lastSyncedAt = Date()
            lastSyncError = nil
        } catch {
            lastSyncError = error.localizedDescription
        }
    }

    // MARK: - Convenience projections for views

    func member(_ id: MemberID) -> Member? { state.members[id] }

    var membersSorted: [Member] {
        state.members.values.sorted { $0.name < $1.name }
    }

    var loansSorted: [Loan] {
        state.loans.values.sorted { $0.requestedAt > $1.requestedAt }
    }

    /// Contributions per cycle for the dashboard chart, oldest first.
    func contributionsByCycle(last count: Int = 6) -> [(cycle: CycleID, total: Money, target: Money)] {
        guard let schedule = state.group?.schedule else { return [] }
        let current = currentCycle.index
        let first = max(0, current - count + 1)
        let target = Money(minor: schedule.amount.minor * Int64(state.members.count), currency: state.currency)
        return (first...current).map { index in
            (CycleID(index), state.contributions(in: CycleID(index)), target)
        }
    }
}

enum SessionError: LocalizedError {
    case notAMember
    var errorDescription: String? { "This phone is not registered as a member of the group." }
}

import Foundation
import MkobaCore
import Observation

/// Root of the object graph: every screen reads ledgers from here and records events here.
/// Views never touch Core Data or URLSession directly, which keeps them trivial to preview.
@Observable
@MainActor
final class AppModel {
    private(set) var groups: [GroupSummary] = []
    private(set) var sessions: [GroupID: GroupSession] = [:]
    var lastError: String?

    let store: any EventStore
    let api: APIClient
    let device: DeviceID
    /// The member this phone belongs to, per group. Set when creating or joining.
    private(set) var identities: [GroupID: MemberID] = [:]

    init(store: any EventStore, api: APIClient, device: DeviceID) {
        self.store = store
        self.api = api
        self.device = device
    }

    struct GroupSummary: Identifiable, Hashable {
        let id: GroupID
        let name: String
        let pot: Money
        let members: Int
    }

    func load() async {
        do {
            let known = try await store.groups()
            var summaries: [GroupSummary] = []
            for (group, name) in known {
                let session = try await session(for: group)
                summaries.append(GroupSummary(id: group, name: session.state.group?.name ?? name,
                                              pot: session.state.pot, members: session.state.members.count))
            }
            groups = summaries.sorted { $0.name < $1.name }
            identities = try await store.identities()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func session(for group: GroupID) async throws -> GroupSession {
        if let session = sessions[group] { return session }
        let events = try await store.events(in: group)
        var log = EventLog(group: group)
        log.merge(events)
        let session = GroupSession(log: log, device: device, store: store, api: api,
                                   me: identities[group])
        sessions[group] = session
        return session
    }

    /// Creates a chama with this phone's owner as chair, offline. Sync happens when it can.
    func createGroup(name: String, myName: String, myPhone: PhoneNumber, schedule: ContributionSchedule) async throws {
        let group = GroupID()
        let me = MemberID()
        var log = EventLog(group: group)
        let created = log.record(.groupCreated(name: name, currency: .kes, schedule: schedule, loanPolicy: .saccoDefault),
                                 by: me, on: device)
        let joined = log.record(.memberJoined(member: me, name: myName, phone: myPhone, role: .chair), by: me, on: device)
        try await store.registerGroup(group, name: name, me: me)
        try await store.append([created, joined])
        identities[group] = me
        sessions[group] = GroupSession(log: log, device: device, store: store, api: api, me: me)
        await load()
        Task { await sessions[group]?.sync() }
    }
}

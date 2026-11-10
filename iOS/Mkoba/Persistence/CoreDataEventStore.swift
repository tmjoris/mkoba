import CoreData
import Foundation
import MkobaCore

/// Events are stored as JSON blobs keyed by (group, clock). The ledger is replayed in memory,
/// so the schema never has to change when a new event kind is added.
final class CoreDataEventStore: EventStore, @unchecked Sendable {
    private let container: NSPersistentContainer

    init(container: NSPersistentContainer) {
        self.container = container
    }

    private func perform<T: Sendable>(_ work: @escaping @Sendable (NSManagedObjectContext) throws -> T) async throws -> T {
        let context = container.newBackgroundContext()
        context.mergePolicy = NSMergePolicy.mergeByPropertyObjectTrump
        return try await context.perform { try work(context) }
    }

    func groups() async throws -> [(GroupID, String)] {
        try await perform { context in
            let request = GroupEntity.fetchRequest()
            request.sortDescriptors = [NSSortDescriptor(key: "name", ascending: true)]
            return try context.fetch(request).compactMap { entity in
                guard let id = entity.id, let name = entity.name else { return nil }
                return (GroupID(id), name)
            }
        }
    }

    func identities() async throws -> [GroupID: MemberID] {
        let defaults = UserDefaults.standard
        guard let raw = defaults.dictionary(forKey: "mkoba.identities") as? [String: String] else { return [:] }
        var result: [GroupID: MemberID] = [:]
        for (group, member) in raw {
            if let g = UUID(uuidString: group), let m = UUID(uuidString: member) {
                result[GroupID(g)] = MemberID(m)
            }
        }
        return result
    }

    func registerGroup(_ group: GroupID, name: String, me: MemberID) async throws {
        try await perform { context in
            let entity = GroupEntity(context: context)
            entity.id = group.raw
            entity.name = name
            try context.save()
        }
        var raw = UserDefaults.standard.dictionary(forKey: "mkoba.identities") as? [String: String] ?? [:]
        raw[group.raw.uuidString] = me.raw.uuidString
        UserDefaults.standard.set(raw, forKey: "mkoba.identities")
    }

    func events(in group: GroupID) async throws -> [LedgerEvent] {
        try await perform { context in
            let request = EventEntity.fetchRequest()
            request.predicate = NSPredicate(format: "groupID == %@", group.raw as CVarArg)
            request.sortDescriptors = [NSSortDescriptor(key: "counter", ascending: true),
                                       NSSortDescriptor(key: "device", ascending: true)]
            return try context.fetch(request).compactMap { entity in
                guard let payload = entity.payload else { return nil }
                return try? JSON.decoder.decode(LedgerEvent.self, from: payload)
            }
        }
    }

    func append(_ events: [LedgerEvent]) async throws {
        guard !events.isEmpty else { return }
        try await perform { context in
            for event in events {
                let entity = EventEntity(context: context)
                entity.id = event.id
                entity.groupID = event.group.raw
                entity.counter = Int64(event.clock.counter)
                entity.device = event.clock.device.raw
                entity.occurredAt = event.occurredAt
                entity.payload = try JSON.encoder.encode(event)
            }
            try context.save()
        }
    }

    func lastSyncedClock(for group: GroupID) async throws -> VectorClock? {
        try await perform { context in
            guard let entity = try Self.groupEntity(group, in: context), let data = entity.lastSyncedClock else {
                return nil
            }
            return try JSON.decoder.decode(VectorClock.self, from: data)
        }
    }

    func setLastSyncedClock(_ clock: VectorClock, for group: GroupID) async throws {
        try await perform { context in
            guard let entity = try Self.groupEntity(group, in: context) else { return }
            entity.lastSyncedClock = try JSON.encoder.encode(clock)
            try context.save()
        }
    }

    func pendingPayments(in group: GroupID) async throws -> [PendingPayment] {
        try await perform { context in
            let request = PendingPaymentEntity.fetchRequest()
            request.predicate = NSPredicate(format: "groupID == %@ AND terminal == NO", group.raw as CVarArg)
            request.sortDescriptors = [NSSortDescriptor(key: "updatedAt", ascending: false)]
            return try context.fetch(request).compactMap { entity in
                entity.payload.flatMap { try? JSON.decoder.decode(PendingPayment.self, from: $0) }
            }
        }
    }

    func save(_ payment: PendingPayment) async throws {
        try await perform { context in
            let entity = PendingPaymentEntity(context: context)
            entity.id = payment.id
            entity.groupID = payment.group.raw
            entity.payload = try JSON.encoder.encode(payment)
            entity.terminal = payment.status.isTerminal
            entity.updatedAt = payment.updatedAt
            try context.save()
        }
    }

    private static func groupEntity(_ group: GroupID, in context: NSManagedObjectContext) throws -> GroupEntity? {
        let request = GroupEntity.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", group.raw as CVarArg)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }
}

import Foundation

/// A device's copy of one group's events plus the vector clock summarising it.
/// Merging is set union; order never matters because `Ledger.replay` sorts.
public struct EventLog: Hashable, Sendable, Codable {
    public let group: GroupID
    public private(set) var events: [UUID: LedgerEvent]
    public private(set) var clock: VectorClock

    public init(group: GroupID) {
        self.group = group
        self.events = [:]
        self.clock = VectorClock()
    }

    public var count: Int { events.count }

    public var ordered: [LedgerEvent] {
        events.values.sorted { $0.clock < $1.clock }
    }

    /// Adds an event. Returns false if it was already present (idempotent).
    @discardableResult
    public mutating func append(_ event: LedgerEvent) -> Bool {
        guard event.group == group, events[event.id] == nil else { return false }
        events[event.id] = event
        clock.observe(event.clock)
        return true
    }

    /// Merges remote events, returning how many were new.
    @discardableResult
    public mutating func merge(_ incoming: some Sequence<LedgerEvent>) -> Int {
        incoming.reduce(0) { $0 + (append($1) ? 1 : 0) }
    }

    /// Events the holder of `other` has not seen yet.
    public func eventsMissing(from other: VectorClock) -> [LedgerEvent] {
        events.values
            .filter { !other.hasSeen($0.clock) }
            .sorted { $0.clock < $1.clock }
    }

    /// Stamps and appends a locally authored event.
    public mutating func record(_ kind: EventKind, by author: MemberID, on device: DeviceID,
                                at date: Date = Date()) -> LedgerEvent {
        let event = LedgerEvent(group: group, clock: clock.next(for: device), occurredAt: date,
                                recordedBy: author, kind: kind)
        append(event)
        return event
    }

    public func replay() -> LedgerState {
        Ledger.replay(events.values)
    }
}

/// Wire format for one sync round trip: "here is what I know and here is what is new
/// since we last spoke; send me what I am missing".
public struct SyncRequest: Hashable, Sendable, Codable {
    public let group: GroupID
    public let known: VectorClock
    public let events: [LedgerEvent]

    public init(group: GroupID, known: VectorClock, events: [LedgerEvent]) {
        self.group = group
        self.known = known
        self.events = events
    }

    public init(from log: EventLog, lastSynced: VectorClock) {
        group = log.group
        known = log.clock
        events = log.eventsMissing(from: lastSynced)
    }
}

public struct SyncResponse: Hashable, Sendable, Codable {
    public let events: [LedgerEvent]
    public let clock: VectorClock
    public let accepted: Int

    public init(events: [LedgerEvent], clock: VectorClock, accepted: Int) {
        self.events = events
        self.clock = clock
        self.accepted = accepted
    }
}

extension EventLog {
    /// Server-side half of a sync: absorb the client's events, answer with what it lacks.
    public mutating func serve(_ request: SyncRequest) -> SyncResponse {
        let accepted = merge(request.events)
        return SyncResponse(events: eventsMissing(from: request.known), clock: clock, accepted: accepted)
    }
}

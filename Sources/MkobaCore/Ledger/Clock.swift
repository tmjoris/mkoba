/// Lamport timestamp plus device tie-break. Gives every event a total order that
/// all devices agree on without a central clock, so replaying the same events in
/// any arrival order yields the same ledger.
public struct EventClock: Hashable, Sendable, Codable, Comparable, CustomStringConvertible {
    public let counter: UInt64
    public let device: DeviceID

    public init(counter: UInt64, device: DeviceID) {
        self.counter = counter
        self.device = device
    }

    public static func < (lhs: EventClock, rhs: EventClock) -> Bool {
        if lhs.counter != rhs.counter { return lhs.counter < rhs.counter }
        return lhs.device < rhs.device
    }

    public var description: String { "\(counter)@\(device)" }
}

/// The highest counter seen from each device. Two devices exchange these to work
/// out exactly which events the other is missing.
public struct VectorClock: Hashable, Sendable, Codable {
    public private(set) var counters: [DeviceID: UInt64]

    public init(_ counters: [DeviceID: UInt64] = [:]) {
        self.counters = counters
    }

    public subscript(device: DeviceID) -> UInt64 {
        counters[device] ?? 0
    }

    /// True if this clock has already seen `event`'s position for its device.
    public func hasSeen(_ clock: EventClock) -> Bool {
        self[clock.device] >= clock.counter
    }

    public mutating func observe(_ clock: EventClock) {
        counters[clock.device] = max(self[clock.device], clock.counter)
    }

    public mutating func merge(_ other: VectorClock) {
        for (device, counter) in other.counters {
            counters[device] = max(self[device], counter)
        }
    }

    /// Lamport rule: the next local event is one past everything seen anywhere.
    public var maxCounter: UInt64 {
        counters.values.max() ?? 0
    }

    public func next(for device: DeviceID) -> EventClock {
        EventClock(counter: maxCounter + 1, device: device)
    }
}

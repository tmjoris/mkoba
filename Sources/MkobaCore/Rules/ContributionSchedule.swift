import Foundation

/// How often and how much each member contributes, and what lateness costs.
public struct ContributionSchedule: Hashable, Sendable, Codable {
    public enum Frequency: String, Hashable, Sendable, Codable, CaseIterable {
        case weekly, monthly
    }

    public let frequency: Frequency
    public let amount: Money
    /// First day of cycle 0, at midnight in `timeZoneIdentifier`.
    public let startDate: Date
    public let lateFee: Money
    /// Days after a cycle starts before a contribution is late.
    public let graceDays: Int
    public let timeZoneIdentifier: String

    public init(frequency: Frequency, amount: Money, startDate: Date, lateFee: Money,
                graceDays: Int = 3, timeZoneIdentifier: String = "Africa/Nairobi") {
        self.frequency = frequency
        self.amount = amount
        self.startDate = startDate
        self.lateFee = lateFee
        self.graceDays = graceDays
        self.timeZoneIdentifier = timeZoneIdentifier
    }

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZoneIdentifier) ?? .gmt
        return calendar
    }

    /// The cycle a date falls into. Dates before the start are cycle 0.
    public func cycle(containing date: Date) -> CycleID {
        guard date >= startDate else { return CycleID(0) }
        let start = calendar.startOfDay(for: startDate)
        let day = calendar.startOfDay(for: date)
        switch frequency {
        case .weekly:
            let days = calendar.dateComponents([.day], from: start, to: day).day ?? 0
            return CycleID(days / 7)
        case .monthly:
            let months = calendar.dateComponents([.month], from: start, to: day).month ?? 0
            return CycleID(months)
        }
    }

    public func start(of cycle: CycleID) -> Date {
        let start = calendar.startOfDay(for: startDate)
        switch frequency {
        case .weekly:
            return calendar.date(byAdding: .day, value: cycle.index * 7, to: start) ?? start
        case .monthly:
            return calendar.date(byAdding: .month, value: cycle.index, to: start) ?? start
        }
    }

    public func dueDate(for cycle: CycleID) -> Date {
        calendar.date(byAdding: .day, value: graceDays, to: start(of: cycle)) ?? start(of: cycle)
    }

    public func isLate(_ date: Date, for cycle: CycleID) -> Bool {
        date > dueDate(for: cycle)
    }
}

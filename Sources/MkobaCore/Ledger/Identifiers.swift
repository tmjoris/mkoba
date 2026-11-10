import Foundation

/// Stable identity of one installed app instance. Every event it writes carries it,
/// which is what lets two treasurers' offline edits merge deterministically.
public struct DeviceID: Hashable, Sendable, Codable, Comparable, CustomStringConvertible {
    public let raw: String
    public init(_ raw: String) { self.raw = raw }
    public static func < (lhs: DeviceID, rhs: DeviceID) -> Bool { lhs.raw < rhs.raw }
    public var description: String { raw }
}

public struct GroupID: Hashable, Sendable, Codable, CustomStringConvertible {
    public let raw: UUID
    public init(_ raw: UUID = UUID()) { self.raw = raw }
    public var description: String { raw.uuidString }
}

public struct MemberID: Hashable, Sendable, Codable, Comparable, CustomStringConvertible {
    public let raw: UUID
    public init(_ raw: UUID = UUID()) { self.raw = raw }
    public static func < (lhs: MemberID, rhs: MemberID) -> Bool { lhs.raw.uuidString < rhs.raw.uuidString }
    public var description: String { raw.uuidString }
}

public struct LoanID: Hashable, Sendable, Codable, CustomStringConvertible {
    public let raw: UUID
    public init(_ raw: UUID = UUID()) { self.raw = raw }
    public var description: String { raw.uuidString }
}

/// Zero-based index of a contribution cycle (week or month) since the group started.
public struct CycleID: Hashable, Sendable, Codable, Comparable, CustomStringConvertible {
    public let index: Int
    public init(_ index: Int) { self.index = index }
    public static func < (lhs: CycleID, rhs: CycleID) -> Bool { lhs.index < rhs.index }
    public var description: String { "cycle-\(index)" }
}

/// M-Pesa receipt number such as "QGH7K2L9MN", proof that money actually moved.
public struct PaymentReference: Hashable, Sendable, Codable, CustomStringConvertible {
    public let mpesaReceipt: String
    public init(mpesaReceipt: String) { self.mpesaReceipt = mpesaReceipt }
    public var description: String { mpesaReceipt }
}

import Foundation

/// Kenyan mobile number normalised to 2547XXXXXXXX / 2541XXXXXXXX, the format Daraja expects.
public struct PhoneNumber: Hashable, Sendable, Codable, CustomStringConvertible {
    public let msisdn: String

    /// Accepts "0712 345 678", "+254712345678", "254712345678" or "712345678".
    public init?(_ raw: String) {
        var digits = raw.filter(\.isNumber)
        if digits.hasPrefix("0") { digits = "254" + digits.dropFirst() }
        if digits.count == 9, digits.hasPrefix("7") || digits.hasPrefix("1") { digits = "254" + digits }
        guard digits.count == 12, digits.hasPrefix("254"),
              digits.dropFirst(3).first == "7" || digits.dropFirst(3).first == "1" else {
            return nil
        }
        msisdn = digits
    }

    /// "0712 345 678" for display.
    public var local: String {
        let body = msisdn.dropFirst(3)
        return "0" + body.prefix(3) + " " + body.dropFirst(3).prefix(3) + " " + body.dropFirst(6)
    }

    public var description: String { msisdn }
}

/// Everything that can happen to a chama, as an immutable fact. The ledger is the
/// fold of these; nothing is ever edited or deleted, which is also what an auditor wants.
public enum EventKind: Hashable, Sendable, Codable {
    case groupCreated(name: String, currency: Currency, schedule: ContributionSchedule, loanPolicy: LoanPolicy)
    case memberJoined(member: MemberID, name: String, phone: PhoneNumber, role: MemberRole)
    case memberRoleChanged(member: MemberID, role: MemberRole)
    case contributionRecorded(member: MemberID, amount: Money, cycle: CycleID, reference: PaymentReference?)
    case penaltyApplied(member: MemberID, amount: Money, cycle: CycleID)
    case payoutRecorded(member: MemberID, amount: Money, reason: String)
    case loanRequested(loan: LoanID, borrower: MemberID, principal: Money, termMonths: Int)
    case loanGuaranteed(loan: LoanID, guarantor: MemberID, amount: Money)
    case loanApproved(loan: LoanID, approver: MemberID)
    case loanRejected(loan: LoanID, approver: MemberID, reason: String)
    case loanDisbursed(loan: LoanID, reference: PaymentReference?)
    case loanRepaid(loan: LoanID, amount: Money, reference: PaymentReference?)
}

public enum MemberRole: String, Hashable, Sendable, Codable, CaseIterable {
    case chair, treasurer, secretary, member

    /// Roles allowed to record money movements and approve loans.
    public var isOfficial: Bool { self != .member }
}

public struct LedgerEvent: Hashable, Sendable, Codable, Identifiable {
    public let id: UUID
    public let group: GroupID
    public let clock: EventClock
    public let occurredAt: Date
    public let recordedBy: MemberID
    public let kind: EventKind

    public init(id: UUID = UUID(), group: GroupID, clock: EventClock, occurredAt: Date,
                recordedBy: MemberID, kind: EventKind) {
        self.id = id
        self.group = group
        self.clock = clock
        self.occurredAt = occurredAt
        self.recordedBy = recordedBy
        self.kind = kind
    }
}

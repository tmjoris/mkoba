import Foundation

public struct Member: Hashable, Sendable, Codable {
    public let id: MemberID
    public var name: String
    public var phone: PhoneNumber
    public var role: MemberRole
    public let joinedAt: Date
}

public struct Contribution: Hashable, Sendable, Codable {
    public let eventID: UUID
    public let member: MemberID
    public let amount: Money
    public let cycle: CycleID
    public let reference: PaymentReference?
    public let at: Date
}

public struct Payout: Hashable, Sendable, Codable {
    public let eventID: UUID
    public let member: MemberID
    public let amount: Money
    public let reason: String
    public let at: Date
}

public enum LoanStatus: Hashable, Sendable, Codable {
    case requested
    case approved
    case rejected(reason: String)
    case disbursed
    case repaid
}

public struct Loan: Hashable, Sendable, Codable {
    public let id: LoanID
    public let borrower: MemberID
    public let principal: Money
    public let termMonths: Int
    public let requestedAt: Date
    public var status: LoanStatus
    public var guarantees: [MemberID: Money]
    public var repaid: Money
    public var disbursedAt: Date?
    public var reference: PaymentReference?
    /// Interest for the whole term, fixed when the loan is requested so a later
    /// policy change never rewrites what a member already agreed to.
    public let interest: Money

    public var totalDue: Money { principal + interest }
    public var outstanding: Money {
        switch status {
        case .disbursed: return totalDue - repaid
        default: return .zero(principal.currency)
        }
    }
    public var guaranteed: Money {
        guarantees.values.reduce(.zero(principal.currency), +)
    }
}

public struct MemberBalance: Hashable, Sendable {
    public var contributed: Money
    public var penalties: Money
    public var payouts: Money
    public var loansOutstanding: Money
    public var guaranteesPledged: Money

    /// Savings the member can borrow against: contributions less payouts and penalties.
    public var savings: Money { contributed - payouts - penalties }
}

public struct GroupInfo: Hashable, Sendable, Codable {
    public let id: GroupID
    public var name: String
    public let currency: Currency
    public var schedule: ContributionSchedule
    public var loanPolicy: LoanPolicy
    public let createdAt: Date
}

/// Why an event was not applied. Rejections are part of the state so every device
/// shows the same red mark next to the same entry.
public enum LedgerError: Error, Hashable, Sendable {
    case groupAlreadyCreated
    case groupNotCreated
    case unknownMember(MemberID)
    case duplicateMember(MemberID)
    case notAnOfficial(MemberID)
    case nonPositiveAmount
    case currencyMismatch
    case unknownLoan(LoanID)
    case loanNotInStatus(LoanID, expected: String)
    case loanExceedsPolicy(limit: Money)
    case loanTermTooLong(maxMonths: Int)
    case insufficientGuarantees(required: Money, pledged: Money)
    case guarantorIsBorrower
    case guaranteeExceedsSavings(available: Money)
    case repaymentExceedsOutstanding(outstanding: Money)
    case insufficientPot(available: Money)
    case alreadyGuaranteed(MemberID)
}

/// The chama as of a set of events. Pure value: cheap to copy, trivially testable.
public struct LedgerState: Hashable, Sendable {
    public var group: GroupInfo?
    public var members: [MemberID: Member] = [:]
    public var contributions: [Contribution] = []
    public var payouts: [Payout] = []
    public var penalties: [Contribution] = []
    public var loans: [LoanID: Loan] = [:]
    /// Cash the group holds: contributions + penalties + repayments - payouts - disbursements.
    public var pot: Money
    public var clock = VectorClock()
    public var applied: Set<UUID> = []
    public var rejected: [UUID: LedgerError] = [:]

    public init(currency: Currency = .kes) {
        pot = .zero(currency)
    }

    public var currency: Currency { pot.currency }

    public func balance(of member: MemberID) -> MemberBalance {
        let zero = Money.zero(currency)
        let contributed = contributions.filter { $0.member == member }.map(\.amount).reduce(zero, +)
        let penalty = penalties.filter { $0.member == member }.map(\.amount).reduce(zero, +)
        let paid = payouts.filter { $0.member == member }.map(\.amount).reduce(zero, +)
        let outstanding = loans.values.filter { $0.borrower == member }.map(\.outstanding).reduce(zero, +)
        let pledged = loans.values
            .filter { $0.status == .disbursed || $0.status == .approved || $0.status == .requested }
            .compactMap { $0.guarantees[member] }
            .reduce(zero, +)
        return MemberBalance(contributed: contributed, penalties: penalty, payouts: paid,
                             loansOutstanding: outstanding, guaranteesPledged: pledged)
    }

    /// Members who have paid less than the scheduled amount for `cycle`.
    public func arrears(for cycle: CycleID) -> [(member: MemberID, shortfall: Money)] {
        guard let schedule = group?.schedule else { return [] }
        return members.keys.sorted().compactMap { member in
            let paid = contributions
                .filter { $0.member == member && $0.cycle == cycle }
                .map(\.amount)
                .reduce(Money.zero(currency), +)
            let shortfall = schedule.amount - paid
            return shortfall.isPositive ? (member, shortfall) : nil
        }
    }

    public func contributions(in cycle: CycleID) -> Money {
        contributions.filter { $0.cycle == cycle }.map(\.amount).reduce(.zero(currency), +)
    }
}

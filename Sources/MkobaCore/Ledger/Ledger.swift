import Foundation

/// Deterministic fold of events into state.
///
/// Validation happens here, at replay time, not when the treasurer taps "record".
/// An offline device cannot know the latest state, so instead every device applies the
/// same rules to the same totally-ordered events and reaches the same answer, including
/// which events to reject. That is what makes offline-first bookkeeping safe.
public enum Ledger {
    /// Replays any bag of events, in any order, possibly with duplicates.
    public static func replay(_ events: some Sequence<LedgerEvent>) -> LedgerState {
        var seen: Set<UUID> = []
        let ordered = events
            .filter { seen.insert($0.id).inserted }
            .sorted { $0.clock < $1.clock }
        var state = LedgerState()
        for event in ordered {
            state = apply(event, to: state)
        }
        return state
    }

    /// Applies one event. Never throws: a rejected event is recorded in `state.rejected`
    /// so the UI can show it, and the clock still advances so sync stays correct.
    public static func apply(_ event: LedgerEvent, to state: LedgerState) -> LedgerState {
        var next = state
        next.clock.observe(event.clock)
        guard next.applied.insert(event.id).inserted else { return state }
        do {
            try mutate(&next, with: event)
        } catch let error as LedgerError {
            next = state
            next.clock.observe(event.clock)
            next.applied.insert(event.id)
            next.rejected[event.id] = error
        } catch {
            next = state
            next.clock.observe(event.clock)
            next.applied.insert(event.id)
            next.rejected[event.id] = .currencyMismatch
        }
        return next
    }

    // MARK: - Rules

    private static func mutate(_ state: inout LedgerState, with event: LedgerEvent) throws {
        switch event.kind {
        case let .groupCreated(name, currency, schedule, policy):
            guard state.group == nil else { throw LedgerError.groupAlreadyCreated }
            state = LedgerState(currency: currency)
            state.clock.observe(event.clock)
            state.applied.insert(event.id)
            state.group = GroupInfo(id: event.group, name: name, currency: currency,
                                    schedule: schedule, loanPolicy: policy, createdAt: event.occurredAt)

        case let .memberJoined(member, name, phone, role):
            let group = try requireGroup(state)
            guard state.members[member] == nil else { throw LedgerError.duplicateMember(member) }
            // The first member bootstraps the group; after that only officials add members.
            if !state.members.isEmpty { try requireOfficial(event.recordedBy, in: state) }
            _ = group
            state.members[member] = Member(id: member, name: name, phone: phone, role: role,
                                           joinedAt: event.occurredAt)

        case let .memberRoleChanged(member, role):
            try requireOfficial(event.recordedBy, in: state)
            guard state.members[member] != nil else { throw LedgerError.unknownMember(member) }
            state.members[member]?.role = role

        case let .contributionRecorded(member, amount, cycle, reference):
            try requireOfficial(event.recordedBy, in: state)
            try requireMember(member, in: state)
            try requirePositive(amount, in: state)
            state.contributions.append(Contribution(eventID: event.id, member: member, amount: amount,
                                                    cycle: cycle, reference: reference, at: event.occurredAt))
            state.pot = state.pot + amount

        case let .penaltyApplied(member, amount, cycle):
            try requireOfficial(event.recordedBy, in: state)
            try requireMember(member, in: state)
            try requirePositive(amount, in: state)
            state.penalties.append(Contribution(eventID: event.id, member: member, amount: amount,
                                                cycle: cycle, reference: nil, at: event.occurredAt))
            state.pot = state.pot + amount

        case let .payoutRecorded(member, amount, reason):
            try requireOfficial(event.recordedBy, in: state)
            try requireMember(member, in: state)
            try requirePositive(amount, in: state)
            guard amount <= state.pot else { throw LedgerError.insufficientPot(available: state.pot) }
            state.payouts.append(Payout(eventID: event.id, member: member, amount: amount,
                                        reason: reason, at: event.occurredAt))
            state.pot = state.pot - amount

        case let .loanRequested(loanID, borrower, principal, termMonths):
            let group = try requireGroup(state)
            try requireMember(borrower, in: state)
            try requirePositive(principal, in: state)
            guard termMonths > 0, termMonths <= group.loanPolicy.maxTermMonths else {
                throw LedgerError.loanTermTooLong(maxMonths: group.loanPolicy.maxTermMonths)
            }
            let savings = state.balance(of: borrower).savings
            let limit = try group.loanPolicy.borrowingLimit(savings: savings)
            guard principal <= limit else { throw LedgerError.loanExceedsPolicy(limit: limit) }
            let interest = try group.loanPolicy.interest(on: principal, termMonths: termMonths)
            state.loans[loanID] = Loan(id: loanID, borrower: borrower, principal: principal,
                                       termMonths: termMonths, requestedAt: event.occurredAt,
                                       status: .requested, guarantees: [:],
                                       repaid: .zero(state.currency), disbursedAt: nil,
                                       reference: nil, interest: interest)

        case let .loanGuaranteed(loanID, guarantor, amount):
            let group = try requireGroup(state)
            try requireMember(guarantor, in: state)
            try requirePositive(amount, in: state)
            var loan = try requireLoan(loanID, in: state, status: .requested)
            guard loan.borrower != guarantor else { throw LedgerError.guarantorIsBorrower }
            guard loan.guarantees[guarantor] == nil else { throw LedgerError.alreadyGuaranteed(guarantor) }
            let balance = state.balance(of: guarantor)
            let free = group.loanPolicy.maxGuarantee(savings: balance.savings) - balance.guaranteesPledged
            guard amount <= free else { throw LedgerError.guaranteeExceedsSavings(available: free) }
            loan.guarantees[guarantor] = amount
            state.loans[loanID] = loan

        case let .loanApproved(loanID, approver):
            let group = try requireGroup(state)
            try requireOfficial(approver, in: state)
            var loan = try requireLoan(loanID, in: state, status: .requested)
            if group.loanPolicy.requireFullGuarantee, loan.guaranteed < loan.principal {
                throw LedgerError.insufficientGuarantees(required: loan.principal, pledged: loan.guaranteed)
            }
            loan.status = .approved
            state.loans[loanID] = loan

        case let .loanRejected(loanID, approver, reason):
            try requireOfficial(approver, in: state)
            var loan = try requireLoan(loanID, in: state, status: .requested)
            loan.status = .rejected(reason: reason)
            state.loans[loanID] = loan

        case let .loanDisbursed(loanID, reference):
            try requireOfficial(event.recordedBy, in: state)
            var loan = try requireLoan(loanID, in: state, status: .approved)
            guard loan.principal <= state.pot else { throw LedgerError.insufficientPot(available: state.pot) }
            loan.status = .disbursed
            loan.disbursedAt = event.occurredAt
            loan.reference = reference
            state.loans[loanID] = loan
            state.pot = state.pot - loan.principal

        case let .loanRepaid(loanID, amount, _):
            try requireOfficial(event.recordedBy, in: state)
            try requirePositive(amount, in: state)
            var loan = try requireLoan(loanID, in: state, status: .disbursed)
            guard amount <= loan.outstanding else {
                throw LedgerError.repaymentExceedsOutstanding(outstanding: loan.outstanding)
            }
            loan.repaid = loan.repaid + amount
            if loan.outstanding.isZero { loan.status = .repaid }
            state.loans[loanID] = loan
            state.pot = state.pot + amount
        }
    }

    // MARK: - Guards

    private static func requireGroup(_ state: LedgerState) throws -> GroupInfo {
        guard let group = state.group else { throw LedgerError.groupNotCreated }
        return group
    }

    private static func requireMember(_ member: MemberID, in state: LedgerState) throws {
        guard state.members[member] != nil else { throw LedgerError.unknownMember(member) }
    }

    private static func requireOfficial(_ member: MemberID, in state: LedgerState) throws {
        guard let record = state.members[member] else { throw LedgerError.unknownMember(member) }
        guard record.role.isOfficial else { throw LedgerError.notAnOfficial(member) }
    }

    private static func requirePositive(_ amount: Money, in state: LedgerState) throws {
        guard amount.currency == state.currency else { throw LedgerError.currencyMismatch }
        guard amount.isPositive else { throw LedgerError.nonPositiveAmount }
    }

    private static func requireLoan(_ id: LoanID, in state: LedgerState, status: LoanStatus) throws -> Loan {
        guard let loan = state.loans[id] else { throw LedgerError.unknownLoan(id) }
        guard loan.status == status else {
            throw LedgerError.loanNotInStatus(id, expected: "\(status)")
        }
        return loan
    }
}

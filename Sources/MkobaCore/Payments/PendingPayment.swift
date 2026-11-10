import Foundation

/// Lifecycle of one M-Pesa contribution, from tapping "Pay" to a receipt on the ledger.
///
/// The hard case is `promptSent` with no callback: the member may well have paid.
/// Nothing is written to the ledger until a receipt exists, and the app never fires a
/// second prompt for the same payment until a status query says the first one is dead.
public enum PaymentStatus: Hashable, Sendable, Codable {
    /// Created locally, nothing sent yet (or we are offline).
    case requested
    /// Daraja accepted the push; the member is looking at the PIN prompt.
    case promptSent(checkoutRequestID: String)
    /// Callback or status query confirmed money moved.
    case completed(MpesaReceipt)
    /// Terminal failure reported by Daraja.
    case failed(code: Int, description: String)
    /// No callback in time. Must be resolved by a status query before any retry.
    case unknown(checkoutRequestID: String)

    public var isTerminal: Bool {
        switch self {
        case .completed, .failed: return true
        case .requested, .promptSent, .unknown: return false
        }
    }

    public var checkoutRequestID: String? {
        switch self {
        case .promptSent(let id), .unknown(let id): return id
        default: return nil
        }
    }
}

public struct PendingPayment: Hashable, Sendable, Codable, Identifiable {
    public let id: UUID
    public let group: GroupID
    public let member: MemberID
    public let amount: Money
    public let cycle: CycleID
    public let phone: PhoneNumber
    public let createdAt: Date
    public private(set) var status: PaymentStatus
    public private(set) var updatedAt: Date
    public private(set) var attempts: Int

    /// How long to wait for a callback before treating the push as unknown. Daraja's own
    /// STK prompt expires after about a minute.
    public static let callbackTimeout: TimeInterval = 90

    public init(id: UUID = UUID(), group: GroupID, member: MemberID, amount: Money, cycle: CycleID,
                phone: PhoneNumber, createdAt: Date = Date()) {
        self.id = id
        self.group = group
        self.member = member
        self.amount = amount
        self.cycle = cycle
        self.phone = phone
        self.createdAt = createdAt
        self.status = .requested
        self.updatedAt = createdAt
        self.attempts = 0
    }

    /// True when it is safe to send (another) STK push.
    public var canSendPrompt: Bool {
        switch status {
        case .requested: return true
        case .failed(let code, _): return Daraja.ResultCode(rawValue: code)?.isRetryable ?? false
        case .promptSent, .unknown, .completed: return false
        }
    }

    public var needsStatusQuery: Bool {
        if case .unknown = status { return true }
        return false
    }

    // MARK: - Transitions (pure; each returns the new value or throws)

    public func promptSent(checkoutRequestID: String, at date: Date) throws -> PendingPayment {
        guard canSendPrompt else { throw PaymentError.invalidTransition }
        var next = self
        next.status = .promptSent(checkoutRequestID: checkoutRequestID)
        next.attempts += 1
        next.updatedAt = date
        return next
    }

    public func callbackReceived(_ callback: Daraja.Callback, at date: Date) throws -> PendingPayment {
        guard let expected = status.checkoutRequestID, expected == callback.checkoutRequestID else {
            throw PaymentError.unknownCheckout(callback.checkoutRequestID)
        }
        var next = self
        if let receipt = callback.receipt() {
            next.status = .completed(receipt)
        } else {
            next.status = .failed(code: callback.resultCode, description: callback.body.stkCallback.resultDesc)
        }
        next.updatedAt = date
        return next
    }

    /// Called by a timer: a prompt with no callback becomes unknown, never failed.
    public func tick(now: Date) -> PendingPayment {
        guard case .promptSent(let id) = status,
              now.timeIntervalSince(updatedAt) > Self.callbackTimeout else { return self }
        var next = self
        next.status = .unknown(checkoutRequestID: id)
        next.updatedAt = now
        return next
    }

    /// Result of a Daraja transaction status query for an unknown payment.
    public enum QueryOutcome: Hashable, Sendable {
        case paid(MpesaReceipt)
        case failed(code: Int, description: String)
        /// Daraja has no record: the push never reached the customer. Safe to retry.
        case notFound
    }

    public func resolved(_ outcome: QueryOutcome, at date: Date) throws -> PendingPayment {
        guard case .unknown = status else { throw PaymentError.invalidTransition }
        var next = self
        switch outcome {
        case .paid(let receipt): next.status = .completed(receipt)
        case .failed(let code, let description): next.status = .failed(code: code, description: description)
        case .notFound: next.status = .requested
        }
        next.updatedAt = date
        return next
    }

    /// The ledger event to append once, and only once, the payment is completed.
    public func ledgerEventKind() -> EventKind? {
        guard case .completed(let receipt) = status else { return nil }
        return .contributionRecorded(member: member, amount: amount, cycle: cycle, reference: receipt.reference)
    }
}

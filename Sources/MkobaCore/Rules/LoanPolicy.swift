/// Lending rules a chama agrees on. Mirrors how SACCOs lend: a multiple of what you
/// have saved, backed by other members' savings.
public struct LoanPolicy: Hashable, Sendable, Codable {
    /// A member may borrow up to this many times their savings. SACCO norm is 3x.
    public let maxMultipleOfSavings: Int
    /// Flat interest per month in basis points. 100 = 1% per month.
    public let monthlyInterestBasisPoints: Int64
    public let maxTermMonths: Int
    /// Guarantees must cover the whole principal before approval.
    public let requireFullGuarantee: Bool
    /// A guarantor can pledge at most this fraction (in percent) of their own free savings.
    public let maxGuaranteePercentOfSavings: Int

    public init(maxMultipleOfSavings: Int = 3, monthlyInterestBasisPoints: Int64 = 100,
                maxTermMonths: Int = 12, requireFullGuarantee: Bool = true,
                maxGuaranteePercentOfSavings: Int = 100) {
        self.maxMultipleOfSavings = maxMultipleOfSavings
        self.monthlyInterestBasisPoints = monthlyInterestBasisPoints
        self.maxTermMonths = maxTermMonths
        self.requireFullGuarantee = requireFullGuarantee
        self.maxGuaranteePercentOfSavings = maxGuaranteePercentOfSavings
    }

    public static let saccoDefault = LoanPolicy()

    public func borrowingLimit(savings: Money) throws -> Money {
        let positive = savings.isNegative ? Money.zero(savings.currency) : savings
        return try positive.multiplied(by: Int64(maxMultipleOfSavings))
    }

    /// Flat interest over the full term: principal x rate x months.
    public func interest(on principal: Money, termMonths: Int) throws -> Money {
        try principal.applying(basisPoints: monthlyInterestBasisPoints * Int64(termMonths))
    }

    /// Equal monthly instalments that sum exactly to total due (last one absorbs rounding).
    public func instalments(principal: Money, termMonths: Int) throws -> [Money] {
        let total = try principal.adding(interest(on: principal, termMonths: termMonths))
        return try total.allocate(parts: termMonths)
    }

    public func maxGuarantee(savings: Money) -> Money {
        let positive = savings.isNegative ? Money.zero(savings.currency) : savings
        return Money(minor: positive.minor * Int64(maxGuaranteePercentOfSavings) / 100,
                     currency: positive.currency)
    }
}

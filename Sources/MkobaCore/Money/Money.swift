import Foundation

/// An exact amount of money stored in minor units (cents for KES).
///
/// Floating point is never used: `Money` is an integer plus a currency, so a
/// chama ledger that adds ten thousand contributions still balances to the cent.
public struct Money: Hashable, Sendable, Codable {
    /// Amount in minor units. KES 1,250.50 is `125050`.
    public let minor: Int64
    public let currency: Currency

    public init(minor: Int64, currency: Currency = .kes) {
        self.minor = minor
        self.currency = currency
    }

    /// Convenience for whole shillings and cents.
    public static func kes(_ shillings: Int64, cents: Int64 = 0) -> Money {
        precondition(cents >= 0 && cents < 100, "cents must be 0...99")
        let sign: Int64 = shillings < 0 ? -1 : 1
        return Money(minor: shillings * 100 + sign * cents, currency: .kes)
    }

    public static func zero(_ currency: Currency = .kes) -> Money {
        Money(minor: 0, currency: currency)
    }

    public var isZero: Bool { minor == 0 }
    public var isNegative: Bool { minor < 0 }
    public var isPositive: Bool { minor > 0 }

    public var majorPart: Int64 { minor / currency.minorUnitsPerMajor }
    public var minorPart: Int64 { abs(minor % currency.minorUnitsPerMajor) }
}

// MARK: - Errors

public enum MoneyError: Error, Equatable, Sendable {
    case currencyMismatch(Currency, Currency)
    case overflow
    case invalidFormat(String)
    case invalidAllocation
}

// MARK: - Arithmetic

extension Money {
    public func adding(_ other: Money) throws -> Money {
        try requireSameCurrency(other)
        let (sum, overflow) = minor.addingReportingOverflow(other.minor)
        if overflow { throw MoneyError.overflow }
        return Money(minor: sum, currency: currency)
    }

    public func subtracting(_ other: Money) throws -> Money {
        try requireSameCurrency(other)
        let (diff, overflow) = minor.subtractingReportingOverflow(other.minor)
        if overflow { throw MoneyError.overflow }
        return Money(minor: diff, currency: currency)
    }

    public func multiplied(by factor: Int64) throws -> Money {
        let (product, overflow) = minor.multipliedReportingOverflow(by: factor)
        if overflow { throw MoneyError.overflow }
        return Money(minor: product, currency: currency)
    }

    /// Applies a rate expressed in basis points (1 bp = 0.01%), rounding half up.
    /// Used for interest: `principal.applying(basisPoints: 100)` is 1%.
    public func applying(basisPoints: Int64) throws -> Money {
        let (scaled, overflow) = minor.multipliedReportingOverflow(by: basisPoints)
        if overflow { throw MoneyError.overflow }
        // Round half up on the magnitude so negatives round symmetrically.
        let magnitude = abs(scaled)
        let rounded = (magnitude + 5_000) / 10_000
        return Money(minor: scaled < 0 ? -rounded : rounded, currency: currency)
    }

    public func negated() -> Money {
        Money(minor: -minor, currency: currency)
    }

    /// Sums a sequence of money, failing on the first currency mismatch or overflow.
    public static func sum<S: Sequence>(_ amounts: S, currency: Currency = .kes) throws -> Money
    where S.Element == Money {
        var total = Money.zero(currency)
        for amount in amounts {
            total = try total.adding(amount)
        }
        return total
    }

    /// Operator form for callers that have already proved both sides share a currency.
    /// Traps on mismatch; prefer `adding(_:)` in code paths that handle user input.
    public static func + (lhs: Money, rhs: Money) -> Money {
        precondition(lhs.currency == rhs.currency, "currency mismatch")
        return Money(minor: lhs.minor + rhs.minor, currency: lhs.currency)
    }

    public static func - (lhs: Money, rhs: Money) -> Money {
        precondition(lhs.currency == rhs.currency, "currency mismatch")
        return Money(minor: lhs.minor - rhs.minor, currency: lhs.currency)
    }

    private func requireSameCurrency(_ other: Money) throws {
        guard currency == other.currency else {
            throw MoneyError.currencyMismatch(currency, other.currency)
        }
    }
}

// MARK: - Comparison

extension Money: Comparable {
    /// Compares amounts. Comparing different currencies is a programmer error.
    public static func < (lhs: Money, rhs: Money) -> Bool {
        precondition(lhs.currency == rhs.currency, "currency mismatch")
        return lhs.minor < rhs.minor
    }
}

// MARK: - Allocation

extension Money {
    /// Splits the amount into `parts` shares that sum exactly to the original.
    /// Remainder cents go to the first shares, one each (largest remainder method).
    ///
    /// `Money.kes(100).allocate(parts: 3)` -> 33.34, 33.33, 33.33
    public func allocate(parts: Int) throws -> [Money] {
        guard parts > 0 else { throw MoneyError.invalidAllocation }
        let base = minor / Int64(parts)
        var remainder = minor - base * Int64(parts)
        let step: Int64 = remainder < 0 ? -1 : 1
        var shares: [Money] = []
        shares.reserveCapacity(parts)
        for _ in 0..<parts {
            var share = base
            if remainder != 0 {
                share += step
                remainder -= step
            }
            shares.append(Money(minor: share, currency: currency))
        }
        return shares
    }

    /// Splits the amount in proportion to `ratios`, summing exactly to the original.
    public func allocate(ratios: [Int]) throws -> [Money] {
        guard !ratios.isEmpty, ratios.allSatisfy({ $0 >= 0 }) else {
            throw MoneyError.invalidAllocation
        }
        let total = ratios.reduce(0, +)
        guard total > 0 else { throw MoneyError.invalidAllocation }

        var shares: [Int64] = []
        var allocated: Int64 = 0
        for ratio in ratios {
            let share = minor * Int64(ratio) / Int64(total)
            shares.append(share)
            allocated += share
        }
        var remainder = minor - allocated
        let step: Int64 = remainder < 0 ? -1 : 1
        var index = 0
        while remainder != 0 {
            if ratios[index] > 0 {
                shares[index] += step
                remainder -= step
            }
            index = (index + 1) % ratios.count
        }
        return shares.map { Money(minor: $0, currency: currency) }
    }
}

// MARK: - Formatting and parsing

extension Money: CustomStringConvertible {
    /// "KES 1,250.50". Deterministic, locale independent, safe for ledgers and logs.
    public var description: String {
        formatted()
    }

    public func formatted(showCode: Bool = true) -> String {
        let sign = minor < 0 ? "-" : ""
        let major = abs(majorPart)
        let fraction = minorPart
        let majorText = Money.groupThousands(major)
        var text = sign + majorText
        if currency.fractionDigits > 0 {
            var fractionText = String(fraction)
            while fractionText.count < currency.fractionDigits {
                fractionText = "0" + fractionText
            }
            text += "." + fractionText
        }
        return showCode ? "\(currency.code) \(text)" : text
    }

    /// Parses "1,250.50", "1250", "KES 1250.5" or "-20.05" into exact minor units.
    public init(parsing text: String, currency: Currency = .kes) throws {
        var cleaned = text.trimmingCharacters(in: .whitespaces)
        if cleaned.uppercased().hasPrefix(currency.code) {
            cleaned = String(cleaned.dropFirst(currency.code.count))
                .trimmingCharacters(in: .whitespaces)
        }
        cleaned = cleaned.replacingOccurrences(of: ",", with: "")
        guard !cleaned.isEmpty else { throw MoneyError.invalidFormat(text) }

        var negative = false
        if cleaned.hasPrefix("-") {
            negative = true
            cleaned.removeFirst()
        }

        let pieces = cleaned.split(separator: ".", omittingEmptySubsequences: false)
        guard pieces.count <= 2 else { throw MoneyError.invalidFormat(text) }

        let majorText = pieces[0].isEmpty ? "0" : String(pieces[0])
        guard let major = Int64(majorText), majorText.allSatisfy(\.isNumber) else {
            throw MoneyError.invalidFormat(text)
        }

        var fraction: Int64 = 0
        if pieces.count == 2 {
            var fractionText = String(pieces[1])
            guard fractionText.allSatisfy(\.isNumber),
                  fractionText.count <= currency.fractionDigits else {
                throw MoneyError.invalidFormat(text)
            }
            while fractionText.count < currency.fractionDigits {
                fractionText += "0"
            }
            fraction = Int64(fractionText) ?? 0
        }

        let (scaled, overflow) = major.multipliedReportingOverflow(by: currency.minorUnitsPerMajor)
        if overflow { throw MoneyError.overflow }
        let magnitude = scaled + fraction
        self.init(minor: negative ? -magnitude : magnitude, currency: currency)
    }

    private static func groupThousands(_ value: Int64) -> String {
        let digits = Array(String(value))
        var result: [Character] = []
        for (offset, digit) in digits.reversed().enumerated() {
            if offset > 0 && offset % 3 == 0 { result.append(",") }
            result.append(digit)
        }
        return String(result.reversed())
    }
}


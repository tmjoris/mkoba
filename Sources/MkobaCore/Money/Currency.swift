/// An ISO 4217 currency with the number of minor units (e.g. cents) per major unit.
public struct Currency: Hashable, Sendable, Codable {
    public let code: String
    /// Number of decimal digits in the minor unit. KES has 2 (cents).
    public let fractionDigits: Int

    public init(code: String, fractionDigits: Int) {
        self.code = code
        self.fractionDigits = fractionDigits
    }

    /// Kenyan shilling.
    public static let kes = Currency(code: "KES", fractionDigits: 2)

    /// How many minor units make one major unit (100 for KES).
    public var minorUnitsPerMajor: Int64 {
        var result: Int64 = 1
        for _ in 0..<fractionDigits { result *= 10 }
        return result
    }
}

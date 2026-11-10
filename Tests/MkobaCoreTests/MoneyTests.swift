import XCTest
@testable import MkobaCore

final class MoneyTests: XCTestCase {
    func testKesConvenienceStoresCents() {
        XCTAssertEqual(Money.kes(1_250, cents: 50).minor, 125_050)
        XCTAssertEqual(Money.kes(-20, cents: 5).minor, -2_005)
    }

    func testFormattingIsDeterministic() {
        XCTAssertEqual(Money.kes(1_250, cents: 50).description, "KES 1,250.50")
        XCTAssertEqual(Money.kes(1_000_000).formatted(showCode: false), "1,000,000.00")
        XCTAssertEqual(Money.kes(-7, cents: 5).description, "KES -7.05")
        XCTAssertEqual(Money.zero().description, "KES 0.00")
    }

    func testParsingAcceptsHumanInput() throws {
        XCTAssertEqual(try Money(parsing: "1,250.50"), .kes(1_250, cents: 50))
        XCTAssertEqual(try Money(parsing: "KES 1250.5"), .kes(1_250, cents: 50))
        XCTAssertEqual(try Money(parsing: "1250"), .kes(1_250))
        XCTAssertEqual(try Money(parsing: "-20.05"), .kes(-20, cents: 5))
        XCTAssertEqual(try Money(parsing: ".5"), .kes(0, cents: 50))
    }

    func testParsingRejectsGarbage() {
        XCTAssertThrowsError(try Money(parsing: "12.345"))
        XCTAssertThrowsError(try Money(parsing: "abc"))
        XCTAssertThrowsError(try Money(parsing: "1.2.3"))
        XCTAssertThrowsError(try Money(parsing: ""))
    }

    func testArithmeticRejectsCurrencyMismatch() {
        let usd = Currency(code: "USD", fractionDigits: 2)
        XCTAssertThrowsError(try Money.kes(1).adding(Money(minor: 1, currency: usd))) { error in
            XCTAssertEqual(error as? MoneyError, .currencyMismatch(.kes, usd))
        }
    }

    func testArithmeticDetectsOverflow() {
        let huge = Money(minor: .max)
        XCTAssertThrowsError(try huge.adding(.kes(1)))
        XCTAssertThrowsError(try huge.multiplied(by: 2))
    }

    func testBasisPointsRoundHalfUp() throws {
        // 1% of 12.34 = 0.1234 -> 0.12
        XCTAssertEqual(try Money.kes(12, cents: 34).applying(basisPoints: 100), .kes(0, cents: 12))
        // 12.5% of 1.00 = 0.125 -> 0.13
        XCTAssertEqual(try Money.kes(1).applying(basisPoints: 1_250), .kes(0, cents: 13))
        XCTAssertEqual(try Money.kes(-1).applying(basisPoints: 1_250), Money(minor: -13))
        // 3% per month over 6 months on 50,000 = 9,000
        XCTAssertEqual(try Money.kes(50_000).applying(basisPoints: 300 * 6), .kes(9_000))
    }

    func testAllocateIntoPartsNeverLosesACent() throws {
        let shares = try Money.kes(100).allocate(parts: 3)
        XCTAssertEqual(shares.map(\.minor), [3_334, 3_333, 3_333])
        XCTAssertEqual(try Money.sum(shares), .kes(100))

        let negative = try Money.kes(-1).allocate(parts: 3)
        XCTAssertEqual(negative.map(\.minor), [-34, -33, -33])
        XCTAssertThrowsError(try Money.kes(1).allocate(parts: 0))
    }

    func testAllocateByRatios() throws {
        let shares = try Money.kes(1_000).allocate(ratios: [1, 1, 2])
        XCTAssertEqual(shares, [.kes(250), .kes(250), .kes(500)])

        let uneven = try Money.kes(0, cents: 5).allocate(ratios: [1, 1, 1])
        XCTAssertEqual(uneven.map(\.minor), [2, 2, 1])
        XCTAssertEqual(try Money.sum(uneven).minor, 5)

        let skipZero = try Money.kes(0, cents: 1).allocate(ratios: [0, 1])
        XCTAssertEqual(skipZero.map(\.minor), [0, 1])
        XCTAssertThrowsError(try Money.kes(1).allocate(ratios: []))
        XCTAssertThrowsError(try Money.kes(1).allocate(ratios: [0, 0]))
    }

    func testCodableRoundTrip() throws {
        let original = Money.kes(99, cents: 99)
        let data = try JSONEncoder().encode(original)
        XCTAssertEqual(try JSONDecoder().decode(Money.self, from: data), original)
    }
}

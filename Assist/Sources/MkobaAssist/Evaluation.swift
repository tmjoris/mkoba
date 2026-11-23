import Foundation
import MkobaCore

/// One labelled message in the test set.
public struct EvalCase: Codable, Sendable {
    public let id: String
    /// What sort of message it is ("standard", "whatsapp-claim", "airtime", ...), for the breakdown.
    public let kind: String
    public let text: String
    /// What a careful treasurer would do with it.
    public let expect: ImportDecision
    /// For `record`: the member's name in the eval chama, the amount ("2000.00"), code and cycle.
    public let member: String?
    public let amount: String?
    public let receipt: String?
    public let cycle: Int?

    public static func load(_ url: URL) throws -> [EvalCase] {
        let decoder = JSONDecoder()
        return try String(contentsOf: url, encoding: .utf8)
            .split(separator: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .map { try decoder.decode(EvalCase.self, from: Data($0.utf8)) }
    }
}

/// How one system handled one case, from the treasurer's point of view.
public enum Outcome: String, Codable, Sendable, CaseIterable {
    /// Did what a careful treasurer would.
    case correct
    /// One tap would put something wrong in the books: a wrong amount, member, code or
    /// cycle, a non-payment recorded, or something that needed a person recorded unseen.
    case wrong
    /// Sent to a person to check when it could have been recorded or skipped. Safe, costs time.
    case flagged
    /// A payment (or something to check) dropped as "not a payment".
    case missed
}

public enum Scoring {
    public static func outcome(of review: ImportReview, for c: EvalCase, in state: LedgerState) -> Outcome {
        switch (c.expect, review.decision) {
        case (.record, .record):
            return matches(review, c, state) ? .correct : .wrong
        case (.record, .check), (.skip, .check):
            return .flagged
        case (.record, .skip), (.check, .skip):
            return .missed
        case (.skip, .skip), (.check, .check):
            return .correct
        case (.skip, .record), (.check, .record):
            return .wrong
        }
    }

    /// A reader that failed outright (no output) leaves the message for a person.
    public static func outcomeOfFailure(for c: EvalCase) -> Outcome {
        c.expect == .check ? .correct : .flagged
    }

    private static func matches(_ review: ImportReview, _ c: EvalCase, _ state: LedgerState) -> Bool {
        guard let member = review.member.flatMap({ state.members[$0] }),
              let amountText = c.amount, let expected = try? Money(parsing: amountText) else { return false }
        return member.name == c.member
            && review.amount == expected
            && review.reference?.mpesaReceipt == c.receipt?.uppercased()
            && review.cycle?.index == c.cycle
    }
}

/// The chama every eval message is read against: ten members, monthly KES 2,000 from
/// January 2026, so November 2026 is cycle 10. Two Wanjikus and two Otienos on purpose.
public enum EvalChama {
    public static let roster: [(name: String, phone: String, role: MemberRole)] = [
        ("Wanjiru Njoroge", "0712345678", .chair),
        ("John Otieno", "0722000111", .treasurer),
        ("Amina Wanjiku", "0733000222", .member),
        ("Grace Wanjiku", "0711222333", .member),
        ("Brian Otieno", "0744000333", .member),
        ("Peter Kamau", "0720456789", .member),
        ("Mary Achieng", "0790123456", .member),
        ("Faith Chebet", "0115678901", .member),
        ("Kevin Mutua", "0701987654", .member),
        ("Esther Nyambura", "0728334455", .member),
    ]

    /// Already in the books, so a message with this code is a duplicate.
    public static let recordedReceipt = "TKA1B2C3D4"

    /// 2026-11-23 12:00 in Nairobi: messages without a date fall in cycle 10.
    public static let now = Date(timeIntervalSince1970: 1_795_424_400)

    public static func state() -> LedgerState {
        let start = Date(timeIntervalSince1970: 1_767_214_800) // 2026-01-01 00:00 Nairobi
        let device = DeviceID("eval")
        var log = EventLog(group: GroupID(id(0)))
        let schedule = ContributionSchedule(frequency: .monthly, amount: .kes(2_000), startDate: start,
                                            lateFee: .kes(200))
        let ids = roster.indices.map { MemberID(id($0 + 1)) }
        log.record(.groupCreated(name: "Umoja Chama", currency: .kes, schedule: schedule, loanPolicy: .saccoDefault),
                   by: ids[0], on: device, at: start)
        for (index, member) in roster.enumerated() {
            log.record(.memberJoined(member: ids[index], name: member.name, phone: PhoneNumber(member.phone)!,
                                     role: member.role),
                       by: ids[0], on: device, at: start)
        }
        log.record(.contributionRecorded(member: ids[5], amount: .kes(2_000), cycle: CycleID(9),
                                         reference: PaymentReference(mpesaReceipt: recordedReceipt)),
                   by: ids[1], on: device, at: start.addingTimeInterval(300 * 86_400))
        return log.replay()
    }

    private static func id(_ n: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012ld", n))!
    }
}

/// What one reader did with one case, before and after the checks.
public struct EvalResult: Codable, Sendable {
    public let id: String
    public let kind: String
    public let expect: ImportDecision
    public let reading: MessageReading?
    public let error: String?
    public let seconds: Double
    public let issues: [ImportIssue]
    public let withChecks: Outcome
    public let withoutChecks: Outcome

    public static func evaluate(_ c: EvalCase, reading: MessageReading?, error: String?, seconds: Double,
                                state: LedgerState) -> EvalResult {
        guard let reading else {
            let outcome = Scoring.outcomeOfFailure(for: c)
            return EvalResult(id: c.id, kind: c.kind, expect: c.expect, reading: nil, error: error,
                              seconds: seconds, issues: [], withChecks: outcome, withoutChecks: outcome)
        }
        let checked = ImportReviewer(checks: true).review([(c.text, reading)], against: state, now: EvalChama.now)[0]
        let trusted = ImportReviewer(checks: false).review([(c.text, reading)], against: state, now: EvalChama.now)[0]
        return EvalResult(id: c.id, kind: c.kind, expect: c.expect, reading: reading, error: error,
                          seconds: seconds, issues: checked.issues,
                          withChecks: Scoring.outcome(of: checked, for: c, in: state),
                          withoutChecks: Scoring.outcome(of: trusted, for: c, in: state))
    }
}

/// Totals for a results file, as a Markdown table row.
public struct EvalSummary {
    public let name: String
    public let results: [EvalResult]

    public init(name: String, results: [EvalResult]) {
        self.name = name
        self.results = results
    }

    public func count(_ outcome: Outcome, checks: Bool) -> Int {
        results.filter { (checks ? $0.withChecks : $0.withoutChecks) == outcome }.count
    }

    public var medianSeconds: Double {
        let sorted = results.map(\.seconds).sorted()
        return sorted.isEmpty ? 0 : sorted[sorted.count / 2]
    }

    public static let header = """
        | Reader | Checks | Correct | Wrong (one tap) | Flagged | Missed | Failed | Median s/msg |
        |---|---|---|---|---|---|---|---|
        """

    public func rows() -> String {
        let failed = results.filter { $0.reading == nil }.count
        return [false, true].map { checks in
            "| \(name) | \(checks ? "on" : "off") | \(count(.correct, checks: checks))/\(results.count) | "
                + "\(count(.wrong, checks: checks)) | \(count(.flagged, checks: checks)) | "
                + "\(count(.missed, checks: checks)) | \(failed) | \(String(format: "%.1f", medianSeconds)) |"
        }.joined(separator: "\n")
    }
}

import Foundation

/// Something about a proposed entry that a person should look at before it is recorded.
public enum ImportIssue: String, Hashable, Sendable, Codable, CaseIterable {
    case receiptMissing
    case receiptMalformed
    case receiptNotInMessage
    case receiptAlreadyRecorded
    case receiptRepeated
    case notAConfirmation
    case moneyNotReceived
    case amountUnreadable
    case amountNotInMessage
    case amountLooksLikeBalance
    case nameNotInMessage
    case phoneNotInMessage
    case memberNotFound
    case memberAmbiguous
    case dateUnreadable

    public var explanation: String {
        switch self {
        case .receiptMissing: return "No M-Pesa code, so it cannot be checked."
        case .receiptMalformed: return "The M-Pesa code does not look like one."
        case .receiptNotInMessage: return "The M-Pesa code is not in the message."
        case .receiptAlreadyRecorded: return "This M-Pesa code is already in the books."
        case .receiptRepeated: return "This M-Pesa code appears twice in what you pasted."
        case .notAConfirmation: return "This reads like a note, not an M-Pesa confirmation."
        case .moneyNotReceived: return "M-Pesa does not say this money was received."
        case .amountUnreadable: return "Could not read the amount."
        case .amountNotInMessage: return "That amount is not in the message."
        case .amountLooksLikeBalance: return "That amount looks like the M-Pesa balance."
        case .nameNotInMessage: return "That name is not in the message."
        case .phoneNotInMessage: return "That phone number is not in the message."
        case .memberNotFound: return "No member matches the sender."
        case .memberAmbiguous: return "More than one member could have sent this."
        case .dateUnreadable: return "Could not read the date."
        }
    }
}

public enum ImportDecision: String, Hashable, Sendable, Codable {
    /// Every check passed; one tap records it.
    case record
    /// A person must look at it.
    case check
    /// Not money coming in (money sent, airtime, Fuliza, chat).
    case skip
}

/// One pasted message, what the reader made of it, and what the checks found.
public struct ImportReview: Hashable, Sendable {
    public let message: String
    public let reading: MessageReading
    public let amount: Money?
    public let member: MemberID?
    public let candidates: [MemberID]
    public let date: Date?
    public let cycle: CycleID?
    public let issues: [ImportIssue]

    public var decision: ImportDecision {
        guard reading.isIncomingPayment else { return .skip }
        return issues.isEmpty && member != nil && amount != nil && cycle != nil ? .record : .check
    }

    public var reference: PaymentReference? {
        let code = reading.receipt.trimmingCharacters(in: .whitespaces).uppercased()
        return code.isEmpty ? nil : PaymentReference(mpesaReceipt: code)
    }

    /// The ledger event this would record. The ledger still applies its own rules on top.
    public var event: EventKind? {
        guard let member, let amount, let cycle else { return nil }
        return .contributionRecorded(member: member, amount: amount, cycle: cycle, reference: reference)
    }
}

/// Checks a reader's output against the message itself and against the books.
///
/// The reader can be wrong in ways that cost money: the balance taken for the amount, a
/// code copied wrongly, the wrong Wanjiku. None of those are recorded without a person
/// looking, because each is checked here with plain code rather than trusted.
public struct ImportReviewer: Sendable {
    /// When false, the reader is trusted: only what is needed to build an entry is required,
    /// and an ambiguous member is resolved to the first candidate. This exists to measure
    /// what the checks are worth, not for the app.
    public var checks: Bool

    public init(checks: Bool = true) {
        self.checks = checks
    }

    public func review(_ items: [(message: String, reading: MessageReading)], against state: LedgerState,
                       now: Date = Date()) -> [ImportReview] {
        let recorded = Set((state.contributions.compactMap(\.reference)
            + state.loans.values.compactMap(\.reference)).map { $0.mpesaReceipt.uppercased() })
        var seen: Set<String> = []
        return items.map { item in
            let review = review(item.message, item.reading, state: state, recorded: recorded,
                                seen: seen, now: now)
            if review.reading.isIncomingPayment, let code = review.reference?.mpesaReceipt {
                seen.insert(code)
            }
            return review
        }
    }

    private func review(_ message: String, _ reading: MessageReading, state: LedgerState,
                        recorded: Set<String>, seen: Set<String>, now: Date) -> ImportReview {
        guard reading.isIncomingPayment else {
            return ImportReview(message: message, reading: reading, amount: nil, member: nil,
                                candidates: [], date: nil, cycle: nil, issues: [])
        }
        var issues: [ImportIssue] = []

        // Receipt
        let code = reading.receipt.trimmingCharacters(in: .whitespaces).uppercased()
        if code.isEmpty {
            if checks { issues.append(.receiptMissing) }
        } else if checks {
            if !Self.looksLikeReceipt(code) { issues.append(.receiptMalformed) }
            if !ImportParsing.contains(message, code) { issues.append(.receiptNotInMessage) }
            if recorded.contains(code) { issues.append(.receiptAlreadyRecorded) }
            if seen.contains(code) { issues.append(.receiptRepeated) }
            if !Self.isConfirmation(message, code: code) {
                issues.append(.notAConfirmation)
            } else if !Self.saysReceived(message) {
                issues.append(.moneyNotReceived)
            }
        }

        // Amount: parsed by code, then found among the amounts actually in the message.
        let amount = ImportParsing.amount(reading.amountText, currency: state.currency)
        if let amount, amount.isPositive {
            if checks {
                let mentions = ImportParsing.amounts(in: message).filter { $0.value == amount }
                if mentions.isEmpty {
                    issues.append(.amountNotInMessage)
                } else if mentions.allSatisfy({ $0.before.contains("balance") || $0.before.contains("salio") }) {
                    issues.append(.amountLooksLikeBalance)
                }
            }
        } else {
            issues.append(.amountUnreadable)
        }

        // Member: whoever the money is for, else the sender.
        let forSomeoneElse = !reading.paidForName.trimmingCharacters(in: .whitespaces).isEmpty
        let name = forSomeoneElse ? reading.paidForName : reading.senderName
        if checks, !name.isEmpty, !ImportParsing.contains(message, name) {
            issues.append(.nameNotInMessage)
        }
        let phone = Self.cleanPhone(reading.senderPhone)
        if checks, !forSomeoneElse, !phone.isEmpty, !ImportParsing.contains(message, phone) {
            issues.append(.phoneNotInMessage)
        }
        let members = state.members.values.sorted { $0.id < $1.id }
        let match = MemberMatcher.match(name: name, phone: forSomeoneElse ? "" : phone,
                                        in: members)
        var member: MemberID?
        switch match {
        case let .one(id):
            member = id
        case let .several(ids):
            if checks {
                issues.append(.memberAmbiguous)
            } else {
                member = ids.first
            }
        case .none:
            issues.append(.memberNotFound)
        }

        // Date decides the cycle. No date at all (a forwarded note) means today.
        let timeZone = TimeZone(identifier: state.group?.schedule.timeZoneIdentifier ?? "Africa/Nairobi") ?? .gmt
        var date: Date?
        if reading.dateText.trimmingCharacters(in: .whitespaces).isEmpty {
            date = now
        } else if let parsed = ImportParsing.date(reading.dateText, timeZone: timeZone) {
            date = parsed
        } else if checks {
            issues.append(.dateUnreadable)
        } else {
            date = now
        }
        let cycle = date.flatMap { state.group?.schedule.cycle(containing: $0) }

        return ImportReview(message: message, reading: reading, amount: amount?.isPositive == true ? amount : nil,
                            member: member, candidates: match.candidates, date: date, cycle: cycle,
                            issues: issues)
    }

    /// Only M-Pesa's own message is proof: the code followed by "Confirmed" (or
    /// "Imethibitishwa" in Swahili). A member's note quoting a code is a claim to check.
    public static func isConfirmation(_ message: String, code: String) -> Bool {
        guard looksLikeReceipt(code), let regex = try? Regex(code + #"\s*(confirmed|imethibitishwa)"#).ignoresCase() else { return false }
        return message.contains(regex)
    }

    /// A confirmation for money coming in says so. Money sent, paid, withdrawn or spent on
    /// airtime is confirmed in the same format, which is exactly what a reader can mistake.
    public static func saysReceived(_ message: String) -> Bool {
        let text = message.lowercased()
        return text.contains("received") || text.contains("umepokea")
    }

    /// Stray "*" or spaces around a number are formatting; masks inside it are kept.
    static func cleanPhone(_ raw: String) -> String {
        raw.trimmingCharacters(in: CharacterSet(charactersIn: "* ").union(.whitespaces))
    }

    /// M-Pesa codes are ten capital letters and digits, with at least one of each.
    public static func looksLikeReceipt(_ code: String) -> Bool {
        code.count == 10
            && code.allSatisfy { $0.isASCII && ($0.isUppercase || $0.isNumber) }
            && code.contains(where: \.isLetter) && code.contains(where: \.isNumber)
    }
}

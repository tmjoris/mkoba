import Foundation

/// What a reader (the regex parser or a language model) says one pasted message contains.
///
/// Every field is text copied out of the message, not interpreted. The reader points at
/// the words; plain code turns them into money, a date and a member. That keeps arithmetic
/// and date maths away from the model, and it makes every field checkable: if the model
/// says the amount is "Ksh1,000.00", that text has to be in the message.
public struct MessageReading: Hashable, Sendable, Codable {
    /// True only when the message says the treasurer received money.
    public var isIncomingPayment: Bool
    public var receipt: String
    public var amountText: String
    public var senderName: String
    public var senderPhone: String
    /// The member the money is for when someone else sent it ("hii ni ya Amina"). Empty if none.
    public var paidForName: String
    public var dateText: String

    public init(isIncomingPayment: Bool, receipt: String = "", amountText: String = "",
                senderName: String = "", senderPhone: String = "", paidForName: String = "",
                dateText: String = "") {
        self.isIncomingPayment = isIncomingPayment
        self.receipt = receipt
        self.amountText = amountText
        self.senderName = senderName
        self.senderPhone = senderPhone
        self.paidForName = paidForName
        self.dateText = dateText
    }

    public static let notAPayment = MessageReading(isIncomingPayment: false)
}

/// Turns the copied text into values. Pure functions, no model involved.
public enum ImportParsing {
    /// "Ksh1,000.00", "KES 2,000", "Sh. 500", "2000/=", "1k" or "1.5K" as money.
    public static func amount(_ text: String, currency: Currency = .kes) -> Money? {
        var t = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        for prefix in ["kshs", "ksh", "kes", "sh"] where t.hasPrefix(prefix) {
            t = String(t.dropFirst(prefix.count))
            break
        }
        t = t.replacingOccurrences(of: "/=", with: "")
            .replacingOccurrences(of: "/-", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: ". ").union(.whitespaces))
        var thousands = false
        if t.hasSuffix("k") {
            thousands = true
            t.removeLast()
            t = t.trimmingCharacters(in: .whitespaces)
        }
        guard !t.isEmpty, t.first?.isNumber == true,
              let money = try? Money(parsing: t, currency: currency) else { return nil }
        return thousands ? try? money.multiplied(by: 1_000) : money
    }

    /// M-Pesa dates are day/month/year: "3/11/26 at 7:42 PM", "03/11/2026 19:42" or "3/11/26".
    public static func date(_ text: String, timeZone: TimeZone) -> Date? {
        guard let regex = try? Regex(#"(\d{1,2})/(\d{1,2})/(\d{2,4})(?:\D{1,5}(\d{1,2}):(\d{2})\s*([AaPp][Mm])?)?"#),
              let match = text.firstMatch(of: regex) else { return nil }
        func int(_ index: Int) -> Int? { match.output[index].substring.flatMap { Int($0) } }
        guard let day = int(1), let month = int(2), var year = int(3) else { return nil }
        if year < 100 { year += 2000 }
        var hour = int(4) ?? 0
        let minute = int(5) ?? 0
        if let meridiem = match.output[6].substring?.lowercased() {
            guard (1...12).contains(hour) else { return nil }
            if meridiem == "pm", hour != 12 { hour += 12 }
            if meridiem == "am", hour == 12 { hour = 0 }
        }
        guard (1...12).contains(month), (1...31).contains(day), (0...23).contains(hour),
              (0...59).contains(minute) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let components = DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)
        guard let date = calendar.date(from: components),
              calendar.component(.day, from: date) == day else { return nil } // rejects 31/2
        return date
    }

    /// Every amount-looking piece of the message with what comes just before it, so the
    /// checks can tell "received Ksh1,000.00" from "balance is Ksh1,000.00".
    static func amounts(in message: String) -> [(value: Money, before: String)] {
        guard let regex = try? Regex(#"(?i)(?:kshs?\.?|kes|sh\.?)?\s?\d[\d,]*(?:\.\d{1,2})?(?:\s?k\b)?"#) else {
            return []
        }
        return message.matches(of: regex).compactMap { match in
            guard let value = amount(String(message[match.range])) else { return nil }
            let start = message.index(match.range.lowerBound, offsetBy: -40,
                                      limitedBy: message.startIndex) ?? message.startIndex
            return (value, String(message[start..<match.range.lowerBound]).lowercased())
        }
    }

    /// Case- and spacing-insensitive "does the message contain this text".
    static func contains(_ message: String, _ fragment: String) -> Bool {
        let needle = squeeze(fragment)
        return !needle.isEmpty && squeeze(message).contains(needle)
    }

    private static func squeeze(_ text: String) -> String {
        text.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}

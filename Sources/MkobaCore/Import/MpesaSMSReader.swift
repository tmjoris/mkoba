/// The baseline reader: one regular expression for the standard "You have received" SMS.
///
/// It is fast, free and exact on messages in that format, and reads anything else
/// (forwarded notes, other wording, Swahili) as "not a payment". The evaluation compares
/// language models against it, so a model has to earn its place.
public enum MpesaSMSReader {
    public static func read(_ message: String) -> MessageReading {
        let pattern = #"([A-Z0-9]{10})\s*Confirmed\.?\s*You have received\s*(Ksh\s?[\d,]+(?:\.\d{1,2})?)\s+from\s+(.+?)\s+([+\d][\d*]{5,})?\s*on\s+(\d{1,2}/\d{1,2}/\d{2,4}\s+at\s+\d{1,2}:\d{2}\s*[AP]M)"#
        guard let regex = try? Regex(pattern).ignoresCase(),
              let match = message.firstMatch(of: regex) else { return .notAPayment }
        func group(_ index: Int) -> String { match.output[index].substring.map(String.init) ?? "" }
        return MessageReading(isIncomingPayment: true, receipt: group(1), amountText: group(2),
                              senderName: group(3), senderPhone: group(4), dateText: group(5))
    }
}

/// Splits a paste into single messages: on blank lines, and wherever a new
/// "XXXXXXXXXX Confirmed" starts in the middle of a line (several SMS copied at once).
public enum MessageSplitter {
    public static func split(_ paste: String) -> [String] {
        let normalized = paste.replacingOccurrences(of: "\r\n", with: "\n")
        var chunks: [String] = []
        var current: [Substring] = []
        for line in normalized.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                if !current.isEmpty { chunks.append(current.joined(separator: "\n")) }
                current = []
            } else {
                current.append(line)
            }
        }
        if !current.isEmpty { chunks.append(current.joined(separator: "\n")) }
        return chunks.flatMap(splitRunTogether)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func splitRunTogether(_ chunk: String) -> [String] {
        guard let regex = try? Regex(#"[A-Z0-9]{10}\s*[Cc]onfirmed"#) else { return [chunk] }
        let starts = chunk.matches(of: regex).map(\.range.lowerBound).filter { $0 != chunk.startIndex }
        guard !starts.isEmpty else { return [chunk] }
        var pieces: [String] = []
        var from = chunk.startIndex
        for start in starts {
            pieces.append(String(chunk[from..<start]))
            from = start
        }
        pieces.append(String(chunk[from...]))
        return pieces
    }
}

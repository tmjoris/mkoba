/// Finds which member a payment came from, using the phone number first and the name second.
public enum MemberMatcher {
    public enum Match: Hashable, Sendable {
        case one(MemberID)
        case several([MemberID])
        case none

        public var candidates: [MemberID] {
            switch self {
            case let .one(id): return [id]
            case let .several(ids): return ids
            case .none: return []
            }
        }
    }

    /// `phone` may be complete ("0733000222", "254733000222") or masked the way newer
    /// M-Pesa messages show it ("0733***222"). A complete number that belongs to a member
    /// wins outright; a masked one only narrows the names down.
    public static func match(name: String, phone: String, in members: [Member]) -> Match {
        if let full = PhoneNumber(phone), !phone.contains("*") {
            let owners = members.filter { $0.phone == full }
            if owners.count == 1 { return .one(owners[0].id) }
        }
        let byPhone = members.filter { masked(phone, matches: $0.phone) }
        let byName = bestByName(name, in: members)

        let both = byPhone.filter { member in byName.contains { $0.id == member.id } }
        if both.count == 1 { return .one(both[0].id) }
        if both.count > 1 { return .several(sorted(both)) }
        if !byPhone.isEmpty, !byName.isEmpty {
            // The phone points at one person and the name at another: a person must decide.
            return .several(sorted(byPhone + byName))
        }
        let only = byPhone.isEmpty ? byName : byPhone
        switch only.count {
        case 0: return .none
        case 1: return .one(only[0].id)
        default: return .several(sorted(only))
        }
    }

    /// Members sharing the most name words with `name`, ignoring case and order; on a tie,
    /// the member more of whose name matched. "AMINA WANJIKU" picks Amina Wanjiku over Grace
    /// Wanjiku, and a member called just "Amina" over Grace too; "WANJIKU" alone picks both.
    static func bestByName(_ name: String, in members: [Member]) -> [Member] {
        let words = Set(tokens(name))
        guard !words.isEmpty else { return [] }
        let scored = members.map { member -> (member: Member, shared: Int, share: Double) in
            let own = tokens(member.name)
            let shared = own.filter(words.contains).count
            return (member, shared, own.isEmpty ? 0 : Double(shared) / Double(own.count))
        }
        guard let best = scored.max(by: { ($0.shared, $0.share) < ($1.shared, $1.share) }), best.shared > 0 else {
            return []
        }
        return scored.filter { $0.shared == best.shared && $0.share == best.share }.map(\.member)
    }

    static func tokens(_ name: String) -> [String] {
        name.uppercased()
            .split { !$0.isLetter }
            .map(String.init)
            .filter { $0.count >= 2 }
    }

    /// "0733***222" or "2547***222": the visible leading and trailing digits must agree.
    static func masked(_ hint: String, matches phone: PhoneNumber) -> Bool {
        guard hint.contains("*") else { return false }
        let pieces = hint.split(separator: "*", omittingEmptySubsequences: true)
        guard pieces.count == 2 else { return false }
        var head = pieces[0].filter(\.isNumber)
        let tail = pieces[1].filter(\.isNumber)
        guard tail.count >= 3 else { return false }
        if head.hasPrefix("0") { head = "254" + head.dropFirst() }
        return phone.msisdn.hasPrefix(head) && phone.msisdn.hasSuffix(tail)
    }

    private static func sorted(_ members: [Member]) -> [MemberID] {
        Array(Set(members.map(\.id))).sorted()
    }
}

import MkobaCore
import SwiftUI

struct MembersView: View {
    @Bindable var session: GroupSession
    @State private var adding = false

    var body: some View {
        List(session.membersSorted, id: \.id) { member in
            let balance = session.state.balance(of: member.id)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(member.name).font(.headline)
                    if member.role != .member {
                        Text(member.role.rawValue.capitalized)
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Theme.gold.opacity(0.2), in: Capsule())
                    }
                    Spacer()
                    MoneyText(amount: balance.savings, font: .subheadline.weight(.semibold))
                }
                HStack(spacing: 12) {
                    Text(member.phone.local)
                    if balance.loansOutstanding.isPositive {
                        Text("Loan \(balance.loansOutstanding.display)")
                    }
                    if balance.guaranteesPledged.isPositive {
                        Text("Guaranteeing \(balance.guaranteesPledged.display)")
                    }
                }
                .font(.caption).foregroundStyle(.secondary)
            }
            .accessibilityIdentifier("member-row-\(member.name)")
        }
        .navigationTitle("Members")
        .toolbar {
            if session.amOfficial {
                Button { adding = true } label: { Image(systemName: "person.badge.plus") }
                    .accessibilityIdentifier("add-member")
            }
        }
        .sheet(isPresented: $adding) { AddMemberView(session: session) }
    }
}

struct AddMemberView: View {
    @Bindable var session: GroupSession
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var phoneText = ""
    @State private var role: MemberRole = .member
    @State private var error: String?

    private var phone: PhoneNumber? { PhoneNumber(phoneText) }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $name).accessibilityIdentifier("member-name")
                TextField("M-Pesa number", text: $phoneText).keyboardType(.phonePad)
                    .accessibilityIdentifier("member-phone")
                Picker("Role", selection: $role) {
                    ForEach(MemberRole.allCases, id: \.self) { Text($0.rawValue.capitalized) }
                }
                ErrorBanner(message: error)
            }
            .navigationTitle("Add member")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { Task { await add() } }
                        .disabled(name.isEmpty || phone == nil)
                        .accessibilityIdentifier("add-member-confirm")
                }
            }
        }
    }

    private func add() async {
        guard let phone else { return }
        do {
            let event = try await session.record(.memberJoined(member: MemberID(), name: name, phone: phone, role: role))
            if let rejection = session.rejection(of: event) {
                error = rejection.userMessage
            } else {
                dismiss()
            }
        } catch {
            self.error = error.localizedDescription
        }
    }
}

extension LedgerError {
    /// Plain-language reasons shown next to a refused entry.
    var userMessage: String {
        switch self {
        case .groupAlreadyCreated: return "This group already exists."
        case .groupNotCreated: return "The group has not been set up yet."
        case .unknownMember: return "That person is not a member."
        case .duplicateMember: return "That member is already in the group."
        case .notAnOfficial: return "Only the chair, treasurer or secretary can do this."
        case .nonPositiveAmount: return "Amount must be more than zero."
        case .currencyMismatch: return "Wrong currency."
        case .unknownLoan: return "That loan does not exist."
        case .loanNotInStatus(_, let expected): return "The loan must be \(expected) first."
        case .loanExceedsPolicy(let limit): return "Loans are capped at \(limit.display) for this member."
        case .loanTermTooLong(let months): return "Loans run for at most \(months) months."
        case .insufficientGuarantees(let required, let pledged):
            return "Guarantees cover \(pledged.display) of \(required.display)."
        case .guarantorIsBorrower: return "A borrower cannot guarantee their own loan."
        case .guaranteeExceedsSavings(let available): return "You can guarantee up to \(available.display)."
        case .repaymentExceedsOutstanding(let outstanding): return "Only \(outstanding.display) is outstanding."
        case .insufficientPot(let available): return "The pot only has \(available.display)."
        case .alreadyGuaranteed: return "You already guaranteed this loan."
        }
    }
}

import MkobaCore
import SwiftUI

struct LoansView: View {
    @Bindable var session: GroupSession
    @State private var requesting = false

    var body: some View {
        List {
            if session.loansSorted.isEmpty {
                ContentUnavailableView("No loans", systemImage: "hand.coins",
                                       description: Text("Members can borrow up to 3x their savings, backed by other members."))
            }
            ForEach(session.loansSorted, id: \.id) { loan in
                NavigationLink {
                    LoanDetailView(session: session, loanID: loan.id)
                } label: {
                    LoanRow(loan: loan, borrower: session.member(loan.borrower)?.name ?? "Unknown")
                }
            }
        }
        .navigationTitle("Loans")
        .toolbar {
            Button { requesting = true } label: { Image(systemName: "plus") }
                .accessibilityIdentifier("request-loan")
        }
        .sheet(isPresented: $requesting) { RequestLoanView(session: session) }
    }
}

struct LoanRow: View {
    let loan: Loan
    let borrower: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(borrower).font(.headline)
                Spacer()
                MoneyText(amount: loan.principal, font: .subheadline.weight(.semibold))
            }
            HStack {
                LoanStatusBadge(status: loan.status)
                Text("\(loan.termMonths) months").font(.caption).foregroundStyle(.secondary)
                if case .disbursed = loan.status {
                    Spacer()
                    Text("Owes \(loan.outstanding.display)").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}

struct LoanStatusBadge: View {
    let status: LoanStatus
    var body: some View {
        Text(label)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(color.opacity(0.18), in: Capsule())
            .foregroundStyle(color)
    }
    private var label: String {
        switch status {
        case .requested: return "Requested"
        case .approved: return "Approved"
        case .rejected: return "Rejected"
        case .disbursed: return "Active"
        case .repaid: return "Repaid"
        }
    }
    private var color: Color {
        switch status {
        case .requested: return Theme.gold
        case .approved: return .blue
        case .rejected: return Theme.danger
        case .disbursed: return Theme.green
        case .repaid: return .secondary
        }
    }
}

struct RequestLoanView: View {
    @Bindable var session: GroupSession
    @Environment(\.dismiss) private var dismiss
    @State private var shillings: Int64?
    @State private var months = 6
    @State private var error: String?

    private var limit: Money? {
        guard let me = session.me, let policy = session.state.group?.loanPolicy else { return nil }
        return try? policy.borrowingLimit(savings: session.state.balance(of: me).savings)
    }

    private var preview: (interest: Money, instalment: Money)? {
        guard let shillings, shillings > 0, let policy = session.state.group?.loanPolicy,
              let interest = try? policy.interest(on: .kes(shillings), termMonths: months),
              let first = try? policy.instalments(principal: .kes(shillings), termMonths: months).first else { return nil }
        return (interest, first)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ShillingField(title: "Amount", shillings: $shillings)
                    Stepper("\(months) months", value: $months, in: 1...(session.state.group?.loanPolicy.maxTermMonths ?? 12))
                } footer: {
                    if let limit { Text("You can borrow up to \(limit.display) (3x your savings).") }
                }
                if let preview {
                    Section("Repayment") {
                        LabeledContent("Interest", value: preview.interest.display)
                        LabeledContent("Monthly instalment", value: preview.instalment.display)
                    }
                }
                ErrorBanner(message: error)
            }
            .navigationTitle("Request a loan")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Request") { Task { await request() } }
                        .disabled((shillings ?? 0) <= 0)
                        .accessibilityIdentifier("request-loan-confirm")
                }
            }
        }
    }

    private func request() async {
        guard let me = session.me, let shillings else { return }
        do {
            let event = try await session.record(.loanRequested(loan: LoanID(), borrower: me,
                                                                principal: .kes(shillings), termMonths: months))
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

struct LoanDetailView: View {
    @Bindable var session: GroupSession
    let loanID: LoanID
    @State private var guaranteeShillings: Int64?
    @State private var repayShillings: Int64?
    @State private var error: String?

    private var loan: Loan? { session.state.loans[loanID] }

    var body: some View {
        if let loan {
            Form {
                Section {
                    LabeledContent("Borrower", value: session.member(loan.borrower)?.name ?? "Unknown")
                    LabeledContent("Principal", value: loan.principal.display)
                    LabeledContent("Interest", value: loan.interest.display)
                    LabeledContent("Total due", value: loan.totalDue.display)
                    if case .disbursed = loan.status {
                        LabeledContent("Repaid", value: loan.repaid.display)
                        LabeledContent("Outstanding", value: loan.outstanding.display)
                    }
                    LabeledContent("Status") { LoanStatusBadge(status: loan.status) }
                }
                Section("Guarantors (\(loan.guaranteed.display) of \(loan.principal.display))") {
                    ForEach(loan.guarantees.sorted(by: { $0.key < $1.key }), id: \.key) { member, amount in
                        LabeledContent(session.member(member)?.name ?? "Unknown", value: amount.display)
                    }
                    if loan.status == .requested, let me = session.me, me != loan.borrower, loan.guarantees[me] == nil {
                        ShillingField(title: "Guarantee amount", shillings: $guaranteeShillings)
                        Button("Guarantee this loan") { Task { await act(.loanGuaranteed(loan: loanID, guarantor: me, amount: .kes(guaranteeShillings ?? 0))) } }
                            .disabled((guaranteeShillings ?? 0) <= 0)
                    }
                }
                if session.amOfficial, let me = session.me {
                    Section("Treasurer actions") {
                        switch loan.status {
                        case .requested:
                            Button("Approve") { Task { await act(.loanApproved(loan: loanID, approver: me)) } }
                                .disabled(loan.guaranteed < loan.principal)
                            Button("Reject", role: .destructive) {
                                Task { await act(.loanRejected(loan: loanID, approver: me, reason: "Declined by officials")) }
                            }
                        case .approved:
                            Button("Mark disbursed from pot (\(session.state.pot.display))") {
                                Task { await act(.loanDisbursed(loan: loanID, reference: nil)) }
                            }
                        case .disbursed:
                            ShillingField(title: "Repayment received", shillings: $repayShillings)
                            Button("Record repayment") {
                                Task { await act(.loanRepaid(loan: loanID, amount: .kes(repayShillings ?? 0), reference: nil)) }
                            }
                            .disabled((repayShillings ?? 0) <= 0)
                        case .rejected, .repaid:
                            Text("Nothing to do").foregroundStyle(.secondary)
                        }
                    }
                }
                ErrorBanner(message: error)
            }
            .navigationTitle("Loan")
        } else {
            ContentUnavailableView("Loan not found", systemImage: "questionmark")
        }
    }

    private func act(_ kind: EventKind) async {
        error = nil
        do {
            let event = try await session.record(kind)
            if let rejection = session.rejection(of: event) { error = rejection.userMessage }
            guaranteeShillings = nil
            repayShillings = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}

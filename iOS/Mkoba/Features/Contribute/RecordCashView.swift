import MkobaCore
import SwiftUI

/// Treasurer records cash handed over at a meeting. Works fully offline.
struct RecordCashView: View {
    @Bindable var session: GroupSession
    @Environment(\.dismiss) private var dismiss
    @State private var member: MemberID?
    @State private var shillings: Int64?
    @State private var error: String?

    var body: some View {
        Form {
            Picker("Member", selection: $member) {
                Text("Choose…").tag(MemberID?.none)
                ForEach(session.membersSorted, id: \.id) { Text($0.name).tag(MemberID?.some($0.id)) }
            }
            .accessibilityIdentifier("cash-member")
            ShillingField(title: "Amount", shillings: $shillings)
            LabeledContent("Cycle", value: "\(session.currentCycle.index)")
            ErrorBanner(message: error)
        }
        .navigationTitle("Record cash")
        .toolbar {
            Button("Save") { Task { await save() } }
                .disabled(member == nil || (shillings ?? 0) <= 0)
                .accessibilityIdentifier("cash-save")
        }
        .onAppear { shillings = session.state.group?.schedule.amount.majorPart }
    }

    private func save() async {
        guard let member, let shillings else { return }
        do {
            let event = try await session.record(.contributionRecorded(
                member: member, amount: .kes(shillings), cycle: session.currentCycle, reference: nil))
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

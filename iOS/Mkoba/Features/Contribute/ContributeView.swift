import MkobaCore
import SwiftUI

/// M-Pesa contribution. The screen mirrors the payment state machine one to one, and the
/// user can never trigger a second STK prompt while the first could still be paid.
struct ContributeView: View {
    @Bindable var session: GroupSession
    @Environment(AppModel.self) private var model
    @State private var viewModel: ContributeViewModel?

    var body: some View {
        if let viewModel {
            ContributeForm(viewModel: viewModel)
        } else {
            ProgressView().task {
                viewModel = ContributeViewModel(session: session, api: model.api)
            }
        }
    }
}

private struct ContributeForm: View {
    @Bindable var viewModel: ContributeViewModel

    var body: some View {
        Form {
            Section("Contribution") {
                ShillingField(title: "Amount", shillings: $viewModel.shillings)
                LabeledContent("Cycle", value: "\(viewModel.session.currentCycle.index)")
                LabeledContent("M-Pesa number", value: viewModel.phone?.local ?? "Unknown")
            }
            if let payment = viewModel.payment {
                Section("Status") {
                    PaymentStatusView(payment: payment)
                }
            }
            ErrorBanner(message: viewModel.error)
        }
        .navigationTitle("Contribute")
        .safeAreaInset(edge: .bottom) {
            Button {
                Task { await viewModel.pay() }
            } label: {
                Label(viewModel.buttonTitle, systemImage: "iphone.radiowaves.left.and.right")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!viewModel.canPay)
            .padding()
            .accessibilityIdentifier("pay-button")
        }
        .task { await viewModel.pollWhileLive() }
    }
}

@Observable
@MainActor
final class ContributeViewModel {
    let session: GroupSession
    private let api: APIClient
    var shillings: Int64?
    private(set) var payment: PendingPayment?
    private(set) var error: String?
    private(set) var busy = false

    init(session: GroupSession, api: APIClient) {
        self.session = session
        self.api = api
        shillings = session.state.group?.schedule.amount.majorPart
    }

    var phone: PhoneNumber? { session.me.flatMap { session.member($0)?.phone } }

    var canPay: Bool {
        guard !busy, (shillings ?? 0) > 0, phone != nil else { return false }
        return payment?.canSendPrompt ?? true
    }

    var buttonTitle: String {
        switch payment?.status {
        case .none, .requested?: return "Send M-Pesa prompt"
        case .promptSent?: return "Waiting for your PIN…"
        case .unknown?: return "Checking with M-Pesa…"
        case .failed?: return "Try again"
        case .completed?: return "Paid"
        }
    }

    func pay() async {
        guard let me = session.me, let phone, let shillings else { return }
        busy = true
        defer { busy = false }
        error = nil
        do {
            if let existing = payment, existing.canSendPrompt {
                payment = try await api.retry(existing.id)
            } else {
                payment = try await api.createPayment(.init(
                    group: session.group, member: me, amountMinor: shillings * 100,
                    cycle: session.currentCycle.index, phone: phone.msisdn,
                    accountReference: session.state.group?.name))
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Polls the server while a prompt is live. The server owns the state machine; the
    /// phone only mirrors it, so a crash or kill mid-payment loses nothing.
    func pollWhileLive() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(2))
            guard let current = payment, !current.status.isTerminal else { continue }
            if let fresh = try? await api.payment(current.id) {
                payment = fresh
                if case .completed = fresh.status { await session.sync() }
            }
        }
    }
}

struct PaymentStatusView: View {
    let payment: PendingPayment

    var body: some View {
        HStack(spacing: 12) {
            icon.font(.title2)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).font(.footnote).foregroundStyle(.secondary)
            }
        }
        .accessibilityIdentifier("payment-status")
        .accessibilityLabel(title)
    }

    @ViewBuilder private var icon: some View {
        switch payment.status {
        case .requested: Image(systemName: "clock")
        case .promptSent: ProgressView()
        case .unknown: Image(systemName: "questionmark.circle").foregroundStyle(Theme.gold)
        case .failed: Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.danger)
        case .completed: Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.green)
        }
    }

    private var title: String {
        switch payment.status {
        case .requested: return "Ready to send"
        case .promptSent: return "Check your phone"
        case .unknown: return "Confirming with M-Pesa"
        case .failed(let code, _): return Daraja.ResultCode(rawValue: code) == .cancelledByUser ? "Cancelled" : "Payment failed"
        case .completed: return "Paid \(payment.amount.display)"
        }
    }

    private var detail: String {
        switch payment.status {
        case .requested: return "Nothing has been charged."
        case .promptSent: return "Enter your M-Pesa PIN on the prompt. Do not pay again."
        case .unknown: return "We did not hear back yet. If you paid, it will appear; you will not be charged twice."
        case .failed(_, let description): return description
        case .completed(let receipt): return "M-Pesa receipt \(receipt.number)"
        }
    }
}

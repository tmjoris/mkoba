import Foundation
import MkobaCore
import Vapor

extension SyncRequest: @retroactive Content {}
extension SyncResponse: @retroactive Content {}
extension PendingPayment: @retroactive Content {}
extension Daraja.Callback: @retroactive Content {}

struct CreatePaymentRequest: Content {
    let group: GroupID
    let member: MemberID
    /// Minor units (cents). KES 2,000 is 200000.
    let amountMinor: Int64
    let cycle: Int
    let phone: String
    let accountReference: String?
}

struct LedgerSummary: Content {
    let group: String
    let name: String?
    let members: Int
    let pot: String
    let events: Int
    let rejected: Int
    let loans: Int
}

/// Drives a payment through its state machine. The store owns the data; this owns the policy.
struct PaymentService: Sendable {
    let store: Store
    let gateway: any DarajaGateway
    let credentials: Daraja.Credentials
    let callbackURL: URL
    let logger: Logger

    func create(_ body: CreatePaymentRequest) async throws -> PendingPayment {
        guard let phone = PhoneNumber(body.phone) else {
            throw Abort(.badRequest, reason: "phone must be a Kenyan mobile number")
        }
        let amount = Money(minor: body.amountMinor)
        guard amount.isPositive, amount.minorPart == 0 else {
            throw Abort(.badRequest, reason: "amount must be whole shillings")
        }
        guard let state = await store.state(for: body.group), state.members[body.member] != nil else {
            throw Abort(.notFound, reason: "member is not in that group")
        }
        var payment = PendingPayment(group: body.group, member: body.member, amount: amount,
                                     cycle: CycleID(body.cycle), phone: phone)
        await store.insert(payment)
        payment = try await sendPrompt(payment, reference: body.accountReference ?? state.group?.name ?? "MKOBA")
        return payment
    }

    func sendPrompt(_ payment: PendingPayment, reference: String) async throws -> PendingPayment {
        guard payment.canSendPrompt else { throw Abort(.conflict, reason: "payment already has a live prompt") }
        let request = try Daraja.StkPushRequest(
            credentials: credentials, amount: payment.amount, phone: payment.phone, callback: callbackURL,
            accountReference: reference, description: "Chama \(payment.cycle)")
        let response = try await gateway.stkPush(request)
        guard response.accepted else {
            throw PaymentError.rejectedByDaraja(code: response.responseCode, description: response.responseDescription)
        }
        let updated = try payment.promptSent(checkoutRequestID: response.checkoutRequestID, at: Date())
        await store.update(updated)
        return updated
    }

    /// Idempotent: Daraja retries callbacks, and a duplicate must not double-record.
    func handleCallback(_ callback: Daraja.Callback) async throws {
        guard let payment = await store.payment(checkout: callback.checkoutRequestID) else {
            logger.warning("callback for unknown checkout \(callback.checkoutRequestID)")
            throw Abort(.notFound)
        }
        if payment.status.isTerminal {
            logger.info("duplicate callback for \(payment.id) ignored")
            return
        }
        let updated = try payment.callbackReceived(callback, at: Date())
        await store.update(updated)
    }

    /// Ages live prompts into `unknown`, then asks Daraja what happened to each unknown one.
    func reconcile(now: Date = Date()) async {
        for payment in await store.pendingPayments() {
            var current = payment.tick(now: now)
            if current != payment { await store.update(current) }
            guard current.needsStatusQuery, let checkout = current.status.checkoutRequestID else { continue }
            do {
                if let outcome = try await gateway.query(checkoutRequestID: checkout) {
                    current = try current.resolved(outcome, at: now)
                    await store.update(current)
                    logger.info("reconciled \(current.id): \(current.status)")
                }
            } catch {
                logger.warning("reconcile \(current.id) failed: \(error)")
            }
        }
    }
}

extension PaymentService {
    struct Key: StorageKey { typealias Value = PaymentService }
}

extension Application {
    var payments: PaymentService {
        get { storage[PaymentService.Key.self]! }
        set { storage[PaymentService.Key.self] = newValue }
    }
}

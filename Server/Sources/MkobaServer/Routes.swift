import MkobaCore
import Vapor

func routes(_ app: Application) throws {
    app.get("health") { _ in ["status": "ok"] }

    let v1 = app.grouped("v1")

    // MARK: Sync

    v1.post("groups", ":group", "sync") { req async throws -> SyncResponse in
        let request = try req.content.decode(SyncRequest.self)
        guard request.group.description == req.parameters.get("group") else {
            throw Abort(.badRequest, reason: "group in path and body differ")
        }
        return await req.application.store.sync(request)
    }

    v1.get("groups", ":group", "ledger") { req async throws -> LedgerSummary in
        guard let raw = req.parameters.get("group"), let uuid = UUID(uuidString: raw),
              let log = await req.application.store.log(for: GroupID(uuid)) else {
            throw Abort(.notFound)
        }
        let state = log.replay()
        return LedgerSummary(group: raw, name: state.group?.name, members: state.members.count,
                             pot: state.pot.description, events: log.count, rejected: state.rejected.count,
                             loans: state.loans.count)
    }

    // MARK: Payments

    v1.post("payments") { req async throws -> Response in
        let body = try req.content.decode(CreatePaymentRequest.self)
        let payment = try await req.application.payments.create(body)
        let response = Response(status: .accepted)
        try response.content.encode(payment)
        return response
    }

    v1.get("payments", ":id") { req async throws -> PendingPayment in
        guard let id = req.parameters.get("id", as: UUID.self),
              let payment = await req.application.store.payment(id) else {
            throw Abort(.notFound)
        }
        return payment
    }

    v1.post("payments", ":id", "retry") { req async throws -> PendingPayment in
        guard let id = req.parameters.get("id", as: UUID.self),
              let payment = await req.application.store.payment(id) else {
            throw Abort(.notFound)
        }
        return try await req.application.payments.sendPrompt(payment, reference: "MKOBA")
    }

    v1.post("payments", "reconcile") { req async throws -> HTTPStatus in
        await req.application.payments.reconcile()
        return .ok
    }

    v1.post("payments", "daraja", "callback") { req async throws -> [String: String] in
        let callback = try req.content.decode(Daraja.Callback.self)
        try await req.application.payments.handleCallback(callback)
        // Daraja expects this exact acknowledgement shape.
        return ["ResultCode": "0", "ResultDesc": "Accepted"]
    }
}

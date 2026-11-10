import Foundation
import MkobaCore
import Vapor

/// Everything the server knows, behind an actor so concurrent syncs and callbacks never
/// race. Persisted as one JSON file: a chama server needs durability, not Postgres.
actor Store {
    struct Snapshot: Codable {
        var logs: [String: EventLog] = [:]
        var payments: [UUID: PendingPayment] = [:]
        var checkouts: [String: UUID] = [:]
    }

    static let device = DeviceID("mkoba-server")

    private var snapshot: Snapshot
    private let fileURL: URL?
    private let logger: Logger

    init(fileURL: URL?, logger: Logger) {
        self.fileURL = fileURL
        self.logger = logger
        snapshot = Snapshot()
        if let fileURL, let data = try? Data(contentsOf: fileURL),
           let loaded = try? Store.decoder.decode(Snapshot.self, from: data) {
            snapshot = loaded
            logger.info("loaded \(loaded.logs.count) groups, \(loaded.payments.count) payments from \(fileURL.path)")
        }
    }

    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    // MARK: - Sync

    func sync(_ request: SyncRequest) -> SyncResponse {
        var log = snapshot.logs[request.group.description] ?? EventLog(group: request.group)
        let response = log.serve(request)
        snapshot.logs[request.group.description] = log
        persist()
        return response
    }

    func log(for group: GroupID) -> EventLog? {
        snapshot.logs[group.description]
    }

    func state(for group: GroupID) -> LedgerState? {
        snapshot.logs[group.description]?.replay()
    }

    // MARK: - Payments

    func insert(_ payment: PendingPayment) {
        snapshot.payments[payment.id] = payment
        persist()
    }

    func payment(_ id: UUID) -> PendingPayment? {
        snapshot.payments[id]
    }

    func payment(checkout: String) -> PendingPayment? {
        snapshot.checkouts[checkout].flatMap { snapshot.payments[$0] }
    }

    func pendingPayments() -> [PendingPayment] {
        snapshot.payments.values.filter { !$0.status.isTerminal }
    }

    /// Replaces a payment and, if it just completed, writes its contribution to the ledger
    /// exactly once. Called for callbacks, ticks and reconciliation alike.
    @discardableResult
    func update(_ payment: PendingPayment) -> LedgerEvent? {
        let previous = snapshot.payments[payment.id]
        snapshot.payments[payment.id] = payment
        if let checkout = payment.status.checkoutRequestID {
            snapshot.checkouts[checkout] = payment.id
        }

        var recorded: LedgerEvent?
        let wasCompleted: Bool = {
            if case .completed = previous?.status { return true }
            return false
        }()
        if !wasCompleted, let kind = payment.ledgerEventKind() {
            var log = snapshot.logs[payment.group.description] ?? EventLog(group: payment.group)
            recorded = log.record(kind, by: payment.member, on: Store.device, at: payment.updatedAt)
            snapshot.logs[payment.group.description] = log
            logger.info("ledger: contribution \(payment.amount) for \(payment.member) via \(payment.status)")
        }
        persist()
        return recorded
    }

    // MARK: - Persistence

    private func persist() {
        guard let fileURL else { return }
        do {
            let data = try Store.encoder.encode(snapshot)
            let tmp = fileURL.appendingPathExtension("tmp")
            try data.write(to: tmp, options: .atomic)
            _ = try FileManager.default.replaceItemAt(fileURL, withItemAt: tmp)
        } catch {
            logger.error("persist failed: \(error)")
        }
    }
}

extension Store {
    static let key = StorageKey()
    struct StorageKey: Vapor.StorageKey { typealias Value = Store }
}

extension Application {
    var store: Store {
        get { storage[Store.StorageKey.self]! }
        set { storage[Store.StorageKey.self] = newValue }
    }
}

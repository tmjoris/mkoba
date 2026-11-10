import Foundation
import MkobaCore
import Vapor

/// What the payment flow needs from M-Pesa. Two implementations: the real Daraja API and
/// a simulator that behaves like Daraja (including losing callbacks) for demos and tests.
protocol DarajaGateway: Sendable {
    func stkPush(_ request: Daraja.StkPushRequest) async throws -> Daraja.StkPushResponse
    func query(checkoutRequestID: String) async throws -> PendingPayment.QueryOutcome?
}

struct DarajaConfig: Sendable {
    let credentials: Daraja.Credentials
    let baseURL: URL
    let callbackURL: URL

    /// Reads DARAJA_* from the environment; nil means run the simulator.
    static func fromEnvironment(_ env: Environment) -> DarajaConfig? {
        guard let key = Environment.get("DARAJA_CONSUMER_KEY"),
              let secret = Environment.get("DARAJA_CONSUMER_SECRET"),
              let passkey = Environment.get("DARAJA_PASSKEY"),
              let publicBase = Environment.get("PUBLIC_BASE_URL").flatMap(URL.init(string:)) else {
            return nil
        }
        let shortCode = Environment.get("DARAJA_SHORTCODE") ?? Daraja.sandboxShortCode
        let base = Environment.get("DARAJA_ENV") == "production" ? Daraja.productionBase : Daraja.sandboxBase
        return DarajaConfig(
            credentials: Daraja.Credentials(consumerKey: key, consumerSecret: secret,
                                            shortCode: shortCode, passkey: passkey),
            baseURL: base,
            callbackURL: publicBase.appendingPathComponent("v1/payments/daraja/callback"))
    }
}

/// Real Daraja over Vapor's HTTP client, with the OAuth token cached until it expires.
actor LiveDaraja: DarajaGateway {
    private let config: DarajaConfig
    private let client: Client
    private let logger: Logger
    private var token: (value: String, expires: Date)?

    init(config: DarajaConfig, client: Client, logger: Logger) {
        self.config = config
        self.client = client
        self.logger = logger
    }

    private func accessToken() async throws -> String {
        if let token, token.expires > Date().addingTimeInterval(30) { return token.value }
        let uri = URI(string: config.baseURL.absoluteString + "/oauth/v1/generate?grant_type=client_credentials")
        let response = try await client.get(uri) { req in
            req.headers.add(name: .authorization, value: config.credentials.basicAuthorization)
        }
        guard response.status == .ok else {
            throw Abort(.badGateway, reason: "Daraja token endpoint returned \(response.status)")
        }
        let body = try response.content.decode(Daraja.TokenResponse.self)
        let ttl = TimeInterval(body.expiresIn) ?? 3_500
        token = (body.accessToken, Date().addingTimeInterval(ttl))
        return body.accessToken
    }

    func stkPush(_ request: Daraja.StkPushRequest) async throws -> Daraja.StkPushResponse {
        let bearer = try await accessToken()
        let uri = URI(string: config.baseURL.absoluteString + "/mpesa/stkpush/v1/processrequest")
        let response = try await client.post(uri) { req in
            req.headers.bearerAuthorization = BearerAuthorization(token: bearer)
            try req.content.encode(request, as: .json)
        }
        guard response.status == .ok else {
            let text = response.body.map { String(buffer: $0) } ?? ""
            logger.warning("stk push rejected: \(response.status) \(text)")
            throw PaymentError.rejectedByDaraja(code: "\(response.status.code)", description: text)
        }
        return try response.content.decode(Daraja.StkPushResponse.self)
    }

    private struct QueryRequest: Content {
        let BusinessShortCode: String
        let Password: String
        let Timestamp: String
        let CheckoutRequestID: String
    }

    private struct QueryResponse: Content {
        let ResultCode: String?
        let ResultDesc: String?
        let errorCode: String?
        let errorMessage: String?
    }

    func query(checkoutRequestID: String) async throws -> PendingPayment.QueryOutcome? {
        let bearer = try await accessToken()
        let stamp = Daraja.timestamp()
        let uri = URI(string: config.baseURL.absoluteString + "/mpesa/stkpushquery/v1/query")
        let response = try await client.post(uri) { req in
            req.headers.bearerAuthorization = BearerAuthorization(token: bearer)
            try req.content.encode(QueryRequest(
                BusinessShortCode: config.credentials.shortCode,
                Password: config.credentials.password(timestamp: stamp),
                Timestamp: stamp,
                CheckoutRequestID: checkoutRequestID), as: .json)
        }
        let body = try response.content.decode(QueryResponse.self)
        // "500.001.1001: The transaction is being processed" means keep waiting.
        if let code = body.errorCode {
            if code == "500.001.1001" { return nil }
            if code.hasSuffix("1032") || body.errorMessage?.contains("not found") == true { return .notFound }
            return .failed(code: -1, description: body.errorMessage ?? code)
        }
        guard let codeText = body.ResultCode, let code = Int(codeText) else { return nil }
        if code == 0 {
            // The query confirms success but carries no receipt; the callback (if it ever
            // arrives) fills it in. Record what we know so the ledger is never short.
            return .paid(MpesaReceipt(number: "STKQ-\(checkoutRequestID.suffix(10))", amount: .zero(),
                                      phone: PhoneNumber("0700000000")!, transactionDate: stamp))
        }
        return .failed(code: code, description: body.ResultDesc ?? "")
    }
}

/// Behaves like the sandbox without network: accepts every push, then after a short delay
/// posts a callback to our own endpoint. Phone numbers ending in specific digits trigger
/// the interesting cases, the same trick card networks use for test cards.
///
/// - ...00 : success (default for everything else too)
/// - ...11 : customer cancels (1032)
/// - ...22 : insufficient funds (1)
/// - ...33 : callback is lost; status query later says paid
/// - ...44 : callback is lost; status query says Daraja never saw it
actor SimulatedDaraja: DarajaGateway {
    typealias Deliver = @Sendable (Daraja.Callback) async -> Void

    private let deliver: Deliver
    private let delay: Duration
    private var pushes: [String: Daraja.StkPushRequest] = [:]
    private var counter = 0

    /// `deliver` plays the role of Safaricom's servers POSTing to our callback URL.
    init(delay: Duration = .seconds(2), deliver: @escaping Deliver) {
        self.deliver = deliver
        self.delay = delay
    }

    func stkPush(_ request: Daraja.StkPushRequest) async throws -> Daraja.StkPushResponse {
        counter += 1
        let checkout = "ws_CO_SIM_\(counter)_\(Int(Date().timeIntervalSince1970))"
        pushes[checkout] = request
        let suffix = String(request.phoneNumber.suffix(2))
        if suffix != "33" && suffix != "44" {
            let payload = Self.callback(for: request, checkout: checkout, suffix: suffix)
            let deliver = deliver
            let delay = delay
            Task.detached {
                try? await Task.sleep(for: delay)
                await deliver(payload)
            }
        }
        return Daraja.StkPushResponse(merchantRequestID: "SIM-\(counter)", checkoutRequestID: checkout,
                                      responseCode: "0", responseDescription: "Success. Request accepted for processing",
                                      customerMessage: "Success. Request accepted for processing")
    }

    func query(checkoutRequestID: String) async throws -> PendingPayment.QueryOutcome? {
        guard let request = pushes[checkoutRequestID] else { return .notFound }
        switch String(request.phoneNumber.suffix(2)) {
        case "33":
            return .paid(MpesaReceipt(number: "SIMQ\(checkoutRequestID.suffix(6))", amount: .kes(request.amount),
                                      phone: PhoneNumber(request.phoneNumber)!, transactionDate: Daraja.timestamp()))
        case "44":
            return .notFound
        default:
            return nil
        }
    }

    static func callback(for request: Daraja.StkPushRequest, checkout: String, suffix: String) -> Daraja.Callback {
        typealias Item = Daraja.Callback.Item
        let failure: (Int, String)? = switch suffix {
        case "11": (1032, "Request cancelled by user")
        case "22": (1, "The balance is insufficient for the transaction.")
        default: nil
        }
        if let (code, desc) = failure {
            return Daraja.Callback(body: .init(stkCallback: .init(
                merchantRequestID: "SIM", checkoutRequestID: checkout, resultCode: code, resultDesc: desc,
                callbackMetadata: nil)))
        }
        let receipt = "SIM" + String(checkout.hashValue.magnitude, radix: 36).uppercased().prefix(7)
        return Daraja.Callback(body: .init(stkCallback: .init(
            merchantRequestID: "SIM", checkoutRequestID: checkout, resultCode: 0,
            resultDesc: "The service request is processed successfully.",
            callbackMetadata: .init(item: [
                Item(name: "Amount", value: .number(Double(request.amount))),
                Item(name: "MpesaReceiptNumber", value: .string(receipt)),
                Item(name: "TransactionDate", value: .number(Double(Daraja.timestamp()) ?? 0)),
                Item(name: "PhoneNumber", value: .number(Double(request.phoneNumber) ?? 0)),
            ]))))
    }
}



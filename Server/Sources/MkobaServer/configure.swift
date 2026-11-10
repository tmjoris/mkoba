import Foundation
import MkobaCore
import Vapor

func configure(_ app: Application) async throws {
    ContentConfiguration.global.use(encoder: Store.encoder, for: .json)
    ContentConfiguration.global.use(decoder: Store.decoder, for: .json)

    let dataPath = Environment.get("MKOBA_DATA") ?? "data/store.json"
    let fileURL: URL? = app.environment == .testing ? nil : URL(fileURLWithPath: dataPath)
    if let fileURL {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
    }
    app.store = Store(fileURL: fileURL, logger: app.logger)

    let gateway: any DarajaGateway
    let credentials: Daraja.Credentials
    let callbackURL: URL
    if let config = DarajaConfig.fromEnvironment(app.environment) {
        gateway = LiveDaraja(config: config, client: app.client, logger: app.logger)
        credentials = config.credentials
        callbackURL = config.callbackURL
        app.logger.notice("Daraja: live (\(config.baseURL.host ?? ""))")
    } else {
        let port = app.http.server.configuration.port
        callbackURL = URL(string: "http://127.0.0.1:\(port)/v1/payments/daraja/callback")!
        credentials = Daraja.Credentials(consumerKey: "sim", consumerSecret: "sim",
                                         shortCode: Daraja.sandboxShortCode, passkey: "sim")
        let delay: Duration = app.environment == .testing ? .milliseconds(50) : .seconds(2)
        gateway = SimulatedDaraja(delay: delay) { [unowned app] callback in
            // Same code path a real Daraja POST takes, minus the socket.
            try? await app.payments.handleCallback(callback)
        }
        app.logger.notice("Daraja: simulator (set DARAJA_CONSUMER_KEY etc. for the sandbox)")
    }
    app.payments = PaymentService(store: app.store, gateway: gateway, credentials: credentials,
                                  callbackURL: callbackURL, logger: app.logger)

    if app.environment != .testing {
        let payments = app.payments
        Task.detached {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                await payments.reconcile()
            }
        }
    }

    try routes(app)
}

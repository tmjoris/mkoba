import Foundation
import MkobaCore

/// Thin typed client over URLSession. App Transport Security is left at its default, so
/// every request is HTTPS with modern TLS; the server must present a public CA certificate.
struct APIClient: Sendable {
    let baseURL: URL
    private let session: URLSession

    init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    struct CreatePayment: Encodable {
        let group: GroupID
        let member: MemberID
        let amountMinor: Int64
        let cycle: Int
        let phone: String
        let accountReference: String?
    }

    enum APIError: LocalizedError {
        case http(Int, String)
        case offline

        var errorDescription: String? {
            switch self {
            case .http(let code, let body): return "Server error \(code): \(body)"
            case .offline: return "You are offline. Changes are saved and will sync later."
            }
        }
    }

    func sync(_ request: SyncRequest) async throws -> SyncResponse {
        try await post("v1/groups/\(request.group)/sync", body: request)
    }

    func createPayment(_ body: CreatePayment) async throws -> PendingPayment {
        try await post("v1/payments", body: body)
    }

    func payment(_ id: UUID) async throws -> PendingPayment {
        try await get("v1/payments/\(id.uuidString)")
    }

    func retry(_ id: UUID) async throws -> PendingPayment {
        try await post("v1/payments/\(id.uuidString)/retry", body: Optional<Int>.none)
    }

    // MARK: - Plumbing

    private func get<Out: Decodable>(_ path: String) async throws -> Out {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = "GET"
        return try await send(request)
    }

    private func post<In: Encodable, Out: Decodable>(_ path: String, body: In?) async throws -> Out {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = "POST"
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSON.encoder.encode(body)
        }
        return try await send(request)
    }

    private func send<Out: Decodable>(_ request: URLRequest) async throws -> Out {
        var request = request
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError where error.code == .notConnectedToInternet || error.code == .timedOut {
            throw APIError.offline
        }
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard (200..<300).contains(http.statusCode) else {
            throw APIError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        return try JSON.decoder.decode(Out.self, from: data)
    }
}

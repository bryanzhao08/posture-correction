import Foundation

struct APIError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

@MainActor
final class APIClient {
    var baseURL: URL
    var token: String?
    var onAuthenticatedSuccess: (() -> Void)?
    private let session: URLSession
    init(baseURL: URL, token: String?) {
        self.baseURL = baseURL
        self.token = token
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 60
        session = URLSession(configuration: configuration)
    }
    func get<T: Decodable>(_ path: String, query: [URLQueryItem] = []) async throws -> T {
        let data = try await send(path, method: "GET", query: query)
        return try JSONDecoder().decode(T.self, from: data)
    }
    func post<B: Encodable, T: Decodable>(_ path: String, body: B, authenticated: Bool = true) async throws -> T {
        let data = try await send(path, method: "POST", body: JSONEncoder().encode(body), authenticated: authenticated)
        return try JSONDecoder().decode(T.self, from: data)
    }
    func patch<B: Encodable, T: Decodable>(_ path: String, body: B) async throws -> T {
        let data = try await send(path, method: "PATCH", body: JSONEncoder().encode(body))
        return try JSONDecoder().decode(T.self, from: data)
    }
    func postEmpty<B: Encodable>(_ path: String, body: B) async throws {
        _ = try await send(path, method: "POST", body: JSONEncoder().encode(body))
    }
    func delete(_ path: String) async throws { _ = try await send(path, method: "DELETE") }
    private func send(_ path: String, method: String, body: Data? = nil,
                      query: [URLQueryItem] = [], authenticated: Bool = true) async throws -> Data {
        let url = baseURL.appendingPathComponent(path.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw APIError(message: "The backend URL is invalid.")
        }
        if !query.isEmpty { components.queryItems = query }
        guard let requestURL = components.url else { throw APIError(message: "The request URL is invalid.") }
        var request = URLRequest(url: requestURL)
        request.httpMethod = method
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        if authenticated {
            guard let token = token else { throw APIError(message: "Please log in again.") }
            request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        }
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw APIError(message: "The server returned an invalid response.") }
        guard (200..<300).contains(response.statusCode) else {
            struct ErrorBody: Decodable {
                let detail: String
                enum CodingKeys: String, CodingKey { case detail }
            }
            let message = (try? JSONDecoder().decode(ErrorBody.self, from: data))?.detail
            throw APIError(message: message ?? "Server error (\(response.statusCode)). Please try again.")
        }
        if authenticated { onAuthenticatedSuccess?() }
        return data
    }
}
